#!/usr/bin/env bash
set -euo pipefail

# Black-box scenarios for the user-level run registry and its observer seam.
# Every assertion goes through the public commands: nothing here reads or
# repairs a registry record by hand, and the only direct file inspection is the
# privacy, permission, corruption, and crash-artifact evidence the ticket
# requires.

readonly script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly telemetry_script="$script_root/run-telemetry.sh"
readonly registry_script="$script_root/run-registry.sh"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

scenario_name=""
fail() {
  printf 'FAIL[%s]: %s\n' "$scenario_name" "$1" >&2
  exit 1
}

scenario() {
  scenario_name="$1"
  export XDG_STATE_HOME="$fixture/state/$1"
  export XDG_CONFIG_HOME="$fixture/config/$1"
  export HOME="$fixture/home/$1"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME"
  unset WORK_ON_OBSERVER
  unset WORK_ON_REGISTRY_CAPACITY
  clear_observer_flags
  printf '  %s\n' "$1"
}

registry_root() {
  printf '%s/work-on/registry\n' "$XDG_STATE_HOME"
}

new_repo() {
  local path="$1" origin="$2"
  git init -q -b main "$path"
  git -C "$path" config user.name 'Registry Test'
  git -C "$path" config user.email registry@example.invalid
  git -C "$path" remote add origin "$origin"
  printf 'fixture\n' >"$path/file.txt"
  git -C "$path" add .
  git -C "$path" commit -qm fixture
}

telemetry() {
  local workdir="$1"
  shift
  (cd "$workdir" && "$telemetry_script" "$@")
}

registry_in() {
  local workdir="$1"
  shift
  (cd "$workdir" && "$registry_script" "$@")
}

record_of() {
  "$registry_script" status --run "$1"
}

assert_field() {
  local handle="$1" field="$2" expected="$3" observed
  observed="$(record_of "$handle" | jq -r --arg field "$field" '.[$field] // "null"')"
  [[ "$observed" == "$expected" ]] \
    || fail "run $handle has $field=$observed, expected $expected"
}

record_count() {
  "$registry_script" status | jq -s 'length'
}

sink_of() {
  local repo="$1" handle="$2"
  printf '%s/work-on-telemetry/runs/%s.jsonl\n' \
    "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)" \
    "${handle%@*}"
}

wait_for_file() {
  local target="$1" waited=0
  while [[ ! -e "$target" ]]; do
    waited=$(( waited + 1 ))
    [[ "$waited" -lt 600 ]] || fail "timed out waiting for $target"
    sleep 0.05
  done
}

# A competing process announces itself, then runs one public command. Its result
# file appears only once that command returns, so "alive with no result" is
# evidence that it is still waiting at the contested boundary.
launch_competitor() {
  local label="$1" workdir="$2"
  shift 2
  rm -f "$fixture/$label.started" "$fixture/$label.result"
  (
    cd "$workdir"
    : >"$fixture/$label.started"
    if "$@" >"$fixture/$label.out" 2>"$fixture/$label.err"; then
      printf 'granted\n' >"$fixture/$label.result"
    else
      printf 'refused\n' >"$fixture/$label.result"
    fi
  ) &
  printf '%s\n' "$!" >"$fixture/$label.pid"
  wait_for_file "$fixture/$label.started"
}

assert_blocked_and_live() {
  local label="$1" pid settle
  pid="$(cat "$fixture/$label.pid")"
  for settle in $(seq 1 20); do
    kill -0 "$pid" 2>/dev/null \
      || fail "$label exited before the contested boundary was released"
    [[ ! -e "$fixture/$label.result" ]] \
      || fail "$label completed without waiting at the contested boundary"
    sleep 0.05
  done
}

competitor_result() {
  wait_for_file "$fixture/$1.result"
  cat "$fixture/$1.result"
}

holder_pid=""
hold_registry_lock() {
  local mode="$1" lock
  lock="$(registry_root)/registry.lock"
  [[ -e "$lock" ]] || fail "the registry lock does not exist yet"
  rm -f "$fixture/lock-held" "$fixture/lock-release"
  (
    flock "$mode" 9
    : >"$fixture/lock-held"
    while [[ ! -e "$fixture/lock-release" ]]; do sleep 0.05; done
  ) 9>>"$lock" &
  holder_pid="$!"
  wait_for_file "$fixture/lock-held"
}

release_registry_lock() {
  : >"$fixture/lock-release"
  wait "$holder_pid" 2>/dev/null || true
  holder_pid=""
}

# One observer program serves every scenario. Its policy answer, its
# finalization result, whether it waits, and whether it crashes its caller are
# driven by fixture flag files, so a scenario changes observer behaviour without
# changing the seam. It deduplicates finalization by the transition identity it
# is handed, which is exactly what the contract asks an observer to do.
observer_program="$fixture/observer"
cat >"$observer_program" <<'OBSERVER'
#!/usr/bin/env bash
set -euo pipefail
flags="$OBSERVER_FLAGS"
case "${1:-}" in
  applies)
    shift
    repository=""
    issue=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repository) repository="$2"; shift 2 ;;
        --issue) issue="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ ! -e "$flags/policy-error" ]] || exit 9
    if [[ -e "$flags/report-capture" ]]; then
      # fd 1 must be duplicated first: inside command substitution it would be
      # the substitution's pipe rather than the observer's own stdout.
      exec 9>&1
      capture="$(readlink /proc/self/fd/9)"
      printf '%s %s\n' "$capture" "$(stat -c '%a' "$capture")" \
        >>"$flags/capture-report"
    fi
    [[ "$repository" == example/telemetry ]] || exit 3
    if [[ -e "$flags/applies-nul" ]]; then
      printf 'observer=nul-observer\ncontrol=nul-control\n'
      printf '\0'
      exit 0
    fi
    if [[ -e "$flags/applies-embedded-nul" ]]; then
      printf 'observer=nul-observer\n'
      printf '\0'
      printf 'control=nul-control\n'
      exit 0
    fi
    if [[ -e "$flags/applies-identity" ]]; then
      cat "$flags/applies-identity"
      exit 0
    fi
    if [[ -e "$flags/applies-output" ]]; then
      cat "$flags/applies-output"
      exit 0
    fi
    if [[ -e "$flags/per-issue-controls" ]]; then
      printf 'observer=test-observer\ncontrol=demo-control-%s\n' "$issue"
    else
      printf 'observer=test-observer\ncontrol=demo-control\n'
    fi
    ;;
  finalize)
    shift
    transition=""
    record=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --record) record="$2"; shift 2 ;;
        --transition) transition="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    printf '%s\n' "$transition" >>"$flags/invocations"
    if [[ -e "$flags/kill-before-accept" ]]; then
      kill -9 "$PPID"
      exit 0
    fi
    if [[ -e "$flags/wait-for-release" ]]; then
      held="$(cat "$flags/wait-for-release")"
      if [[ -z "$held" || "$record" == *"$held"* ]]; then
        : >"$flags/observer-entered"
        while [[ ! -e "$flags/release" ]]; do sleep 0.05; done
      fi
    fi
    # A repeated transition identity is the same transition, not a new one.
    if [[ -e "$flags/accepted" ]] && grep -Fqx "$transition" "$flags/accepted"; then
      exit 0
    fi
    [[ ! -e "$flags/finalize-error" ]] || exit 1
    printf '%s\n' "$transition" >>"$flags/accepted"
    if [[ -e "$flags/kill-after-accept" ]]; then
      kill -9 "$PPID"
      exit 0
    fi
    ;;
  *) exit 2 ;;
esac
OBSERVER
chmod +x "$observer_program"
export OBSERVER_FLAGS="$fixture/flags"

enable_observer() {
  export WORK_ON_OBSERVER="$observer_program"
}

clear_observer_flags() {
  rm -rf "$OBSERVER_FLAGS"
  mkdir -p "$OBSERVER_FLAGS"
}
clear_observer_flags

count_lines() {
  [[ -e "$1" ]] || { printf '0\n'; return 0; }
  grep -c . "$1" || printf '0\n'
}

observer_acceptances() {
  [[ -e "$OBSERVER_FLAGS/accepted" ]] || { printf '0\n'; return 0; }
  sort -u "$OBSERVER_FLAGS/accepted" | grep -c . || printf '0\n'
}

observer_invocations() {
  count_lines "$OBSERVER_FLAGS/invocations"
}

