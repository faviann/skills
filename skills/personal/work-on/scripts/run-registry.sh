#!/usr/bin/env bash
set -euo pipefail

# Track one work-on run's lifecycle obligation outside the repository it ran in,
# so an interrupted or forgotten run stays visible after its worktree, branch, or
# clone is gone.
#
# The registry is bounded metadata only. It holds enumerated lifecycle states,
# an issue number, a normalized repository slug, resolved identifiers, two
# filesystem locators, and a hash of the sink's own deterministic summary. It has
# no field for a prompt, a diff, a command line, an output, a credential, or a
# reviewer's prose, and every record is validated against that closed shape
# before it is written, so such material cannot be stored even by mistake. Raw
# events stay in the run's sink under the repository's Git common directory and
# are never copied here.
#
# Whether a run carries a finalization obligation is decided by an optional
# external observer program. This script knows only two bounded tokens from it —
# an observer id and a control id — and nothing about any experiment those
# tokens belong to.

readonly record_schema=1
readonly lifecycle_states=(active resolved sealed unknown)
readonly finalization_states=(pending finalizing finalized failed unreproducible)
readonly run_outcomes=(Closes Progresses preflight-aborted abandoned failed)
readonly failure_codes=(
  OUTCOME_UNRESOLVED OUTCOME_CONFLICT RESOLVE_FAILED SEAL_FAILED
  INTEGRITY_INCOMPLETE INTEGRITY_INVALID SUMMARY_FAILED
  OBSERVER_FAILED SINK_MISSING REPOSITORY_MISSING
)
readonly default_capacity=512
readonly default_retention_days=30

