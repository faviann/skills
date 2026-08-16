#!/usr/bin/env bash
set -euo pipefail

# Black-box scenarios for the user-level run registry and its observer seam.
# Every assertion goes through the public commands: nothing here reads or
# repairs a registry record by hand, and the only file inspection is the
# privacy/permission evidence the ticket requires.

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
  export HOME="$fixture/home/$1"
  mkdir -p "$HOME"
  unset WORK_ON_OBSERVER
  printf '  %s\n' "$1"
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
  local run_id="$1"
  "$registry_script" status --run-id "$run_id"
}

assert_field() {
  local run_id="$1" field="$2" expected="$3" observed
  observed="$(record_of "$run_id" | jq -r --arg field "$field" '.[$field] // "null"')"
  [[ "$observed" == "$expected" ]] \
    || fail "run $run_id has $field=$observed, expected $expected"
}

record_count() {
  "$registry_script" status | jq -s 'length'
}

# One observer program serves every scenario. Its policy, its finalization
# result, and whether it crashes its caller are all driven by fixture flag
# files, so a scenario changes observer behaviour without changing the seam.
observer_program="$fixture/observer"
cat >"$observer_program" <<'OBSERVER'
#!/usr/bin/env bash
set -euo pipefail
flags="$OBSERVER_FLAGS"
case "${1:-}" in
  applies)
    shift
    repository=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repository) repository="$2"; shift 2 ;;
        --issue) shift 2 ;;
        *) shift ;;
      esac
    done
    [[ ! -e "$flags/policy-error" ]] || exit 9
    [[ ! -e "$flags/policy-garbage" ]] || { printf 'observer=BAD ID\n'; exit 0; }
    [[ "$repository" == example/telemetry ]] || exit 3
    printf 'observer=test-observer\ncontrol=demo-control\n'
    ;;
  finalize)
    [[ ! -e "$flags/kill-caller" ]] || kill -9 "$PPID"
    [[ ! -e "$flags/finalize-error" ]] || exit 1
    printf '%s\n' "$3" >>"$flags/finalized-records"
    ;;
  *) exit 2 ;;
esac
OBSERVER
chmod +x "$observer_program"
export OBSERVER_FLAGS="$fixture/flags"
mkdir -p "$OBSERVER_FLAGS"

enable_observer() {
  export WORK_ON_OBSERVER="$observer_program"
}

clear_observer_flags() {
  rm -f "$OBSERVER_FLAGS"/policy-error "$OBSERVER_FLAGS"/policy-garbage \
    "$OBSERVER_FLAGS"/finalize-error "$OBSERVER_FLAGS"/kill-caller
}
clear_observer_flags

printf 'run registry scenarios\n'

# --- 1-4: every outcome finalizes -------------------------------------------

scenario closes-finalizes-automatically
repo="$fixture/closes"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
telemetry "$repo" exec --run "$handle" --command-id registry-tests --phase gate --round 1 -- true
# The workflow resolves at the closure gate and keeps recording closeout
# evidence; finalization seals only afterwards, exactly as #71 allows.
telemetry "$repo" resolve --run "$handle" --outcome Closes
telemetry "$repo" exec --run "$handle" --command-id registry-tests --phase closeout --round 1 -- true
[[ "$(registry_in "$repo" finalize --run "$handle")" == "finalized $run_id" ]] \
  || fail "finalize did not report the run finalized"
assert_field "$run_id" finalization finalized
assert_field "$run_id" outcome Closes
assert_field "$run_id" lifecycle sealed
assert_field "$run_id" failure_code null
[[ "$(telemetry "$repo" summary --run "$handle" | jq -r '.integrity.state')" == valid ]] \
  || fail "the finalized run's telemetry is not valid"

scenario progresses-finalizes-automatically
repo="$fixture/progresses"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
# Hand-back supplies the outcome: finalization resolves, seals, and discharges
# in one step rather than relying on a remembered operator sequence.
registry_in "$repo" finalize --run "$handle" --outcome Progresses >/dev/null
assert_field "$run_id" finalization finalized
assert_field "$run_id" outcome Progresses
assert_field "$run_id" lifecycle sealed

scenario preflight-aborted-finalizes-automatically
repo="$fixture/preflight"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
registry_in "$repo" finalize --run "$handle" --outcome preflight-aborted >/dev/null
assert_field "$run_id" finalization finalized
assert_field "$run_id" outcome preflight-aborted

