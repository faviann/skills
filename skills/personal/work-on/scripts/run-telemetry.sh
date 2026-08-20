#!/usr/bin/env bash
set -euo pipefail

# Record and aggregate one work-on run's mechanical telemetry. Events are
# appended as JSON lines to a run-scoped sink inside the target repository's
# absolute Git common directory, providing durable storage that is untracked
# by construction and never reaches a published artifact.
#
# The recorder stores a closed set of enumerated fields, resolved SHAs,
# byte/duration counts, and a caller-supplied validation identifier. It has no
# field for a prompt, an issue body, a diff, a file's contents, a command's
# arguments, or a command's output, so that material cannot be recorded even by
# mistake.

readonly schema_version=3
readonly launch_roles=(
  implementation
  other
)
readonly review_roles=(readiness review-standards review-spec closure-sweep)
readonly review_kinds=(readiness full delta)
readonly phases=(orient implementation checkpoint gate remediation closeout)
readonly run_outcomes=(Closes Progresses preflight-aborted abandoned failed)
readonly observation_scopes=(completed-thread checkpoint-snapshot)
readonly finding_classes=(contract-defect evidence-gap)
readonly finding_dispositions=(accepted rejected follow-up unresolved)

fail() {
  printf 'run telemetry: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: run-telemetry.sh <subcommand>
  start --issue N [--continues-run HANDLE]  begin a schema-3 run; prints its bound handle
  launch --run HANDLE --role R --phase P --round N
  review-delegation --run HANDLE --role R --kind K --phase P --round N --base REF (--head REF | --worktree)
  runtime-observation --run HANDLE --scope S [--agent-id ID] [model/effort and token fields]
  finding-adjudicated --run HANDLE --reviewer-agent-id ID --class C --disposition D
  finding-resolved --run HANDLE --finding-id ID
  exec --run HANDLE --command-id ID --phase P --round N -- <command...>
                                            run and time a validation command
  resolve --run HANDLE --outcome (Closes|Progresses|preflight-aborted|abandoned|failed)
  seal --run HANDLE                          explicitly end recording
  summary --run HANDLE                      deterministic aggregate as JSON
USAGE
  exit 1
}

contains() {
  local needle="$1" candidate
  shift
  for candidate in "$@"; do
    [[ "$candidate" == "$needle" ]] && return 0
  done
  return 1
}

require_enum() {
  local label="$1" value="$2"
  shift 2
  contains "$value" "$@" || fail "$label must be one of: $*"
}

require_round() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]] || fail "round must be a nonnegative integer"
}

require_count() {
  [[ "$2" =~ ^(0|[1-9][0-9]*)$ ]] || fail "$1 must be a nonnegative integer"
}

# A validation is named by the caller, never derived from the command it runs.
# The syntax is deliberately narrow — lowercase letters and digits in
# hyphen-separated words — so the identifier cannot smuggle a path, an
# argument, a URL, or a credential into the sink, and so two runs of the same
# check are recognisably the same check.
readonly command_id_pattern='^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
readonly command_id_max_length=48

require_command_id() {
  [[ -n "$1" ]] || fail "exec requires --command-id"
  [[ "${#1}" -le "$command_id_max_length" ]] \
    || fail "command-id must be at most $command_id_max_length characters"
  [[ "$1" =~ $command_id_pattern ]] \
    || fail "command-id must be lowercase alphanumeric words joined by single hyphens"
}

require_review_combination() {
  local role="$1" kind="$2" phase="$3"
  case "$role:$kind:$phase" in
    readiness:readiness:checkpoint) ;;
    review-standards:full:gate|review-spec:full:gate|closure-sweep:full:gate) ;;
    review-standards:delta:remediation|review-spec:delta:remediation|closure-sweep:delta:remediation) ;;
    closure-sweep:full:closeout) ;;
    *) fail "review role/kind/phase combination is invalid" ;;
  esac
}

# Milliseconds since the epoch. EPOCHREALTIME avoids a subprocess per event;
# a shell without it degrades to whole seconds rather than failing.
now_ms() {
  local raw="${EPOCHREALTIME:-}"
  if [[ "$raw" =~ ^([0-9]+)[.,]([0-9]+)$ ]]; then
    printf '%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]:0:3}"
  else
    printf '%s000\n' "$(date -u +%s)"
  fi
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

command -v git >/dev/null 2>&1 || fail "run telemetry requires git"
command -v jq >/dev/null 2>&1 || fail "run telemetry requires jq"
command -v flock >/dev/null 2>&1 || fail "run telemetry requires flock"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || fail "run telemetry requires a Git-backed target repository"
git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)" \
  || fail "could not resolve the repository's Git directory"
git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || fail "could not resolve the repository's Git common directory"
telemetry_root="$git_common_dir/work-on-telemetry"
runs_root="$telemetry_root/runs"
repository_binding_file="$telemetry_root/repository-binding"
repository_binding_lock="$telemetry_root/repository-binding.lock"

readonly run_id_pattern='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'
readonly run_handle_pattern='^([0-9]{8}T[0-9]{6}Z-[0-9a-f]{8})@([0-9a-f]{32})$'
readonly repository_binding_pattern='^[0-9a-f]{32}$'

normalized_repository=""
resolve_repository_identity() {
  local origin slug
  origin="$(git remote get-url origin 2>/dev/null)" \
    || fail "origin must identify a GitHub owner/repository"
  case "$origin" in
    git@github.com:*) slug="${origin#git@github.com:}" ;;
    https://github.com/*) slug="${origin#https://github.com/}" ;;
    ssh://git@github.com/*) slug="${origin#ssh://git@github.com/}" ;;
    *) fail "origin must identify a GitHub owner/repository" ;;
  esac
  slug="${slug%.git}"
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || fail "origin must identify a GitHub owner/repository"
  normalized_repository="${slug,,}"
}

require_issue() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail "issue must be a positive integer"
}

# The sink records what a workstation's runs did, so it is created for its owner
# only. The umask closes the window between creation and the chmod; the chmod
# also tightens a directory an earlier version left readable. The umask is set
# in a subshell so it never reaches a command `exec` runs.
create_private_dir() {
  [[ -d "$1" ]] || (umask 077 && mkdir -p "$1")
  chmod 700 "$1"
}

create_private_file() {
  [[ -e "$1" ]] || (umask 077 && : >"$1")
  chmod 600 "$1"
}

# One opaque binding belongs to the Git common directory and therefore to all
# of its linked worktrees. It lives beside the sinks rather than in schema-1
# events: the handle proves routing authority without changing event semantics.
repository_binding=""
load_repository_binding() {
  [[ -f "$repository_binding_file" ]] \
    || fail "repository binding is missing; run start first"
  IFS= read -r repository_binding <"$repository_binding_file" \
    || fail "repository binding is unreadable"
  [[ "$repository_binding" =~ $repository_binding_pattern ]] \
    || fail "repository binding is malformed"
}

ensure_repository_binding() {
  local binding_lock_fd staged binding=""
  create_private_file "$repository_binding_lock"
  exec {binding_lock_fd}>>"$repository_binding_lock"
  flock -x "$binding_lock_fd" \
    || fail "could not lock the repository binding"
  if [[ ! -f "$repository_binding_file" ]]; then
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
      IFS= read -r binding </proc/sys/kernel/random/uuid || true
      binding="${binding//-/}"
    fi
    [[ "$binding" =~ $repository_binding_pattern ]] \
      || binding="$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')"
    [[ "$binding" =~ $repository_binding_pattern ]] \
      || fail "could not mint a repository binding"
    staged="$repository_binding_file.$$"
    create_private_file "$staged"
    printf '%s\n' "$binding" >"$staged"
    mv -f "$staged" "$repository_binding_file"
  fi
  chmod 600 "$repository_binding_file"
  load_repository_binding
  exec {binding_lock_fd}>&-
}