# Two repositories may legitimately mint the same textual run id; #70 keeps them
# apart by the repository binding. Pinning the public clock and random boundary
# reproduces that collision deterministically.
collision_bin="$fixture/collision-bin"
mkdir "$collision_bin"
cat >"$collision_bin/date" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  +%Y%m%dT%H%M%SZ) printf '20260816T180000Z\n' ;;
  +%Y-%m-%dT%H:%M:%SZ) printf '2026-08-16T18:00:00Z\n' ;;
  +%s) printf '1786903200\n' ;;
  *) exit 1 ;;
esac
EOF
cat >"$collision_bin/od" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *' -N4 '* ]]; then
  printf ' aa bb cc dd\n'
else
  /usr/bin/od "$@"
fi
EOF
chmod +x "$collision_bin/date" "$collision_bin/od"

printf 'run registry scenarios\n'

# --- every outcome finalizes ------------------------------------------------

scenario closes-finalizes-automatically
repo="$fixture/closes"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
telemetry "$repo" exec --run "$handle" --command-id registry-tests --phase gate --round 1 -- true
# The workflow resolves at the closure gate and keeps recording closeout
# evidence; finalization seals only afterwards, exactly as #71 allows.
telemetry "$repo" resolve --run "$handle" --outcome Closes
telemetry "$repo" exec --run "$handle" --command-id registry-tests --phase closeout --round 1 -- true
[[ "$(registry_in "$repo" finalize --run "$handle")" == "finalized ${handle%@*}" ]] \
  || fail "finalize did not report the run finalized"
assert_field "$handle" finalization finalized
assert_field "$handle" outcome Closes
assert_field "$handle" lifecycle sealed
assert_field "$handle" failure_code null
[[ "$(telemetry "$repo" summary --run "$handle" | jq -r '.integrity.state')" == valid ]] \
  || fail "the finalized run's telemetry is not valid"

scenario progresses-finalizes-automatically
repo="$fixture/progresses"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
registry_in "$repo" finalize --run "$handle" --outcome Progresses >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" outcome Progresses
assert_field "$handle" lifecycle sealed

scenario preflight-aborted-finalizes-automatically
repo="$fixture/preflight"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
registry_in "$repo" finalize --run "$handle" --outcome preflight-aborted >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" outcome preflight-aborted

scenario abandoned-and-failed-remain-finalizable
for outcome in abandoned failed; do
  repo="$fixture/$outcome"
  new_repo "$repo" 'git@github.com:Example/Telemetry.git'
  handle="$(telemetry "$repo" start --issue 72)"
  registry_in "$repo" register --run "$handle" >/dev/null
  telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
  registry_in "$repo" finalize --run "$handle" --outcome "$outcome" >/dev/null
  assert_field "$handle" finalization finalized
  assert_field "$handle" outcome "$outcome"
done

# --- repository-bound registry authority ------------------------------------

scenario same-run-id-in-two-repositories-cannot-alias
first_repo="$fixture/collision-first"
second_repo="$fixture/collision-second"
new_repo "$first_repo" 'git@github.com:Example/CollisionFirst.git'
new_repo "$second_repo" 'git@github.com:Example/CollisionSecond.git'
first="$(cd "$first_repo" && PATH="$collision_bin:$PATH" "$telemetry_script" start --issue 72)"
second="$(cd "$second_repo" && PATH="$collision_bin:$PATH" "$telemetry_script" start --issue 72)"
[[ "${first%@*}" == "${second%@*}" ]] \
  || fail "the fixture did not reproduce a same-run-id collision"
[[ "$first" != "$second" ]] || fail "the two handles are identical"
registry_in "$first_repo" register --run "$first" >/dev/null
# The second repository cannot register, read, finalize, or recover the first
# repository's lifecycle through its own same-named run.
! registry_in "$second_repo" register --run "$first" >/dev/null 2>&1 \
  || fail "a foreign bound handle was accepted for registration"
[[ -z "$(record_of "$second")" ]] \
  || fail "the second repository's handle selected the first repository's record"
[[ -n "$(record_of "$first")" ]] || fail "the first record is not addressable"
registry_in "$second_repo" register --run "$second" >/dev/null
[[ "$(record_count)" -eq 2 ]] || fail "two same-id runs did not produce two records"
registry_in "$second_repo" finalize --run "$second" --outcome Closes >/dev/null
assert_field "$second" finalization finalized
assert_field "$second" outcome Closes
assert_field "$first" finalization pending
assert_field "$first" outcome null
[[ "$(record_of "$first" | jq -r '.repository')" == example/collisionfirst ]] \
  || fail "the first record lost its repository identity"
registry_in "$first_repo" recover --run "$first" --outcome abandoned >/dev/null
assert_field "$first" finalization finalized
assert_field "$first" outcome abandoned
assert_field "$second" outcome Closes
[[ "$(telemetry "$second_repo" summary --run "$second" | jq -r '.final_workflow_outcome')" == Closes ]] \
  || fail "the second repository's sink was driven by the wrong lifecycle"
[[ "$(telemetry "$first_repo" summary --run "$first" | jq -r '.final_workflow_outcome')" == abandoned ]] \
  || fail "the first repository's sink was driven by the wrong lifecycle"
# Retention addresses records by the same bound identity.
[[ "$("$registry_script" prune --older-than-days 0)" == 'pruned 2' ]] \
  || fail "retention did not address both same-id records"

scenario registry-refuses-a-row-that-disagrees-with-its-sink
repo="$fixture/identity"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
# The sink is canonical: a row whose issue no longer matches it is a corrupted
# index entry, and the index must never act on a lifecycle it cannot vouch for.
record_file="$(registry_root)/runs/$handle.json"
jq -c '.issue = 999' "$record_file" >"$record_file.rewritten"
mv "$record_file.rewritten" "$record_file"
! registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null 2>&1 \
  || fail "finalization proceeded against a record disagreeing with the sink"
assert_field "$handle" failure_code IDENTITY_MISMATCH
assert_field "$handle" finalization failed
[[ "$(telemetry "$repo" summary --run "$handle" | jq -r '.final_workflow_outcome')" == null ]] \
  || fail "a mismatched record still drove the sink"

# --- governed registration is provably pre-work -----------------------------

scenario governed-registration-refuses-late-registration
enable_observer
for class in launch review validation; do
  repo="$fixture/late-$class"
  new_repo "$repo" 'git@github.com:Example/Telemetry.git'
  handle="$(telemetry "$repo" start --issue 72)"
  case "$class" in
    launch) telemetry "$repo" launch --run "$handle" --role implementation \
      --phase implementation --round 1 ;;
    review) telemetry "$repo" review-delegation --run "$handle" --role readiness \
      --kind readiness --phase checkpoint --round 1 --base HEAD --worktree ;;
    validation) telemetry "$repo" exec --run "$handle" --command-id registry-tests \
      --phase gate --round 1 -- true ;;
  esac
  ! registry_in "$repo" register --run "$handle" >"$fixture/late-$class.err" 2>&1 \
    || fail "a governed run was registered after $class work"
  grep -Fq 'must be registered before implementation' "$fixture/late-$class.err" \
    || fail "the refusal for $class does not name the pre-implementation rule"
  [[ -z "$(record_of "$handle")" ]] \
    || fail "a late governed registration still created a record for $class"
done
for class in resolved sealed; do
  repo="$fixture/late-$class"
  new_repo "$repo" 'git@github.com:Example/Telemetry.git'
  handle="$(telemetry "$repo" start --issue 72)"
  telemetry "$repo" resolve --run "$handle" --outcome Closes
  [[ "$class" == resolved ]] || telemetry "$repo" seal --run "$handle"
  ! registry_in "$repo" register --run "$handle" >/dev/null 2>&1 \
    || fail "a governed run was registered after it $class its lifecycle"
  [[ -z "$(record_of "$handle")" ]] || fail "a late governed registration created a record"
done
# A pristine run still registers, and re-registering it stays idempotent.
repo="$fixture/late-pristine"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
registry_in "$repo" register --run "$handle" >/dev/null \
  || fail "re-registering an existing run stopped being idempotent"
[[ "$(record_count)" -eq 1 ]] || fail "re-registration created a second record"

# --- the printed recovery command recovers ----------------------------------