scenario abandoned-and-failed-remain-finalizable
for outcome in abandoned failed; do
  repo="$fixture/$outcome"
  new_repo "$repo" 'git@github.com:Example/Telemetry.git'
  handle="$(telemetry "$repo" start --issue 72)"
  run_id="${handle%@*}"
  registry_in "$repo" register --run "$handle" >/dev/null
  telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
  registry_in "$repo" finalize --run "$handle" --outcome "$outcome" >/dev/null
  assert_field "$run_id" finalization finalized
  assert_field "$run_id" outcome "$outcome"
done

scenario outcome-conflict-is-refused
repo="$fixture/conflict"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" resolve --run "$handle" --outcome Progresses
! registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null 2>&1 \
  || fail "finalization accepted an outcome contradicting the sink"
assert_field "$run_id" finalization failed
assert_field "$run_id" failure_code OUTCOME_CONFLICT
# The same run still finalizes honestly against its own recorded outcome.
registry_in "$repo" recover --run-id "$run_id" >/dev/null
assert_field "$run_id" finalization finalized
assert_field "$run_id" outcome Progresses

scenario invalid-integrity-never-claims-success
repo="$fixture/integrity"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" resolve --run "$handle" --outcome Closes
telemetry "$repo" seal --run "$handle"
sink="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/work-on-telemetry/runs/$run_id.jsonl"
printf 'not json\n' >>"$sink"
! registry_in "$repo" finalize --run "$handle" >/dev/null 2>&1 \
  || fail "finalization claimed success for an invalid sink"
assert_field "$run_id" finalization failed
assert_field "$run_id" failure_code INTEGRITY_INVALID
assert_field "$run_id" summary_sha256 null

# --- 5: an interrupted run stays visible ------------------------------------

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
run_id="${handle%@*}"
[[ -n "$(record_of "$run_id")" ]] || fail "a killed run left no registry record"
assert_field "$run_id" run_id "$run_id"
assert_field "$run_id" lifecycle active
assert_field "$run_id" finalization pending
[[ "$("$registry_script" status --pending | jq -r '.run_id')" == "$run_id" ]] \
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
run_id="${handle%@*}"
# Recovery needs no outcome: the run already resolved one, so it is sealed and
# finalized as the run it always was.
registry_in "$repo" recover --run-id "$run_id" >/dev/null
assert_field "$run_id" finalization finalized
assert_field "$run_id" outcome Closes
assert_field "$run_id" lifecycle sealed

scenario killed-during-finalization
enable_observer
repo="$fixture/killed-finalizing"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
: >"$OBSERVER_FLAGS/kill-caller"
registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null 2>&1 || true
clear_observer_flags
assert_field "$run_id" finalization finalizing
[[ "$("$registry_script" status --pending | jq -r '.run_id')" == "$run_id" ]] \
  || fail "an interrupted finalization is not reported as outstanding"
registry_in "$repo" recover --run-id "$run_id" >/dev/null
assert_field "$run_id" finalization finalized
assert_field "$run_id" outcome Closes

# --- 6-7: the pending-obligation guard --------------------------------------

scenario pending-obligation-blocks-matching-run
enable_observer
repo="$fixture/guard"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
first_id="${first%@*}"
registry_in "$repo" register --run "$first" >/dev/null
second="$(telemetry "$repo" start --issue 73)"
second_id="${second%@*}"
refusal="$fixture/guard-refusal"
! registry_in "$repo" register --run "$second" >"$refusal" 2>&1 \
  || fail "a matching run started while a prior obligation was pending"
grep -Fq "$first_id" "$refusal" || fail "the refusal does not name the blocking run"
grep -Fq 'lifecycle: active, finalization: pending' "$refusal" \
  || fail "the refusal does not state the blocking run's bounded status"
[[ "$(grep -c 'recover with: ' "$refusal")" -eq 1 ]] \
  || fail "the refusal does not print exactly one recovery command"
[[ -z "$(record_of "$second_id")" ]] || fail "a refused run was still registered"
# The printed command is the recovery path, run exactly as printed.
recovery="$(sed -n 's/^  recover with: //p' "$refusal")"
$recovery --outcome abandoned >/dev/null
assert_field "$first_id" finalization finalized
registry_in "$repo" register --run "$second" >/dev/null
assert_field "$second_id" finalization pending