fail() {
  printf 'run registry: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: run-registry.sh <subcommand>
  register --run HANDLE                     record the run's lifecycle obligation
  finalize --run HANDLE [--outcome O]       seal and discharge the obligation
  recover (--run HANDLE | --run-id ID | --all) [--outcome O]
                                            idempotently finish the same run
  status [--run-id ID] [--repository R] [--issue N] [--pending]
  prune [--older-than-days N]               drop retained ungoverned records
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

registry_root="${XDG_STATE_HOME:-$HOME/.local/state}/work-on/registry"
runs_root="$registry_root/runs"
registry_lock="$registry_root/registry.lock"

readonly run_id_pattern='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'
readonly run_handle_pattern='^([0-9]{8}T[0-9]{6}Z-[0-9a-f]{8})@([0-9a-f]{32})$'
readonly token_pattern='^[a-z0-9][a-z0-9-]{0,63}$'

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

record_path() {
  printf '%s/%s.json\n' "$runs_root" "$1"
}

record_lock_path() {
  printf '%s/%s.lock\n' "$runs_root" "$1"
}

# One closed shape, checked on the way in. A record that does not match it is
# never written, so a later reader can trust the field set as well as the values.
readonly record_validator='
  def token: type == "string" and test("^[a-z0-9][a-z0-9-]{0,63}$");
  def locator: type == "string" and (length > 0) and (length <= 4096)
    and startswith("/") and (test("[\\n\\r\\t]") | not);
  def stamp: type == "string"
    and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
  type == "object"
  and (keys == [
    "control_id","failure_code","finalization","issue","lifecycle","observer",
    "outcome","registered_at","repository","repository_binding","run_id",
    "schema","sink","summary_sha256","telemetry_schema","updated_at",
    "updated_epoch","worktree"])
  and .schema == 1
  and (.run_id | type == "string" and test("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$"))
  and (.repository | type == "string" and test("^[a-z0-9_.-]+/[a-z0-9_.-]+$"))
  and (.issue | type == "number" and floor == . and . > 0)
  and .telemetry_schema == 2
  and (.sink | locator) and (.worktree | locator)
  and (.repository_binding | type == "string" and test("^[0-9a-f]{32}$"))
  and (.lifecycle | IN($lifecycles[]))
  and (.outcome == null or (.outcome | IN($outcomes[])))
  and (.summary_sha256 == null
    or (.summary_sha256 | type == "string" and test("^[0-9a-f]{64}$")))
  and (.finalization | IN($finalizations[]))
  and (.observer == null or (.observer | token))
  and (.control_id == null or (.control_id | token))
  and (.registered_at | stamp) and (.updated_at | stamp)
  and (.updated_epoch | type == "number" and floor == . and . >= 0)
  and (.failure_code == null or (.failure_code | IN($failure_codes[])))
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

# Records are replaced whole, never appended to: a reader under no lock at all
# sees either the previous record or the next one.
write_record() {
  local run="$1" body="$2" staged
  printf '%s' "$body" | validate_record \
    || fail "refusing to write a registry record outside its bounded shape"
  staged="$(record_path "$run").staged.$$"
  create_private_file "$staged"
  printf '%s\n' "$body" >"$staged"
  mv -f "$staged" "$(record_path "$run")"
}

read_record() {
  local run="$1" file
  file="$(record_path "$run")"
  [[ -f "$file" ]] || return 1
  cat "$file"
}

record_field() {
  jq -r --arg field "$2" '.[$field] // "" | tostring' <<<"$1"
}

# Every mutation names its run, so two agents working on different runs never
# contend and can never reach each other's record.
lock_record() {
  local run="$1"
  create_private_file "$(record_lock_path "$run")"
  exec {record_lock_fd}>>"$(record_lock_path "$run")"
  flock -x "$record_lock_fd" || fail "could not lock registry record $run"
}

unlock_record() {
  [[ -n "${record_lock_fd:-}" ]] || return 0
  exec {record_lock_fd}>&-
  record_lock_fd=""
}

lock_registry() {
  exec {registry_lock_fd}>>"$registry_lock"
  flock -x "$registry_lock_fd" || fail "could not lock the run registry"
}

unlock_registry() {
  [[ -n "${registry_lock_fd:-}" ]] || return 0
  exec {registry_lock_fd}>&-
  registry_lock_fd=""
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
# repository/issue carry an obligation — and answers with two bounded tokens or
# a refusal. Anything else is a policy error, and a run that might be governed
# is never allowed to proceed on a guess.

observer_program=""
resolve_observer_program() {
  local candidate="${WORK_ON_OBSERVER:-}"
  if [[ -n "$candidate" ]]; then
    [[ -x "$candidate" ]] || fail "observer program is not executable: $candidate"
    observer_program="$candidate"
    return 0
  fi
  candidate="${XDG_CONFIG_HOME:-$HOME/.config}/work-on/observer"
  [[ -x "$candidate" ]] && observer_program="$candidate"
  return 0
}

observer_id=""
control_id=""
resolve_observer_applicability() {
  local repository="$1" issue="$2" output status line
  observer_id=""
  control_id=""
  resolve_observer_program
  [[ -n "$observer_program" ]] || return 0
  status=0
  output="$("$observer_program" applies --repository "$repository" \
    --issue "$issue" 2>/dev/null)" || status=$?
  case "$status" in
    0) ;;
    3) return 0 ;;
    *) fail "observer policy could not decide whether this run is governed" ;;
  esac
  while IFS= read -r line; do
    case "$line" in
      observer=*) observer_id="${line#observer=}" ;;
      control=*) control_id="${line#control=}" ;;
    esac
  done <<<"$output"
  [[ "$observer_id" =~ $token_pattern && "$control_id" =~ $token_pattern ]] \
    || fail "observer policy returned a malformed applicability answer"
}

# A record naming a control has an obligation to that observer. If the observer
# is unreachable when the obligation comes due, the obligation stays outstanding
# rather than being discharged against nothing.
notify_observer_finalized() {
  local run="$1"
  [[ -n "$control_id" ]] || return 0
  [[ -n "$observer_program" ]] || return 1
  "$observer_program" finalize --record "$(record_path "$run")" >/dev/null 2>&1
}

# --- sink identity ----------------------------------------------------------