scenario pending-obligation-blocks-matching-run
enable_observer
repo="$fixture/guard"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$first" >/dev/null
second="$(telemetry "$repo" start --issue 73)"
refusal="$fixture/guard-refusal"
! registry_in "$repo" register --run "$second" >"$refusal" 2>&1 \
  || fail "a matching run started while a prior obligation was pending"
grep -Fq "$first" "$refusal" \
  || fail "the refusal does not name the blocking run's bound handle"
grep -Fq 'lifecycle: active, finalization: pending' "$refusal" \
  || fail "the refusal does not state the blocking run's bounded status"
[[ "$(grep -c 'recover with: ' "$refusal")" -eq 1 ]] \
  || fail "the refusal does not print exactly one recovery command"
[[ -z "$(record_of "$second")" ]] || fail "a refused run was still registered"
# The printed command is executed byte-for-byte, with nothing appended.
sed -n 's/^  recover with: //p' "$refusal" >"$fixture/guard-recovery.sh"
bash "$fixture/guard-recovery.sh" >/dev/null \
  || fail "the printed recovery command failed when run exactly as printed"
assert_field "$first" finalization finalized
assert_field "$first" outcome abandoned
bash "$fixture/guard-recovery.sh" >/dev/null \
  || fail "the printed recovery command is not idempotent"
registry_in "$repo" register --run "$second" >/dev/null
assert_field "$second" finalization pending

scenario failed-obligation-prints-a-working-recovery-command
enable_observer
repo="$fixture/guard-failed"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$first" >/dev/null
: >"$OBSERVER_FLAGS/finalize-error"
! registry_in "$repo" finalize --run "$first" --outcome Closes >/dev/null 2>&1 \
  || fail "finalization succeeded while its observer refused"
assert_field "$first" finalization failed
assert_field "$first" failure_code OBSERVER_FAILED
second="$(telemetry "$repo" start --issue 74)"
refusal="$fixture/guard-failed-refusal"
! registry_in "$repo" register --run "$second" >"$refusal" 2>&1 \
  || fail "a matching run started while a prior obligation had failed"
rm -f "$OBSERVER_FLAGS/finalize-error"
sed -n 's/^  recover with: //p' "$refusal" >"$fixture/guard-failed-recovery.sh"
bash "$fixture/guard-failed-recovery.sh" >/dev/null \
  || fail "the printed recovery command failed for a failed obligation"
assert_field "$first" finalization finalized
assert_field "$first" outcome Closes
registry_in "$repo" register --run "$second" >/dev/null

# --- observer finalization is idempotent across the crash window ------------

scenario observer-acceptance-then-crash-yields-one-transition
enable_observer
repo="$fixture/crash-window"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
: >"$OBSERVER_FLAGS/kill-after-accept"
( registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null 2>&1 || :; ) 2>/dev/null
rm -f "$OBSERVER_FLAGS/kill-after-accept"
[[ "$(observer_acceptances)" -eq 1 ]] \
  || fail "the observer did not accept exactly one transition before the crash"
assert_field "$handle" finalization finalizing
first_transition="$(record_of "$handle" | jq -r '.finalization_id')"
[[ "$first_transition" =~ ^[0-9a-f]{64}$ ]] \
  || fail "the in-flight transition identity was not recorded before the observer ran"
registry_in "$repo" recover --run "$handle" >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" finalization_id "$first_transition"
[[ "$(observer_invocations)" -eq 2 ]] \
  || fail "recovery did not redeliver the transition to the observer"
[[ "$(observer_acceptances)" -eq 1 ]] \
  || fail "recovery produced $(observer_acceptances) logical observer transitions"
registry_in "$repo" recover --run "$handle" >/dev/null
[[ "$(observer_acceptances)" -eq 1 ]] \
  || fail "repeated recovery produced more than one logical observer transition"

scenario killed-during-finalization-before-the-observer-acts
enable_observer
repo="$fixture/killed-finalizing"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
: >"$OBSERVER_FLAGS/kill-before-accept"
( registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null 2>&1 || :; ) 2>/dev/null
rm -f "$OBSERVER_FLAGS/kill-before-accept"
assert_field "$handle" finalization finalizing
[[ "$(observer_acceptances)" -eq 0 ]] || fail "the observer accepted before it was meant to"
registry_in "$repo" recover --run "$handle" >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" outcome Closes
[[ "$(observer_acceptances)" -eq 1 ]] || fail "recovery did not produce one transition"

# --- interruption before hand-back ------------------------------------------

scenario killed-run-remains-registered
repo="$fixture/killed"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle_file="$fixture/killed-handle"
( bash -c '
  set -euo pipefail
  cd "$1"
  handle="$("$2" start --issue 72)"
  "$3" register --run "$handle" >/dev/null
  printf "%s" "$handle" >"$4"
  kill -9 $$
' _ "$repo" "$telemetry_script" "$registry_script" "$handle_file" || :; ) 2>/dev/null
handle="$(cat "$handle_file")"
[[ -n "$(record_of "$handle")" ]] || fail "a killed run left no registry record"
assert_field "$handle" run_id "${handle%@*}"
assert_field "$handle" repository_binding "${handle#*@}"
assert_field "$handle" lifecycle active
assert_field "$handle" finalization pending
[[ "$("$registry_script" status --pending | jq -r '.run_id')" == "${handle%@*}" ]] \
  || fail "the killed run is not reported as pending"

scenario killed-between-resolve-and-seal
repo="$fixture/killed-resolved"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle_file="$fixture/killed-resolved-handle"
( bash -c '
  set -euo pipefail
  cd "$1"
  handle="$("$2" start --issue 72)"
  "$3" register --run "$handle" >/dev/null
  "$2" resolve --run "$handle" --outcome Closes
  printf "%s" "$handle" >"$4"
  kill -9 $$
' _ "$repo" "$telemetry_script" "$registry_script" "$handle_file" || :; ) 2>/dev/null
handle="$(cat "$handle_file")"
registry_in "$repo" recover --run "$handle" >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" outcome Closes
assert_field "$handle" lifecycle sealed

# --- the registry never contradicts the sink --------------------------------

scenario failure-paths-keep-the-registry-agreeing-with-the-sink
enable_observer
# Each failure class is its own control, so one outstanding obligation does not
# decide the next case.
: >"$OBSERVER_FLAGS/per-issue-controls"
# Failure after outcome resolution.
repo="$fixture/agree-conflict"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" resolve --run "$handle" --outcome Progresses
! registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null 2>&1 \
  || fail "finalization accepted an outcome contradicting the sink"
assert_field "$handle" failure_code OUTCOME_CONFLICT
assert_field "$handle" lifecycle resolved
assert_field "$handle" outcome Progresses
registry_in "$repo" recover --run "$handle" >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" outcome Progresses

# Failure after sealing, with the sealed sink corrupted afterwards.
repo="$fixture/agree-integrity"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 73)"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" resolve --run "$handle" --outcome Closes
telemetry "$repo" seal --run "$handle"
printf 'not json\n' >>"$(sink_of "$repo" "$handle")"
! registry_in "$repo" finalize --run "$handle" >/dev/null 2>&1 \
  || fail "finalization claimed success for an invalid sink"
assert_field "$handle" finalization failed
assert_field "$handle" failure_code INTEGRITY_INVALID
assert_field "$handle" lifecycle sealed
assert_field "$handle" outcome Closes
assert_field "$handle" summary_sha256 null

# Failure at the observer, after the sink is already sealed and valid.
repo="$fixture/agree-observer"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 74)"
registry_in "$repo" register --run "$handle" >/dev/null
: >"$OBSERVER_FLAGS/finalize-error"
! registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null 2>&1 \
  || fail "finalization succeeded while its observer refused"
rm -f "$OBSERVER_FLAGS/finalize-error"
assert_field "$handle" failure_code OBSERVER_FAILED
assert_field "$handle" lifecycle sealed
assert_field "$handle" outcome Closes
[[ "$(record_of "$handle" | jq -r '.summary_sha256')" =~ ^[0-9a-f]{64}$ ]] \
  || fail "the sealed run's summary hash was not retained on the observer failure"

# --- unrelated runs and absent observers ------------------------------------

