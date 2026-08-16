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

readonly schema_version=1
readonly roles=(
  implementation
  readiness
  review-standards
  review-spec
  closure-sweep
  other
)
readonly review_kinds=(readiness full delta)
readonly phases=(orient implementation checkpoint gate remediation closeout)
readonly run_outcomes=(Closes Progresses aborted)

fail() {
  printf 'run telemetry: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: run-telemetry.sh <subcommand>
  start                                     begin a run; prints its bound handle
  launch --run HANDLE --role R --phase P --round N [--tokens-in N] [--tokens-out N]
  review --run HANDLE --kind K --phase P --round N --base REF (--head REF | --worktree)
  exec --run HANDLE --command-id ID --phase P --round N -- <command...>
                                            run and time a validation command
  finish --run HANDLE --outcome (Closes|Progresses|aborted)
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
resolve_summary_run() {
  local handle="$1" legacy_run_file
  [[ -n "$handle" ]] || fail "operation requires --run"
  if [[ "$handle" =~ $run_handle_pattern ]]; then
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

open_sink() {
  sink_run_file="$runs_root/$1.jsonl"
  exec {sink_lock_fd}>>"$sink_run_file"
  flock -x "$sink_lock_fd" \
    || fail "could not lock the telemetry sink: $sink_run_file"
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
  open_sink "$1"
  write_event "$@"
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
    [[ "$#" -eq 0 ]] || usage
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
    head_sha="$(git rev-parse --verify HEAD 2>/dev/null || printf '')"
    append_event "$run_id" run_start "$(
      jq -cn --arg head "$head_sha" \
        '{workflow: "work-on"} + (if $head == "" then {} else {head: $head} end)'
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
        --tokens-in) tokens_in="${2:?--tokens-in requires a value}"; shift 2 ;;
        --tokens-out) tokens_out="${2:?--tokens-out requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_run_handle "$run_id"
    require_enum role "$role" "${roles[@]}"
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    # Token counts are optional: a runtime that does not expose them records a
    # launch without them rather than failing or inventing a number.
    [[ -z "$tokens_in" ]] || require_count tokens-in "$tokens_in"
    [[ -z "$tokens_out" ]] || require_count tokens-out "$tokens_out"
    append_event "$run_id" subagent_launch "$(
      jq -cn \
        --arg role "$role" --arg phase "$phase" --argjson round "$round" \
        --arg tokens_in "$tokens_in" --arg tokens_out "$tokens_out" \
        '{role: $role, phase: $phase, round: $round}
          + (if $tokens_in == "" then {} else {tokens_in: ($tokens_in | tonumber)} end)
          + (if $tokens_out == "" then {} else {tokens_out: ($tokens_out | tonumber)} end)'
    )"
    ;;

  review)
    run_id=""
    kind=""
    phase=""
    round=""
    base=""
    head_ref=""
    worktree=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
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
    require_enum kind "$kind" "${review_kinds[@]}"
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    [[ -n "$base" ]] || fail "review requires --base"
    if [[ "$worktree" == true ]]; then
      [[ -z "$head_ref" ]] || fail "review takes --head or --worktree, not both"
      head_ref=HEAD
    else
      [[ -n "$head_ref" ]] || fail "review requires --head or --worktree"
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
    append_event "$run_id" review "$(
      jq -cn \
        --arg kind "$kind" --arg phase "$phase" --argjson round "$round" \
        --arg base "$base_sha" --arg head "$head_sha" \
        --argjson worktree "$worktree" --argjson input_bytes "$input_bytes" \
        '{kind: $kind, phase: $phase, round: $round, base: $base, head: $head,
          head_is_worktree: $worktree, input_bytes: $input_bytes}'
    )"
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
    open_sink "$run_id"
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
      append_event "$run_id" validation_end "$(
        jq -cn \
          --arg exec_id "$exec_id" --arg command_id "$command_id" \
          --arg phase "$phase" --argjson round "$round" \
          --arg outcome "$outcome" --argjson exit_status "$status" \
          --argjson duration_ms "$(( $(now_ms) - started_ms ))" \
          '{exec_id: $exec_id, command_id: $command_id,
            phase: $phase, round: $round, outcome: $outcome,
            exit_status: $exit_status, duration_ms: $duration_ms}'
      )"
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

  finish)
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
    # `run_finish` and writing this one happen under a single lock, so two
    # closers cannot both find none and both write.
    open_sink "$run_id"
    finish_count="$(
      jq -n -R '[inputs | fromjson? // empty
        | select(type == "object" and .type == "run_finish")] | length' \
        <"$sink_run_file"
    )"
    if [[ "$finish_count" -ne 0 ]]; then
      close_sink
      fail "run $run_id already recorded its final outcome"
    fi
    write_event "$run_id" run_finish "$(
      jq -cn --arg outcome "$outcome" '{outcome: $outcome}'
    )"
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
    # Aggregation is a pure function of one run's sink: enumerated keys in a
    # fixed order, and lines that are not this run's schema-1 JSON ignored.
    #
    # A finished run's summary is final, not a snapshot of the moment it was
    # asked for. The window closes at `run_finish`, so the same finished run
    # always summarizes to the same document however often it is rendered, and
    # anything recorded afterwards is reported as `events_after_finish` rather
    # than folded into counts the closeout body already published.
    jq -n -R -c \
      --argjson schema "$schema_version" \
      --arg run "$run_id" \
      --argjson roles "$(printf '%s\n' "${roles[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
      --argjson kinds "$(printf '%s\n' "${review_kinds[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
      --argjson phases "$(printf '%s\n' "${phases[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" '
      [inputs | select(length > 0)] as $lines
      | [$lines[] | fromjson? // empty] as $parsed
      | [$parsed[] | select(type == "object" and .run == $run and .schema == $schema)] as $recorded
      | [$recorded[] | select(.type == "run_finish")] as $finishes
      | ($finishes | first) as $finish
      | (if $finish == null then null else ($finish.seq // 0) end) as $final_seq
      | [$recorded[]
        | select($final_seq == null or (.seq // 0) <= $final_seq)] as $events
      | [$events[] | select(.type == "subagent_launch")] as $launches
      | [$events[] | select(.type == "review")] as $reviews
      | [$events[] | select(.type == "validation_start")] as $starts
      | [$events[] | select(.type == "validation_end")] as $ends
      | ([$ends[] | .exec_id] | unique) as $ended_ids
      | [$launches[] | select(has("tokens_in") or has("tokens_out"))] as $token_launches
      | {
          schema: $schema,
          run: $run,
          started_at: ([$events[] | select(.type == "run_start") | .at] | first),
          finished_at: (if $finish == null then null else $finish.at end),
          final_workflow_outcome:
            (if $finish == null then null else $finish.outcome end),
          finish_events: ($finishes | length),
          events: ($events | length),
          events_after_finish: (($recorded | length) - ($events | length)),
          malformed_lines: (($lines | length) - ($parsed | length)),
          subagent_launches: {
            total: ($launches | length),
            by_role: (reduce $roles[] as $role ({};
              .[$role] = ([$launches[] | select(.role == $role)] | length)))
          },
          reviews: {
            total: ($reviews | length),
            by_kind: (reduce $kinds[] as $kind ({};
              .[$kind] = ([$reviews[] | select(.kind == $kind)] | length))),
            input_bytes: ([$reviews[] | .input_bytes] | add // 0)
          },
          validations: {
            total: ($starts | length),
            passed: ([$ends[] | select(.outcome == "passed")] | length),
            failed: ([$ends[] | select(.outcome == "failed")] | length),
            interrupted: ([$ends[] | select(.outcome == "interrupted")] | length),
            incomplete: ([$starts[]
              | select(.exec_id as $id | ($ended_ids | index($id)) == null)]
              | length),
            duration_ms: ([$ends[] | .duration_ms] | add // 0)
          },
          phase_elapsed_ms: (reduce $phases[] as $phase ({};
            ([$events[] | select(.phase == $phase) | .epoch_ms]) as $stamps
            | if ($stamps | length) > 0
              then .[$phase] = (($stamps | max) - ($stamps | min))
              else . end)),
          tokens: {
            input: ([$token_launches[] | .tokens_in // 0] | add // 0),
            output: ([$token_launches[] | .tokens_out // 0] | add // 0),
            coverage:
              (if ($token_launches | length) == 0 then "none"
               elif ($token_launches | length) == ($launches | length) then "complete"
               else "partial" end)
          }
        }
    ' <"$summary_run_file"
    ;;

  *)
    usage
    ;;
esac