summary_json=""
read_summary() {
  local workdir="$1" handle="$2"
  summary_json=""
  summary_json="$( (cd "$workdir" && "$telemetry_script" summary --run "$handle") 2>/dev/null )" \
    || return 1
  [[ "$(jq -r '.schema' <<<"$summary_json")" == 2 ]] || return 1
  return 0
}

sink_path_for() {
  local common_dir="$1" run="$2"
  printf '%s/work-on-telemetry/runs/%s.jsonl\n' "$common_dir" "$run"
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
  local binding="$6" lifecycle="$7" outcome="$8" stamp
  stamp="$(now_iso)"
  jq -cn \
    --argjson schema "$record_schema" \
    --arg run_id "$run" --arg repository "$repository" --argjson issue "$issue" \
    --arg sink "$sink" --arg worktree "$worktree" --arg binding "$binding" \
    --arg lifecycle "$lifecycle" --arg outcome "$outcome" \
    --arg observer "$observer_id" --arg control "$control_id" \
    --arg stamp "$stamp" --argjson updated_epoch "$(now_epoch)" \
    'def maybe: if . == "" then null else . end;
     {schema: $schema, run_id: $run_id, repository: $repository, issue: $issue,
      telemetry_schema: 2, sink: $sink, worktree: $worktree,
      repository_binding: $binding, lifecycle: $lifecycle,
      outcome: ($outcome | maybe), summary_sha256: null,
      finalization: "pending", observer: ($observer | maybe),
      control_id: ($control | maybe), registered_at: $stamp,
      updated_at: $stamp, updated_epoch: $updated_epoch, failure_code: null}'
}

# Transitions restate the whole record from the one it replaces, so a field this
# transition does not name cannot be lost or silently changed.
transition_record() {
  local current="$1" lifecycle="$2" outcome="$3" summary_sha256="$4"
  local finalization="$5" failure_code="$6"
  jq -c \
    --arg lifecycle "$lifecycle" --arg outcome "$outcome" \
    --arg summary_sha256 "$summary_sha256" --arg finalization "$finalization" \
    --arg failure_code "$failure_code" --arg updated_at "$(now_iso)" \
    --argjson updated_epoch "$(now_epoch)" \
    'def maybe: if . == "" then null else . end;
     .lifecycle = $lifecycle
     | .outcome = ($outcome | maybe)
     | .summary_sha256 = ($summary_sha256 | maybe)
     | .finalization = $finalization
     | .failure_code = ($failure_code | maybe)
     | .updated_at = $updated_at
     | .updated_epoch = $updated_epoch' <<<"$current"
}

lifecycle_from_summary() {
  local summary="$1"
  if [[ "$(jq -r '.sealed_at // "null"' <<<"$summary")" != null ]]; then
    printf 'sealed\n'
  elif [[ "$(jq -r '.final_workflow_outcome // "null"' <<<"$summary")" != null ]]; then
    printf 'resolved\n'
  else
    printf 'active\n'
  fi
}

recovery_command() {
  printf '%s recover --run-id %s\n' "$registry_script" "$1"
}

# --- capacity and retention -------------------------------------------------
#
# A record that nothing governs may always be dropped to make room. A governed
# record may be dropped only once its obligation is discharged. When neither
# frees a slot, registration refuses rather than quietly losing the evidence an
# observer still needs.
readonly evictable_filter='.control_id == null or .finalization == "finalized"'