scenario unrelated-runs-are-not-blocked
enable_observer
governed="$fixture/unrelated-governed"
ordinary="$fixture/unrelated-ordinary"
new_repo "$governed" 'git@github.com:Example/Telemetry.git'
new_repo "$ordinary" 'git@github.com:Example/Other.git'
governed_handle="$(telemetry "$governed" start --issue 72)"
registry_in "$governed" register --run "$governed_handle" >/dev/null
ordinary_handle="$(telemetry "$ordinary" start --issue 72)"
registry_in "$ordinary" register --run "$ordinary_handle" >/dev/null
assert_field "$ordinary_handle" control_id null
assert_field "$ordinary_handle" observer null
registry_in "$ordinary" finalize --run "$ordinary_handle" --outcome Closes >/dev/null
assert_field "$ordinary_handle" finalization finalized
second_ordinary="$(telemetry "$ordinary" start --issue 73)"
registry_in "$ordinary" register --run "$second_ordinary" >/dev/null \
  || fail "an ordinary run was refused by another repository's obligation"

scenario observer-absent-leaves-behaviour-unchanged
repo="$fixture/no-observer"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$first" >/dev/null
second="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$second" >/dev/null \
  || fail "an unobserved run was blocked by another unobserved run"
assert_field "$first" control_id null
# The pre-implementation rule governs observed runs; an unobserved run is an
# index entry and may be recorded whenever the workflow gets to it.
third="$(telemetry "$repo" start --issue 72)"
telemetry "$repo" launch --run "$third" --role implementation --phase implementation --round 1
registry_in "$repo" register --run "$third" >/dev/null \
  || fail "an ordinary run could not be recorded after work began"

# --- strict observer response grammar ---------------------------------------

scenario observer-answers-outside-the-documented-shape-fail-closed
enable_observer
repo="$fixture/policy"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
assert_policy_refused() {
  local label="$1" answer="$2" policy_handle
  policy_handle="$(telemetry "$repo" start --issue 72)"
  printf '%s' "$answer" >"$OBSERVER_FLAGS/applies-output"
  ! registry_in "$repo" register --run "$policy_handle" >/dev/null 2>&1 \
    || fail "observer answer '$label' was accepted"
  [[ -z "$(record_of "$policy_handle")" ]] \
    || fail "observer answer '$label' still produced a record"
}
assert_policy_refused extra-line 'observer=test-observer
control=demo-control
extra=surprise
'
assert_policy_refused bare-line 'observer=test-observer
control=demo-control
note
'
assert_policy_refused duplicate-observer 'observer=test-observer
observer=other-observer
control=demo-control
'
assert_policy_refused duplicate-control 'observer=test-observer
control=demo-control
control=other-control
'
assert_policy_refused missing-control 'observer=test-observer
'
assert_policy_refused missing-observer 'control=demo-control
'
assert_policy_refused doubled-hyphen 'observer=test-observer
control=bad--token
'
assert_policy_refused trailing-hyphen 'observer=test-observer
control=bad-
'
assert_policy_refused leading-hyphen 'observer=test-observer
control=-bad
'
assert_policy_refused empty-token 'observer=test-observer
control=
'
assert_policy_refused uppercase 'observer=test-observer
control=BadToken
'
assert_policy_refused spaced-keys 'observer = test-observer
control = demo-control
'
assert_policy_refused inline-space 'observer=test observer
control=demo-control
'
assert_policy_refused overlong "observer=test-observer
control=$(printf 'a%.0s' $(seq 1 65))
"
rm -f "$OBSERVER_FLAGS/applies-output"
: >"$OBSERVER_FLAGS/policy-error"
handle="$(telemetry "$repo" start --issue 72)"
! registry_in "$repo" register --run "$handle" >/dev/null 2>&1 \
  || fail "registration proceeded on an undecidable observer policy"
rm -f "$OBSERVER_FLAGS/policy-error"
# The documented shape itself is still accepted.
registry_in "$repo" register --run "$handle" >/dev/null \
  || fail "the documented observer answer was refused"
assert_field "$handle" control_id demo-control

# --- user-level roots are absolute ------------------------------------------

scenario relative-xdg-roots-are-refused
repo="$fixture/relative-roots"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
mkdir -p "$repo/work-on"
cat >"$repo/work-on/observer" <<EOF
#!/usr/bin/env bash
: >"$fixture/repository-observer-ran"
printf 'observer=repo-observer\ncontrol=repo-control\n'
EOF
chmod +x "$repo/work-on/observer"
handle="$(telemetry "$repo" start --issue 72)"
assert_root_refused() {
  local label="$1"
  shift
  ! ( cd "$repo" && env "$@" "$registry_script" register --run "$handle" ) \
    >/dev/null 2>&1 || fail "$label was accepted as a user-level root"
}
assert_root_refused relative-state XDG_STATE_HOME=.state \
  "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
assert_root_refused relative-config "XDG_STATE_HOME=$XDG_STATE_HOME" \
  XDG_CONFIG_HOME=.
assert_root_refused relative-observer "XDG_STATE_HOME=$XDG_STATE_HOME" \
  "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" WORK_ON_OBSERVER=work-on/observer
assert_root_refused relative-home --unset=XDG_STATE_HOME \
  --unset=XDG_CONFIG_HOME HOME=relative-home
[[ ! -e "$fixture/repository-observer-ran" ]] \
  || fail "repository content was executed as the observer policy"
[[ ! -e "$repo/.state" && ! -e "$repo/work-on/registry" ]] \
  || fail "registry state was created inside the repository"
# The absolute configuration still works from the same repository.
registry_in "$repo" register --run "$handle" >/dev/null
assert_field "$handle" control_id null

# --- recovery, canonical summary, durability --------------------------------

scenario recovery-is-idempotent-on-the-same-run
enable_observer
repo="$fixture/idempotent"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
before="$(record_count)"
registry_in "$repo" recover --run "$handle" --outcome abandoned >/dev/null
first_record="$(record_of "$handle")"
registry_in "$repo" recover --run "$handle" --outcome abandoned >/dev/null
registry_in "$repo" recover --run "$handle" >/dev/null
[[ "$(record_of "$handle")" == "$first_record" ]] \
  || fail "repeated recovery changed the finalized record"
[[ "$(record_count)" -eq "$before" ]] || fail "recovery minted a replacement record"
[[ "$(observer_acceptances)" -eq 1 ]] \
  || fail "recovery produced more than one logical observer transition"

scenario canonical-summary-hash-comes-from-the-sink
repo="$fixture/hash"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null
expected="$(telemetry "$repo" summary --run "$handle" | tr -d '\n' | sha256sum | cut -d' ' -f1)"
assert_field "$handle" summary_sha256 "$expected"

scenario worktree-removal-does-not-erase-the-record
repo="$fixture/durable"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
linked="$fixture/durable-linked"
git -C "$repo" worktree add -q -b feature "$linked" >/dev/null
handle="$(telemetry "$linked" start --issue 72)"
registry_in "$linked" register --run "$handle" >/dev/null
telemetry "$linked" resolve --run "$handle" --outcome Closes
git -C "$repo" worktree remove --force "$linked"
[[ ! -d "$linked" ]] || fail "the linked worktree was not removed"
[[ -n "$(record_of "$handle")" ]] || fail "worktree removal erased the registry record"
"$registry_script" recover --run "$handle" >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" outcome Closes

scenario missing-sink-becomes-unreproducible
repo="$fixture/missing-sink"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
rm -f "$(sink_of "$repo" "$handle")"
registry_in "$repo" recover --run "$handle" >/dev/null 2>&1
assert_field "$handle" finalization unreproducible
assert_field "$handle" failure_code SINK_MISSING
assert_field "$handle" run_id "${handle%@*}"

scenario missing-repository-becomes-unreproducible
enable_observer
repo="$fixture/missing-repo"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
rm -rf "$repo"
"$registry_script" recover --run "$handle" >/dev/null 2>&1
assert_field "$handle" finalization unreproducible
assert_field "$handle" failure_code REPOSITORY_MISSING
assert_field "$handle" repository example/telemetry
assert_field "$handle" issue 72
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
next="$(telemetry "$repo" start --issue 73)"
registry_in "$repo" register --run "$next" >/dev/null \
  || fail "an unreproducible obligation kept blocking new runs"
[[ "$(record_count)" -eq 2 ]] || fail "the unreproducible run left the population"

# --- concurrency proven at the contested boundary ---------------------------

scenario competing-matching-starts-cannot-both-proceed
enable_observer
repo="$fixture/competing"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
second="$(telemetry "$repo" start --issue 73)"
"$registry_script" status >/dev/null
hold_registry_lock -x
launch_competitor competing-first "$repo" "$registry_script" register --run "$first"
launch_competitor competing-second "$repo" "$registry_script" register --run "$second"
assert_blocked_and_live competing-first
assert_blocked_and_live competing-second
release_registry_lock
granted=0
for label in competing-first competing-second; do
  [[ "$(competitor_result "$label")" != granted ]] || granted=$(( granted + 1 ))
