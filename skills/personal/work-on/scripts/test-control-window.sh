#!/usr/bin/env bash
set -euo pipefail

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
adapter="$script_root/control-window.sh"
fixtures="$(dirname "$script_root")/fixtures/control-window"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'control window test: %s\n' "$1" >&2
  exit 1
}

scenario() {
  printf 'scenario: %s\n' "$1"
}

export XDG_STATE_HOME="$test_root/state"
export XDG_CONFIG_HOME="$test_root/config"

scenario policy-manifests-are-versioned-and-reusable
"$adapter" validate --policy "$fixtures/demo-policy.json" >/dev/null
"$adapter" validate --policy "$fixtures/b2-like-policy.json" >/dev/null
unsafe_policy="$test_root/unsafe-policy.json"
jq '.results.pull_request.reviewer_material = "free-form review"' \
  "$fixtures/demo-policy.json" >"$unsafe_policy"
! "$adapter" validate --policy "$unsafe_policy" >/dev/null 2>&1 \
  || fail "policy accepted a free-form publication field"

scenario prepared-demo-policy-never-matches-or-activates
export WORK_ON_CONTROL_POLICY="$fixtures/demo-policy.json"
if "$adapter" applies --repository faviann/skills --issue 73 >"$test_root/applies"; then
  fail "a prepared demo policy matched observation work"
else
  [[ "$?" -eq 3 ]] || fail "a non-matching policy did not use the observer not-applicable status"
fi
[[ ! -s "$test_root/applies" ]] || fail "a non-matching policy emitted applicability material"
! "$adapter" activate --policy "$fixtures/demo-policy.json" >/dev/null 2>&1 \
  || fail "a demo policy could activate"

scenario ordinary-runs-preserve-the-generic-registry-path
unset WORK_ON_CONTROL_POLICY WORK_ON_OBSERVER || true
ordinary="$test_root/ordinary"
mkdir -p "$ordinary"
git -C "$ordinary" init -q
git -C "$ordinary" config user.name tester
git -C "$ordinary" config user.email tester@example.invalid
git -C "$ordinary" remote add origin git@github.com:example/ordinary.git
printf 'ordinary\n' >"$ordinary/README.md"
git -C "$ordinary" add README.md
git -C "$ordinary" commit -qm base
ordinary_handle="$(cd "$ordinary" && "$script_root/run-telemetry.sh" start --issue 1)"
[[ "$(cd "$ordinary" && "$adapter" register --run "$ordinary_handle")" \
  == "registered ${ordinary_handle%@*} observer=none control=none" ]] \
  || fail "the adapter changed ordinary generic registration"
[[ "$(cd "$ordinary" && "$adapter" finalize --run "$ordinary_handle" \
  --outcome preflight-aborted)" == "finalized ${ordinary_handle%@*}" ]] \
  || fail "the adapter changed ordinary generic finalization"

scenario prepared-results-surface-precedes-activation
seed="$test_root/seed"
remote="$test_root/results.git"
mkdir -p "$seed"
git -C "$seed" init -q
git -C "$seed" config user.name tester
git -C "$seed" config user.email tester@example.invalid
printf 'base\n' >"$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit -qm base
git -C "$seed" branch -M main
git clone -q --bare "$seed" "$remote"

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
export CONTROL_WINDOW_REAL_GIT="$(command -v git)"
cat >"$fake_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
state="${CONTROL_WINDOW_FAKE_GH_STATE:?}"
[[ "${1:-}" == pr ]] || exit 2
case "${2:-}" in
  list)
    if [[ -f "$state" ]]; then jq -cs '.' "$state"; else printf '[]\n'; fi
    ;;
  create)
    shift 2
    base="" head="" title="" body_file=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -R|--repo) shift 2 ;;
        --base) base="$2"; shift 2 ;;
        --head) head="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body-file) body_file="$2"; shift 2 ;;
        --draft) shift ;;
        *) exit 2 ;;
      esac
    done
    jq -cn --argjson number 101 --arg url 'https://example.invalid/pull/101' \
      --arg base "$base" --arg head "$head" --arg title "$title" \
      --arg body "$(cat "$body_file")" \
      '{number:$number,url:$url,isDraft:true,baseRefName:$base,headRefName:$head,title:$title,body:$body,state:"OPEN"}' >"$state"
    printf 'https://example.invalid/pull/101\n'
    ;;
  view)
    cat "$state"
    ;;
  *) exit 2 ;;
