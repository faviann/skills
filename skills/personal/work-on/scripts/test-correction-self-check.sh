#!/usr/bin/env bash
set -euo pipefail

# The correction self-check is one portable instruction contract with two thin
# workflow entry paths. Exercise that public seam without parsing runtime
# Rechecked prose or freezing incidental document layout.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

SKILL="$skill_dir/SKILL.md"
WORKFLOW="$skill_dir/references/default-workflow.md"
STATE="$skill_dir/references/review-state-machine.md"
GLOSSARY="$skill_dir/../../../CONTEXT.md"

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
    fail "$3 (missing in ${1#"$skill_dir/"}: $2)"
  fi
}

lacks() {
  if grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3 (unexpected in ${1#"$skill_dir/"}: $2)"
  fi
}

extract_section() {
  local source="$1" heading="$2" output="$3"
  awk -v heading="$heading" '
    $0 == heading { inside = 1 }
    inside && $0 != heading && /^#{1,3} / { exit }
    inside { print }
  ' "$source" >"$output"
}

extract_h2_section() {
  local source="$1" heading="$2" output="$3"
  awk -v heading="$heading" '
    $0 == heading { inside = 1 }
    inside && $0 != heading && /^## / { exit }
    inside { print }
  ' "$source" >"$output"
}

contract="$fixture_dir/correction-contract"
readiness="$fixture_dir/readiness"
remediation="$fixture_dir/remediation"
cumulative="$fixture_dir/cumulative-package"
delta="$fixture_dir/delta-package"
extract_section "$WORKFLOW" '### Accepted-blocker correction self-check' "$contract"
extract_h2_section "$WORKFLOW" '## 3. Primary checkpoint' "$readiness"
extract_h2_section "$WORKFLOW" '## 5. Adjudicate and remediate through delta review' "$remediation"
extract_section "$STATE" '### Cumulative-review package' "$cumulative"
extract_section "$STATE" '### Delta-review package' "$delta"

## The cross-workflow invariant stays representation-agnostic.
has "$SKILL" \
  'Require every accepted-blocker correction by the retained implementation delegate.{0,100}applicable correction-scoped self-check before it advances' \
  'SKILL binds every workflow to the correction-scoped self-check before advancement'
lacks "$SKILL" 'Rechecked:' \
  'SKILL does not prescribe the default workflow return field'

## One shared contract owns the concrete correction-only return.
has "$contract" \
  'accepted-blocker correction.*readiness and post-gate corrections' \
  'the shared contract covers both accepted-blocker correction regions'
has "$contract" \
  'every accepted-blocker correction round.{0,180}implementation owner.s ordinary return.{0,180}continues the retained context.{0,120}fresh-delegate fallback' \
  'every correction round uses Rechecked through continuation or the existing fallback'
has "$contract" 'Changed:.*Evidence:.*Rechecked:.*Unverified:.*Risks:' \
  'the correction return has the existing channels plus Rechecked'
has "$contract" \
  'initial implementation and bounded coherence pass keep the unchanged return above' \
  'initial implementation and coherence completion keep their existing return'

## Applicability is discovered once before dispatch and again from implementation.
has "$contract" \
  'Before dispatch, the primary derives and dispatches minimum obligations.{0,100}accepted blocker.{0,100}only information it owns' \
  'the primary derives directive-known obligations before dispatch'
has "$contract" \
  'After implementing, the retained delegate accounts for additional applicability created by its chosen mechanism' \
  'the delegate accounts for implementation-induced applicability after implementing'
has "$contract" 'not applicable.{0,40}one-line reason.{0,80}valid delegate declaration' \
  'delegate-discovered non-applicability has a reasoned declaration'
for path in "$readiness" "$remediation"; do
  has "$path" \
    'Accepted-blocker correction self-check.s dispatch rule.{0,160}directive-known minimum obligations' \
    'each correction path reaches dispatch-time applicability'
  has "$path" \
    '(shared )?(correction )?self-check.s pre-commit completion rule' \
    'each correction path reaches the shared pre-commit completion rule'
done

## Repository standards are correction-specific on every correction.
has "$contract" 'Correction-specific repository standards.{0,60}every correction' \
  'the standards check applies to every correction'
has "$contract" \
  'named correction-specific governing sources plus the outcome.{0,100}no correction-specific governing repository source was identified' \
  'the standards declaration accepts a named source and outcome or an explicit no-source result'
has "$contract" 'Bare `standards: checked`-style boilerplate is insufficient' \
  'bare standards boilerplate cannot satisfy the contract'
has "$contract" 'reads repository standards directly' \
  'the delegate reads correction-specific standards from the repository'

## The adversarial check retains its narrow population boundary.
has "$contract" \
  'depends on absence, rejection, a forbidden case, exhaustive enumeration, or population closure' \
  'the adversarial check names the complete narrow applicability family'
has "$contract" \
  'plausible false candidate, contradiction, omitted member, or forbidden case.{0,80}report the result' \
  'an applicable adversarial check exercises a plausible counterexample'
has "$contract" 'Do not extend this to every falsifiable universal claim' \
  'the adversarial check does not widen to every universal claim'

## Validation offered as proof names both what it proves and where it observed it.
has "$contract" \
  'In `Rechecked:`, name the claim and actual observed surface, then state whether that surface can or cannot establish the claim' \
  'Rechecked records the claim, observed surface, and capability assessment'
has "$contract" \
  'validation execution and result in `Evidence:`' \
  'validation execution and results remain in Evidence'

## Completion returns missing work and blocks unresolved corrections before closeout.
has "$contract" \
  'Missing or incomplete required information returns through the existing implementation-owner mechanism for completion' \
  'missing self-check information reuses the continuation-or-fallback owner mechanism'
has "$contract" \
  'explicitly unresolved required check blocks commit.{0,220}revise or reshape.{0,180}narrow.{0,120}replace.{0,120}another way' \
  'an unresolved check blocks commit while ordinary correction remains the first route'
has "$contract" \
  'Only when no advancing correction can be produced.{0,220}`Progresses`.{0,120}`failed`' \
  'closeout vocabulary applies only after correction alternatives are exhausted'
has "$contract" \
  'existing closeout rules directly.{0,300}does not pass through `references/normative-remediation.md`' \
  'correction-self-check closeout routing bypasses normative remediation'

## Existing normative remediation composes with the broader self-check.
has "$contract" \
  'Complete this self-check in the working tree before commit.{0,180}qualifying post-gate Corrective batch.{0,120}both this self-check and the existing `references/normative-remediation.md` checkpoint must be complete before commit' \
  'qualifying post-gate corrections complete both pre-commit obligations'
has "$contract" \
  'reference retains ownership of its contract' \
  'normative-remediation ownership remains in its existing reference'

## Rechecked reasoning stays primary-side while raw evidence uses existing slots.
has "$contract" \
  'Keep `Rechecked:` rationale, applicability declarations, conclusions, and correction reasoning in primary-side working state, excluded from cumulative and delta reviewer packages' \
  'the shared contract positively excludes Rechecked reasoning from both package types'
for package in "$cumulative" "$delta"; do
  has "$package" \
    'Candidate identity.*Mechanically exact.*Full trusted contract.*Binding Standards input.*Validation-surface manifest.*Qualifying raw validation evidence' \
    'the reviewer package retains its enumerated contract and evidence slots'
done

## Self-checking remains implementation work rather than another review stage.
has "$contract" \
  'retained implementation delegate owns the checks.{0,180}existing reviewers remain the independent backstop' \
  'the retained implementation delegate owns correction self-checking'

## The broad new term leaves the narrower Corrective batch bytes untouched.
expected_corrective_batch="$fixture_dir/expected-corrective-batch"
actual_corrective_batch="$fixture_dir/actual-corrective-batch"
cat >"$expected_corrective_batch" <<'EOF'
**Corrective batch**:
One automatic, accepted-blocker-driven correction after the initial cumulative gate that changes the exact candidate content identity. Blockers adjudicated and repaired together form one batch; surrounding review, validation, evidence gathering, synchronization, and state-machine restarts do not.
_Avoid_: finding, review round, validation run, remediation attempt
EOF
awk '
  /^\*\*Corrective batch\*\*:/ { inside = 1 }
  inside && /^[[:space:]]*$/ { exit }
  inside { print }
' "$GLOSSARY" >"$actual_corrective_batch"
if ! cmp -s "$expected_corrective_batch" "$actual_corrective_batch"; then
  fail 'the Corrective batch glossary definition remains byte-identical'
fi
has "$GLOSSARY" \
  '\*\*Accepted-blocker correction\*\*:.*readiness corrections.*post-gate corrections.*Every \*\*Corrective batch\*\*.*narrower concept used by normative remediation' \
  'the glossary distinguishes the broad correction unit from the narrower Corrective batch'

if (( failures > 0 )); then
  printf '\n%s correction-self-check assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll correction-self-check contract assertions held.\n'