done
wait
[[ "$granted" -eq 1 ]] \
  || fail "$granted competing matching starts acquired permission to proceed"
[[ "$(record_count)" -eq 1 ]] \
  || fail "a refused competing start still left a registry record"

scenario same-record-finalizations-arbitrate-and-unrelated-ones-progress
enable_observer
: >"$OBSERVER_FLAGS/per-issue-controls"
repo="$fixture/concurrent"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
linked="$fixture/concurrent-linked"
git -C "$repo" worktree add -q -b concurrent "$linked" >/dev/null
held_handle="$(telemetry "$repo" start --issue 72)"
unrelated_handle="$(telemetry "$linked" start --issue 73)"
registry_in "$repo" register --run "$held_handle" >/dev/null
registry_in "$linked" register --run "$unrelated_handle" >/dev/null
# One finalization is held inside its observer, so it owns the shared registry
# lock and its own record lock for as long as the fixture wants. Only that
# record is held: the unrelated one must be free to finish meanwhile.
printf '%s' "${held_handle%@*}" >"$OBSERVER_FLAGS/wait-for-release"
launch_competitor concurrent-held "$repo" "$registry_script" finalize \
  --run "$held_handle" --outcome Closes
wait_for_file "$OBSERVER_FLAGS/observer-entered"
# A. Same record: a second finalization cannot cross the record boundary.
launch_competitor concurrent-same "$repo" "$registry_script" finalize \
  --run "$held_handle" --outcome Closes
assert_blocked_and_live concurrent-same
# B. Unrelated record: finalization completes while A is still held, which a
# globally serialized implementation could not do. It is launched the same way,
# so a serialized implementation fails the bounded wait instead of passing.
launch_competitor concurrent-unrelated "$linked" "$registry_script" finalize \
  --run "$unrelated_handle" --outcome Progresses
[[ "$(competitor_result concurrent-unrelated)" == granted ]] \
  || fail "an unrelated record could not finalize during a live transition"
assert_field "$unrelated_handle" finalization finalized
assert_field "$unrelated_handle" outcome Progresses
[[ ! -e "$fixture/concurrent-held.result" ]] \
  || fail "the held finalization completed before its boundary was released"
[[ ! -e "$fixture/concurrent-same.result" ]] \
  || fail "the same-record competitor crossed the boundary before release"
: >"$OBSERVER_FLAGS/release"
[[ "$(competitor_result concurrent-held)" == granted ]] \
  || fail "the held finalization did not complete"
[[ "$(competitor_result concurrent-same)" == granted ]] \
  || fail "the same-record retry did not resolve idempotently after release"
wait
rm -f "$OBSERVER_FLAGS/wait-for-release" "$OBSERVER_FLAGS/release" \
  "$OBSERVER_FLAGS/observer-entered"
assert_field "$held_handle" finalization finalized
assert_field "$held_handle" outcome Closes
[[ "$(observer_acceptances)" -eq 2 ]] \
  || fail "the two records did not produce exactly one transition each"
[[ "$(record_count)" -eq 2 ]] || fail "concurrent finalization lost or added records"

scenario prune-cannot-run-during-a-live-transition
enable_observer
repo="$fixture/prune-race"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
: >"$OBSERVER_FLAGS/wait-for-release"
: >"$OBSERVER_FLAGS/finalize-error"
launch_competitor prune-finalize "$repo" "$registry_script" finalize \
  --run "$handle" --outcome Closes
wait_for_file "$OBSERVER_FLAGS/observer-entered"
launch_competitor prune-cleanup "$repo" "$registry_script" prune --older-than-days 0
assert_blocked_and_live prune-cleanup
[[ -n "$(record_of "$handle")" ]] || fail "the record vanished during its own transition"
: >"$OBSERVER_FLAGS/release"
[[ "$(competitor_result prune-finalize)" == refused ]] \
  || fail "the observer failure did not surface"
[[ "$(competitor_result prune-cleanup)" == granted ]] \
  || fail "prune did not complete after the transition finished"
wait
[[ "$(cat "$fixture/prune-cleanup.out")" == 'pruned 0' ]] \
  || fail "prune removed a record an observer still needs"