resolved_run_id=""
resolve_bound_handle() {
  local handle="$1" supplied_binding
  [[ -n "$handle" ]] || fail "operation requires --run"
  [[ "$handle" =~ $run_handle_pattern ]] \
    || fail "run handle is malformed"
  resolved_run_id="${BASH_REMATCH[1]}"
  supplied_binding="${BASH_REMATCH[2]}"
  load_repository_binding
  [[ "$supplied_binding" == "$repository_binding" ]] \
    || fail "run handle belongs to another repository"
}

require_run_handle() {
  resolve_bound_handle "$1"
  run_id="$resolved_run_id"
  [[ -f "$runs_root/$run_id.jsonl" ]] \
    || fail "telemetry sink is missing for run $run_id"
}

# Aggregation alone can read a schema-1 sink from the location used before
# linked worktrees adopted common-directory storage. For a plain ID, that local
# legacy sink takes precedence over a same-named canonical sink; a bound handle
# still selects canonical storage. The legacy lookup is deliberately limited to
# this worktree's own Git directory: it is not discovery, and every writer still
# passes require_run_handle above and therefore targets only runs_root.
summary_run_file=""
summary_handle_is_bound=false
resolve_summary_run() {
  local handle="$1" legacy_run_file
  [[ -n "$handle" ]] || fail "operation requires --run"
  if [[ "$handle" =~ $run_handle_pattern ]]; then
    summary_handle_is_bound=true
    resolve_bound_handle "$handle"
    run_id="$resolved_run_id"
    [[ -f "$runs_root/$run_id.jsonl" ]] \
      || fail "telemetry sink is missing for run $run_id"
    summary_run_file="$runs_root/$run_id.jsonl"
    return 0
  fi
  [[ "$handle" =~ $run_id_pattern ]] \
    || fail "run handle is malformed"
  run_id="$handle"
  legacy_run_file="$git_dir/work-on-telemetry/runs/$run_id.jsonl"
  if [[ "$git_dir" != "$git_common_dir" && -f "$legacy_run_file" ]]; then
    summary_run_file="$legacy_run_file"
    return 0
  fi
  if [[ -f "$runs_root/$run_id.jsonl" ]]; then
    summary_run_file="$runs_root/$run_id.jsonl"
    return 0
  fi
  fail "telemetry sink is missing for run $run_id"
}

# Recording is concurrent: several subagents and validation wrappers may append
# to one run at the same time. Sequence numbers, execution ids, and the append
# itself are therefore allocated under an exclusive lock on the sink, so no two
# writers can read the same state and then both act on it.
sink_lock_fd=""
sink_run_file=""

# A writer killed mid-append leaves a line with no terminator. Under the lock,
# before anything is allocated or written, that torn line is closed off: it
# becomes one line the aggregator counts as malformed and ignores, instead of
# fusing with the next event and destroying both.
repair_partial_line() {
  [[ -s "$sink_run_file" ]] || return 0
  [[ "$(tail -c 1 "$sink_run_file" | od -An -tx1 | tr -d ' \n')" == 0a ]] \
    || printf '\n' >&"$sink_lock_fd"
}

lock_sink() {
  sink_run_file="$runs_root/$1.jsonl"
  exec {sink_lock_fd}>>"$sink_run_file"
  flock -x "$sink_lock_fd" \
    || fail "could not lock the telemetry sink: $sink_run_file"
}

open_current_sink() {
  local observed_schemas
  lock_sink "$1"
  observed_schemas="$(jq -n -R -c \
    '[inputs | fromjson? // empty | select(type == "object") | .schema]
    | unique' <"$sink_run_file")"
  if [[ "$observed_schemas" != "[$schema_version]" ]]; then
    close_sink
    fail "schema-$schema_version writer requires a schema-$schema_version run"
  fi
  repair_partial_line
}

close_sink() {
  exec {sink_lock_fd}>&-
  sink_lock_fd=""
}

# Writes exactly one line through the held lock. `extra` is a compact JSON
# object supplying the event's own fields; the envelope is identical for every
# event type.
write_event() {
  local run_id="$1" type="$2" extra="${3:-}" sequence
  [[ -n "$extra" ]] || extra='{}'
  sequence=$(( $(wc -l <"$sink_run_file" | tr -d ' ') + 1 ))
  jq -cn \
    --argjson schema "$schema_version" \
    --arg run "$run_id" \
    --argjson seq "$sequence" \
    --arg at "$(now_iso)" \
    --argjson epoch_ms "$(now_ms)" \
    --arg type "$type" \
    --argjson extra "$extra" \
    '{schema: $schema, run: $run, seq: $seq, at: $at, epoch_ms: $epoch_ms, type: $type}
      + $extra' >&"$sink_lock_fd"
}

append_event() {
  # start owns the only empty sink initialization path. Existing-run writers
  # must use open_current_sink so they cannot modify historical schemas.
  lock_sink "$1"
  write_event "$@"
  close_sink
}

event_count_locked() {
  jq -n -R --arg type "$1" \
    '[inputs | fromjson? // empty
      | select(type == "object" and .type == $type)] | length' \
    <"$sink_run_file"
}

agent_id=""
allocate_agent_id_locked() {
  local agent_index
  agent_index="$(jq -n -R '[inputs | fromjson? // empty
    | select(type == "object"
      and (.type == "subagent_launch" or .type == "review_delegation"))]
    | length' <"$sink_run_file")"
  agent_id="$(printf '%s-a%03d' "$run_id" "$((agent_index + 1))")"
}

require_recording_open_locked() {
  [[ "$(event_count_locked run_sealed)" -eq 0 ]] \
    || fail "run $run_id is sealed"
}

require_event_lifecycle_locked() {
  local type="$1" phase="${2:-}" role="${3:-}" resolutions
  require_recording_open_locked
  resolutions="$(event_count_locked outcome_resolved)"
  [[ "$resolutions" -le 1 ]] || fail "run $run_id has invalid lifecycle state"
  [[ "$resolutions" -eq 0 ]] && return 0
  case "$type:$phase:$role" in
    validation_start:closeout:|validation_end:closeout:|subagent_launch:closeout:other) ;;
    *) fail "run $run_id has already resolved its outcome" ;;
  esac
}

append_recording_event() {
  local target_run="$1" type="$2" extra="$3" phase="${4:-}" role="${5:-}"
  open_current_sink "$target_run"
  require_event_lifecycle_locked "$type" "$phase" "$role"
  write_event "$target_run" "$type" "$extra"
  close_sink
}

# A review's size is the size of one named artifact, produced the same way every
# time. Presentation configuration — colour, quoted paths, external and textconv
# drivers, prefixes — is pinned, and every command runs from the repository root,
# so the same repository state always yields the same bytes no matter which
# directory the recorder was called from.
diff_git() {
  git -C "$repo_root" \
    -c core.quotePath=false \
    -c diff.noprefix=false \
    -c diff.mnemonicPrefix=false \
    --no-pager diff --no-ext-diff --no-color --no-textconv "$@"
}

# The worktree-review bundle: exactly what a readiness sweep is told to inspect,
# in one deterministic order.
#
#   1. every tracked change against the base, staged and unstaged alike
#      (`git diff <base>` compares the working tree to the base commit, so a
#      staged addition is already a tracked change and is not counted twice);
#   2. every untracked, non-ignored regular file, as its whole content.
#
# `git ls-files` emits its paths sorted and NUL-delimited, so a name holding a
# space, a quote, or a newline is passed through exactly and the order does not
# depend on the shell. `--no-index` reports a difference with status 1, which is
# the expected result here, not a failure.
worktree_review_bundle() {
  local base_sha="$1" untracked
  diff_git "$base_sha"
  while IFS= read -r -d '' untracked; do
    [[ -f "$repo_root/$untracked" ]] || continue
    diff_git --no-index -- /dev/null "$untracked" || true
  done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
}

subcommand="${1:-}"
[[ -n "$subcommand" ]] || usage
shift || true

