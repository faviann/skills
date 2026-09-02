#!/usr/bin/env bash
set -euo pipefail

# The reset is one qualification test the workflow spine keeps, so a run decides
# qualification with nothing preloaded, plus one post-qualification contract its
# module owns. Exercise that ownership boundary and the delegate-first dispatch,
# which is the only path where the delegate acts without a primary round trip.
#
# Assertions cover stable instruction structure. Independent Spec and closure
# interpret the governing prose; this suite does not parse arbitrary English.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

WORKFLOW="$skill_dir/references/default-workflow.md"
MODULE="$skill_dir/references/default-workflow/implementation-mechanism-reset.md"

failures=0
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

flatten() {
  local source="$1"
  local flat="$fixture_dir/$(printf '%s' "${source#"$skill_dir/"}" | tr '/' '_')"
  [[ -f "$flat" ]] || awk '
    /^[[:space:]]*$/ { print paragraph; paragraph = ""; next }
    { paragraph = (paragraph == "" ? $0 : paragraph " " $0) }
    END { print paragraph }
  ' "$source" | tr -s ' ' >"$flat"
  printf '%s' "$flat"
}

has() {
  if ! grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3"
  fi
}

lacks() {
  if grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3"
  fi
}

remediation="$fixture_dir/remediation-step.md"
awk '/^## / { inside = ($0 ~ /^## 5\./) } inside { print }' \
  "$WORKFLOW" >"$remediation"
if [[ ! -s "$MODULE" || ! -s "$remediation" ]]; then
  fail 'the reset has a module reached from the adjudicate-and-remediate step'
  printf '\n%s implementation-mechanism-reset assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

## Qualification is decidable from the spine with nothing preloaded.
awk '/^## / { inside = ($0 ~ /^## 5\./) }
  inside && /^### Implementation-mechanism reset/ { found = 1 }
  END { exit !found }' "$WORKFLOW" ||
  fail 'reset qualification sits inside the adjudicate-and-remediate step'
has "$remediation" \
  '\*\*Support loop\*\*.{0,400}no independent contract reason to survive if the approach changes' \
  'the support-loop entry is defined in the spine'
has "$remediation" \
  '\*\*Accepted incompatibility\*\*.{0,300}discriminator cannot jointly satisfy the required properties' \
  'the accepted-incompatibility entry is defined in the spine'
has "$remediation" \
  'direct correction at the accepted boundary.{0,160}ordinary helper fix.{0,160}ordinary fixture correction.{0,160}unrelated defect in the same subsystem' \
  'the spine keeps every negative discriminator'
has "$remediation" \
  'Repeated blockers, complexity, implementation size, and review count establish neither entry' \
  'volume and size establish no entry'
lacks "$MODULE" \
  'Repeated blockers, complexity, implementation size|conflicting reproduced witnesses' \
  'the module does not restate the qualification the spine owns'
echo 'ok - qualification is decidable from the spine alone'

## The qualified reset has one authoritative home.
has "$MODULE" 'Reconsider only the implementation premise exposed by this blocker' \
  'the module carries the bounded instruction'
has "$MODULE" '(uphold or revise|Uphold or revise)' \
  'the module carries the Uphold/revise dispositions'
has "$MODULE" \
  'creates no reset marker, ledger entry, flag, acknowledgement object, counter, or other recorded proof artifact' \
  'the module keeps the no-artifact rule'
has "$MODULE" 'retained implementation delegate owns the disposition and the implementation shape' \
  'the module keeps disposition ownership with the retained delegate'
has "$MODULE" 'Uphold returns to ordinary remediation' \
  'the module returns an upheld reset to ordinary remediation'
has "$MODULE" 'Both dispositions keep the accepted blocker until it is resolved' \
  'the accepted blocker stays open across both dispositions'
has "$MODULE" \
  'Later remediation evaluates both entries anew.{0,200}no exemption, suppression, one-shot status' \
  'later remediation re-evaluates qualification afresh with no standing earned'
for restated in \
  'Reconsider only the implementation premise' \
  'creates no reset marker' \
  'evaluates both entries anew'; do
  lacks "$remediation" "$restated" \
    "the call site does not restate the module contract ($restated)"
done
echo 'ok - the qualified reset contract has a single authoritative home'

## The call site reaches the module and says what returns control.
has "$remediation" \
  '(when|once) either entry qualifies.{0,120}`references/default-workflow/implementation-mechanism-reset\.md`' \
  'the call site names the module its trigger reaches'
has "$remediation" \
  'return control to ordinary remediation.{0,80}accepted blocker still open' \
  'the call site states what returns control to the workflow'
echo 'ok - the call site carries trigger, owner, and return without the contract'

## Delegate-first detection is served by the remediation dispatch.
has "$MODULE" \
  'delegate detection, the delegate applies it where it stands, with no authorization round trip' \
  'the module permits delegate-first detection without a round trip'
has "$remediation" \
  'delegate may itself reach a qualifying entry with no authorization round trip' \
  'the dispatch names delegate-first detection as the reason it carries the contract'
has "$remediation" \
  'read `references/default-workflow/implementation-mechanism-reset\.md` at this dispatch' \
  'every remediation dispatch reads the reset contract at that point'
has "$remediation" \
  'supply it, together with the Implementation-mechanism reset qualification above, as content rather than as a path' \
  'the delegate receives the reset contract and its qualification as content'
lacks "$remediation" \
  'supply.{0,80}(path to|its path) `references/default-workflow/implementation-mechanism-reset\.md`' \
  'the delegate is never handed a skills-checkout path instead of content'
echo 'ok - delegate-first detection receives the contract as dispatched content'

## No lifecycle machinery is introduced to carry the reset.
for forbidden in 'reset registry' 'reset receipt' 'reset loader' 'reset resolver' \
  'reset state machine'; do
  for source in "$MODULE" "$remediation"; do
    lacks "$source" "$forbidden" "the reset introduces no $forbidden"
  done
done
echo 'ok - the reset stays instruction-only'

if (( failures > 0 )); then
  printf '\n%s implementation-mechanism-reset assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll implementation-mechanism-reset contract assertions held.\n'