evict_for_capacity() {
  local occupied victim
  occupied="$(all_records | jq -s 'length')"
  while [[ "$occupied" -ge "$capacity" ]]; do
    victim="$(all_records | jq -rs "
      [.[] | select($evictable_filter)]
      | sort_by(.updated_epoch, .run_id) | .[0].run_id // empty")"
    [[ -n "$victim" ]] || return 1
    rm -f "$(record_path "$victim")" "$(record_lock_path "$victim")"
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

# Every way finalization can stop short ends here, keeping whatever the run had
# already established. An outstanding obligation exits nonzero with the one
# command that retries it; a run nobody can reproduce has nothing left to retry,
# so it is recorded as such and reported as final.
halt_finalization() {
  local run="$1" current="$2" lifecycle="$3" finalization="$4" code="$5"
  local message="$6"
  write_record "$run" \
    "$(transition_record "$current" "$lifecycle" \
      "$(record_field "$current" outcome)" \
      "$(record_field "$current" summary_sha256)" "$finalization" "$code")"
  unlock_record
  printf 'run registry: %s\n' "$message" >&2
  if [[ "$finalization" == unreproducible ]]; then
    printf 'run registry: run %s is recorded as unreproducible\n' "$run" >&2
    exit 0
  fi
  printf 'run registry: recover with: %s\n' "$(recovery_command "$run")" >&2
  exit 1
}

drive_finalization() {
  local run="$1" requested_outcome="$2" current sink worktree binding handle
  local resolved integrity outcome summary_sha256 lifecycle

  current="$(read_record "$run")" \
    || fail "run $run is not registered; register it before finalizing"
  lock_record "$run"
  current="$(read_record "$run")"

  if [[ "$(record_field "$current" finalization)" == finalized ]]; then
    unlock_record
    printf 'finalized %s\n' "$run"
    return 0
  fi

  observer_id="$(record_field "$current" observer)"
  control_id="$(record_field "$current" control_id)"
  resolve_observer_program

  sink="$(record_field "$current" sink)"
  worktree="$(record_field "$current" worktree)"
  binding="$(record_field "$current" repository_binding)"
  handle="$run@$binding"

  # An interrupted finalization is visible as such, so a recovery can tell a
  # crash apart from an obligation nobody has started discharging.
  write_record "$run" \
    "$(transition_record "$current" \
      "$(record_field "$current" lifecycle)" \
      "$(record_field "$current" outcome)" \
      "$(record_field "$current" summary_sha256)" finalizing \
      "$(record_field "$current" failure_code)")"
  current="$(read_record "$run")"

  # A vanished clone takes its sink with it, so the repository is asked about
  # first: the narrower code is reserved for a sink that went missing from a
  # repository that is still there.
  resolve_workdir "$sink" "$worktree" \
    || halt_finalization "$run" "$current" unknown unreproducible \
      REPOSITORY_MISSING \
      "run $run has no reachable repository for its telemetry sink"
  [[ -f "$sink" ]] \
    || halt_finalization "$run" "$current" unknown unreproducible SINK_MISSING \
      "run $run has no telemetry sink at its recorded location"

  read_summary "$resolved_workdir" "$handle" \
    || halt_finalization "$run" "$current" unknown unreproducible \
      SUMMARY_FAILED "run $run has no readable schema-2 summary"

  resolved="$(jq -r '.final_workflow_outcome // ""' <<<"$summary_json")"
  if [[ -z "$resolved" ]]; then
    [[ -n "$requested_outcome" ]] \
      || halt_finalization "$run" "$current" active failed OUTCOME_UNRESOLVED \
        "run $run has resolved no outcome; supply --outcome to finalize it"
    (cd "$resolved_workdir" && "$telemetry_script" resolve --run "$handle" \
      --outcome "$requested_outcome") >/dev/null \
      || halt_finalization "$run" "$current" active failed RESOLVE_FAILED \
        "run $run could not resolve outcome $requested_outcome"
    resolved="$requested_outcome"
  elif [[ -n "$requested_outcome" && "$requested_outcome" != "$resolved" ]]; then
    halt_finalization "$run" "$current" resolved failed OUTCOME_CONFLICT \
      "run $run already resolved $resolved; refusing to finalize as $requested_outcome"
  fi

  if [[ "$(jq -r '.sealed_at // ""' <<<"$summary_json")" == "" ]]; then
    (cd "$resolved_workdir" && "$telemetry_script" seal --run "$handle") \
      >/dev/null \
      || halt_finalization "$run" "$current" resolved failed SEAL_FAILED \
        "run $run could not be sealed"
  fi

  read_summary "$resolved_workdir" "$handle" \
    || halt_finalization "$run" "$current" resolved failed SUMMARY_FAILED \
      "run $run has no readable schema-2 summary after sealing"
  lifecycle="$(lifecycle_from_summary "$summary_json")"
  outcome="$(jq -r '.final_workflow_outcome // ""' <<<"$summary_json")"
  integrity="$(jq -r '.integrity.state' <<<"$summary_json")"
  if [[ "$integrity" != valid ]]; then
    case "$integrity" in
      incomplete) halt_finalization "$run" "$current" "$lifecycle" failed \
        INTEGRITY_INCOMPLETE "run $run is sealed but its telemetry is incomplete" ;;
      *) halt_finalization "$run" "$current" "$lifecycle" failed \
        INTEGRITY_INVALID \
        "run $run is sealed but its telemetry integrity is $integrity" ;;
    esac
  fi

  # The canonical summary is the sink's own deterministic aggregate; the record
  # keeps its hash, never a reconstruction of it.
  summary_sha256="$(printf '%s' "$summary_json" | sha256_of_stdin)"
  write_record "$run" \
    "$(transition_record "$current" "$lifecycle" "$outcome" "$summary_sha256" \
      finalizing "")"
  current="$(read_record "$run")"

  notify_observer_finalized "$run" \
    || halt_finalization "$run" "$current" "$lifecycle" failed OBSERVER_FAILED \
      "run $run was sealed but its observer did not accept the finalization"

  write_record "$run" \
    "$(transition_record "$current" "$lifecycle" "$outcome" "$summary_sha256" \
      finalized "")"
  unlock_record
  printf 'finalized %s\n' "$run"
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
    [[ "$handle" =~ $run_handle_pattern ]] || fail "run handle is malformed"
    run_id="${BASH_REMATCH[1]}"
    binding="${BASH_REMATCH[2]}"

    worktree="$(git rev-parse --show-toplevel 2>/dev/null)" \
      || fail "register requires a Git-backed target repository"
    common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
      || fail "could not resolve the repository's Git common directory"
    sink="$(sink_path_for "$common_dir" "$run_id")"
    read_summary "$worktree" "$handle" \
      || fail "register requires a schema-2 run in this repository"
    repository="$(jq -r '.repository // ""' <<<"$summary_json")"
    issue="$(jq -r '.issue // ""' <<<"$summary_json")"
    [[ -n "$repository" && "$issue" =~ ^[1-9][0-9]*$ ]] \
      || fail "run $run_id has no repository/issue identity to register"

    resolve_observer_applicability "$repository" "$issue"

    # A governed run may not proceed on an unrecorded obligation. A run nothing
    # observes owes nobody anything, so a registry problem is reported and the
    # run continues exactly as it would have before the registry existed.
    registration_problem() {
      [[ -z "$control_id" ]] || fail "$1"
      printf 'run registry: %s\n' "$1" >&2
      exit 0
    }

    ensure_registry_root
    lock_registry
    existing="$(read_record "$run_id")" || existing=""

    if [[ -n "$control_id" && -z "$existing" ]]; then
      blocking="$(all_records | jq -rs --arg control "$control_id" '
        [.[] | select(.control_id == $control
          and (.finalization | IN("pending","finalizing","failed")))]
        | sort_by(.updated_epoch, .run_id) | .[0] // empty
        | "\(.run_id) \(.repository) \(.issue) \(.lifecycle) \(.finalization) \(.failure_code // "none")"')"
      if [[ -n "$blocking" ]]; then
        read -r blocked_run blocked_repository blocked_issue blocked_lifecycle \
          blocked_finalization blocked_code <<<"$blocking"
        unlock_registry
        {
          printf 'run registry: a prior observed run has an unfinished obligation\n'
          printf '  run: %s (%s#%s)\n' "$blocked_run" "$blocked_repository" \
            "$blocked_issue"
          printf '  lifecycle: %s, finalization: %s, failure: %s\n' \
            "$blocked_lifecycle" "$blocked_finalization" "$blocked_code"
          printf '  recover with: %s\n' "$(recovery_command "$blocked_run")"
        } >&2
        exit 1
      fi
    fi

    if [[ -z "$existing" ]]; then
      evict_for_capacity || {
        unlock_registry
        registration_problem \
          "the run registry is full of unfinished obligations; discharge them with $registry_script recover --all"
      }
      write_record "$run_id" "$(initial_record "$run_id" "$repository" "$issue" \
        "$sink" "$worktree" "$binding" \
        "$(lifecycle_from_summary "$summary_json")" \
        "$(jq -r '.final_workflow_outcome // ""' <<<"$summary_json")")"
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
    [[ "$handle" =~ $run_handle_pattern ]] || fail "run handle is malformed"
    run_id="${BASH_REMATCH[1]}"
    [[ -z "$outcome" ]] \
      || contains "$outcome" "${run_outcomes[@]}" \
      || fail "outcome must be one of: ${run_outcomes[*]}"
    ensure_registry_root
    drive_finalization "$run_id" "$outcome"
    ;;

  recover)
    handle=""
    run_id=""
    outcome=""
    recover_all=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        --run-id) run_id="${2:?--run-id requires a value}"; shift 2 ;;
        --outcome) outcome="${2:?--outcome requires a value}"; shift 2 ;;
        --all) recover_all=true; shift ;;
        *) usage ;;
      esac
    done
    [[ -z "$outcome" ]] \
      || contains "$outcome" "${run_outcomes[@]}" \
      || fail "outcome must be one of: ${run_outcomes[*]}"
    if [[ -n "$handle" ]]; then
      [[ "$handle" =~ $run_handle_pattern ]] || fail "run handle is malformed"
      run_id="${BASH_REMATCH[1]}"
    fi
    ensure_registry_root
    if [[ "$recover_all" == true ]]; then
      [[ -z "$run_id" ]] || fail "recover takes --all or one run, not both"
      status=0
      # Each run is driven in a subshell, so one run that stops short reports
      # itself and the sweep still reaches the rest.
      while IFS= read -r pending_run; do
        [[ -n "$pending_run" ]] || continue
        ( drive_finalization "$pending_run" "$outcome" ) || status=1
      done < <(all_records | jq -rs '
        [.[] | select(.finalization | IN("pending","finalizing","failed"))]
        | sort_by(.updated_epoch, .run_id) | .[].run_id')
      exit "$status"
    fi
    [[ "$run_id" =~ $run_id_pattern ]] \
      || fail "recover requires --run, --run-id, or --all"
    drive_finalization "$run_id" "$outcome"
    ;;

  status)
    run_id=""
    repository=""
    issue=""
    pending_only=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run-id) run_id="${2:?--run-id requires a value}"; shift 2 ;;
        --repository) repository="${2:?--repository requires a value}"; shift 2 ;;
        --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
        --pending) pending_only=true; shift ;;
        *) usage ;;
      esac
    done
    ensure_registry_root
    all_records | jq -sc \
      --arg run_id "$run_id" --arg repository "$repository" --arg issue "$issue" \
      --argjson pending_only "$pending_only" '
      [.[]
        | select($run_id == "" or .run_id == $run_id)
        | select($repository == "" or .repository == $repository)
        | select($issue == "" or (.issue | tostring) == $issue)
        | select(($pending_only | not)
          or (.finalization | IN("pending","finalizing","failed")))]
      | sort_by(.updated_epoch, .run_id) | .[]'
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
    lock_registry
    pruned=0
    while IFS= read -r stale_run; do
      [[ -n "$stale_run" ]] || continue
      rm -f "$(record_path "$stale_run")" "$(record_lock_path "$stale_run")"
      pruned=$(( pruned + 1 ))
    done < <(all_records | jq -rs \
      --argjson cutoff "$(( $(now_epoch) - older_than_days * 86400 ))" "
      [.[] | select(($evictable_filter) and .updated_epoch <= \$cutoff)]
      | .[].run_id")
    unlock_registry
    printf 'pruned %s\n' "$pruned"
    ;;

  *)
    usage
    ;;
esac