case "$subcommand" in
  start)
    issue=""
    continues_run=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
        --continues-run) continues_run="${2:?--continues-run requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_issue "$issue"
    resolve_repository_identity
    continues_run_id=""
    if [[ -n "$continues_run" ]]; then
      resolve_bound_handle "$continues_run"
      continues_run_id="$resolved_run_id"
      continued_sink="$runs_root/$continues_run_id.jsonl"
      [[ -f "$continued_sink" ]] \
        || fail "continued run telemetry sink is missing"
      continued_identity="$(jq -n -R -c --arg run "$continues_run_id" \
        --argjson schema "$schema_version" '
        [inputs | fromjson? // empty
          | select(type == "object" and .schema == $schema and .type == "run_start")]
        | if length == 1 and .[0].seq == 1 and .[0].run == $run
            and .[0].run_identity == $run
            and (.[0].head | type == "string" and test("^[0-9a-f]{40}$"))
          then {repository: .[0].repository, issue: .[0].issue}
          else null end
      ' <"$continued_sink")"
      [[ "$(jq -r '.repository // empty' <<<"$continued_identity")" == \
          "$normalized_repository" \
        && "$(jq -r '.issue // empty' <<<"$continued_identity")" == "$issue" ]] \
        || fail "continued run belongs to another repository or issue"
    fi
    create_private_dir "$telemetry_root"
    create_private_dir "$runs_root"
    ensure_repository_binding
    suffix="$(od -An -tx1 -N4 /dev/urandom 2>/dev/null | tr -d ' \n')"
    [[ "$suffix" =~ ^[0-9a-f]{8}$ ]] \
      || suffix="$(printf '%08x' $(( (RANDOM << 16 | RANDOM) & 0xffffffff )))"
    run_id="$(date -u +%Y%m%dT%H%M%SZ)-$suffix"
    [[ "$run_id" =~ $run_id_pattern ]] || fail "could not mint a run id"
    [[ ! -e "$runs_root/$run_id.jsonl" ]] || fail "run id collision: $run_id"
    create_private_file "$runs_root/$run_id.jsonl"
    head_sha="$(git rev-parse --verify HEAD^{commit} 2>/dev/null)" \
      || fail "start requires a committed HEAD"
    append_event "$run_id" run_start "$(
      jq -cn --arg repository "$normalized_repository" \
        --argjson issue "$issue" --arg head "$head_sha" --arg run "$run_id" \
        --arg continues_run "$continues_run_id" \
        '{workflow: "work-on", repository: $repository, issue: $issue,
          head: $head, run_identity: $run}
          + (if $continues_run == "" then {}
             else {continues_run: $continues_run} end)'
    )"
    printf '%s@%s\n' "$run_id" "$repository_binding"
    ;;

  launch)
    run_id=""
    role=""
    phase=""
    round=""
    tokens_in=""
    tokens_out=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        --role) role="${2:?--role requires a value}"; shift 2 ;;
        --phase) phase="${2:?--phase requires a value}"; shift 2 ;;
        --round) round="${2:?--round requires a value}"; shift 2 ;;
        --tokens-in)
          [[ "$schema_version" -eq 2 ]] || usage
          tokens_in="${2:?--tokens-in requires a value}"; shift 2 ;;
        --tokens-out)
          [[ "$schema_version" -eq 2 ]] || usage
          tokens_out="${2:?--tokens-out requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    require_enum role "$role" "${launch_roles[@]}"
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    # Token counts are optional: a runtime that does not expose them records a
    # launch without them rather than failing or inventing a number.
    [[ -z "$tokens_in" ]] || require_count tokens-in "$tokens_in"
    [[ -z "$tokens_out" ]] || require_count tokens-out "$tokens_out"
    open_current_sink "$run_id"
    require_event_lifecycle_locked subagent_launch "$phase" "$role"
    allocate_agent_id_locked
    write_event "$run_id" subagent_launch "$(
      jq -cn \
        --argjson schema "$schema_version" \
        --arg agent_id "$agent_id" --arg role "$role" \
        --arg phase "$phase" --argjson round "$round" \
        --arg tokens_in "$tokens_in" --arg tokens_out "$tokens_out" \
        '{role: $role, phase: $phase, round: $round}
          + (if $schema == 3 then {agent_id: $agent_id} else {} end)
          + (if $tokens_in == "" then {} else {tokens_in: ($tokens_in | tonumber)} end)
          + (if $tokens_out == "" then {} else {tokens_out: ($tokens_out | tonumber)} end)'
    )"
    close_sink
    [[ "$schema_version" -ne 3 ]] || printf '%s\n' "$agent_id"
    ;;

  review-delegation)
    run_id=""
    role=""
    kind=""
    phase=""
    round=""
    base=""
    head_ref=""
    worktree=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        --role) role="${2:?--role requires a value}"; shift 2 ;;
        --kind) kind="${2:?--kind requires a value}"; shift 2 ;;
        --phase) phase="${2:?--phase requires a value}"; shift 2 ;;
        --round) round="${2:?--round requires a value}"; shift 2 ;;
        --base) base="${2:?--base requires a value}"; shift 2 ;;
        --head) head_ref="${2:?--head requires a value}"; shift 2 ;;
        --worktree) worktree=true; shift ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    require_enum role "$role" "${review_roles[@]}"
    require_enum kind "$kind" "${review_kinds[@]}"
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    require_review_combination "$role" "$kind" "$phase"
    [[ -n "$base" ]] || fail "review-delegation requires --base"
    if [[ "$worktree" == true ]]; then
      [[ -z "$head_ref" ]] || fail "review-delegation takes --head or --worktree, not both"
      head_ref=HEAD
    else
      [[ -n "$head_ref" ]] || fail "review-delegation requires --head or --worktree"
    fi
    base_sha="$(git rev-parse --verify "$base^{commit}" 2>/dev/null)" \
      || fail "review --base does not resolve to a commit: $base"
    head_sha="$(git rev-parse --verify "$head_ref^{commit}" 2>/dev/null)" \
      || fail "review --head does not resolve to a commit: $head_ref"
    # Only the size of the reviewed artifact is recorded; the artifact itself is
    # measured as it streams and never lands anywhere. A worktree sweep reads
    # new files that git does not track yet, so their content is part of what
    # the reviewer was handed — measuring `git diff` alone would report a sweep
    # whose whole subject is new code as a zero-byte review. Ignored files are
    # not part of it.
    if [[ "$worktree" == true ]]; then
      input_bytes="$(worktree_review_bundle "$base_sha" | wc -c | tr -d ' ')"
    else
      input_bytes="$(diff_git "$base_sha...$head_sha" | wc -c | tr -d ' ')"
    fi
    open_current_sink "$run_id"
    require_event_lifecycle_locked review_delegation "$phase" "$role"
    allocate_agent_id_locked
    write_event "$run_id" review_delegation "$(
      jq -cn \
        --argjson schema "$schema_version" \
        --arg agent_id "$agent_id" --arg role "$role" \
        --arg kind "$kind" --arg phase "$phase" \
        --argjson round "$round" \
        --arg base "$base_sha" --arg head "$head_sha" \
        --argjson worktree "$worktree" --argjson input_bytes "$input_bytes" \
        '{role: $role, kind: $kind, phase: $phase, round: $round,
          base: $base, head: $head,
          head_is_worktree: $worktree, input_bytes: $input_bytes}
          + (if $schema == 3 then {agent_id: $agent_id} else {} end)'
    )"
    close_sink
    [[ "$schema_version" -ne 3 ]] || printf '%s\n' "$agent_id"
    ;;

  runtime-observation)
    run_id=""
    scope=""
    agent_id=""
    model=""
    effort=""
    total_input=""
    cached_input=""
    cache_write_input=""
    output=""
    reasoning_output=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        --scope) scope="${2:?--scope requires a value}"; shift 2 ;;
        --agent-id) agent_id="${2:?--agent-id requires a value}"; shift 2 ;;
        --model) model="${2:?--model requires a value}"; shift 2 ;;
        --effort) effort="${2:?--effort requires a value}"; shift 2 ;;
        --total-input) total_input="${2:?--total-input requires a value}"; shift 2 ;;
        --cached-input) cached_input="${2:?--cached-input requires a value}"; shift 2 ;;
        --cache-write-input) cache_write_input="${2:?--cache-write-input requires a value}"; shift 2 ;;
        --output) output="${2:?--output requires a value}"; shift 2 ;;
        --reasoning-output) reasoning_output="${2:?--reasoning-output requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    require_enum scope "$scope" "${observation_scopes[@]}"
    if [[ "$scope" == completed-thread ]]; then
      [[ -n "$agent_id" ]] || fail "completed-thread observation requires --agent-id"
    else
      [[ -z "$agent_id" ]] || fail "checkpoint-snapshot observation refers to the primary"
    fi
    if [[ -n "$model" || -n "$effort" ]]; then
      [[ "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
        || fail "model is invalid"
      require_enum effort "$effort" none minimal low medium high xhigh max ultra
    fi
    token_values=("$total_input" "$cached_input" "$cache_write_input" "$output" "$reasoning_output")
    supplied_tokens=0
    for token_value in "${token_values[@]}"; do
      [[ -z "$token_value" ]] || supplied_tokens=$((supplied_tokens + 1))
    done
    [[ "$supplied_tokens" -eq 0 || "$supplied_tokens" -eq 5 ]] \
      || fail "runtime token fields must be supplied together"
    [[ -n "$model" || "$supplied_tokens" -eq 5 ]] \
      || fail "runtime observation requires model/effort or tokens"
    if [[ "$supplied_tokens" -eq 5 ]]; then
      require_count total-input "$total_input"
      require_count cached-input "$cached_input"
      require_count cache-write-input "$cache_write_input"
      require_count output "$output"
      require_count reasoning-output "$reasoning_output"
      (( cached_input + cache_write_input <= total_input )) \
        || fail "cached plus cache-write input cannot exceed total input"
      (( reasoning_output <= output )) \
        || fail "reasoning output cannot exceed output"
    fi
    open_current_sink "$run_id"
    require_event_lifecycle_locked runtime_observation
    if [[ "$scope" == completed-thread ]]; then
      known_agents="$(jq -n -R --arg id "$agent_id" '[inputs | fromjson? // empty
        | select(type == "object"
          and (.type == "subagent_launch" or .type == "review_delegation")
          and .agent_id == $id)] | length' <"$sink_run_file")"
      [[ "$known_agents" -eq 1 ]] || {
        close_sink
        fail "runtime observation requires one known agent"
      }
    fi
    prior_observations="$(jq -n -R --arg scope "$scope" --arg id "$agent_id" '
      [inputs | fromjson? // empty
        | select(type == "object" and .type == "runtime_observation"
          and .scope == $scope
          and (if $scope == "completed-thread" then .agent_id == $id else true end))]
      | length' <"$sink_run_file")"
    [[ "$prior_observations" -eq 0 ]] || {
      close_sink
      fail "runtime observation already recorded"
    }
    write_event "$run_id" runtime_observation "$(jq -cn \
      --arg scope "$scope" --arg agent_id "$agent_id" \
      --arg model "$model" --arg effort "$effort" \
      --arg total_input "$total_input" --arg cached_input "$cached_input" \
      --arg cache_write_input "$cache_write_input" --arg output "$output" \
      --arg reasoning_output "$reasoning_output" '
      {scope: $scope}
      + (if $agent_id == "" then {} else {agent_id: $agent_id} end)
      + (if $model == "" then {} else {model: $model, effort: $effort} end)
      + (if $total_input == "" then {} else {tokens: {
          total_input: ($total_input | tonumber),
          cached_input: ($cached_input | tonumber),
          cache_write_input: ($cache_write_input | tonumber),
          output: ($output | tonumber),
          reasoning_output: ($reasoning_output | tonumber)}} end)')"
    close_sink
    ;;

  finding-adjudicated)
    run_id=""
    reviewer_agent_id=""
    finding_class=""
    disposition=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        --reviewer-agent-id) reviewer_agent_id="${2:?--reviewer-agent-id requires a value}"; shift 2 ;;
        --class) finding_class="${2:?--class requires a value}"; shift 2 ;;
        --disposition) disposition="${2:?--disposition requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    require_enum class "$finding_class" "${finding_classes[@]}"
    require_enum disposition "$disposition" "${finding_dispositions[@]}"
    open_current_sink "$run_id"
    require_event_lifecycle_locked finding_adjudicated
    reviewer_count="$(jq -n -R --arg id "$reviewer_agent_id" '
      [inputs | fromjson? // empty
        | select(type == "object" and .type == "review_delegation"
          and .agent_id == $id)] | length' <"$sink_run_file")"
    [[ "$reviewer_count" -eq 1 ]] || {
      close_sink
      fail "finding origin requires one reviewer delegation"
    }
    finding_index="$(event_count_locked finding_adjudicated)"
    finding_id="$(printf '%s-f%03d' "$run_id" "$((finding_index + 1))")"
    write_event "$run_id" finding_adjudicated "$(jq -cn \
      --arg finding_id "$finding_id" --arg reviewer_agent_id "$reviewer_agent_id" \
      --arg class "$finding_class" --arg disposition "$disposition" \
      '{finding_id: $finding_id, reviewer_agent_id: $reviewer_agent_id,
        class: $class, disposition: $disposition}')"
    close_sink
    printf '%s\n' "$finding_id"
    ;;

  finding-resolved)
    run_id=""
    finding_id=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        --finding-id) finding_id="${2:?--finding-id requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    open_current_sink "$run_id"
    require_event_lifecycle_locked finding_resolved
    accepted_count="$(jq -n -R --arg id "$finding_id" '
      [inputs | fromjson? // empty
        | select(type == "object" and .type == "finding_adjudicated"
          and .finding_id == $id and .disposition == "accepted")] | length' \
      <"$sink_run_file")"
    resolved_count="$(jq -n -R --arg id "$finding_id" '
      [inputs | fromjson? // empty
        | select(type == "object" and .type == "finding_resolved"
          and .finding_id == $id)] | length' <"$sink_run_file")"
    [[ "$accepted_count" -eq 1 && "$resolved_count" -eq 0 ]] || {
      close_sink
      fail "finding resolution requires one unresolved accepted finding"
    }
    write_event "$run_id" finding_resolved "$(jq -cn \
      --arg finding_id "$finding_id" '{finding_id: $finding_id}')"
    close_sink
    ;;

  exec)
    run_id=""
    command_id=""
    phase=""
    round=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        --command-id) command_id="${2:?--command-id requires a value}"; shift 2 ;;
        --phase) phase="${2:?--phase requires a value}"; shift 2 ;;
        --round) round="${2:?--round requires a value}"; shift 2 ;;
        --) shift; break ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    # The identifier is validated before the command runs, so a run cannot
    # record executions the next run has no name for.
    require_command_id "$command_id"
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    [[ "$#" -gt 0 ]] || fail "exec requires a command after --"
    # Nothing about the command itself is examined, hashed, or stored — not its
    # arguments, not its program, not its path. A validation is whatever the
    # caller deliberately named it, and that name is all the sink learns.
    started_ms="$(now_ms)"

    # Counting prior executions and writing this one's start happen under a
    # single lock, so two wrappers starting at once cannot be handed the same
    # execution id.
    open_current_sink "$run_id"
    require_event_lifecycle_locked validation_start "$phase"
    execution_index="$(
      jq -n -R '[inputs | fromjson? // empty
        | select(type == "object" and .type == "validation_start")] | length' \
        <"$sink_run_file"
    )"
    exec_id="$(printf '%s-e%03d' "$run_id" "$((execution_index + 1))")"
    write_event "$run_id" validation_start "$(
      jq -cn \
        --arg exec_id "$exec_id" --arg command_id "$command_id" \
        --arg phase "$phase" --argjson round "$round" \
        '{exec_id: $exec_id, command_id: $command_id,
          phase: $phase, round: $round}'
    )"
    close_sink

    validation_ended=false
    record_end() {
      local outcome="$1" status="$2"
      validation_ended=true
      append_recording_event "$run_id" validation_end "$(
        jq -cn \
          --arg exec_id "$exec_id" --arg command_id "$command_id" \
          --arg phase "$phase" --argjson round "$round" \
          --arg outcome "$outcome" --argjson exit_status "$status" \
          --argjson duration_ms "$(( $(now_ms) - started_ms ))" \
          '{exec_id: $exec_id, command_id: $command_id,
            phase: $phase, round: $round, outcome: $outcome,
            exit_status: $exit_status, duration_ms: $duration_ms}'
      )" "$phase"
    }
    # An interrupted wrapper still closes its own execution, so the sink holds
    # a controlled `interrupted` record instead of a dangling start.
    on_exit() {
      [[ "$validation_ended" == true ]] || record_end interrupted null
    }
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    set +e
    "$@"
    exit_status=$?
    set -e
    if [[ "$exit_status" -eq 0 ]]; then
      record_end passed "$exit_status"
    else
      record_end failed "$exit_status"
    fi
    exit "$exit_status"
    ;;

  resolve)
    run_id=""
    outcome=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        --outcome) outcome="${2:?--outcome requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    require_enum outcome "$outcome" "${run_outcomes[@]}"
    # A run resolves its outcome exactly once. Checking for an existing
    # resolution and writing this one happen under a single lock, so two
    # closers cannot both find none and both write.
    open_current_sink "$run_id"
    require_recording_open_locked
    resolution_count="$(event_count_locked outcome_resolved)"
    if [[ "$resolution_count" -ne 0 ]]; then
      close_sink
      fail "run $run_id already resolved its outcome"
    fi
    if [[ "$outcome" == preflight-aborted ]]; then
      work_count="$(jq -n -R '[inputs | fromjson? // empty
        | select(type == "object"
          and ((.type == "subagent_launch" and .role == "implementation")
            or .type == "review_delegation"))] | length' <"$sink_run_file")"
      if [[ "$work_count" -ne 0 ]]; then
        close_sink
        fail "preflight-aborted is invalid after implementation or review delegation"
      fi
    fi
    write_event "$run_id" outcome_resolved "$(
      jq -cn --arg outcome "$outcome" '{outcome: $outcome}'
    )"
    close_sink
    ;;

  seal)
    run_id=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    open_current_sink "$run_id"
    seal_count="$(event_count_locked run_sealed)"
    [[ "$seal_count" -eq 0 ]] || {
      close_sink
      fail "run $run_id is already sealed"
    }
    resolution_count="$(event_count_locked outcome_resolved)"
    [[ "$resolution_count" -eq 1 ]] || {
      close_sink
      fail "run $run_id must resolve exactly one outcome before sealing"
    }
    validation_balance="$(jq -n -R '[inputs | fromjson? // empty
      | select(type == "object")]
      | ([.[] | select(.type == "validation_start")] | length)
        - ([.[] | select(.type == "validation_end")] | length)' \
      <"$sink_run_file")"
    [[ "$validation_balance" -eq 0 ]] || {
      close_sink
      fail "run $run_id has incomplete validation executions"
    }
    write_event "$run_id" run_sealed
    close_sink
    ;;

  summary)
    run_id=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    resolve_summary_run "$run_id"
    # Integrity is evaluated from one stable physical artifact. Writers take an
    # exclusive lock on this same file, so the shared lock prevents a summary
    # from observing an append between its framing check and JSON evaluation.
    exec {summary_lock_fd}<"$summary_run_file"
    flock -s "$summary_lock_fd" \
      || fail "could not lock the telemetry sink: $summary_run_file"
    terminal_newline_missing=false
    if [[ -s "$summary_run_file" ]] \
        && [[ "$(tail -c 1 "$summary_run_file" | od -An -tx1 | tr -d ' \n')" != 0a ]]; then
      terminal_newline_missing=true
    fi
    observed_schemas="$(jq -n -R -c \
      '[inputs | fromjson? // empty | select(type == "object") | .schema]
      | unique' <"$summary_run_file")"
    if [[ "$summary_handle_is_bound" == false \
        && "$observed_schemas" != '[1]' ]]; then
      fail "schema-2 summary requires a repository-bound handle"
    fi
    if [[ "$observed_schemas" == '[1]' ]]; then
      # Schema 1 is historical evidence. Preserve its aggregation window and
      # recorded-event counts, but never promote those observations into exact
      # reviewer accounting or retrospectively claim integrity.
      jq -n -R -c --arg run "$run_id" \
        --argjson roles '["implementation","readiness","review-standards","review-spec","closure-sweep","other"]' \
        --argjson kinds '["readiness","full","delta"]' \
        --argjson phases '["orient","implementation","checkpoint","gate","remediation","closeout"]' '
        [inputs | select(length > 0)] as $lines
        | [$lines[] | fromjson? // empty] as $parsed
        | [$parsed[] | select(type == "object" and .run == $run and .schema == 1)] as $recorded
        | [$recorded[] | select(.type == "run_finish")] as $finishes
        | ($finishes | first) as $finish
        | (if $finish == null then null else ($finish.seq // 0) end) as $final_seq
        | [$recorded[] | select($final_seq == null or (.seq // 0) <= $final_seq)] as $events
        | [$events[] | select(.type == "subagent_launch")] as $launches
        | [$events[] | select(.type == "review")] as $reviews
        | [$events[] | select(.type == "validation_start")] as $starts
        | [$events[] | select(.type == "validation_end")] as $ends
        | ([$ends[] | .exec_id] | unique) as $ended_ids
        | [$launches[] | select(has("tokens_in") or has("tokens_out"))] as $token_launches
        | {
            schema: 1, run: $run,
            integrity: {state: "legacy-unverifiable", reasons: []},
            reviewer_accounting: "legacy-unverifiable",
            started_at: ([$events[] | select(.type == "run_start") | .at] | first),
            finished_at: (if $finish == null then null else $finish.at end),
            final_workflow_outcome: (if $finish == null then null else $finish.outcome end),
            # Schema 1 has no seal transition and no attributable review
            # delegation, so neither the interval nor any round is derivable
            # from it. Report unavailable rather than reconstruct.
            start_to_seal_ms: null,
            rounds: {implementation: null, independent_review: null,
              remediation: null},
            finish_events: ($finishes | length), events: ($events | length),
            events_after_finish: (($recorded | length) - ($events | length)),
            malformed_lines: (($lines | length) - ($parsed | length)),
            subagent_launches: {total: ($launches | length),
              by_role: (reduce $roles[] as $role ({};
                .[$role] = ([$launches[] | select(.role == $role)] | length)))},
            reviews: {total: ($reviews | length),
              by_kind: (reduce $kinds[] as $kind ({};
                .[$kind] = ([$reviews[] | select(.kind == $kind)] | length))),
              input_bytes: ([$reviews[] | .input_bytes] | add // 0)},
            validations: {total: ($starts | length),
              passed: ([$ends[] | select(.outcome == "passed")] | length),
              failed: ([$ends[] | select(.outcome == "failed")] | length),
              interrupted: ([$ends[] | select(.outcome == "interrupted")] | length),
              incomplete: ([$starts[]
                | select(.exec_id as $id | ($ended_ids | index($id)) == null)] | length),
              duration_ms: ([$ends[] | .duration_ms] | add // 0)},
            phase_elapsed_ms: (reduce $phases[] as $phase ({};
              ([$events[] | select(.phase == $phase) | .epoch_ms]) as $stamps
              | if ($stamps | length) > 0
                then .[$phase] = (($stamps | max) - ($stamps | min)) else . end)),
            tokens: {input: ([$token_launches[] | .tokens_in // 0] | add // 0),
              output: ([$token_launches[] | .tokens_out // 0] | add // 0),
              coverage: (if ($token_launches | length) == 0 then "none"
                elif ($token_launches | length) == ($launches | length)
                then "complete" else "partial" end)}
          }
      ' <"$summary_run_file"
      exit 0
    fi

    active_schema=2
    [[ "$observed_schemas" == '[3]' ]] && active_schema=3
    resolve_repository_identity
    jq -n -R -c \
      --arg run "$run_id" --arg repository "$normalized_repository" \
      --argjson active_schema "$active_schema" \
      --argjson terminal_newline_missing "$terminal_newline_missing" \
      --argjson launch_roles "$(printf '%s\n' "${launch_roles[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
      --argjson review_roles "$(printf '%s\n' "${review_roles[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
      --argjson kinds "$(printf '%s\n' "${review_kinds[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
      --argjson phases "$(printf '%s\n' "${phases[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" '
      def integer: type == "number" and floor == .;
      def nonnegative: integer and . >= 0;
      def only_keys($allowed): ((keys - $allowed) | length) == 0;
      def sequence_id($prefix; $index):
        ($index | tostring) as $number
        | $run + "-" + $prefix
          + (if ($number | length) == 1 then "00" + $number
             elif ($number | length) == 2 then "0" + $number
             else $number end);
      def token_totals($observations):
        reduce ($observations[] | select(has("tokens"))) as $observation
          ({total_input:0,cached_input:0,cache_write_input:0,
            fresh_input:0,output:0,reasoning_output:0};
            .total_input += $observation.tokens.total_input
            | .cached_input += $observation.tokens.cached_input
            | .cache_write_input += $observation.tokens.cache_write_input
            | .fresh_input += ($observation.tokens.total_input
                - $observation.tokens.cached_input
                - $observation.tokens.cache_write_input)
            | .output += $observation.tokens.output
            | .reasoning_output += $observation.tokens.reasoning_output);
      def observation_view:
        {scope, model, effort,
          tokens: (if has("tokens") then .tokens + {
            fresh_input: (.tokens.total_input - .tokens.cached_input
              - .tokens.cache_write_input)} else null end)}
        | with_entries(select(.value != null));
      def envelope:
        type == "object" and .schema == $active_schema
        and (.run | type == "string"
          and test("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$"))
        and (.seq | integer and . > 0)
        and (.at | type == "string"
          and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
        and (.epoch_ms | nonnegative)
        and (.type | type == "string");
      def event_shape:
        envelope and
        if .type == "run_start" then
          only_keys(["schema","run","seq","at","epoch_ms","type","workflow","repository","issue","head","run_identity","continues_run"])
          and .workflow == "work-on"
          and (.repository | type == "string" and test("^[a-z0-9_.-]+/[a-z0-9_.-]+$"))
          and (.issue | integer and . > 0)
          and (.head | type == "string" and test("^[0-9a-f]{40}$"))
          and (.run_identity | type == "string")
          and ((has("continues_run") | not)
            or (.continues_run | type == "string"
              and test("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$")))
        elif .type == "subagent_launch" then
          only_keys((["schema","run","seq","at","epoch_ms","type","role","phase","round"]
            + (if $active_schema == 3 then ["agent_id"] else ["tokens_in","tokens_out"] end)))
          and (if $active_schema == 3 then
            (.agent_id | type == "string" and test("^" + $run + "-a[0-9]{3,}$"))
            else has("agent_id") | not end)
          and (.role == "implementation" or .role == "other")
          and (.phase | type == "string" and IN($phases[]))
          and (.round | nonnegative)
          and ((has("tokens_in") | not) or (.tokens_in | nonnegative))
          and ((has("tokens_out") | not) or (.tokens_out | nonnegative))
        elif .type == "review_delegation" then
          only_keys((["schema","run","seq","at","epoch_ms","type","role","kind","phase","round","base","head","head_is_worktree","input_bytes"]
            + (if $active_schema == 3 then ["agent_id"] else [] end)))
          and (if $active_schema == 3 then
            (.agent_id | type == "string" and test("^" + $run + "-a[0-9]{3,}$"))
            else has("agent_id") | not end)
          and (.role | type == "string" and IN($review_roles[]))
          and (.kind | type == "string" and IN($kinds[]))
          and (.phase | type == "string" and IN($phases[]))
          and (.round | nonnegative)
          and (.base | type == "string" and test("^[0-9a-f]{40}$"))
          and (.head | type == "string" and test("^[0-9a-f]{40}$"))
          and (.head_is_worktree | type == "boolean")
          and (.input_bytes | nonnegative)
        elif .type == "validation_start" then
          only_keys(["schema","run","seq","at","epoch_ms","type","exec_id","command_id","phase","round"])
          and (.exec_id | type == "string"
            and test("^" + $run + "-e[0-9]{3,}$"))
          and (.command_id | type == "string" and length <= 48
            and test("^[a-z][a-z0-9]*(-[a-z0-9]+)*$"))
          and (.phase | type == "string" and IN($phases[]))
          and (.round | nonnegative)
        elif .type == "validation_end" then
          only_keys(["schema","run","seq","at","epoch_ms","type","exec_id","command_id","phase","round","outcome","exit_status","duration_ms"])
          and (.exec_id | type == "string"
            and test("^" + $run + "-e[0-9]{3,}$"))
          and (.command_id | type == "string" and length <= 48
            and test("^[a-z][a-z0-9]*(-[a-z0-9]+)*$"))
          and (.phase | type == "string" and IN($phases[]))
          and (.round | nonnegative) and (.outcome | type == "string")
          and ((.exit_status == null) or (.exit_status | nonnegative))
          and (.duration_ms | nonnegative)
        elif .type == "runtime_observation" then
          only_keys(["schema","run","seq","at","epoch_ms","type","scope","agent_id","model","effort","tokens"])
          and (.scope == "completed-thread" or .scope == "checkpoint-snapshot")
          and (if .scope == "completed-thread" then
            (.agent_id | type == "string" and test("^" + $run + "-a[0-9]{3,}$"))
            else has("agent_id") | not end)
          and ((has("model") and has("effort"))
            or ((has("model") | not) and (has("effort") | not)))
          and ((has("model") | not) or
            ((.model | type == "string" and length > 0 and length <= 64
              and test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))
            and (.effort | IN("none","minimal","low","medium","high","xhigh","max","ultra"))))
          and ((has("tokens") | not) or
            (.tokens | type == "object"
              and only_keys(["total_input","cached_input","cache_write_input","output","reasoning_output"])
              and (.total_input | nonnegative) and (.cached_input | nonnegative)
              and (.cache_write_input | nonnegative) and (.output | nonnegative)
              and (.reasoning_output | nonnegative)
              and (.cached_input + .cache_write_input <= .total_input)
              and (.reasoning_output <= .output)))
          and (has("model") or has("tokens"))
        elif .type == "finding_adjudicated" then
          only_keys(["schema","run","seq","at","epoch_ms","type","finding_id","reviewer_agent_id","class","disposition"])
          and (.finding_id | type == "string" and test("^" + $run + "-f[0-9]{3,}$"))
          and (.reviewer_agent_id | type == "string" and test("^" + $run + "-a[0-9]{3,}$"))
          and (.class == "contract-defect" or .class == "evidence-gap")
          and (.disposition | IN("accepted","rejected","follow-up","unresolved"))
        elif .type == "finding_resolved" then
          only_keys(["schema","run","seq","at","epoch_ms","type","finding_id"])
          and (.finding_id | type == "string" and test("^" + $run + "-f[0-9]{3,}$"))
        elif .type == "outcome_resolved" then
          only_keys(["schema","run","seq","at","epoch_ms","type","outcome"])
          and (.outcome | type == "string")
        elif .type == "run_sealed" then
          only_keys(["schema","run","seq","at","epoch_ms","type"])
        else false end;
      def valid_review:
        (.role == "readiness" and .kind == "readiness" and .phase == "checkpoint")
        or ((.role == "review-standards" or .role == "review-spec" or .role == "closure-sweep")
          and .kind == "full" and (.phase == "gate" or (.role == "closure-sweep" and .phase == "closeout")))
        or ((.role == "review-standards" or .role == "review-spec" or .role == "closure-sweep")
          and .kind == "delta" and .phase == "remediation");
      [inputs] as $lines
      | [$lines[] | fromjson? // empty] as $parsed
      | [$parsed[] | select(type == "object" and .schema == $active_schema)] as $events
      | [$events[] | select(.type == "run_start")] as $starts_run
      | [$events[] | select(.type == "outcome_resolved")] as $resolutions
      | [$events[] | select(.type == "run_sealed")] as $seals
      | [$events[] | select(.type == "subagent_launch")] as $launches
      | [$events[] | select(.type == "review_delegation")] as $reviews
      | ($launches + $reviews) as $agent_events
      | ($launch_roles + $review_roles) as $agent_roles
      | [$events[] | select(.type == "runtime_observation")] as $runtime_observations
      | [$runtime_observations[] | select(.scope == "completed-thread")] as $completed_observations
      | [$completed_observations[] | select(has("tokens"))] as $completed_token_observations
      | ([$runtime_observations[] | select(.scope == "checkpoint-snapshot")] | first) as $primary_observation
      | [$events[] | select(.type == "finding_adjudicated")] as $adjudications
      | [$events[] | select(.type == "finding_resolved")] as $finding_resolutions
      | [$events[] | select(.type == "validation_start")] as $starts
      | [$events[] | select(.type == "validation_end")] as $ends
      | ([($starts[].exec_id), ($ends[].exec_id)] | unique) as $exec_ids
      | ($resolutions | first) as $resolution
      | ($seals | first) as $seal
      | ([$events[] | select(event_shape | not)] | length) as $bad_shapes
      | ([$reviews[] | select(valid_review | not)] | length) as $bad_reviews
      | ([$exec_ids[] as $id
          | [$starts[] | select(.exec_id == $id)] as $matching_starts
          | [$ends[] | select(.exec_id == $id)] as $matching_ends
          | select(($matching_starts | length) > 1
            or ($matching_ends | length) > 1
            or (($matching_starts | length) == 0
              and ($matching_ends | length) > 0)
            or (($matching_starts | length) == 1
              and ($matching_ends | length) == 1
              and $matching_ends[0].seq <= $matching_starts[0].seq))]
          | length) as $bad_pairs
      | ([$exec_ids[] as $id
          | ([$starts[] | select(.exec_id == $id)] | first) as $start
          | ([$ends[] | select(.exec_id == $id)] | first) as $end
          | select($start != null and $end != null
            and ($start.command_id != $end.command_id
              or $start.phase != $end.phase or $start.round != $end.round))]
          | length) as $bad_validation_identity
      | ([$ends[] | select(
          ((.outcome == "passed" and .exit_status == 0)
            or (.outcome == "failed" and (.exit_status | integer and . > 0))
            or (.outcome == "interrupted" and .exit_status == null)) | not)]
          | length) as $bad_completions
      | ([$starts[] | select(.exec_id as $id
          | ([$ends[] | select(.exec_id == $id)] | length) == 0)] | length)
          as $incomplete_validations
      | (([$completed_observations[] as $observation
          | [$agent_events[] | select(.agent_id == $observation.agent_id)] as $origins
          | select(($origins | length) != 1
            or $observation.seq <= ($origins[0].seq // 0))] | length)
        + ([$completed_observations | group_by(.agent_id)[]
            | select(length > 1)] | length)
        + (([$runtime_observations[] | select(.scope == "checkpoint-snapshot")] | length)
            | if . > 1 then . - 1 else 0 end)
        + (if $primary_observation != null and $resolution != null
              and $primary_observation.seq + 1 != $resolution.seq
            then 1 else 0 end)) as $bad_runtime_observations
      | ([$adjudications[] as $finding
          | [$reviews[] | select(.agent_id == $finding.reviewer_agent_id)] as $origins
          | select(($origins | length) != 1
            or $finding.seq <= ($origins[0].seq // 0))] | length) as $bad_finding_origins
      | ([$adjudications | group_by(.finding_id)[] | select(length > 1)] | length) as $duplicate_findings
      | (([$finding_resolutions[] as $resolution_event
          | [$adjudications[] | select(.finding_id == $resolution_event.finding_id
              and .disposition == "accepted"
              and .seq < $resolution_event.seq)] as $accepted
          | select(($accepted | length) != 1)] | length)
        + ([$finding_resolutions | group_by(.finding_id)[]
            | select(length > 1)] | length)) as $bad_finding_resolutions
      | (if $seal == null then 0
         else ([$events[] | select(.seq > $seal.seq)] | length) end) as $after_seal
      | (if $resolution == null then [] else
          [$events[] | select(.seq > $resolution.seq
            and ($seal == null or .seq < $seal.seq)
            and (((.type == "validation_start" or .type == "validation_end") and .phase == "closeout")
              or (.type == "subagent_launch" and .role == "other" and .phase == "closeout")
              | not))] end | length) as $bad_post_resolution
      | ((if (($lines | length) - ($parsed | length)) > 0 then ["MALFORMED_LINE"] else [] end)
        + (if $terminal_newline_missing then ["TERMINAL_NEWLINE_MISSING"] else [] end)
        + (if ([$parsed[] | select(type != "object" or .schema != $active_schema)] | length) > 0 then ["MIXED_SCHEMA"] else [] end)
        + (if ($starts_run | length) != 1 then ["RUN_START_COUNT_INVALID"] else [] end)
        + (if ($starts_run | length) == 1 and
            ($starts_run[0].seq != 1 or $starts_run[0].run != $run
              or $starts_run[0].run_identity != $run
              or $starts_run[0].repository != $repository)
          then ["RUN_START_IDENTITY_INVALID"] else [] end)
        + (if ([$events[] | select(.run != $run)] | length) > 0 then ["RUN_IDENTITY_MISMATCH"] else [] end)
        + (if [$events[].seq] != [range(1; ($events | length) + 1)] then ["SEQUENCE_INVALID"] else [] end)
        + (if $bad_shapes > 0 then ["EVENT_SHAPE_INVALID"] else [] end)
        + (if $bad_reviews > 0 then ["REVIEW_DELEGATION_INVALID"] else [] end)
        + (if $bad_pairs > 0 then ["VALIDATION_PAIR_INVALID"] else [] end)
        + (if $bad_validation_identity > 0 then ["VALIDATION_IDENTITY_MISMATCH"] else [] end)
        + (if $bad_completions > 0 then ["VALIDATION_COMPLETION_INVALID"] else [] end)
        + (if $active_schema == 3 and
            (([$agent_events[].agent_id] | unique | length) != ($agent_events | length)
              or [$agent_events[].agent_id] !=
                [$agent_events | to_entries[]
                  | sequence_id("a"; .key + 1)])
          then ["AGENT_IDENTITY_INVALID"] else [] end)
        + (if $bad_runtime_observations > 0 then ["RUNTIME_OBSERVATION_INVALID"] else [] end)
        + (if $bad_finding_origins > 0 or $duplicate_findings > 0
            or ($active_schema == 3 and [$adjudications[].finding_id] !=
              [$adjudications | to_entries[]
                | sequence_id("f"; .key + 1)])
          then ["FINDING_ADJUDICATION_INVALID"] else [] end)
        + (if $bad_finding_resolutions > 0 then ["FINDING_RESOLUTION_INVALID"] else [] end)
        + (if ($resolutions | length) > 1 then ["OUTCOME_RESOLUTION_COUNT_INVALID"] else [] end)
        + (if ($resolutions | length) == 1
            and ($resolutions[0].outcome | IN("Closes","Progresses","preflight-aborted","abandoned","failed") | not)
          then ["OUTCOME_RESOLUTION_INVALID"] else [] end)
        + (if ($seals | length) > 1 then ["SEAL_COUNT_INVALID"] else [] end)
        + (if ($seals | length) > 0
            and (($resolutions | length) != 1 or $seals[0].seq < $resolutions[0].seq)
          then ["LIFECYCLE_TRANSITION_INVALID"] else [] end)
        + (if $bad_post_resolution > 0 then ["LIFECYCLE_TRANSITION_INVALID"] else [] end)
        + (if $after_seal > 0 then ["EVENT_AFTER_SEAL"] else [] end)
        + (if ($resolutions | length) == 1 and $resolutions[0].outcome == "preflight-aborted"
            and ([$events[] | select(.seq < $resolutions[0].seq
              and ((.type == "subagent_launch" and .role == "implementation")
                or .type == "review_delegation"))] | length) > 0
          then ["PREFLIGHT_ABORT_AFTER_WORK"] else [] end)
        | unique | sort) as $invalid_reasons
      | ((if ($resolutions | length) == 0 then ["OUTCOME_UNRESOLVED"] else [] end)
        + (if ($resolutions | length) == 1 and ($seals | length) == 0 then ["RUN_UNSEALED"] else [] end)
        + (if $incomplete_validations > 0 then ["VALIDATION_INCOMPLETE"] else [] end)
        | unique | sort) as $incomplete_reasons
      | [$launches[] | select(has("tokens_in") or has("tokens_out"))] as $token_launches
      | {
          schema: $active_schema, run: $run,
          repository: ($starts_run[0].repository // null),
          issue: ($starts_run[0].issue // null),
          started_head: ($starts_run[0].head // null),
          continues_run: ($starts_run[0].continues_run // null),
          integrity: (if ($invalid_reasons | length) > 0
            then {state: "invalid", reasons: $invalid_reasons}
            elif ($incomplete_reasons | length) > 0
            then {state: "incomplete", reasons: $incomplete_reasons}
            else {state: "valid", reasons: []} end),
          started_at: ($starts_run[0].at // null),
          outcome_resolved_at: ($resolution.at // null), sealed_at: ($seal.at // null),
          final_workflow_outcome: ($resolution.outcome // null),
          # A seal stamped before its own start describes no interval. Report
          # that it is unavailable rather than clamp, estimate, or fabricate one.
          start_to_seal_ms: (($starts_run[0].epoch_ms // null) as $from
            | ($seal.epoch_ms // null) as $to
            | if $from == null or $to == null or $to < $from then null
              else $to - $from end),
          # Rounds are distinct observed round numbers, not event counts, so
          # Standards, Spec, and a gate closure sweep sharing round 1 are one
          # independent-review round. A gate-phase closure sweep counts; the
          # closeout-phase one, readiness, and delta remediation review do not.
          rounds: {
            implementation: ([$launches[]
              | select(.role == "implementation" and .phase == "implementation")
              | .round | numbers] | unique | length),
            independent_review: ([$reviews[]
              | select(.kind == "full" and .phase == "gate")
              | .round | numbers] | unique | length),
            remediation: ([$launches[]
              | select(.role == "implementation" and .phase == "remediation")
              | .round | numbers] | unique | length)},
          outcome_resolution_events: ($resolutions | length),
          seal_events: ($seals | length), events: ($events | length),
          events_after_seal: $after_seal,
          malformed_lines: (($lines | length) - ($parsed | length)),
          subagent_launches: {total: ($agent_events | length),
            by_role: (reduce $agent_roles[] as $role ({};
              .[$role] = ([$agent_events[] | select(.role == $role)] | length)))},
          review_delegations: {total: ($reviews | length),
            by_role: (reduce $review_roles[] as $role ({};
              .[$role] = ([$reviews[] | select(.role == $role)] | length))),
            by_kind: (reduce $kinds[] as $kind ({};
              .[$kind] = ([$reviews[] | select(.kind == $kind)] | length))),
            input_bytes: ([$reviews[] | .input_bytes | select(nonnegative)]
              | add // 0)},
          validations: {total: ($starts | length),
            passed: ([$ends[] | select(.outcome == "passed")] | length),
            failed: ([$ends[] | select(.outcome == "failed")] | length),
            interrupted: ([$ends[] | select(.outcome == "interrupted")] | length),
            incomplete: $incomplete_validations,
            duration_ms: ([$ends[] | .duration_ms | numbers] | add // 0)},
          phase_elapsed_ms: (reduce $phases[] as $phase ({};
            ([$events[] | select(.phase == $phase) | .epoch_ms | numbers]) as $stamps
            | if ($stamps | length) > 0
              then .[$phase] = (($stamps | max) - ($stamps | min)) else . end)),
          tokens: {input: ([$token_launches[] | .tokens_in // 0 | numbers] | add // 0),
            output: ([$token_launches[] | .tokens_out // 0 | numbers] | add // 0),
            coverage: (if ($token_launches | length) == 0 then "none"
              elif ($token_launches | length) == ($launches | length)
              then "complete" else "partial" end)}
        }
        + (if $active_schema == 3 then {
            agents: [$agent_events[]
              | {agent_id, role, phase, round}
                + (if .type == "review_delegation" then {kind} else {} end)],
            model_configurations: ([$runtime_observations[]
              | select(has("model")) | {model, effort}]
              | group_by([.model, .effort])
              | map({model: .[0].model, effort: .[0].effort,
                  observations: length})),
            runtime_observations: {
              primary: (if $primary_observation == null then null
                else ($primary_observation | observation_view) end),
              completed: {
                observed: ($completed_token_observations | length),
                runtime_observed: ($completed_observations | length),
                total_agents: ($agent_events | length),
                coverage: (if ($completed_token_observations | length) == 0 then "none"
                  elif ($completed_token_observations | length) == ($agent_events | length)
                  then "complete" else "partial" end),
                tokens: token_totals($completed_observations),
                by_agent: [$completed_observations[] as $observation
                  | $agent_events[]
                  | select(.agent_id == $observation.agent_id)
                  | {agent_id, role,
                      model: ($observation.model // null),
                      effort: ($observation.effort // null),
                      tokens: (($observation | observation_view).tokens // null)}
                    | with_entries(select(.value != null))],
                by_role: (reduce $agent_roles[] as $role ({};
                  ([$completed_observations[] as $observation
                    | $agent_events[]
                    | select(.agent_id == $observation.agent_id and .role == $role)
                    | $observation]) as $role_observations
                  | .[$role] = {
                      observed: ([$role_observations[] | select(has("tokens"))] | length),
                      tokens: token_totals($role_observations)
                    }))
              }
            },
            findings: {
              resolved: ($finding_resolutions | length),
              rejected: ([$adjudications[]
                | select(.disposition == "rejected")] | length),
              by_reviewer: [$reviews[] as $reviewer
                | {agent_id: $reviewer.agent_id, role: $reviewer.role,
                    accepted: ([$adjudications[]
                      | select(.reviewer_agent_id == $reviewer.agent_id
                        and .disposition == "accepted")] | length),
                    rejected: ([$adjudications[]
                      | select(.reviewer_agent_id == $reviewer.agent_id
                        and .disposition == "rejected")] | length),
                    follow_up: ([$adjudications[]
                      | select(.reviewer_agent_id == $reviewer.agent_id
                        and .disposition == "follow-up")] | length),
                    unresolved: ([$adjudications[]
                      | select(.reviewer_agent_id == $reviewer.agent_id
                        and .disposition == "unresolved")] | length)}]
            }
          } else {} end)
    ' <"$summary_run_file"
    ;;

  *)
    usage
    ;;
esac
