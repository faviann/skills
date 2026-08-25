#!/usr/bin/env bash
set -euo pipefail

# Exercise the highest mechanical seam: the issue-keyed semantic authority that
# every workflow context must recover before blocker-driven candidate mutation.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command_under_test="$script_dir/convergence-state.sh"
skill_dir="$(cd "$script_dir/.." && pwd)"
workflow="$skill_dir/references/default-workflow.md"
state_contract="$skill_dir/references/convergence-state.md"
review_contract="$skill_dir/references/review-state-machine.md"
closeout="$skill_dir/references/github-closeout.md"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
repo="$fixture/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name Test
git -C "$repo" config user.email test@example.com
git -C "$repo" remote add origin https://github.com/example/project.git
printf 'base\n' >"$repo/artifact"
git -C "$repo" add artifact
git -C "$repo" commit -qm base

state() {
  (cd "$repo" && "$command_under_test" "$@")
}

candidate() {
  state candidate
}

next_candidate() {
  printf '%s\n' "$1" >>"$repo/artifact"
  git -C "$repo" add artifact
  git -C "$repo" commit -qm "$1"
  candidate
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$fixture/$label.out" 2>"$fixture/$label.err"; then
    printf 'not ok - %s unexpectedly succeeded\n' "$label" >&2
    exit 1
  fi
}

has() {
  local flat="$fixture/$(basename "$1").flat"
  awk '
    /^[[:space:]]*$/ { print paragraph; paragraph = ""; next }
    { paragraph = (paragraph == "" ? $0 : paragraph " " $0) }
    END { print paragraph }
  ' "$1" | tr -s ' ' >"$flat"
  grep -Eqi -- "$2" "$flat" || {
    printf 'not ok - %s (missing in %s: %s)\n' "$3" "$1" "$2" >&2
    exit 1
  }
}

source_candidate="$(candidate)"
[[ "$source_candidate" =~ ^repo:example/project\;tree:[0-9a-f]{40}$ ]]
printf 'dirty\n' >"$repo/untracked"
expect_failure dirty-candidate candidate
rm "$repo/untracked"
echo 'ok - Candidate identity binds the repository and exact clean content tree'

lifecycle="$(state begin --issue 106 --run run-one@example/project --candidate "$source_candidate")"
[[ "$lifecycle" =~ ^[0-9a-f]{32}$ ]]
state_file="$repo/.git/work-on-convergence/issue-106.json"
[[ "$(stat -c '%a' "$(dirname "$state_file")")" == 700 ]]
[[ "$(stat -c '%a' "$state_file")" == 600 ]]
[[ "$(jq -r '.lifecycle.consumed' "$state_file")" == 0 ]]
echo 'ok - one owner-only issue authority creates the initial lifecycle and budget'

correction_one="$(state authorize --issue 106 --lifecycle "$lifecycle" --candidate "$source_candidate")"
recovered="$(state recover --issue 106 --run continuation@example/project --candidate "$source_candidate")"
[[ "$(jq -r '.consumed' <<<"$recovered")" == 0 ]]
[[ "$(jq -r '.pending_correction.id' <<<"$recovered")" == "$correction_one" ]]
[[ "$(state authorize --issue 106 --lifecycle "$lifecycle" --candidate "$source_candidate")" == "$correction_one" ]]
echo 'ok - authorized-but-unchanged recovery preserves the unit and the exact source'

result_one="$(next_candidate correction-one)"
[[ "$(state complete --issue 106 --lifecycle "$lifecycle" --correction "$correction_one" --source "$source_candidate" --result "$result_one")" == 1 ]]
[[ "$(state complete --issue 106 --lifecycle "$lifecycle" --correction "$correction_one" --source "$source_candidate" --result "$result_one")" == 1 ]]
[[ "$(jq -r '.lifecycle.corrections[0].source_candidate' "$state_file")" == "$source_candidate" ]]
[[ "$(jq -r '.lifecycle.corrections[0].result_candidate' "$state_file")" == "$result_one" ]]
echo 'ok - a completed source-to-result transition consumes exactly once after recovery'

