#!/usr/bin/env bash
set -euo pipefail

# Track one work-on run's lifecycle obligation outside the repository it ran in,
# so an interrupted or forgotten run stays visible after its worktree, branch, or
# clone is gone.
#
# The registry is an index over runs, never a second source of truth for what a
# run did. The sink under the repository's Git common directory stays canonical:
# every lifecycle fact here is projected from that sink's own deterministic
# summary, and no registry command invents one.
#
# The registry is bounded metadata only. It holds enumerated lifecycle states,
# an issue number, a normalized repository slug, resolved identifiers, two
# filesystem locators, and hashes of the sink's summary and of the transition
# being finalized. It has no field for a prompt, a diff, a command line, an
# output, a credential, or a reviewer's prose, and every record is validated
# against that closed shape before it is written, so such material cannot be
# stored even by mistake.
#
# Whether a run carries a finalization obligation is decided by an optional
# external observer program. This script knows only two bounded tokens from it —
# an observer id and a control id — and nothing about any experiment those
# tokens belong to.

readonly record_schema=1
readonly lifecycle_states=(active resolved sealed)
readonly finalization_states=(pending finalizing finalized failed unreproducible)
readonly run_outcomes=(Closes Progresses preflight-aborted abandoned failed)
readonly failure_codes=(
  OUTCOME_UNRESOLVED OUTCOME_CONFLICT RESOLVE_FAILED SEAL_FAILED
  INTEGRITY_INCOMPLETE INTEGRITY_INVALID SUMMARY_FAILED IDENTITY_MISMATCH
  OBSERVER_FAILED OBSERVER_IDENTITY_MISMATCH SINK_MISSING REPOSITORY_MISSING
)
readonly default_capacity=512
readonly default_retention_days=30
# The outcome the guard prescribes for a run that was interrupted before it
# resolved one. Recovery never guesses an outcome on its own; this is the
# explicit, documented one its printed command supplies.
readonly interrupted_run_outcome=abandoned