esac
GH
chmod +x "$fake_bin/gh"
cat >"$fake_bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER:-}" ]]; then
  for argument in "$@"; do
    if [[ "$argument" == push && ! -e "$CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER" ]]; then
      "$CONTROL_WINDOW_REAL_GIT" "$@"
      : >"$CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER"
      exit 1
    fi
  done
fi
exec "$CONTROL_WINDOW_REAL_GIT" "$@"
GIT
chmod +x "$fake_bin/git"
export PATH="$fake_bin:$PATH"
export CONTROL_WINDOW_FAKE_GH_STATE="$test_root/pr.json"
export CONTROL_WINDOW_REMOTE_URL="$remote"
demo_policy="$test_root/demo-policy.json"
jq --arg branch 'demo/control-window-prepared-test' \
  '.results.branch = $branch' "$fixtures/demo-policy.json" >"$demo_policy"
export WORK_ON_CONTROL_POLICY="$demo_policy"

prepared_url="$($adapter prepare --policy "$demo_policy")"
[[ "$prepared_url" == https://example.invalid/pull/101 ]] \
  || fail "prepare did not return the verified draft PR URL"
git --git-dir="$remote" show-ref --verify --quiet \
  refs/heads/demo/control-window-prepared-test \
  || fail "prepare did not create the evidence branch"
head="$(git --git-dir="$remote" rev-parse refs/heads/demo/control-window-prepared-test)"
tree="$(git --git-dir="$remote" ls-tree -r --name-only "$head")"
grep -Fxq 'control-window/demo-control-window-73/policy.json' <<<"$tree" \
  || fail "the prepared branch lacks its bounded policy projection"
[[ "$(grep -c '/transitions/' <<<"$tree")" -eq 1 ]] \
  || fail "prepare did not publish exactly one transition artifact"
[[ "$(jq -r .phase "$(dirname "$XDG_STATE_HOME")/state/work-on/control-windows/demo-control-window-73.json")" == prepared ]] \
  || fail "prepare did not retain distinct prepared state"
grep -Fq 'PREPARED / NON-OBSERVING' "$CONTROL_WINDOW_FAKE_GH_STATE" \
  || fail "the draft PR does not visibly identify prepared non-observing state"
before_count="$(git --git-dir="$remote" rev-list --count main..demo/control-window-prepared-test)"
[[ "$($adapter prepare --policy "$demo_policy")" == "$prepared_url" ]] \
  || fail "an idempotent prepare did not adopt the existing PR"
after_count="$(git --git-dir="$remote" rev-list --count main..demo/control-window-prepared-test)"
[[ "$before_count" == "$after_count" ]] \
  || fail "an idempotent prepare appended a second prepared transition"
[[ ! -e "$XDG_CONFIG_HOME/work-on/observer" \
  && ! -e "$XDG_CONFIG_HOME/work-on/control-policy" ]] \
  || fail "demo preparation installed a real observer/control descriptor"

scenario activation-readback-precedes-matching
rm -f "$CONTROL_WINDOW_FAKE_GH_STATE"
production_policy="$test_root/production-policy.json"
jq --arg branch 'experiment/fixture-b2-activation-test' \
  '.results.branch = $branch' "$fixtures/b2-like-policy.json" >"$production_policy"
export WORK_ON_CONTROL_POLICY="$production_policy"
"$adapter" prepare --policy "$production_policy" >/dev/null
published_policy="$(git --git-dir="$remote" show \
  experiment/fixture-b2-activation-test:control-window/fixture-b2-comparison/policy.json)"
[[ "$(jq -r '.arm | has("configuration")' <<<"$published_policy")" == false \
  && "$(jq -r '.results | has("pull_request")' <<<"$published_policy")" == false ]] \
  || fail "the public policy serializer copied local free-form configuration"
# An ordinary advance of the configured base is not a results-branch rewrite;
# later verification remains pinned to the preparation merge-base.
printf 'base advanced\n' >>"$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit -qm 'advance main after preparation'
git -C "$seed" push -q "$remote" main
if "$adapter" applies --repository example/comparison-repository --issue 101 \
  >"$test_root/pre-activation-applies"; then
  fail "prepared production state matched before activation"
else
  [[ "$?" -eq 3 ]] || fail "prepared production state returned a policy error"
fi
rm -f "$CONTROL_WINDOW_FAKE_GH_STATE"
! "$adapter" activate --policy "$production_policy" >/dev/null 2>&1 \
  || fail "activation proceeded without the prepared results PR"
"$adapter" prepare --policy "$production_policy" >/dev/null
activation_output="$test_root/activation-output"
if ! "$adapter" activate --policy "$production_policy" >"$activation_output" 2>&1; then
  fail "verified activation failed: $(cat "$activation_output")"
fi
activation_id="$(cat "$activation_output")"
[[ "$activation_id" =~ ^[0-9a-f]{64}$ ]] \
  || fail "activation did not return its opening identity"
state_file="$XDG_STATE_HOME/work-on/control-windows/fixture-b2-comparison.json"
[[ "$(jq -r .phase "$state_file")" == active \
  && "$(jq -r .activation_transition "$state_file")" == "$activation_id" ]] \
  || fail "active state was not installed after verified publication"
activation_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
[[ "$(git --git-dir="$remote" ls-tree -r --name-only "$activation_head" \
  | grep -c '/transitions/')" -eq 2 ]] \
  || fail "activation did not append exactly one immutable transition"
unset WORK_ON_CONTROL_POLICY
[[ "$($adapter applies --repository example/comparison-repository --issue 101)" \
  == $'observer=control-window-publisher\ncontrol=fixture-b2-comparison' ]] \
  || fail "verified active policy did not match its declared population"
if "$adapter" applies --repository example/other --issue 101 >/dev/null; then
  fail "active policy matched a repository outside its population"
else
  [[ "$?" -eq 3 ]] || fail "a population miss returned a policy error"
fi

scenario registration-is-published-before-work-may-begin
target="$test_root/target"
mkdir -p "$target"
git -C "$target" init -q
git -C "$target" config user.name tester
git -C "$target" config user.email tester@example.invalid
git -C "$target" remote add origin git@github.com:example/comparison-repository.git
printf 'target\n' >"$target/README.md"
git -C "$target" add README.md
git -C "$target" commit -qm base
handle="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
registration="$(cd "$target" && "$adapter" register --run "$handle")"
[[ "$registration" == "registered ${handle%@*}" ]] \
  || fail "the adapter did not acknowledge the published registration"
registration_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
registered_file="$(git --git-dir="$remote" ls-tree -r --name-only "$registration_head" \
  | while read -r candidate; do
      [[ "$candidate" == */transitions/*.json ]] || continue
      [[ "$(git --git-dir="$remote" show "$registration_head:$candidate" | jq -r .kind)" == run-registered ]] \
        && printf '%s\n' "$candidate"
    done || true)"
[[ -n "$registered_file" ]] || fail "registration returned before its transition existed"
published_registration="$(git --git-dir="$remote" show "$registration_head:$registered_file")"
[[ "$(jq -r .run_id <<<"$published_registration")" == "${handle%@*}" ]] \
  || fail "the registration transition names the wrong run"
for prohibited in sink worktree prompt diff command output diagnostic credential reviewer; do
  ! jq -e --arg field "$prohibited" 'has($field)' <<<"$published_registration" >/dev/null \
    || fail "the publication serializer exposed prohibited field $prohibited"
done
(cd "$target" && "$script_root/run-telemetry.sh" launch --run "$handle" \
  --role implementation --phase implementation --round 1)

scenario finalization-publishes-bounded-canonical-evidence
finalized="$(cd "$target" && "$adapter" finalize --run "$handle" --outcome Closes)"
[[ "$finalized" == "finalized ${handle%@*}" ]] \
  || fail "the adapter did not finish the generic #72 finalization"
final_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
final_file="$(git --git-dir="$remote" ls-tree -r --name-only "$final_head" \
  | while read -r candidate; do
      [[ "$candidate" == */transitions/*.json ]] || continue
      kind="$(git --git-dir="$remote" show "$final_head:$candidate" | jq -r .kind)"
      [[ "$kind" == run-finalized ]] && printf '%s\n' "$candidate"
    done || true)"
[[ -n "$final_file" ]] || fail "finalization did not publish a terminal transition"
published_final="$(git --git-dir="$remote" show "$final_head:$final_file")"
[[ "$(jq -r .outcome <<<"$published_final")" == Closes \
  && "$(jq -r .integrity <<<"$published_final")" == valid \
  && "$(jq -r .summary_sha256 <<<"$published_final")" =~ ^[0-9a-f]{64}$ ]] \
  || fail "finalization did not use the bounded canonical summary"
for prohibited in sink worktree prompt diff command output diagnostic credential reviewer; do
  ! jq -e --arg field "$prohibited" 'has($field)' <<<"$published_final" >/dev/null \
    || fail "finalization publication exposed prohibited field $prohibited"
done
before_retry="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
(cd "$target" && "$adapter" finalize --run "$handle" --outcome Closes) >/dev/null
after_retry="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
[[ "$before_retry" == "$after_retry" ]] \
  || fail "idempotent finalization appended a duplicate transition"

scenario registration-publication-failure-fails-closed-and-recovers
reject_hook="$remote/hooks/pre-receive"
cat >"$reject_hook" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$reject_hook"
failed_registration="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$failed_registration") \
  >"$test_root/register-failure" 2>&1 \
  || fail "registration succeeded despite rejected GitHub publication"
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$failed_registration" \
  | jq -r .finalization)" == pending ]] \
  || fail "failed registration publication lost the generic pending lease"
blocked_after_registration="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$blocked_after_registration") \
  >"$test_root/register-guard" 2>&1 \
  || fail "the next matching run bypassed the pending registration obligation"
grep -Fq 'unfinished obligation' "$test_root/register-guard" \
  || fail "the #72 next-run guard did not explain the blocked predecessor"
rm -f "$reject_hook"
[[ "$(cd "$target" && "$adapter" register --run "$failed_registration")" \
  == "registered ${failed_registration%@*}" ]] \
  || fail "registration recovery did not publish the original run"

scenario finalization-publication-failure-preserves-evidence-and-guard
(cd "$target" && "$script_root/run-telemetry.sh" launch --run "$failed_registration" \
  --role implementation --phase implementation --round 1)
cat >"$reject_hook" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$reject_hook"
! (cd "$target" && "$adapter" finalize --run "$failed_registration" --outcome failed) \
  >"$test_root/finalize-failure" 2>&1 \
  || fail "finalization succeeded despite rejected GitHub publication"
failed_row="$(cd "$target" && "$script_root/run-registry.sh" status --run "$failed_registration")"
[[ "$(jq -r .finalization <<<"$failed_row")" == failed \
  && "$(jq -r .failure_code <<<"$failed_row")" == OBSERVER_FAILED \
  && "$(jq -r .outcome <<<"$failed_row")" == failed \
  && -f "$(jq -r .sink <<<"$failed_row")" ]] \
  || fail "publication failure did not preserve the failed row and raw sink"
! (cd "$target" && "$adapter" register --run "$blocked_after_registration") \
  >/dev/null 2>&1 || fail "the failed finalization did not keep the next run blocked"
rm -f "$reject_hook"
recovery_output="$test_root/recovery-output"
if ! (cd "$target" && "$adapter" recover --run "$failed_registration") \
  >"$recovery_output" 2>&1; then
  fail "publication recovery failed: $(cat "$recovery_output")"
fi
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$failed_registration" \
  | jq -r .finalization)" == finalized ]] \
  || fail "recovery did not discharge the failed publication obligation"
failure_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
git --git-dir="$remote" grep -q '"kind": "run-failed"' "$failure_head" \
  || fail "failed workflow outcome disappeared from published history"

scenario generic-failed-state-is-published-before-recovery
lifecycle_failure="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && "$adapter" register --run "$lifecycle_failure") >/dev/null
(cd "$target" && "$script_root/run-telemetry.sh" resolve --run "$lifecycle_failure" \
  --outcome Progresses) >/dev/null
! (cd "$target" && "$adapter" finalize --run "$lifecycle_failure" --outcome Closes) \
  >"$test_root/outcome-conflict" 2>&1 \
  || fail "a contradictory finalization assertion succeeded"
lifecycle_row="$(cd "$target" && "$script_root/run-registry.sh" status --run "$lifecycle_failure")"
[[ "$(jq -r .finalization <<<"$lifecycle_row")" == failed \
  && "$(jq -r .failure_code <<<"$lifecycle_row")" == OUTCOME_CONFLICT ]] \
  || fail "the generic lifecycle failure was not preserved"
lifecycle_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
git --git-dir="$remote" grep -q '"failure_code": "OUTCOME_CONFLICT"' "$lifecycle_head" \
  || fail "generic failed state disappeared from published history"
(cd "$target" && "$adapter" recover --run "$lifecycle_failure") >/dev/null
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$lifecycle_failure" \
  | jq -r .finalization)" == finalized ]] \
  || fail "a published failed state could not later recover"

scenario missing-sink-publishes-unreproducible-without-disappearing
unreproducible="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && "$adapter" register --run "$unreproducible") >/dev/null
unreproducible_row="$(cd "$target" && "$script_root/run-registry.sh" status --run "$unreproducible")"
rm -f "$(jq -r .sink <<<"$unreproducible_row")"
(cd "$target" && "$adapter" recover --run "$unreproducible" --outcome abandoned) >/dev/null
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$unreproducible" \
  | jq -r .finalization)" == unreproducible ]] \
  || fail "missing sink was not retained as unreproducible"
unreproducible_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
git --git-dir="$remote" grep -q '"kind": "run-unreproducible"' "$unreproducible_head" \
  || fail "unreproducible lifecycle state disappeared from published history"

scenario concurrent-matching-agents-share-the-run-registry-lease
candidate_a="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
candidate_b="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && "$adapter" register --run "$candidate_a") \
  >"$test_root/concurrent-a.out" 2>"$test_root/concurrent-a.err" &
pid_a=$!
(cd "$target" && "$adapter" register --run "$candidate_b") \
  >"$test_root/concurrent-b.out" 2>"$test_root/concurrent-b.err" &
pid_b=$!
status_a=0; wait "$pid_a" || status_a=$?
status_b=0; wait "$pid_b" || status_b=$?
[[ "$(( (status_a == 0) + (status_b == 0) ))" -eq 1 ]] \
  || fail "concurrent matching registrations did not produce exactly one lease"
if [[ "$status_a" -eq 0 ]]; then winner="$candidate_a"; else winner="$candidate_b"; fi
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --pending \
  | jq -s --arg control fixture-b2-comparison \
    '[.[] | select(.control_id == $control)] | length')" -eq 1 ]] \
  || fail "concurrent registration produced conflicting pending records"

scenario ambiguous-success-is-adopted-with-one-logical-transition
(cd "$target" && "$script_root/run-telemetry.sh" launch --run "$winner" \
  --role implementation --phase implementation --round 1)
export CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER="$test_root/ambiguous-push"
before_ambiguous="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
(cd "$target" && "$adapter" finalize --run "$winner" --outcome Progresses) >/dev/null
unset CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER
[[ -e "$test_root/ambiguous-push" ]] || fail "the ambiguous-success boundary was not exercised"
after_ambiguous="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
[[ "$after_ambiguous" -eq $(( before_ambiguous + 1 )) ]] \
  || fail "ambiguous success produced more than one remote transition"
(cd "$target" && "$adapter" recover --run "$winner") >/dev/null
[[ "$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)" \
  -eq "$after_ambiguous" ]] || fail "ambiguous-success retry duplicated publication"

scenario conflicting-remote-content-is-rejected
good_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
attack="$test_root/attack"
git clone -q "$remote" "$attack"
git -C "$attack" config user.name attacker
git -C "$attack" config user.email attacker@example.invalid
git -C "$attack" switch -q experiment/fixture-b2-activation-test
victim="$(git -C "$attack" ls-tree -r --name-only HEAD \
  | while read -r candidate; do
      [[ "$candidate" == */transitions/*.json ]] || continue
      [[ "$(git -C "$attack" show "HEAD:$candidate" | jq -r .kind)" == run-registered ]] \
        && printf '%s\n' "$candidate" && break
    done)"
jq '.issue = 999' "$attack/$victim" >"$attack/$victim.changed"
mv "$attack/$victim.changed" "$attack/$victim"
git -C "$attack" add -- "$victim"
git -C "$attack" commit -qm 'rewrite published evidence'
git -C "$attack" push -q origin HEAD:refs/heads/experiment/fixture-b2-activation-test
conflict_run="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$conflict_run") \
  >"$test_root/conflict.out" 2>&1 \
  || fail "conflicting remote evidence was accepted"
grep -Eq 'rewrites a published artifact|content does not match its identity' \
  "$test_root/conflict.out" || fail "remote content conflict lacked a fail-closed diagnostic"
git --git-dir="$remote" update-ref refs/heads/experiment/fixture-b2-activation-test "$good_head"
(cd "$target" && "$adapter" register --run "$conflict_run") >/dev/null
(cd "$target" && "$adapter" finalize --run "$conflict_run" --outcome abandoned) >/dev/null

scenario branch-rewrite-is-detected-without-force-push-recovery
rewrite_good_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
rewound_head="$(git --git-dir="$remote" rev-parse "$rewrite_good_head^")"
git --git-dir="$remote" update-ref refs/heads/experiment/fixture-b2-activation-test "$rewound_head"
rewrite_run="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$rewrite_run") \
  >"$test_root/rewrite.out" 2>&1 \
  || fail "a rewritten results branch was accepted"
grep -Fq 'rewritten behind the last verified head' "$test_root/rewrite.out" \
  || fail "branch rewrite lacked its fail-closed diagnostic"
[[ "$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)" \
  == "$rewound_head" ]] || fail "the adapter force-repaired the rewritten branch"
git --git-dir="$remote" update-ref refs/heads/experiment/fixture-b2-activation-test "$rewrite_good_head"
(cd "$target" && "$adapter" register --run "$rewrite_run") >/dev/null
(cd "$target" && "$adapter" finalize --run "$rewrite_run" --outcome abandoned) >/dev/null

scenario closing-and-closed-are-distinct-append-only-transitions
closing_id="$($adapter close --policy "$production_policy")"
[[ "$closing_id" =~ ^[0-9a-f]{64}$ \
  && "$(jq -r .phase "$state_file")" == closing ]] \
  || fail "control closing was not durably distinct"
if "$adapter" applies --repository example/comparison-repository --issue 101 >/dev/null; then
  fail "a closing control still matched new work"
else
  [[ "$?" -eq 3 ]] || fail "closing applicability returned a policy error"
fi
closed_id="$($adapter close --policy "$production_policy" --complete)"
[[ "$closed_id" =~ ^[0-9a-f]{64}$ \
  && "$(jq -r .phase "$state_file")" == closed ]] \
  || fail "control closed was not durably distinct"

scenario unexpected-demo-branch-content-fails-closed
demo_attack="$test_root/demo-attack"
git clone -q "$remote" "$demo_attack"
git -C "$demo_attack" config user.name attacker
git -C "$demo_attack" config user.email attacker@example.invalid
git -C "$demo_attack" switch -q demo/control-window-prepared-test
printf 'unexpected\n' >"$demo_attack/unexpected.txt"
git -C "$demo_attack" add unexpected.txt
git -C "$demo_attack" commit -qm 'unexpected evidence content'
git -C "$demo_attack" push -q origin HEAD:refs/heads/demo/control-window-prepared-test
! "$adapter" prepare --policy "$demo_policy" >"$test_root/unexpected.out" 2>&1 \
  || fail "unexpected results-branch content was accepted"
grep -Fq 'unexpected content' "$test_root/unexpected.out" \
  || fail "unexpected branch content lacked its fail-closed diagnostic"

! rg -n 'git .*push.*(--force|-f)|push .*\+' "$adapter" >/dev/null \
  || fail "the publisher contains a force-push recovery path"

scenario work-on-uses-the-policy-aware-public-wrapper
grep -Fq 'scripts/control-window.sh register --run "$RUN_HANDLE"' \
  "$(dirname "$script_root")/SKILL.md" \
  || fail "work-on does not use publication-gated registration"
grep -Fq 'scripts/control-window.sh finalize --run "$RUN_HANDLE"' \
  "$(dirname "$script_root")/references/github-closeout.md" \
  || fail "normal closeout bypasses the publication-aware finalizer"
grep -Fq 'scripts/control-window.sh finalize --run "$RUN_HANDLE" --outcome preflight-aborted' \
  "$(dirname "$script_root")/references/closability-gate.md" \
  || fail "preflight hand-back bypasses the publication-aware finalizer"

printf 'control window scenarios passed\n'