scenario failed-obligation-blocks-matching-run
enable_observer
repo="$fixture/guard-failed"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
first_id="${first%@*}"
registry_in "$repo" register --run "$first" >/dev/null
: >"$OBSERVER_FLAGS/finalize-error"
! registry_in "$repo" finalize --run "$first" --outcome Closes >/dev/null 2>&1 \
  || fail "finalization succeeded while its observer refused"
assert_field "$first_id" finalization failed
assert_field "$first_id" failure_code OBSERVER_FAILED
second="$(telemetry "$repo" start --issue 74)"
! registry_in "$repo" register --run "$second" >/dev/null 2>&1 \
  || fail "a matching run started while a prior obligation had failed"
clear_observer_flags
registry_in "$repo" recover --run-id "$first_id" >/dev/null
assert_field "$first_id" finalization finalized
registry_in "$repo" register --run "$second" >/dev/null

scenario unrelated-runs-are-not-blocked
enable_observer
governed="$fixture/unrelated-governed"
ordinary="$fixture/unrelated-ordinary"
new_repo "$governed" 'git@github.com:Example/Telemetry.git'
new_repo "$ordinary" 'git@github.com:Example/Other.git'
governed_handle="$(telemetry "$governed" start --issue 72)"
registry_in "$governed" register --run "$governed_handle" >/dev/null
ordinary_handle="$(telemetry "$ordinary" start --issue 72)"
ordinary_id="${ordinary_handle%@*}"
registry_in "$ordinary" register --run "$ordinary_handle" >/dev/null
assert_field "$ordinary_id" control_id null
assert_field "$ordinary_id" observer null
registry_in "$ordinary" finalize --run "$ordinary_handle" --outcome Closes >/dev/null
assert_field "$ordinary_id" finalization finalized
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
assert_field "${first%@*}" control_id null

scenario observer-policy-error-fails-closed
enable_observer
repo="$fixture/policy-error"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
: >"$OBSERVER_FLAGS/policy-error"
! registry_in "$repo" register --run "$handle" >/dev/null 2>&1 \
  || fail "registration proceeded on an undecidable observer policy"
rm -f "$OBSERVER_FLAGS/policy-error"
: >"$OBSERVER_FLAGS/policy-garbage"
! registry_in "$repo" register --run "$handle" >/dev/null 2>&1 \
  || fail "registration accepted a malformed observer answer"
clear_observer_flags
[[ -z "$(record_of "${handle%@*}")" ]] \
  || fail "a run was registered despite an unusable observer policy"

# --- 8-9: recovery and canonical summary ------------------------------------

scenario recovery-is-idempotent-on-the-same-run
enable_observer
repo="$fixture/idempotent"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
before="$(record_count)"
registry_in "$repo" recover --run-id "$run_id" --outcome abandoned >/dev/null
first_record="$(record_of "$run_id")"
registry_in "$repo" recover --run-id "$run_id" --outcome abandoned >/dev/null
registry_in "$repo" recover --run-id "$run_id" >/dev/null
[[ "$(record_of "$run_id")" == "$first_record" ]] \
  || fail "repeated recovery changed the finalized record"
[[ "$(record_count)" -eq "$before" ]] \
  || fail "recovery minted a replacement record"
observer_notifications="$(grep -c "$run_id" "$OBSERVER_FLAGS/finalized-records")"
[[ "$observer_notifications" -eq 1 ]] \
  || fail "recovery notified the observer $observer_notifications times"

scenario canonical-summary-hash-comes-from-the-sink
repo="$fixture/hash"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null
expected="$(telemetry "$repo" summary --run "$handle" | tr -d '\n' | sha256sum | cut -d' ' -f1)"
assert_field "$run_id" summary_sha256 "$expected"

# --- 10-11: durability beyond the worktree and the clone --------------------