# Session, telemetry, review, validation, and bookkeeping boundaries recover the
# same state. Synchronization and governing-state restart explicitly advance the
# Candidate without touching the consumed count.
for run in review-chain telemetry-segment resumed-session; do
  state recover --issue 106 --run "$run@example/project" --candidate "$result_one" >/dev/null
done
sync_candidate="$(next_candidate synchronization)"
[[ "$(state advance --issue 106 --lifecycle "$lifecycle" --kind synchronization --source "$result_one" --result "$sync_candidate")" == 1 ]]
governing_candidate="$(next_candidate governing-restart)"
[[ "$(state advance --issue 106 --lifecycle "$lifecycle" --kind governing-state-restart --source "$sync_candidate" --result "$governing_candidate")" == 1 ]]
[[ "$(jq -r '.lifecycle.consumed' "$state_file")" == 1 ]]
[[ "$(jq -r '.lifecycle.runs | length' "$state_file")" == 5 ]]
echo 'ok - continuation, synchronization, and restart boundaries retain one lifecycle and count'

correction_two="$(state authorize --issue 106 --lifecycle "$lifecycle" --candidate "$governing_candidate")"
result_two="$(next_candidate correction-two)"
[[ "$(state complete --issue 106 --lifecycle "$lifecycle" --correction "$correction_two" --source "$governing_candidate" --result "$result_two")" == 2 ]]
before="$(sha256sum <"$state_file")"
expect_failure third-refused state authorize --issue 106 --lifecycle "$lifecycle" --candidate "$result_two"
grep -Fq 'budget exhausted before authorization' "$fixture/third-refused.err"
[[ "$(sha256sum <"$state_file")" == "$before" ]]
echo 'ok - first and second batches complete; the third is refused before mutation'

printf '%s\n' 'B-17: accepted blocker remains unresolved' >"$fixture/blockers"
state exhaust --issue 106 --lifecycle "$lifecycle" --candidate "$result_two" \
  --outcome Progresses --blockers-file "$fixture/blockers" \
  --reentry-condition 'prerequisite #200 completes'
[[ "$(jq -r '.lifecycle.status' "$state_file")" == ended ]]
[[ "$(jq -r '.lifecycle.outcome' "$state_file")" == Progresses ]]
[[ "$(jq -r '.lifecycle.current_candidate' "$state_file")" == "$result_two" ]]
[[ "$(jq -r '.lifecycle.unresolved_blockers' "$state_file")" == 'B-17: accepted blocker remains unresolved' ]]
expect_failure mere-continuation state begin --issue 106 --run try-again@example/project --candidate "$result_two"
expect_failure false-reentry state reenter --issue 106 --run new@example/project --candidate "$result_two" \
  --condition 'something else happened' --evidence 'claim'
successor="$(state reenter --issue 106 --run new@example/project --candidate "$result_two" \
  --condition 'prerequisite #200 completes' --evidence 'issue #200 is closed with required artifact')"
[[ "$successor" != "$lifecycle" ]]
[[ "$(jq -r '.lifecycle.consumed' "$state_file")" == 0 ]]
[[ "$(jq -r '.lifecycle.predecessor' "$state_file")" == "$lifecycle" ]]
[[ "$(jq -r '.history[0].consumed' "$state_file")" == 2 ]]
echo 'ok - only matched, evidenced material re-entry creates a new lifecycle'

# The other settled exhaustion outcome is available when ordinary partial
# closeout cannot safely hand back a useful candidate.
issue_two_source="$(candidate)"
issue_two_lifecycle="$(state begin --issue 107 --run afk@example/project --candidate "$issue_two_source")"
for n in 11 12; do
  cid="$(state authorize --issue 107 --lifecycle "$issue_two_lifecycle" --candidate "$issue_two_source")"
  next="$(next_candidate "afk-correction-$n")"
  state complete --issue 107 --lifecycle "$issue_two_lifecycle" --correction "$cid" --source "$issue_two_source" --result "$next" >/dev/null
  issue_two_source="$next"
