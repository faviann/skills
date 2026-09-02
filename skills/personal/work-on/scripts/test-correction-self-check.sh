#!/usr/bin/env bash
set -euo pipefail

# The correction self-check is one portable instruction contract with two thin
# workflow entry paths. Exercise that public seam against the contract's own
# module plus the spine call sites that reach it, without parsing runtime
# Rechecked prose or freezing incidental document layout.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

SKILL="$skill_dir/SKILL.md"
WORKFLOW="$skill_dir/references/default-workflow.md"
CONTRACT="$skill_dir/references/default-workflow/accepted-blocker-correction-self-check.md"
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
  local source="$1" title="$2" output="$3"
  awk -v title="$title" '
    $0 ~ "^## ([0-9]+\\. )?" title "$" { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$source" >"$output"
}

extract_text_manifest() {
  local source="$1" output="$2"
  awk '
    $0 == "```text" { inside = 1; next }
    inside && $0 == "```" { exit }
    inside { print }
  ' "$source" >"$output"
}

contract="$CONTRACT"
readiness="$fixture_dir/readiness"
remediation="$fixture_dir/remediation"
cumulative_section="$fixture_dir/cumulative-package-section"
delta_section="$fixture_dir/delta-package-section"
cumulative="$fixture_dir/cumulative-package-manifest"
delta="$fixture_dir/delta-package-manifest"
[[ -f "$contract" ]] || {
  fail 'the correction self-check has its own authoritative module'
  printf '\n%s correction-self-check assertion(s) failed.\n' "$failures" >&2
  exit 1
}
extract_h2_section "$WORKFLOW" 'Primary checkpoint' "$readiness"
extract_h2_section "$WORKFLOW" 'Adjudicate and remediate through delta review' "$remediation"
extract_section "$STATE" '### Cumulative-review package' "$cumulative_section"
extract_section "$STATE" '### Delta-review package' "$delta_section"
extract_text_manifest "$cumulative_section" "$cumulative"
extract_text_manifest "$delta_section" "$delta"

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
  has "$path" \
    '`references/default-workflow/accepted-blocker-correction-self-check.md`' \
    'each correction call site names the module that owns the contract'
  has "$path" \
    "content verbatim in the dispatch rather than its path" \
    'each correction call site hands the delegate content instead of a path'
  lacks "$path" 'Bare `standards: checked`|adversarial negative' \
    'no call site restates the checks the module owns'
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
  'Complete this self-check in the working tree before commit.{0,180}qualifying post-gate Corrective batch.{0,120}complete this self-check before applying the existing `references/normative-remediation.md` checkpoint to the actual correction.{0,80}both must be complete before commit' \
  'qualifying post-gate corrections complete the self-check before the normative checkpoint and commit'
has "$contract" \
  'reference retains ownership of its contract' \
  'normative-remediation ownership remains in its existing reference'
if ! awk '
  /shared correction self-check.s pre-commit/ { self_check = NR }
  /reconciliation against the actual correction/ { normative = NR }
  END { exit !(self_check && normative && self_check < normative) }
' "$(flatten "$remediation")"; then
  fail 'post-correction self-check completion precedes normative reconciliation in remediation'
fi

## Rechecked reasoning stays primary-side and outside package manifests.
has "$contract" \
  'Keep `Rechecked:` rationale, applicability declarations, conclusions, and correction reasoning in primary-side working state, excluded from cumulative and delta reviewer packages' \
  'the shared contract positively excludes Rechecked reasoning from both package types'
for package in "$cumulative" "$delta"; do
  if ! grep -q '[^[:space:]]' "$package"; then
    fail 'the extracted reviewer package manifest is non-empty'
  fi
  lacks "$package" \
    '(^|[[:space:]])-[[:space:]]+([*][*]|`)?Rechecked:([*][*]|`)?([[:space:]]|$)' \
    'the reviewer package does not enumerate Rechecked as a field'
done

## Self-checking remains implementation work rather than another review stage.
has "$contract" \
  'retained implementation delegate owns the checks.{0,180}existing reviewers remain the independent backstop' \
  'the retained implementation delegate owns correction self-checking'

## The broad new term remains distinct from the narrower Corrective batch.
has "$GLOSSARY" \
  '\*\*Accepted-blocker correction\*\*:.*readiness corrections.*post-gate corrections.*Every \*\*Corrective batch\*\*.*narrower concept used by normative remediation' \
  'the glossary distinguishes the broad correction unit from the narrower Corrective batch'

if (( failures > 0 )); then
  printf '\n%s correction-self-check assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll correction-self-check contract assertions held.\n'