scenario worktree-removal-does-not-erase-the-record
repo="$fixture/durable"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
linked="$fixture/durable-linked"
git -C "$repo" worktree add -q -b feature "$linked" >/dev/null
handle="$(telemetry "$linked" start --issue 72)"
run_id="${handle%@*}"
registry_in "$linked" register --run "$handle" >/dev/null
telemetry "$linked" resolve --run "$handle" --outcome Closes
git -C "$repo" worktree remove --force "$linked"
[[ ! -d "$linked" ]] || fail "the linked worktree was not removed"
[[ -n "$(record_of "$run_id")" ]] || fail "worktree removal erased the registry record"
# The sink outlived its worktree, so the same run still finalizes from the
# repository that owns it.
"$registry_script" recover --run-id "$run_id" >/dev/null
assert_field "$run_id" finalization finalized
assert_field "$run_id" outcome Closes

scenario missing-sink-becomes-unreproducible
repo="$fixture/missing-sink"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
sink="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/work-on-telemetry/runs/$run_id.jsonl"
rm -f "$sink"
registry_in "$repo" recover --run-id "$run_id" >/dev/null 2>&1
assert_field "$run_id" finalization unreproducible
assert_field "$run_id" failure_code SINK_MISSING
assert_field "$run_id" run_id "$run_id"

scenario missing-repository-becomes-unreproducible
enable_observer
repo="$fixture/missing-repo"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
rm -rf "$repo"
"$registry_script" recover --run-id "$run_id" >/dev/null 2>&1
assert_field "$run_id" finalization unreproducible
assert_field "$run_id" failure_code REPOSITORY_MISSING
assert_field "$run_id" repository example/telemetry
assert_field "$run_id" issue 72
# A run nobody can reproduce stays in the population but stops blocking work.
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
next="$(telemetry "$repo" start --issue 73)"
registry_in "$repo" register --run "$next" >/dev/null \
  || fail "an unreproducible obligation kept blocking new runs"
[[ "$(record_count)" -eq 2 ]] || fail "the unreproducible run left the population"

# --- 12-13: concurrency ------------------------------------------------------

scenario concurrent-finalizations-do-not-cross-contaminate
repo="$fixture/concurrent"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
linked="$fixture/concurrent-linked"
git -C "$repo" worktree add -q -b concurrent "$linked" >/dev/null
main_handle="$(telemetry "$repo" start --issue 72)"
linked_handle="$(telemetry "$linked" start --issue 73)"
same_handle="$(telemetry "$repo" start --issue 74)"
registry_in "$repo" register --run "$main_handle" >/dev/null
registry_in "$linked" register --run "$linked_handle" >/dev/null
registry_in "$repo" register --run "$same_handle" >/dev/null
gate="$fixture/concurrent-gate"
finalize_at_gate() {
  local workdir="$1" handle="$2" outcome="$3"
  (
    while [[ ! -e "$gate" ]]; do :; done
    cd "$workdir"
    "$registry_script" finalize --run "$handle" --outcome "$outcome"
  ) >/dev/null &
}
finalize_at_gate "$repo" "$main_handle" Closes
finalize_at_gate "$linked" "$linked_handle" Progresses
finalize_at_gate "$repo" "$same_handle" abandoned
: >"$gate"
wait
assert_field "${main_handle%@*}" outcome Closes
assert_field "${linked_handle%@*}" outcome Progresses
assert_field "${same_handle%@*}" outcome abandoned
for id in "${main_handle%@*}" "${linked_handle%@*}" "${same_handle%@*}"; do
  assert_field "$id" finalization finalized
done
[[ "$(record_count)" -eq 3 ]] || fail "concurrent finalization lost or added records"

scenario competing-matching-starts-cannot-both-proceed
enable_observer
repo="$fixture/competing"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
first="$(telemetry "$repo" start --issue 72)"
second="$(telemetry "$repo" start --issue 73)"
gate="$fixture/competing-gate"
register_at_gate() {
  local handle="$1" result="$2"
  (
    while [[ ! -e "$gate" ]]; do :; done
    cd "$repo"
    if "$registry_script" register --run "$handle" >/dev/null 2>&1; then
      printf 'granted\n' >"$result"
    else
      printf 'refused\n' >"$result"
    fi
  ) &
}
register_at_gate "$first" "$fixture/competing-first"
register_at_gate "$second" "$fixture/competing-second"
: >"$gate"
wait
granted="$(cat "$fixture/competing-first" "$fixture/competing-second" \
  | grep -c granted)"
[[ "$granted" -eq 1 ]] \
  || fail "$granted competing matching starts acquired permission to proceed"
[[ "$(record_count)" -eq 1 ]] \
  || fail "a refused competing start still left a registry record"