done
printf 'unsafe partial candidate\n' >"$fixture/unsafe-blockers"
state exhaust --issue 107 --lifecycle "$issue_two_lifecycle" --candidate "$issue_two_source" \
  --outcome failed --blockers-file "$fixture/unsafe-blockers" \
  --reentry-condition 'trusted contract is materially rescoped'
[[ "$(jq -r '.lifecycle.outcome' "$repo/.git/work-on-convergence/issue-107.json")" == failed ]]
echo 'ok - exhaustion records either Progresses or failed without a new outcome'

# If the delegate changed Candidate content but completion was never correlated,
# recovery cannot guess whether to restore the unit.
drift_source="$(candidate)"
drift_lifecycle="$(state begin --issue 108 --run interrupted@example/project --candidate "$drift_source")"
state authorize --issue 108 --lifecycle "$drift_lifecycle" --candidate "$drift_source" >/dev/null
drift_result="$(next_candidate interrupted-uncorrelated-change)"
expect_failure irreconcilable state recover --issue 108 --run resumed@example/project --candidate "$drift_result"
grep -Fq 'no correlated result' "$fixture/irreconcilable.err"
[[ "$(jq -r '.lifecycle.status' "$repo/.git/work-on-convergence/issue-108.json")" == irreconcilable ]]
expect_failure irreconcilable-authorize state authorize --issue 108 --lifecycle "$drift_lifecycle" --candidate "$drift_result"
expect_failure irreconcilable-closes state end --issue 108 --lifecycle "$drift_lifecycle" \
  --candidate "$drift_result" --outcome Closes
echo 'ok - an uncorrelated Candidate transition fails closed instead of restoring budget'

pending_source="$(candidate)"
pending_lifecycle="$(state begin --issue 110 --run pending@example/project --candidate "$pending_source")"
state authorize --issue 110 --lifecycle "$pending_lifecycle" --candidate "$pending_source" >/dev/null
expect_failure pending-closes state end --issue 110 --lifecycle "$pending_lifecycle" \
  --candidate "$pending_source" --outcome Closes
echo 'ok - an accepted unresolved correction cannot reach Closes without mutation'

corrupt_source="$(candidate)"
corrupt_lifecycle="$(state begin --issue 109 --run corrupt@example/project --candidate "$corrupt_source")"
corrupt_state="$repo/.git/work-on-convergence/issue-109.json"
jq '.lifecycle.current_candidate = "repo:example/project;tree:0000000000000000000000000000000000000000"' \
  "$corrupt_state" >"$fixture/corrupt.json"
cp "$fixture/corrupt.json" "$corrupt_state"
chmod 600 "$corrupt_state"
expect_failure corrupt-chain state recover --issue 109 --run resumed@example/project --candidate "$corrupt_source"
grep -Fq 'semantic state is corrupt' "$fixture/corrupt-chain.err"
[[ -n "$corrupt_lifecycle" ]]
echo 'ok - corrupt semantic continuity is rejected rather than reconstructed from Git'

# Pin the agent-facing composition that the command cannot infer from content.
has "$workflow" 'recover.*Convergence lifecycle.*before acting.*accepted blocker' \
  'the workflow recovers authority before correction'
has "$state_contract" 'findings.*adjudication.*review.*validation.*evidence.*do not consume' \
  'non-mutating events do not consume budget'
has "$state_contract" 'AFK follows this exact state machine' \
  'AFK has no reset or override'
has "$state_contract" 'Progresses.*safe.*independently useful.*failed.*otherwise' \
  'ordinary partial-closeout semantics choose the outcome'
has "$review_contract" 'post-delegation.*Validation-surface manifest.*takes precedence.*Convergence' \
  'manifest invalidation precedes convergence handling'
has "$closeout" 'Convergence.*exhaust' \
  'closeout preserves the exhausted durable hand-back'
echo 'ok - workflow, AFK, closeout, and manifest precedence compose at the public seam'

printf '\nAll Convergence lifecycle authority scenarios passed.\n'