assert_field "$handle" finalization failed
assert_field "$handle" failure_code OBSERVER_FAILED
shopt -s nullglob
staged=("$(registry_root)"/runs/*.staged.*)
shopt -u nullglob
[[ "${#staged[@]}" -eq 0 ]] || fail "a staged write escaped the transition"

scenario capacity-eviction-waits-for-a-live-transition
enable_observer
: >"$OBSERVER_FLAGS/per-issue-controls"
export WORK_ON_REGISTRY_CAPACITY=2
governed="$fixture/evict-governed"
ordinary="$fixture/evict-ordinary"
new_repo "$governed" 'git@github.com:Example/Telemetry.git'
new_repo "$ordinary" 'git@github.com:Example/Other.git'
ordinary_handle="$(telemetry "$ordinary" start --issue 72)"
registry_in "$ordinary" register --run "$ordinary_handle" >/dev/null
governed_handle="$(telemetry "$governed" start --issue 72)"
registry_in "$governed" register --run "$governed_handle" >/dev/null
[[ "$(record_count)" -eq 2 ]] || fail "the capacity fixture is not full"
: >"$OBSERVER_FLAGS/wait-for-release"
launch_competitor evict-finalize "$governed" "$registry_script" finalize \
  --run "$governed_handle" --outcome Closes
wait_for_file "$OBSERVER_FLAGS/observer-entered"
next_handle="$(telemetry "$governed" start --issue 99)"
launch_competitor evict-register "$governed" "$registry_script" register \
  --run "$next_handle"
assert_blocked_and_live evict-register
: >"$OBSERVER_FLAGS/release"
[[ "$(competitor_result evict-finalize)" == granted ]] \
  || fail "the live transition did not complete"
[[ "$(competitor_result evict-register)" == granted ]] \
  || fail "admission did not proceed once the transition finished"
wait
assert_field "$governed_handle" finalization finalized
assert_field "$next_handle" finalization pending
[[ -z "$(record_of "$ordinary_handle")" ]] \
  || fail "eviction did not reclaim the ungoverned record"
[[ "$(record_count)" -eq 2 ]] || fail "the registry grew past its capacity"
unset WORK_ON_REGISTRY_CAPACITY

scenario staged-write-artifacts-are-reaped
repo="$fixture/staged"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
orphan="$(registry_root)/runs/$handle.json.staged.999999"
printf '{"crash":true}\n' >"$orphan"
"$registry_script" prune --older-than-days 3650 >/dev/null
[[ ! -e "$orphan" ]] || fail "a crashed writer's staged file survived cleanup"
[[ -n "$(record_of "$handle")" ]] || fail "cleanup removed a live record"

# --- capacity and retention -------------------------------------------------

scenario capacity-exhaustion-fails-closed-for-governed-runs
enable_observer
: >"$OBSERVER_FLAGS/per-issue-controls"
export WORK_ON_REGISTRY_CAPACITY=2
repo="$fixture/capacity"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$first" >/dev/null
second="$(telemetry "$repo" start --issue 73)"
registry_in "$repo" register --run "$second" >/dev/null
[[ "$(record_count)" -eq 2 ]] || fail "the registry did not reach capacity"
# Distinct controls, so the same-control guard cannot decide this attempt: the
# only thing left to refuse it is capacity itself.
third="$(telemetry "$repo" start --issue 74)"
refusal="$fixture/capacity-refusal"
! registry_in "$repo" register --run "$third" >"$refusal" 2>&1 \
  || fail "a governed run was admitted with no safe capacity"
grep -Fq 'registry capacity 2 is exhausted' "$refusal" \
  || fail "the refusal is not the capacity-specific diagnostic"
! grep -Fq 'a prior observed run has an unfinished obligation' "$refusal" \
  || fail "the same-control guard decided the capacity attempt"
[[ -z "$(record_of "$third")" ]] || fail "the refused run was still recorded"
assert_field "$first" finalization pending
assert_field "$second" finalization pending
[[ "$(record_count)" -eq 2 ]] || fail "the refusal changed the registry contents"
# The identical attempt succeeds once capacity allows it, so capacity — and not
# some other refusal — is what decided the previous attempt.
WORK_ON_REGISTRY_CAPACITY=3 registry_in "$repo" register --run "$third" >/dev/null \
  || fail "the same registration failed for a reason other than capacity"
assert_field "$third" finalization pending
unset WORK_ON_REGISTRY_CAPACITY

scenario ordinary-run-completes-hand-back-without-a-record
enable_observer
: >"$OBSERVER_FLAGS/per-issue-controls"
export WORK_ON_REGISTRY_CAPACITY=2
governed="$fixture/fallback-governed"
ordinary="$fixture/fallback-ordinary"
new_repo "$governed" 'git@github.com:Example/Telemetry.git'
new_repo "$ordinary" 'git@github.com:Example/Other.git'
for issue in 72 73; do
  governed_handle="$(telemetry "$governed" start --issue "$issue")"
  registry_in "$governed" register --run "$governed_handle" >/dev/null
done
[[ "$(record_count)" -eq 2 ]] || fail "the registry did not reach capacity"
ordinary_handle="$(telemetry "$ordinary" start --issue 72)"
admission="$fixture/fallback-admission"
registry_in "$ordinary" register --run "$ordinary_handle" >"$admission" 2>&1 \
  || fail "an ordinary run was blocked by exhausted control capacity"
grep -Fq 'continues unregistered' "$admission" \
  || fail "admission did not say the ordinary run continues unregistered"
[[ -z "$(record_of "$ordinary_handle")" ]] || fail "an unadmitted run was recorded"
telemetry "$ordinary" launch --run "$ordinary_handle" --role implementation \
  --phase implementation --round 1
# The whole hand-back still completes: a run that was allowed to proceed can
# always finish, through #71's own resolve/seal path.
[[ "$(registry_in "$ordinary" finalize --run "$ordinary_handle" --outcome Closes)" \
  == "finalized ${ordinary_handle%@*} unregistered" ]] \
  || fail "the unregistered ordinary hand-back did not complete"
summary="$(telemetry "$ordinary" summary --run "$ordinary_handle")"
[[ "$(jq -r '.integrity.state' <<<"$summary")" == valid ]] \
  || fail "the unregistered hand-back left an invalid sink"
[[ "$(jq -r '.final_workflow_outcome' <<<"$summary")" == Closes ]] \
  || fail "the unregistered hand-back lost its outcome"
[[ "$(jq -r '.sealed_at' <<<"$summary")" != null ]] \
  || fail "the unregistered hand-back did not seal the run"
# A governed run reaching hand-back unregistered is still a hard failure.
unregistered_governed="$(telemetry "$governed" start --issue 91)"
! registry_in "$governed" finalize --run "$unregistered_governed" --outcome Closes \
  >/dev/null 2>&1 \
  || fail "a governed run finalized without ever being registered"
unset WORK_ON_REGISTRY_CAPACITY

scenario retention-protects-outstanding-obligations
enable_observer
repo="$fixture/retention"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
outstanding="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$outstanding" >/dev/null
ordinary_repo="$fixture/retention-ordinary"
new_repo "$ordinary_repo" 'git@github.com:Example/Other.git'
ordinary_handle="$(telemetry "$ordinary_repo" start --issue 72)"
registry_in "$ordinary_repo" register --run "$ordinary_handle" >/dev/null
[[ "$("$registry_script" prune --older-than-days 0)" == 'pruned 1' ]] \
  || fail "prune did not drop exactly the one retainable record"
[[ -n "$(record_of "$outstanding")" ]] \
  || fail "prune erased a record an observer still needs"
registry_in "$repo" finalize --run "$outstanding" --outcome Closes >/dev/null
[[ "$("$registry_script" prune --older-than-days 0)" == 'pruned 1' ]] \
  || fail "prune did not drop the discharged obligation"
[[ "$(record_count)" -eq 0 ]] || fail "prune left records behind"

# --- ownership and privacy --------------------------------------------------

scenario registry-is-owner-only
repo="$fixture/permissions"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
while IFS= read -r entry; do
  mode="$(stat -c '%a' "$entry")"
  if [[ -d "$entry" ]]; then
    [[ "$mode" == 700 ]] || fail "directory $entry is mode $mode"
  else
    [[ "$mode" == 600 ]] || fail "file $entry is mode $mode"
  fi
done < <(find "$(registry_root)")

scenario registry-holds-no-raw-telemetry
enable_observer
repo="$fixture/privacy"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
telemetry "$repo" exec --run "$handle" --command-id secret-looking-check \
  --phase gate --round 1 -- printf 'sensitive output\n' >/dev/null
registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null
[[ "$(record_of "$handle" | jq -sc 'map(keys) | unique')" == \
  '[["control_id","failure_code","finalization","finalization_id","issue","lifecycle","observer","outcome","registered_at","repository","repository_binding","run_id","schema","sink","summary_sha256","telemetry_schema","updated_at","updated_epoch","worktree"]]' ]] \
  || fail "the registry record does not carry exactly the bounded field set"
for forbidden in '"type"' 'subagent_launch' 'validation_start' 'epoch_ms' \
  'secret-looking-check' 'sensitive output'; do
  ! grep -rqF "$forbidden" "$(registry_root)" \
    || fail "the registry stored prohibited material: $forbidden"
done

# --- final-confirmation regressions -----------------------------------------

scenario unregistered-fallback-enforces-sink-truth
enable_observer
: >"$OBSERVER_FLAGS/per-issue-controls"
export WORK_ON_REGISTRY_CAPACITY=1
governed="$fixture/fallback-truth-governed"
ordinary="$fixture/fallback-truth"
new_repo "$governed" 'git@github.com:Example/Telemetry.git'
new_repo "$ordinary" 'git@github.com:Example/Other.git'
governed_handle="$(telemetry "$governed" start --issue 72)"
registry_in "$governed" register --run "$governed_handle" >/dev/null
# Every run below is admitted as "continues unregistered", so each exercises the
# fallback rather than a registry row.
unregistered_run() {
  local handle
  handle="$(telemetry "$ordinary" start --issue "$1")"
  registry_in "$ordinary" register --run "$handle" >/dev/null 2>&1
  [[ -z "$(record_of "$handle")" ]] || fail "the fallback fixture registered a row"
  printf '%s\n' "$handle"
}
# An invalid sink cannot be reported as finalized.
invalid_handle="$(unregistered_run 81)"
printf 'not json\n' >>"$(sink_of "$ordinary" "$invalid_handle")"
! registry_in "$ordinary" finalize --run "$invalid_handle" --outcome Closes \
  >"$fixture/fallback-invalid.out" 2>&1 \
  || fail "the unregistered fallback finalized an invalid sink"
! grep -Fq 'finalized' "$fixture/fallback-invalid.out" \
  || fail "the unregistered fallback claimed success for an invalid sink"
grep -Fq 'integrity is invalid' "$fixture/fallback-invalid.out" \
  || fail "the unregistered refusal does not name the integrity state"
# A contradictory assertion cannot be accepted, and must not seal the run.
conflict_handle="$(unregistered_run 82)"
telemetry "$ordinary" resolve --run "$conflict_handle" --outcome Progresses
! registry_in "$ordinary" finalize --run "$conflict_handle" --outcome Closes \
  >"$fixture/fallback-conflict.out" 2>&1 \
  || fail "the unregistered fallback accepted a contradictory outcome"
! grep -Fq 'finalized' "$fixture/fallback-conflict.out" \
  || fail "the unregistered fallback claimed a false outcome assertion succeeded"
[[ "$(telemetry "$ordinary" summary --run "$conflict_handle" | jq -r '.sealed_at')" == null ]] \
  || fail "a refused unregistered assertion still sealed the run"
registry_in "$ordinary" finalize --run "$conflict_handle" --outcome Progresses >/dev/null \
  || fail "the honest unregistered assertion was refused"
# The ordinary happy paths still complete for both closing outcomes.
for outcome in Closes Progresses; do
  happy_handle="$(unregistered_run 83)"
  telemetry "$ordinary" launch --run "$happy_handle" --role implementation \
    --phase implementation --round 1
  [[ "$(registry_in "$ordinary" finalize --run "$happy_handle" --outcome "$outcome")" \
    == "finalized ${happy_handle%@*} unregistered" ]] \
    || fail "the ordinary unregistered $outcome hand-back did not complete"
  summary="$(telemetry "$ordinary" summary --run "$happy_handle")"
  [[ "$(jq -r '.integrity.state' <<<"$summary")" == valid ]] \
    || fail "the unregistered $outcome hand-back left an invalid sink"
  [[ "$(jq -r '.final_workflow_outcome' <<<"$summary")" == "$outcome" ]] \
    || fail "the unregistered hand-back lost its $outcome outcome"
done
unset WORK_ON_REGISTRY_CAPACITY

scenario re-registration-refuses-governance-drift
enable_observer
repo="$fixture/drift"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
# The reproduced sequence: an ungoverned run does work, then an observer starts
# applying, and the retry must not claim a governance the record does not hold.
ungoverned="$(telemetry "$repo" start --issue 72)"
( cd "$repo" && env -u WORK_ON_OBSERVER "$registry_script" register --run "$ungoverned" ) >/dev/null
assert_field "$ungoverned" control_id null
telemetry "$repo" launch --run "$ungoverned" --role implementation \
  --phase implementation --round 1
printf 'observer=late-observer\ncontrol=shared-token\n' >"$OBSERVER_FLAGS/applies-identity"
! registry_in "$repo" register --run "$ungoverned" >"$fixture/drift-late.out" 2>&1 \
  || fail "an ungoverned record was re-registered as governed"
grep -Fq 'refusing a retry' "$fixture/drift-late.out" \
  || fail "the drift refusal is not the governance-drift diagnostic"
assert_field "$ungoverned" control_id null
assert_field "$ungoverned" observer null
# ungoverned -> same ungoverned is idempotent.
rm -f "$OBSERVER_FLAGS/applies-identity"
( cd "$repo" && env -u WORK_ON_OBSERVER "$registry_script" register --run "$ungoverned" ) >/dev/null \
  || fail "an unchanged ungoverned retry was refused"
# governed A/X -> same A/X is idempotent; every drift is refused.
printf 'observer=observer-a\ncontrol=control-x\n' >"$OBSERVER_FLAGS/applies-identity"
governed="$(telemetry "$repo" start --issue 73)"
registry_in "$repo" register --run "$governed" >/dev/null
assert_field "$governed" observer observer-a
assert_field "$governed" control_id control-x
registry_in "$repo" register --run "$governed" >/dev/null \
  || fail "an unchanged governed retry was refused"
assert_drift_refused() {
  local label="$1" answer="$2"
  if [[ "$answer" == none ]]; then
    rm -f "$OBSERVER_FLAGS/applies-identity"
  else
    printf '%s' "$answer" >"$OBSERVER_FLAGS/applies-identity"
  fi
  ! registry_in "$repo" register --run "$governed" >/dev/null 2>&1 \
    || fail "governance drift '$label' was accepted"
  assert_field "$governed" observer observer-a
  assert_field "$governed" control_id control-x
}
assert_drift_refused governed-to-ungoverned none
assert_drift_refused observer-change 'observer=observer-b
control=control-x
'
assert_drift_refused control-change 'observer=observer-a
control=control-y
'
rm -f "$OBSERVER_FLAGS/applies-identity"

scenario stored-observer-identity-is-immutable
enable_observer
repo="$fixture/observer-identity"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
printf 'observer=original-observer\ncontrol=shared-token\n' \
  >"$OBSERVER_FLAGS/applies-identity"
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
assert_field "$handle" observer original-observer
# A replacement executable that answers with a different identity, and whose
# finalize would happily succeed, cannot discharge this obligation.
replacement="$fixture/replacement-observer"
cat >"$replacement" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\$1" in
  applies) printf 'observer=replacement-observer\ncontrol=replacement-control\n' ;;
  finalize) : >"$fixture/replacement-finalized" ;;
esac
EOF
chmod +x "$replacement"
! ( cd "$repo" && WORK_ON_OBSERVER="$replacement" "$registry_script" finalize \
  --run "$handle" --outcome Closes ) >/dev/null 2>&1 \
  || fail "a replacement observer discharged another observer's obligation"
[[ ! -e "$fixture/replacement-finalized" ]] \
  || fail "the replacement observer was called at all"
assert_field "$handle" finalization failed
assert_field "$handle" failure_code OBSERVER_IDENTITY_MISMATCH
[[ "$(observer_acceptances)" -eq 0 ]] || fail "the obligation was discharged"
# A different token or control from the configured policy is refused the same way.
assert_identity_refused() {
  local label="$1" answer="$2"
  printf '%s' "$answer" >"$OBSERVER_FLAGS/applies-identity"
  ! registry_in "$repo" recover --run "$handle" >/dev/null 2>&1 \
    || fail "observer identity '$label' discharged the obligation"
  assert_field "$handle" failure_code OBSERVER_IDENTITY_MISMATCH
  assert_field "$handle" observer original-observer
  assert_field "$handle" control_id shared-token
}
assert_identity_refused observer-token 'observer=other-observer
control=shared-token
'
assert_identity_refused control-id 'observer=original-observer
control=other-token
'
# An unreachable observer leaves the obligation outstanding.
! ( cd "$repo" && env -u WORK_ON_OBSERVER XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
  "$registry_script" recover --run "$handle" ) >/dev/null 2>&1 \
  || fail "a missing observer discharged the obligation"
assert_field "$handle" failure_code OBSERVER_FAILED
assert_field "$handle" finalization failed
# The stored pair still finalizes, reusing the exact transition identity.
printf 'observer=original-observer\ncontrol=shared-token\n' \
  >"$OBSERVER_FLAGS/applies-identity"
transition_before="$(record_of "$handle" | jq -r '.finalization_id')"
registry_in "$repo" recover --run "$handle" >/dev/null
assert_field "$handle" finalization finalized
assert_field "$handle" finalization_id "$transition_before"
[[ "$(observer_acceptances)" -eq 1 ]] || fail "the stored observer did not discharge once"
rm -f "$OBSERVER_FLAGS/applies-identity"

scenario observer-answers-with-nul-bytes-fail-closed
enable_observer
repo="$fixture/nul"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
for flag in applies-nul applies-embedded-nul; do
  : >"$OBSERVER_FLAGS/$flag"
  nul_handle="$(telemetry "$repo" start --issue 72)"
  ! registry_in "$repo" register --run "$nul_handle" >/dev/null 2>&1 \
    || fail "an applicability answer containing a NUL byte was accepted"
  [[ -z "$(record_of "$nul_handle")" ]] \
    || fail "a NUL-bearing answer still produced a record"
  rm -f "$OBSERVER_FLAGS/$flag"
done
# The documented shape still succeeds, and its capture is owner-only and gone.
: >"$OBSERVER_FLAGS/report-capture"
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
assert_field "$handle" control_id demo-control
[[ "$(count_lines "$OBSERVER_FLAGS/capture-report")" -ge 1 ]] \
  || fail "the observer did not report its capture artifact"
while read -r capture_path capture_mode; do
  [[ "$capture_mode" == 600 ]] \
    || fail "the applicability capture was mode $capture_mode"
  [[ ! -e "$capture_path" ]] \
    || fail "the applicability capture survived the command"
  [[ "$capture_path" != "$(registry_root)"/* ]] \
    || fail "the applicability capture was written into the registry"
done <"$OBSERVER_FLAGS/capture-report"
rm -f "$OBSERVER_FLAGS/report-capture"

scenario finalized-runs-still-validate-outcome-assertions
enable_observer
: >"$OBSERVER_FLAGS/per-issue-controls"
repo="$fixture/finalized-assertions"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null
registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null \
  || fail "an identical finalize retry was refused"
registry_in "$repo" finalize --run "$handle" >/dev/null \
  || fail "a finalize retry with no assertion was refused"
! registry_in "$repo" finalize --run "$handle" --outcome Progresses \
  >"$fixture/finalized-conflict.out" 2>&1 \
  || fail "a contradictory assertion was acknowledged on a finalized run"
grep -Fq 'already finalized as Closes' "$fixture/finalized-conflict.out" \
  || fail "the refusal does not name the durable outcome"
assert_field "$handle" outcome Closes
other="$(telemetry "$repo" start --issue 73)"
registry_in "$repo" register --run "$other" >/dev/null
registry_in "$repo" finalize --run "$other" --outcome abandoned >/dev/null
! registry_in "$repo" finalize --run "$other" --outcome failed >/dev/null 2>&1 \
  || fail "a contradictory assertion was acknowledged for abandoned"
assert_field "$other" outcome abandoned
# Recovery keeps its offer-only semantics on a finalized run.
registry_in "$repo" recover --run "$handle" --outcome Progresses >/dev/null \
  || fail "recovery stopped being an offer on a finalized run"
assert_field "$handle" outcome Closes

# --- maintainer-directed corrections ----------------------------------------

scenario finalized-retries-reconcile-with-the-sink
repo="$fixture/reconcile"
new_repo "$repo" 'git@github.com:Example/Other.git'
finalized_run() {
  local handle
  handle="$(telemetry "$repo" start --issue "$1")"
  registry_in "$repo" register --run "$handle" >/dev/null
  registry_in "$repo" finalize --run "$handle" --outcome "${2:-Closes}" >/dev/null
  printf '%s\n' "$handle"
}
# C. An unchanged sink and row stay idempotently successful.
happy="$(finalized_run 71)"
[[ "$(registry_in "$repo" finalize --run "$happy")" == "finalized ${happy%@*}" ]] \
  || fail "an unchanged finalized retry stopped being idempotent"
[[ "$(registry_in "$repo" finalize --run "$happy" --outcome Closes)" \
  == "finalized ${happy%@*}" ]] \
  || fail "an unchanged finalized assertion stopped being idempotent"
assert_field "$happy" finalization finalized
# A. Corruption appended after the recorded finalization must not be blessed.
corrupted="$(finalized_run 72)"
printf 'not json\n' >>"$(sink_of "$repo" "$corrupted")"
! registry_in "$repo" finalize --run "$corrupted" >"$fixture/reconcile-a.out" 2>&1 \
  || fail "a finalized retry succeeded for a sink corrupted after finalization"
! grep -Fq 'finalized ' "$fixture/reconcile-a.out" \
  || fail "the retry printed successful finalized status for a corrupted sink"
assert_field "$corrupted" finalization failed
assert_field "$corrupted" failure_code INTEGRITY_INVALID
# D. Recovery reconciles the same way.
recovered="$(finalized_run 73)"
printf 'not json\n' >>"$(sink_of "$repo" "$recovered")"
! registry_in "$repo" recover --run "$recovered" >"$fixture/reconcile-d.out" 2>&1 \
  || fail "a finalized recovery succeeded for a corrupted sink"
! grep -Fq 'finalized ' "$fixture/reconcile-d.out" \
  || fail "recovery printed successful finalized status for a corrupted sink"
assert_field "$recovered" failure_code INTEGRITY_INVALID
# B. A row edited to another schema-valid outcome cannot outvote the sink, and
# the false assertion that matches the row is refused.
outvoted="$(finalized_run 74 Closes)"
record_file="$(registry_root)/runs/$outvoted.json"
jq -c '.outcome = "Progresses"' "$record_file" >"$record_file.rewritten"
mv "$record_file.rewritten" "$record_file"
! registry_in "$repo" finalize --run "$outvoted" --outcome Progresses \
  >"$fixture/reconcile-b.out" 2>&1 \
  || fail "a stale registry outcome outvoted the canonical sink"
! grep -Fq 'finalized ' "$fixture/reconcile-b.out" \
  || fail "the retry printed successful finalized status for a stale row"
assert_field "$outvoted" failure_code IDENTITY_MISMATCH
[[ "$(telemetry "$repo" summary --run "$outvoted" | jq -r '.final_workflow_outcome')" == Closes ]] \
  || fail "the canonical sink outcome changed"
# E. A stored hash that no longer matches the canonical summary is rejected.
rehashed="$(finalized_run 75)"
record_file="$(registry_root)/runs/$rehashed.json"
jq -c '.summary_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
  "$record_file" >"$record_file.rewritten"
mv "$record_file.rewritten" "$record_file"
! registry_in "$repo" finalize --run "$rehashed" >/dev/null 2>&1 \
  || fail "a finalized retry accepted a summary hash that no longer matches"
assert_field "$rehashed" failure_code IDENTITY_MISMATCH
# F. Missing canonical evidence takes the bounded unreproducible path.
vanished="$(finalized_run 76)"
rm -f "$(sink_of "$repo" "$vanished")"
registry_in "$repo" finalize --run "$vanished" >"$fixture/reconcile-f.out" 2>&1
! grep -Fq 'finalized ' "$fixture/reconcile-f.out" \
  || fail "a finalized retry claimed success with no canonical evidence"
assert_field "$vanished" finalization unreproducible
assert_field "$vanished" failure_code SINK_MISSING

scenario ordinary-runs-survive-registry-storage-failure
enable_observer
governed="$fixture/storage-governed"
ordinary="$fixture/storage-ordinary"
new_repo "$governed" 'git@github.com:Example/Telemetry.git'
new_repo "$ordinary" 'git@github.com:Example/Other.git'
break_state_root() {
  mkdir -p "$XDG_STATE_HOME/work-on"
  chmod 500 "$XDG_STATE_HOME/work-on"
}
repair_state_root() {
  chmod 700 "$XDG_STATE_HOME/work-on"
}
# A. No observer applies, and the registry cannot be created at all.
break_state_root
ordinary_handle="$(telemetry "$ordinary" start --issue 72)"
admission="$fixture/storage-admission"
registry_in "$ordinary" register --run "$ordinary_handle" >"$admission" 2>&1 \
  || fail "an ordinary run failed because optional registry storage was unavailable"
grep -Fq 'continues unregistered' "$admission" \
  || fail "the ordinary run was not routed to the unregistered path"
# E. Nothing is claimed or created that could not be persisted.
! grep -Fq 'registered ' "$admission" \
  || fail "admission claimed a registration it could not persist"
[[ ! -e "$(registry_root)" ]] || fail "a registry was created despite the failure"
# D. Its hand-back still completes through the hardened unregistered path.
telemetry "$ordinary" launch --run "$ordinary_handle" --role implementation \
  --phase implementation --round 1
[[ "$(registry_in "$ordinary" finalize --run "$ordinary_handle" --outcome Closes)" \
  == "finalized ${ordinary_handle%@*} unregistered" ]] \
  || fail "the ordinary hand-back did not complete without registry storage"
summary="$(telemetry "$ordinary" summary --run "$ordinary_handle")"
[[ "$(jq -r '.integrity.state' <<<"$summary")" == valid \
  && "$(jq -r '.final_workflow_outcome' <<<"$summary")" == Closes \
  && "$(jq -r '.sealed_at' <<<"$summary")" != null ]] \
  || fail "the storage-failure hand-back did not produce a sealed valid sink"
# B. The same failure is fatal for a governed run, before implementation.
governed_handle="$(telemetry "$governed" start --issue 72)"
! registry_in "$governed" register --run "$governed_handle" >/dev/null 2>&1 \
  || fail "a governed run proceeded without a recorded obligation"
repair_state_root
# C. A failure beyond root creation: the registry lock cannot be acquired.
seed="$fixture/storage-seed"
new_repo "$seed" 'git@github.com:Example/Other.git'
seed_handle="$(telemetry "$seed" start --issue 72)"
registry_in "$seed" register --run "$seed_handle" >/dev/null
rm -f "$(registry_root)/registry.lock"
mkdir "$(registry_root)/registry.lock"
locked_ordinary="$(telemetry "$ordinary" start --issue 73)"
locked_admission="$fixture/storage-locked-admission"
registry_in "$ordinary" register --run "$locked_ordinary" >"$locked_admission" 2>&1 \
  || fail "an ordinary run failed because the registry lock was unusable"
grep -Fq 'continues unregistered' "$locked_admission" \
  || fail "an unusable registry lock did not route the ordinary run"
locked_governed="$(telemetry "$governed" start --issue 73)"
! registry_in "$governed" register --run "$locked_governed" >/dev/null 2>&1 \
  || fail "a governed run proceeded with an unusable registry lock"
[[ "$(registry_in "$ordinary" finalize --run "$locked_ordinary" --outcome Progresses)" \
  == "finalized ${locked_ordinary%@*} unregistered" ]] \
  || fail "the ordinary hand-back did not complete with an unusable registry lock"
rmdir "$(registry_root)/registry.lock"
# F. The capacity fallback is unchanged: the seeded record is still there.
[[ -n "$(record_of "$seed_handle")" ]] \
  || fail "the seeded registry record did not survive the storage failures"

printf 'run registry scenarios passed\n'