# --- 14, 16: ownership and privacy ------------------------------------------

scenario registry-is-owner-only
repo="$fixture/permissions"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
registry_in "$repo" register --run "$handle" >/dev/null
registry_root="$XDG_STATE_HOME/work-on/registry"
while IFS= read -r entry; do
  mode="$(stat -c '%a' "$entry")"
  if [[ -d "$entry" ]]; then
    [[ "$mode" == 700 ]] || fail "directory $entry is mode $mode"
  else
    [[ "$mode" == 600 ]] || fail "file $entry is mode $mode"
  fi
done < <(find "$registry_root")

scenario registry-holds-no-raw-telemetry
enable_observer
repo="$fixture/privacy"
new_repo "$repo" 'git@github.com:Example/Telemetry.git'
handle="$(telemetry "$repo" start --issue 72)"
run_id="${handle%@*}"
registry_in "$repo" register --run "$handle" >/dev/null
telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
telemetry "$repo" exec --run "$handle" --command-id secret-looking-check \
  --phase gate --round 1 -- printf 'sensitive output\n' >/dev/null
registry_in "$repo" finalize --run "$handle" --outcome Closes >/dev/null
record="$(record_of "$run_id")"
[[ "$(jq -sc 'map(keys) | unique' <<<"$record")" == \
  '[["control_id","failure_code","finalization","issue","lifecycle","observer","outcome","registered_at","repository","repository_binding","run_id","schema","sink","summary_sha256","telemetry_schema","updated_at","updated_epoch","worktree"]]' ]] \
  || fail "the registry record does not carry exactly the bounded field set"
registry_root="$XDG_STATE_HOME/work-on/registry"
for forbidden in '"type"' 'subagent_launch' 'validation_start' 'epoch_ms' \
  'secret-looking-check' 'sensitive output'; do
  ! grep -rqF "$forbidden" "$registry_root" \
    || fail "the registry stored prohibited material: $forbidden"
done

# --- 15: capacity and retention ---------------------------------------------

scenario capacity-exhaustion-fails-closed
enable_observer
export WORK_ON_REGISTRY_CAPACITY=2
governed="$fixture/capacity-governed"
ordinary="$fixture/capacity-ordinary"
new_repo "$governed" 'git@github.com:Example/Telemetry.git'
new_repo "$ordinary" 'git@github.com:Example/Other.git'
first_ordinary="$(telemetry "$ordinary" start --issue 72)"
registry_in "$ordinary" register --run "$first_ordinary" >/dev/null
second_ordinary="$(telemetry "$ordinary" start --issue 73)"
registry_in "$ordinary" register --run "$second_ordinary" >/dev/null
governed_handle="$(telemetry "$governed" start --issue 72)"
# An ungoverned record yields its slot; the governed obligation is admitted.
registry_in "$governed" register --run "$governed_handle" >/dev/null
[[ -n "$(record_of "${governed_handle%@*}")" ]] \
  || fail "a governed run was refused while evictable records existed"
[[ "$(record_count)" -eq 2 ]] || fail "eviction did not bound the registry"
# With every remaining slot holding an outstanding obligation, there is nothing
# safe to drop, so registration refuses instead of losing the evidence.
"$registry_script" finalize --run "$governed_handle" --outcome Closes >/dev/null
second_governed="$(telemetry "$governed" start --issue 73)"
registry_in "$governed" register --run "$second_governed" >/dev/null
third_governed="$(telemetry "$governed" start --issue 74)"
refusal="$fixture/capacity-refusal"
! registry_in "$governed" register --run "$third_governed" >"$refusal" 2>&1 \
  || fail "registration proceeded with no safe capacity"
grep -Fq 'run registry:' "$refusal" || fail "capacity refusal was silent"
[[ -n "$(record_of "${second_governed%@*}")" ]] \
  || fail "an outstanding governed obligation was evicted"
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
[[ -n "$(record_of "${outstanding%@*}")" ]] \
  || fail "prune erased a record an observer still needs"
registry_in "$repo" finalize --run "$outstanding" --outcome Closes >/dev/null
[[ "$("$registry_script" prune --older-than-days 0)" == 'pruned 1' ]] \
  || fail "prune did not drop the discharged obligation"
[[ "$(record_count)" -eq 0 ]] || fail "prune left records behind"

printf 'run registry scenarios passed\n'