fail() {
  printf 'run registry: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: run-registry.sh <subcommand>
  register --run HANDLE                     record the run's lifecycle obligation
  finalize --run HANDLE [--outcome O]       seal and discharge the obligation
  recover (--run HANDLE | --all) [--outcome O]
                                            idempotently finish the same run
  status [--run HANDLE] [--repository R] [--issue N] [--pending]
  prune [--older-than-days N]               drop retained ungoverned records

HANDLE is the repository-bound handle printed by run-telemetry.sh start.
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

command -v git >/dev/null 2>&1 || fail "run registry requires git"
command -v jq >/dev/null 2>&1 || fail "run registry requires jq"
command -v flock >/dev/null 2>&1 || fail "run registry requires flock"

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly telemetry_script="$script_root/run-telemetry.sh"
readonly registry_script="$script_root/run-registry.sh"
[[ -x "$telemetry_script" ]] || fail "run telemetry script is missing"

# User-level state and policy are user-level: a root is used only when it is
# absolute. A relative override would otherwise be interpreted against the
# working directory, which is the target repository — putting the registry
# inside the clone it must outlive, or letting repository content become the
# observer program. Such an override is refused rather than reinterpreted.
require_absolute_root() {
  local name="$1" value="$2"
  [[ "$value" == /* ]] \
    || fail "$name must be an absolute path when set; refusing to resolve it against the working directory"
}

resolve_user_root() {
  local name="$1" fallback_suffix="$2" value="${3:-}"
  if [[ -n "$value" ]]; then
    require_absolute_root "$name" "$value"
    printf '%s\n' "$value"
    return 0
  fi
  require_absolute_root HOME "${HOME:-}"
  printf '%s/%s\n' "$HOME" "$fallback_suffix"
}

state_home="$(resolve_user_root XDG_STATE_HOME .local/state "${XDG_STATE_HOME:-}")"
config_home="$(resolve_user_root XDG_CONFIG_HOME .config "${XDG_CONFIG_HOME:-}")"
registry_root="$state_home/work-on/registry"
runs_root="$registry_root/runs"
registry_lock="$registry_root/registry.lock"

readonly run_id_pattern='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'
readonly run_handle_pattern='^([0-9]{8}T[0-9]{6}Z-[0-9a-f]{8})@([0-9a-f]{32})$'
# The documented observer token grammar: alphanumeric words joined by single
# hyphens, so a leading, trailing, or doubled hyphen is not a token.
readonly token_pattern='^[a-z0-9]+(-[a-z0-9]+)*$'
readonly token_max_length=64

capacity="${WORK_ON_REGISTRY_CAPACITY:-$default_capacity}"
[[ "$capacity" =~ ^[1-9][0-9]*$ ]] \
  || fail "WORK_ON_REGISTRY_CAPACITY must be a positive integer"

# The registry records what a workstation's runs owe, so it is created for its
# owner only. The umask closes the window between creation and the chmod; the
# chmod also tightens anything an earlier version left readable.
create_private_dir() {
  [[ -d "$1" ]] || (umask 077 && mkdir -p "$1")
  chmod 700 "$1"
}

create_private_file() {
  [[ -e "$1" ]] || (umask 077 && : >"$1")
  chmod 600 "$1"
}

ensure_registry_root() {
  create_private_dir "$registry_root"
  create_private_dir "$runs_root"
  create_private_file "$registry_lock"
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

now_epoch() {
  date -u +%s
}

sha256_of_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    fail "run registry requires sha256sum or shasum"
  fi
}

# --- identity ---------------------------------------------------------------
#
# A run id is unique only within the repository that minted it: #70 keeps two
# repositories able to hold the same textual id, and pairs it with an opaque
# repository binding to tell them apart. The registry key is that whole bound
# handle, so one repository's record can never be selected, mutated, locked,
# evicted, or finalized through another repository's identically named run.

record_key=""
record_run_id=""
record_binding=""
parse_handle() {
  local handle="$1"
  [[ -n "$handle" ]] || fail "operation requires --run"
  [[ "$handle" =~ $run_handle_pattern ]] || fail "run handle is malformed"
  record_run_id="${BASH_REMATCH[1]}"
  record_binding="${BASH_REMATCH[2]}"
  record_key="$record_run_id@$record_binding"
}

handle_of_record() {
  printf '%s@%s\n' "$(record_field "$1" run_id)" \
    "$(record_field "$1" repository_binding)"
}

record_path() {
  printf '%s/%s.json\n' "$runs_root" "$1"
}

record_lock_path() {
  printf '%s/%s.lock\n' "$runs_root" "$1"
}

# One closed shape, checked on the way in. A record that does not match it is
# never written, so a later reader can trust the field set as well as the
# values — including that a projected lifecycle and outcome cannot contradict
# each other.
readonly record_validator='
  def token: type == "string" and (length <= 64)
    and test("^[a-z0-9]+(-[a-z0-9]+)*$");
  def locator: type == "string" and (length > 0) and (length <= 4096)
    and startswith("/") and (test("[\\n\\r\\t]") | not);
  def stamp: type == "string"
    and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
  def digest: type == "string" and test("^[0-9a-f]{64}$");
  type == "object"
  and (keys == [
    "control_id","failure_code","finalization","finalization_id","issue",
    "lifecycle","observer","outcome","registered_at","repository",
    "repository_binding","run_id","schema","sink","summary_sha256",
    "telemetry_schema","updated_at","updated_epoch","worktree"])
  and .schema == 1
  and (.run_id | type == "string" and test("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$"))
  and (.repository | type == "string" and test("^[a-z0-9_.-]+/[a-z0-9_.-]+$"))
  and (.issue | type == "number" and floor == . and . > 0)
  and .telemetry_schema == 2
  and (.sink | locator) and (.worktree | locator)
  and (.repository_binding | type == "string" and test("^[0-9a-f]{32}$"))
  and (.lifecycle | IN($lifecycles[]))
  and (.outcome == null or (.outcome | IN($outcomes[])))
  and (.summary_sha256 == null or (.summary_sha256 | digest))
  and (.finalization_id == null or (.finalization_id | digest))
  and (.finalization | IN($finalizations[]))
  and (.observer == null or (.observer | token))
  and (.control_id == null or (.control_id | token))
  and (.registered_at | stamp) and (.updated_at | stamp)
  and (.updated_epoch | type == "number" and floor == . and . >= 0)
  and (.failure_code == null or (.failure_code | IN($failure_codes[])))
  and (if .lifecycle == "active" then .outcome == null else .outcome != null end)
  and (.finalization != "finalized"
    or (.lifecycle == "sealed" and .outcome != null
      and .summary_sha256 != null))
'

jq_string_array() {
  printf '%s\n' "$@" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

validate_record() {
  jq -e \
    --argjson lifecycles "$(jq_string_array "${lifecycle_states[@]}")" \
    --argjson finalizations "$(jq_string_array "${finalization_states[@]}")" \
    --argjson outcomes "$(jq_string_array "${run_outcomes[@]}")" \
    --argjson failure_codes "$(jq_string_array "${failure_codes[@]}")" \
    "$record_validator" >/dev/null
}

# Records are replaced whole, never appended to: a reader sees either the
# previous record or the next one. The staged file is tracked so an interrupted
# writer cannot leave an artifact behind, and cleanup reaps any that a killed
# writer still managed to strand.
staged_record_file=""
remove_staged_record_file() {
  [[ -z "$staged_record_file" ]] || rm -f "$staged_record_file"
  staged_record_file=""
}

# The observer's answer is captured outside the registry and the telemetry sink,
# and never outlives the command that asked for it.
observer_capture_file=""
remove_observer_capture_file() {
  [[ -z "$observer_capture_file" ]] || rm -f "$observer_capture_file"
  observer_capture_file=""
}

remove_temporary_artifacts() {
  remove_staged_record_file
  remove_observer_capture_file
}
trap remove_temporary_artifacts EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

write_record() {
  local key="$1" body="$2"
  printf '%s' "$body" | validate_record \
    || fail "refusing to write a registry record outside its bounded shape"
  staged_record_file="$(record_path "$key").staged.$$"
  create_private_file "$staged_record_file"
  printf '%s\n' "$body" >"$staged_record_file"
  mv -f "$staged_record_file" "$(record_path "$key")"
  staged_record_file=""
}

read_record() {
  local file
  file="$(record_path "$1")"
  [[ -f "$file" ]] || return 1
  cat "$file"
}

record_field() {
  jq -r --arg field "$2" '.[$field] // "" | tostring' <<<"$1"
}

# --- locking ----------------------------------------------------------------
#
# One order, everywhere: the registry lock is taken before a record lock, and
# never the other way round, so no cycle exists.
#
#   * a record transition holds the registry lock SHARED for its whole command,
#     then its own record lock exclusively;
#   * admission, eviction, and retention hold the registry lock EXCLUSIVE.
#
# Cleanup therefore cannot run while any transition is in flight, a row can
# never be unlinked underneath a live holder, and a lock pathname can never be
# split into two independent lock domains.

registry_lock_fd=""
lock_registry() {
  local mode="$1"
  exec {registry_lock_fd}>>"$registry_lock"
  flock "$mode" "$registry_lock_fd" || fail "could not lock the run registry"
}

unlock_registry() {
  [[ -n "$registry_lock_fd" ]] || return 0
  exec {registry_lock_fd}>&-
  registry_lock_fd=""
}

record_lock_fd=""
lock_record() {
  local key="$1"
  create_private_file "$(record_lock_path "$key")"
  exec {record_lock_fd}>>"$(record_lock_path "$key")"
  flock -x "$record_lock_fd" || fail "could not lock registry record $key"
}

unlock_record() {
  [[ -n "$record_lock_fd" ]] || return 0
  exec {record_lock_fd}>&-
  record_lock_fd=""
}

# Removal happens only under the exclusive registry lock, and still takes the
# record's own lock first: a row is never unlinked while any holder of its
# transition lock can exist.
remove_record() {
  local key="$1" victim_fd
  create_private_file "$(record_lock_path "$key")"
  exec {victim_fd}>>"$(record_lock_path "$key")"
  if ! flock -x -n "$victim_fd"; then
    exec {victim_fd}>&-
    return 1
  fi
  rm -f "$(record_path "$key")"
  exec {victim_fd}>&-
  rm -f "$(record_lock_path "$key")"
  return 0
}

reap_staged_records() {
  local staged
  shopt -s nullglob
  for staged in "$runs_root"/*.staged.*; do
    rm -f "$staged"
  done
  shopt -u nullglob
}

all_records() {
  local file
  shopt -s nullglob
  for file in "$runs_root"/*.json; do
    cat "$file"
  done
  shopt -u nullglob
}

# --- the observer seam ------------------------------------------------------
#
# Policy lives in an external program. It is asked one question — does this
# repository/issue carry an obligation — and answers with exactly two bounded
# lines or a refusal. Anything else is a policy error, and a run that might be
# governed is never allowed to proceed on a guess.

observer_program=""
resolve_observer_program() {
  local candidate="${WORK_ON_OBSERVER:-}"
  if [[ -n "$candidate" ]]; then
    require_absolute_root WORK_ON_OBSERVER "$candidate"
    [[ -x "$candidate" ]] || fail "observer program is not executable: $candidate"
    observer_program="$candidate"
    return 0
  fi
  candidate="$config_home/work-on/observer"
  [[ -x "$candidate" ]] && observer_program="$candidate"
  return 0
}

# Exactly one observer= line and one control= line, each a token in the
# documented grammar, and no other non-empty output. An extra line, a repeated
# key, an unknown key, or an edge-form token is a policy error.
parse_applicability_answer() {
  local output="$1" line key value seen_observer=false seen_control=false
  observer_id=""
  control_id=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ "$line" == *=* ]] || return 1
    [[ "${#value}" -le "$token_max_length" ]] || return 1
    [[ "$value" =~ $token_pattern ]] || return 1
    case "$key" in
      observer)
        [[ "$seen_observer" == false ]] || return 1
        seen_observer=true
        observer_id="$value"
        ;;
      control)
        [[ "$seen_control" == false ]] || return 1
        seen_control=true
        control_id="$value"
        ;;
      *) return 1 ;;
    esac
  done <<<"$output"
  [[ "$seen_observer" == true && "$seen_control" == true ]] || return 1
  return 0
}

observer_id=""
control_id=""
observer_applicability_error=""

# The answer is captured as bytes, not as shell text. Command substitution
# silently discards a NUL, which would let material outside the closed grammar
# disappear before it could be rejected, so the program writes to an owner-only
# temporary file that is inspected for NUL first and removed on every exit path.
probe_observer_applicability() {
  local repository="$1" issue="$2" status=0 raw_bytes text_bytes
  observer_id=""
  control_id=""
  observer_applicability_error=""
  resolve_observer_program
  [[ -n "$observer_program" ]] || return 0

  observer_capture_file="$( (umask 077 && mktemp "${TMPDIR:-/tmp}/work-on-applies.XXXXXX") )" \
    || { observer_applicability_error="could not capture the observer's answer"
      return 1; }
  chmod 600 "$observer_capture_file"
  "$observer_program" applies --repository "$repository" --issue "$issue" \
    >"$observer_capture_file" 2>/dev/null || status=$?
  case "$status" in
    0) ;;
    3) remove_observer_capture_file; return 0 ;;
    *)
      remove_observer_capture_file
      observer_applicability_error="observer policy could not decide whether this run is governed"
      return 1
      ;;
  esac
  raw_bytes="$(wc -c <"$observer_capture_file")"
  text_bytes="$(tr -d '\0' <"$observer_capture_file" | wc -c)"
  if [[ "$raw_bytes" -ne "$text_bytes" ]]; then
    remove_observer_capture_file
    observer_applicability_error="observer policy returned a malformed applicability answer"
    return 1
  fi
  if ! parse_applicability_answer "$(cat "$observer_capture_file")"; then
    remove_observer_capture_file
    observer_id=""
    control_id=""
    observer_applicability_error="observer policy returned a malformed applicability answer"
    return 1
  fi
  remove_observer_capture_file
  return 0
}

# Admission cannot proceed on an undecided policy, so it turns a probe failure
# into a refusal. Finalization records the outstanding obligation instead, and
# therefore probes directly.
resolve_observer_applicability() {
  probe_observer_applicability "$1" "$2" || fail "$observer_applicability_error"
}

# The transition identity an observer deduplicates on. It is derived from the
# run's immutable bound identity plus the transition being finalized, so every
# retry of the same finalization presents the same value and a genuinely
# different transition cannot reuse it.
finalization_identity() {
  local key="$1" repository="$2" issue="$3" outcome="$4" summary_sha256="$5"
  printf 'work-on-finalize\0%s\0%s\0%s\0%s\0%s' \
    "$key" "$repository" "$issue" "$outcome" "$summary_sha256" | sha256_of_stdin
}

# The obligation belongs to the observer and control the run registered with,
# not to whichever program happens to be configured now. Applicability is
# re-established through the same closed interface and must name that exact
# pair; anything else leaves the original obligation outstanding.
observer_identity_matches_record() {
  local repository="$1" issue="$2" stored_observer="$3" stored_control="$4"
  probe_observer_applicability "$repository" "$issue" || return 1
  [[ "$observer_id" == "$stored_observer" && "$control_id" == "$stored_control" ]]
}

# Delivery is at-least-once: the intended transition is recorded durably before
# the observer is called, so a crash after acceptance replays the same identity
# instead of inventing a second transition. A record naming a control owes that
# observer something, so an unreachable observer leaves the obligation
# outstanding rather than discharging it against nothing.
notify_observer_finalized() {
  local key="$1" transition="$2"
  [[ -n "$control_id" ]] || return 0
  [[ -n "$observer_program" ]] || return 1
  "$observer_program" finalize --record "$(record_path "$key")" \
    --transition "$transition" >/dev/null 2>&1
}

# --- canonical sink facts ---------------------------------------------------
#
# Everything the registry knows about a run's lifecycle comes from here. The
# projection is refreshed after every successful sink transition, so a record
# written on a failure path still carries what the sink had already established.

summary_json=""
sink_lifecycle=""
sink_outcome=""
read_summary() {
  local workdir="$1" handle="$2"
  summary_json=""
  summary_json="$( (cd "$workdir" && "$telemetry_script" summary --run "$handle") 2>/dev/null )" \
    || return 1
  [[ "$(jq -r '.schema' <<<"$summary_json")" == 2 ]] || return 1
  sink_outcome="$(jq -r '.final_workflow_outcome // ""' <<<"$summary_json")"
  if [[ "$(jq -r '.sealed_at // ""' <<<"$summary_json")" != "" ]]; then
    sink_lifecycle=sealed
  elif [[ -n "$sink_outcome" ]]; then
    sink_lifecycle=resolved
  else
    sink_lifecycle=active
  fi
  return 0
}

sink_path_for() {
  printf '%s/work-on-telemetry/runs/%s.jsonl\n' "$1" "$2"
}

# A recovery may run long after the worktree that started the run was removed.
# The record keeps the worktree it started in and the sink's absolute path; the
# sink's location determines the Git common directory, whose own parent is the
# main worktree. Whichever of those still resolves to that same common directory
# can drive the sink's telemetry commands.
resolved_workdir=""
resolve_workdir() {
  local sink="$1" worktree="$2" common_dir candidate observed
  resolved_workdir=""
  common_dir="$(dirname "$(dirname "$(dirname "$sink")")")"
  for candidate in "$worktree" "$(dirname "$common_dir")"; do
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    observed="$(git -C "$candidate" rev-parse --path-format=absolute \
      --git-common-dir 2>/dev/null)" || continue
    [[ "$observed" == "$common_dir" ]] || continue
    resolved_workdir="$candidate"
    return 0
  done
  return 1
}

# --- record construction ----------------------------------------------------

# The record a newly registered run starts from: identity and locators that
# never change again, plus the lifecycle the sink reports right now.
initial_record() {
  local run="$1" repository="$2" issue="$3" sink="$4" worktree="$5"
  local binding="$6" stamp
  stamp="$(now_iso)"
  jq -cn \
    --argjson schema "$record_schema" \
    --arg run_id "$run" --arg repository "$repository" --argjson issue "$issue" \
    --arg sink "$sink" --arg worktree "$worktree" --arg binding "$binding" \
    --arg lifecycle "$sink_lifecycle" --arg outcome "$sink_outcome" \
    --arg observer "$observer_id" --arg control "$control_id" \
    --arg stamp "$stamp" --argjson updated_epoch "$(now_epoch)" \
    'def maybe: if . == "" then null else . end;
     {schema: $schema, run_id: $run_id, repository: $repository, issue: $issue,
      telemetry_schema: 2, sink: $sink, worktree: $worktree,
      repository_binding: $binding, lifecycle: $lifecycle,
      outcome: ($outcome | maybe), summary_sha256: null, finalization_id: null,
      finalization: "pending", observer: ($observer | maybe),
      control_id: ($control | maybe), registered_at: $stamp,
      updated_at: $stamp, updated_epoch: $updated_epoch, failure_code: null}'
}

# Transitions restate the whole record from the one it replaces, so a field this
# transition does not name cannot be lost or silently changed. The lifecycle and
# outcome always come from the sink projection when one is available: a registry
# row may record that processing failed, never a lifecycle fact contradicting
# the sink.
transition_record() {
  local current="$1" finalization="$2" failure_code="$3"
  local summary_sha256="${4:-}" finalization_id="${5:-}"
  local lifecycle="$sink_lifecycle" outcome="$sink_outcome"
  if [[ -z "$lifecycle" ]]; then
    lifecycle="$(record_field "$current" lifecycle)"
    outcome="$(record_field "$current" outcome)"
  fi
  [[ -n "$summary_sha256" ]] \
    || summary_sha256="$(record_field "$current" summary_sha256)"
  [[ -n "$finalization_id" ]] \
    || finalization_id="$(record_field "$current" finalization_id)"
  jq -c \
    --arg lifecycle "$lifecycle" --arg outcome "$outcome" \
    --arg summary_sha256 "$summary_sha256" --arg finalization "$finalization" \
    --arg finalization_id "$finalization_id" \
    --arg failure_code "$failure_code" --arg updated_at "$(now_iso)" \
    --argjson updated_epoch "$(now_epoch)" \
    'def maybe: if . == "" then null else . end;
     .lifecycle = $lifecycle
     | .outcome = ($outcome | maybe)
     | .summary_sha256 = ($summary_sha256 | maybe)
     | .finalization_id = ($finalization_id | maybe)
     | .finalization = $finalization
     | .failure_code = ($failure_code | maybe)
     | .updated_at = $updated_at
     | .updated_epoch = $updated_epoch' <<<"$current"
}

# The one command a caller is told to run next. It carries the bound handle, so
# it can never select another repository's identically named run, and it names
# the outcome when the run was interrupted before resolving one — the state in
# which a bare recovery would otherwise be a dead end.
recovery_command_for() {
  local current="$1" handle
  handle="$(handle_of_record "$current")"
  if [[ -z "$(record_field "$current" outcome)" ]]; then
    printf '%s recover --run %s --outcome %s\n' "$registry_script" "$handle" \
      "$interrupted_run_outcome"
  else
    printf '%s recover --run %s\n' "$registry_script" "$handle"
  fi
}

# --- capacity and retention -------------------------------------------------
#
# A record that nothing governs may always be dropped to make room. A governed
# record may be dropped only once its obligation is discharged. When neither
# frees a slot, admission of a governed run refuses rather than quietly losing
# the evidence an observer still needs.
readonly evictable_filter='.control_id == null or .finalization == "finalized"'

# Eligibility is evaluated, and the victim removed, under the exclusive registry
# lock this caller already holds.
evict_for_capacity() {
  local occupied victim
  occupied="$(all_records | jq -s 'length')"
  while [[ "$occupied" -ge "$capacity" ]]; do
    victim="$(all_records | jq -rs "
      [.[] | select($evictable_filter)]
      | sort_by(.updated_epoch, .run_id)
      | .[0] // empty
      | \"\(.run_id)@\(.repository_binding)\"")"
    [[ -n "$victim" ]] || return 1
    remove_record "$victim" || return 1
    occupied=$(( occupied - 1 ))
  done
  return 0
}

# --- finalization -----------------------------------------------------------
#
# One path drives every ending. It adopts the sink's own resolution when the
# workflow already recorded one, resolves only when the caller supplies the
# outcome for a run that never got that far, seals only if the run is unsealed,
# and claims success only after the sealed sink's own integrity is valid.

# Every way finalization can stop short ends here, with the record reconciled
# from whatever the sink last established. An outstanding obligation exits
# nonzero with the one command that retries it; a run nobody can reproduce has
# nothing left to retry, so it is recorded as such and reported as final.
halt_finalization() {
  local key="$1" current="$2" finalization="$3" code="$4" message="$5" updated
  updated="$(transition_record "$current" "$finalization" "$code")"
  write_record "$key" "$updated"
  unlock_record
  printf 'run registry: %s\n' "$message" >&2
  if [[ "$finalization" == unreproducible ]]; then
    printf 'run registry: run %s is recorded as unreproducible\n' "$key" >&2
    exit 0
  fi
  printf 'run registry: recover with: %s\n' "$(recovery_command_for "$updated")" >&2
  exit 1
}

# An ordinary run that registry admission deliberately skipped still hands back
# through #71's own resolve/seal path, so nothing about it depends on a row that
# was never created. Omitting the registry is all this path omits: the outcome
# assertion, the run's identity, the seal, and schema-2 integrity are required
# here exactly as they are for a registered run, because a caller may not be
# told a hand-back succeeded on weaker terms than #71's.
finalize_unregistered_run() {
  local handle="$1" run_id="$2" requested_outcome="$3" workdir="$4" integrity
  if [[ -n "$sink_outcome" && -n "$requested_outcome" \
    && "$requested_outcome" != "$sink_outcome" ]]; then
    fail "run $run_id already resolved $sink_outcome; refusing to finalize as $requested_outcome"
  fi
  if [[ -z "$sink_outcome" ]]; then
    [[ -n "$requested_outcome" ]] \
      || fail "run $run_id is not registered and has resolved no outcome; supply --outcome"
    (cd "$workdir" && "$telemetry_script" resolve --run "$handle" \
      --outcome "$requested_outcome") >/dev/null \
      || fail "run $run_id could not resolve outcome $requested_outcome"
    read_summary "$workdir" "$handle" \
      || fail "run $run_id has no readable schema-2 summary after resolving"
  fi
  if [[ "$sink_lifecycle" != sealed ]]; then
    (cd "$workdir" && "$telemetry_script" seal --run "$handle") >/dev/null \
      || fail "run $run_id could not be sealed"
  fi
  read_summary "$workdir" "$handle" \
    || fail "run $run_id has no readable schema-2 summary after sealing"
  [[ "$(jq -r '.run' <<<"$summary_json")" == "$run_id" \
    && -n "$(jq -r '.repository // ""' <<<"$summary_json")" ]] \
    || fail "run $run_id does not match the sink its handle selects"
  [[ -z "$requested_outcome" || "$requested_outcome" == "$sink_outcome" ]] \
    || fail "run $run_id resolved $sink_outcome; refusing to finalize as $requested_outcome"
  [[ "$sink_lifecycle" == sealed ]] || fail "run $run_id is not sealed"
  integrity="$(jq -r '.integrity.state' <<<"$summary_json")"
  [[ "$integrity" == valid ]] \
    || fail "run $run_id is sealed but its telemetry integrity is $integrity"
  printf 'finalized %s unregistered\n' "$run_id"
}

# A run that is not registered is only acceptable when nothing observes it: a
# governed run reaching hand-back without a record is exactly the missing
# obligation this mechanism exists to surface.
finalize_without_record() {
  local handle="$1" run_id="$2" requested_outcome="$3" workdir repository issue
  workdir="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || fail "run $run_id is not registered and no repository is available here"
  read_summary "$workdir" "$handle" \
    || fail "run $run_id is not registered and has no readable schema-2 summary"
  repository="$(jq -r '.repository // ""' <<<"$summary_json")"
  issue="$(jq -r '.issue // ""' <<<"$summary_json")"
  resolve_observer_applicability "$repository" "$issue"
  [[ -z "$control_id" ]] \
    || fail "governed run $run_id is not registered; its obligation was never recorded"
  finalize_unregistered_run "$handle" "$run_id" "$requested_outcome" "$workdir"
}

# `--outcome` means different things to the two callers, and the difference is
# what makes the guard's printed command work in every state it can report:
# finalize asserts the outcome (a contradiction is an error), while recover
# offers one only for a run that resolved none.
drive_finalization() {
  local key="$1" requested_outcome="$2" outcome_is_assertion="$3"
  local current sink worktree binding run_id handle transition summary_sha256
  local stored_observer stored_control

  run_id="${key%@*}"
  binding="${key#*@}"
  handle="$run_id@$binding"

  current="$(read_record "$key")" || {
    finalize_without_record "$handle" "$run_id" "$requested_outcome"
    return 0
  }
  lock_record "$key"
  current="$(read_record "$key")" \
    || fail "registry record $key disappeared before it could be locked"

  # Only an identical retry is idempotent. A finalized run still answers a
  # caller's assertion about it, so a contradictory outcome is refused here
  # rather than acknowledged as success.
  if [[ "$(record_field "$current" finalization)" == finalized ]]; then
    printf '%s' "$current" | validate_record \
      || fail "the finalized record for run $run_id is not internally valid"
    if [[ "$outcome_is_assertion" == true && -n "$requested_outcome" \
      && "$requested_outcome" != "$(record_field "$current" outcome)" ]]; then
      unlock_record
      fail "run $run_id already finalized as $(record_field "$current" outcome); refusing to finalize as $requested_outcome"
    fi
    unlock_record
    printf 'finalized %s\n' "$run_id"
    return 0
  fi

  observer_id="$(record_field "$current" observer)"
  control_id="$(record_field "$current" control_id)"
  resolve_observer_program

  sink="$(record_field "$current" sink)"
  worktree="$(record_field "$current" worktree)"
  sink_lifecycle=""
  sink_outcome=""

  # A vanished clone takes its sink with it, so the repository is asked about
  # first: the narrower code is reserved for a sink that went missing from a
  # repository that is still there.
  resolve_workdir "$sink" "$worktree" \
    || halt_finalization "$key" "$current" unreproducible REPOSITORY_MISSING \
      "run $run_id has no reachable repository for its telemetry sink"
  [[ -f "$sink" ]] \
    || halt_finalization "$key" "$current" unreproducible SINK_MISSING \
      "run $run_id has no telemetry sink at its recorded location"
  read_summary "$resolved_workdir" "$handle" \
    || halt_finalization "$key" "$current" unreproducible SUMMARY_FAILED \
      "run $run_id has no readable schema-2 summary"

  # The sink is canonical for identity too: a row whose repository, issue, or
  # run no longer matches the sink it names is never acted on — and its
  # lifecycle facts are not adopted from a sink that is not its own.
  if [[ "$(jq -r '.run' <<<"$summary_json")" != "$run_id" \
    || "$(jq -r '.repository // ""' <<<"$summary_json")" != \
      "$(record_field "$current" repository)" \
    || "$(jq -r '.issue // ""' <<<"$summary_json")" != \
      "$(record_field "$current" issue)" ]]; then
    sink_lifecycle=""
    sink_outcome=""
    halt_finalization "$key" "$current" failed IDENTITY_MISMATCH \
      "run $run_id does not match the identity recorded for it"
  fi

  # An interrupted finalization is visible as such, so a recovery can tell a
  # crash apart from an obligation nobody has started discharging.
  write_record "$key" "$(transition_record "$current" finalizing \
    "$(record_field "$current" failure_code)")"
  current="$(read_record "$key")"

  if [[ -z "$sink_outcome" ]]; then
    [[ -n "$requested_outcome" ]] \
      || halt_finalization "$key" "$current" failed OUTCOME_UNRESOLVED \
        "run $run_id has resolved no outcome; supply --outcome to finalize it"
    (cd "$resolved_workdir" && "$telemetry_script" resolve --run "$handle" \
      --outcome "$requested_outcome") >/dev/null \
      || halt_finalization "$key" "$current" failed RESOLVE_FAILED \
        "run $run_id could not resolve outcome $requested_outcome"
    read_summary "$resolved_workdir" "$handle" \
      || halt_finalization "$key" "$current" failed SUMMARY_FAILED \
        "run $run_id has no readable schema-2 summary after resolving"
    write_record "$key" "$(transition_record "$current" finalizing "")"
    current="$(read_record "$key")"
  elif [[ "$outcome_is_assertion" == true && -n "$requested_outcome" \
      && "$requested_outcome" != "$sink_outcome" ]]; then
    halt_finalization "$key" "$current" failed OUTCOME_CONFLICT \
      "run $run_id already resolved $sink_outcome; refusing to finalize as $requested_outcome"
  fi

  if [[ "$sink_lifecycle" != sealed ]]; then
    (cd "$resolved_workdir" && "$telemetry_script" seal --run "$handle") \
      >/dev/null \
      || halt_finalization "$key" "$current" failed SEAL_FAILED \
        "run $run_id could not be sealed"
    read_summary "$resolved_workdir" "$handle" \
      || halt_finalization "$key" "$current" failed SUMMARY_FAILED \
        "run $run_id has no readable schema-2 summary after sealing"
    write_record "$key" "$(transition_record "$current" finalizing "")"
    current="$(read_record "$key")"
  fi

  case "$(jq -r '.integrity.state' <<<"$summary_json")" in
    valid) ;;
    incomplete) halt_finalization "$key" "$current" failed INTEGRITY_INCOMPLETE \
      "run $run_id is sealed but its telemetry is incomplete" ;;
    *) halt_finalization "$key" "$current" failed INTEGRITY_INVALID \
      "run $run_id is sealed but its telemetry integrity is not valid" ;;
  esac

  # The canonical summary is the sink's own deterministic aggregate; the record
  # keeps its hash, never a reconstruction of it. The transition identity is
  # written durably before the observer is called, so a crash after acceptance
  # replays the same transition instead of starting a second one.
  summary_sha256="$(printf '%s' "$summary_json" | sha256_of_stdin)"
  transition="$(record_field "$current" finalization_id)"
  [[ -n "$transition" ]] || transition="$(finalization_identity "$key" \
    "$(record_field "$current" repository)" "$(record_field "$current" issue)" \
    "$sink_outcome" "$summary_sha256")"
  write_record "$key" "$(transition_record "$current" finalizing "" \
    "$summary_sha256" "$transition")"
  current="$(read_record "$key")"

  # The obligation is owed to the pair this run registered with. Whatever
  # program is configured now must still identify itself as that pair before it
  # is allowed to discharge it.
  if [[ -n "$control_id" ]]; then
    stored_observer="$observer_id"
    stored_control="$control_id"
    if [[ -z "$observer_program" ]]; then
      halt_finalization "$key" "$current" failed OBSERVER_FAILED \
        "run $run_id is owed to $stored_observer/$stored_control, and no observer policy is reachable"
    fi
    if ! observer_identity_matches_record \
      "$(record_field "$current" repository)" \
      "$(record_field "$current" issue)" "$stored_observer" "$stored_control"; then
      observer_id="$stored_observer"
      control_id="$stored_control"
      halt_finalization "$key" "$current" failed OBSERVER_IDENTITY_MISMATCH \
        "run $run_id is owed to $stored_observer/$stored_control, which the configured observer policy does not identify as"
    fi
  fi

  notify_observer_finalized "$key" "$transition" \
    || halt_finalization "$key" "$current" failed OBSERVER_FAILED \
      "run $run_id was sealed but its observer did not accept the finalization"

  write_record "$key" "$(transition_record "$current" finalized "")"
  unlock_record
  printf 'finalized %s\n' "$run_id"
}

subcommand="${1:-}"
[[ -n "$subcommand" ]] || usage
shift || true

case "$subcommand" in
  register)
    handle=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    parse_handle "$handle"
    run_id="$record_run_id"
    key="$record_key"

    worktree="$(git rev-parse --show-toplevel 2>/dev/null)" \
      || fail "register requires a Git-backed target repository"
    common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
      || fail "could not resolve the repository's Git common directory"
    sink="$(sink_path_for "$common_dir" "$run_id")"
    # The bound handle is resolved by the telemetry sink itself, so a handle
    # belonging to another repository is refused here even when this repository
    # holds a sink with the same textual run id.
    read_summary "$worktree" "$handle" \
      || fail "register requires a schema-2 run in this repository"
    [[ "$(jq -r '.run' <<<"$summary_json")" == "$run_id" ]] \
      || fail "the run handle does not match the sink it selects"
    repository="$(jq -r '.repository // ""' <<<"$summary_json")"
    issue="$(jq -r '.issue // ""' <<<"$summary_json")"
    [[ -n "$repository" && "$issue" =~ ^[1-9][0-9]*$ ]] \
      || fail "run $run_id has no repository/issue identity to register"

    resolve_observer_applicability "$repository" "$issue"

    # A governed run may not proceed on an unrecorded obligation. A run nothing
    # observes owes nobody anything, so a registry problem is reported and the
    # run continues exactly as it would have before the registry existed; its
    # hand-back still completes through the unregistered path above.
    registration_problem() {
      [[ -z "$control_id" ]] || fail "$1"
      printf 'run registry: %s\n' "$1" >&2
      printf 'run registry: run %s continues unregistered\n' "$run_id" >&2
      exit 0
    }

    ensure_registry_root
    lock_registry -x
    reap_staged_records
    existing="$(read_record "$key")" || existing=""

    if [[ -n "$existing" ]]; then
      # A retry is the same run or nothing: every immutable field must agree
      # with the sink this handle selects.
      [[ "$(record_field "$existing" repository)" == "$repository" \
        && "$(record_field "$existing" issue)" == "$issue" \
        && "$(record_field "$existing" sink)" == "$sink" \
        && "$(record_field "$existing" repository_binding)" == "$record_binding" ]] \
        || fail "run $run_id is already registered with a different identity"
      # Applicability is part of that identity. Governance cannot be retrofitted
      # onto a run that already did work under none, nor removed from one that
      # owes an obligation, nor moved to another observer or control.
      registered_observer="$(record_field "$existing" observer)"
      registered_control="$(record_field "$existing" control_id)"
      if [[ "$registered_observer" != "$observer_id" \
        || "$registered_control" != "$control_id" ]]; then
        unlock_registry
        fail "run $run_id is registered to ${registered_observer:-no observer}/${registered_control:-no control}; refusing a retry under ${observer_id:-no observer}/${control_id:-no control}"
      fi
    else
      if [[ -n "$control_id" ]]; then
        # A governed run may not begin while a prior run under the same control
        # still owes its observer a finalization. The scan and this run's
        # admission happen under one exclusive lock, so two competing starts
        # cannot both find no obligation and both be admitted.
        blocking="$(all_records | jq -rs --arg control "$control_id" \
          --arg key "$key" '
          [.[] | select(.control_id == $control
            and ("\(.run_id)@\(.repository_binding)") != $key
            and (.finalization | IN("pending","finalizing","failed")))]
          | sort_by(.updated_epoch, .run_id) | .[0] // empty | tojson')"
        if [[ -n "$blocking" ]]; then
          unlock_registry
          {
            printf 'run registry: a prior observed run has an unfinished obligation\n'
            printf '  run: %s (%s#%s)\n' \
              "$(handle_of_record "$blocking")" \
              "$(record_field "$blocking" repository)" \
              "$(record_field "$blocking" issue)"
            printf '  lifecycle: %s, finalization: %s, failure: %s\n' \
              "$(record_field "$blocking" lifecycle)" \
              "$(record_field "$blocking" finalization)" \
              "$(jq -r '.failure_code // "none"' <<<"$blocking")"
            printf '  recover with: %s\n' "$(recovery_command_for "$blocking")"
          } >&2
          exit 1
        fi

        # Registration must be provably before implementation, and the sink is
        # the only evidence of that. Registry timestamps prove nothing about
        # what the run had already done.
        pristine="$(jq -r '
          if (.subagent_launches.total == 0 and .review_delegations.total == 0
            and .validations.total == 0 and .outcome_resolution_events == 0
            and .seal_events == 0 and .events == 1)
          then "pristine"
          elif .subagent_launches.total > 0 then "subagent launches"
          elif .review_delegations.total > 0 then "reviewer delegations"
          elif .validations.total > 0 then "validation executions"
          elif .outcome_resolution_events > 0 then "a resolved outcome"
          elif .seal_events > 0 then "a seal"
          else "recorded work" end' <<<"$summary_json")"
        [[ "$pristine" == pristine ]] || {
          unlock_registry
          fail "run $run_id already recorded $pristine; a governed run must be registered before implementation"
        }
      fi

      evict_for_capacity || {
        unlock_registry
        registration_problem \
          "registry capacity $capacity is exhausted by unfinished obligations; discharge them with $registry_script recover --all"
      }
      write_record "$key" "$(initial_record "$run_id" "$repository" "$issue" \
        "$sink" "$worktree" "$record_binding")"
    fi

    unlock_registry
    printf 'registered %s observer=%s control=%s\n' "$run_id" \
      "${observer_id:-none}" "${control_id:-none}"
    ;;

  finalize)
    handle=""
    outcome=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        --outcome) outcome="${2:?--outcome requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    parse_handle "$handle"
    [[ -z "$outcome" ]] \
      || contains "$outcome" "${run_outcomes[@]}" \
      || fail "outcome must be one of: ${run_outcomes[*]}"
    ensure_registry_root
    lock_registry -s
    drive_finalization "$record_key" "$outcome" true
    ;;

  recover)
    handle=""
    outcome=""
    recover_all=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        --outcome) outcome="${2:?--outcome requires a value}"; shift 2 ;;
        --all) recover_all=true; shift ;;
        *) usage ;;
      esac
    done
    [[ -z "$outcome" ]] \
      || contains "$outcome" "${run_outcomes[@]}" \
      || fail "outcome must be one of: ${run_outcomes[*]}"
    ensure_registry_root
    lock_registry -s
    if [[ "$recover_all" == true ]]; then
      [[ -z "$handle" ]] || fail "recover takes --all or one run, not both"
      status=0
      # Each run is driven in a subshell, so one run that stops short reports
      # itself and the sweep still reaches the rest.
      while IFS= read -r pending_key; do
        [[ -n "$pending_key" ]] || continue
        ( drive_finalization "$pending_key" "$outcome" false ) || status=1
      done < <(all_records | jq -rs '
        [.[] | select(.finalization | IN("pending","finalizing","failed"))]
        | sort_by(.updated_epoch, .run_id)
        | .[] | "\(.run_id)@\(.repository_binding)"')
      exit "$status"
    fi
    parse_handle "$handle"
    drive_finalization "$record_key" "$outcome" false
    ;;

  status)
    handle=""
    repository=""
    issue=""
    pending_only=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        --repository) repository="${2:?--repository requires a value}"; shift 2 ;;
        --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
        --pending) pending_only=true; shift ;;
        *) usage ;;
      esac
    done
    key=""
    if [[ -n "$handle" ]]; then
      parse_handle "$handle"
      key="$record_key"
    fi
    ensure_registry_root
    lock_registry -s
    all_records | jq -sc \
      --arg key "$key" --arg repository "$repository" --arg issue "$issue" \
      --argjson pending_only "$pending_only" '
      [.[]
        | select($key == "" or ("\(.run_id)@\(.repository_binding)") == $key)
        | select($repository == "" or .repository == $repository)
        | select($issue == "" or (.issue | tostring) == $issue)
        | select(($pending_only | not)
          or (.finalization | IN("pending","finalizing","failed")))]
      | sort_by(.updated_epoch, .run_id) | .[]'
    unlock_registry
    ;;

  prune)
    older_than_days="$default_retention_days"
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --older-than-days) older_than_days="${2:?--older-than-days requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    [[ "$older_than_days" =~ ^(0|[1-9][0-9]*)$ ]] \
      || fail "--older-than-days must be a nonnegative integer"
    ensure_registry_root
    lock_registry -x
    reap_staged_records
    pruned=0
    while IFS= read -r stale_key; do
      [[ -n "$stale_key" ]] || continue
      remove_record "$stale_key" || continue
      pruned=$(( pruned + 1 ))
    done < <(all_records | jq -rs \
      --argjson cutoff "$(( $(now_epoch) - older_than_days * 86400 ))" "
      [.[] | select(($evictable_filter) and .updated_epoch <= \$cutoff)]
      | .[] | \"\(.run_id)@\(.repository_binding)\"")
    unlock_registry
    printf 'pruned %s\n' "$pruned"
    ;;

  *)
    usage
    ;;
esac
