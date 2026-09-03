#!/usr/bin/env bash
set -euo pipefail

# Delta review is an orchestration contract: the workflow, review skill, and
# closure gate must agree on identities, transitions, reviewer inputs, and the
# two stronger validation contracts that govern it. Exercise that public seam
# rather than any one prompt-construction detail.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

WORKFLOW="$skill_dir/references/default-workflow.md"
STATE="$skill_dir/references/review-state-machine.md"
SKILL="$skill_dir/SKILL.md"
CLOSEOUT="$skill_dir/references/github-closeout.md"
REVIEW="$skill_dir/../../engineering/code-review/SKILL.md"
EVIDENCE="$skill_dir/references/validation-evidence.md"

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

has "$WORKFLOW" 'references/review-state-machine.md' \
  'the selected workflow applies the authoritative review state machine'
has "$SKILL" 'Apply `references/review-state-machine.md` to every selected workflow' \
  'the top-level authority binds custom workflows to the same state machine'

## One frozen governing state and one exact candidate per gate
has "$STATE" \
  'freeze.*comparison base.*trusted (contract )?snapshot.*complete Standards input.*accepted full review contract.*Validation-surface manifest' \
  'one review chain freezes every governing input'
has "$STATE" \
  'Before the initial gate.*materialize.*complete frozen Standards input' \
  'the review chain materializes the Standards input before review'
has "$STATE" \
  'applicable repository standards source.*source-labelled path.*exact content' \
  'the frozen Standards input includes repository standards sources and content'
has "$STATE" \
  'complete Fowler smell baseline.*code-review/SKILL.md' \
  'the frozen Standards input includes code-review.s full Fowler baseline'
has "$STATE" \
  'repo overrides.*judgement call.*frozen Standards input' \
  'the frozen Standards input preserves the baseline semantics'
has "$STATE" \
  'initial.*cumulative.*Standards.*Spec.*closure.*same exact Candidate identity' \
  'the initial cumulative gate binds all three axes to one candidate'
has "$STATE" \
  'Reviewed anchor only after.*Standards.*Spec.*closure.*complete.*same exact candidate' \
  'the initial anchor waits for all three axes'
has "$STATE" \
  'clean.*initial cumulative gate.*unchanged.*satisfies.*fresh blind cumulative confirmation.*no second' \
  'a clean unchanged initial gate is not duplicated at closeout'
echo 'ok - the initial cumulative gate establishes one exact reviewed anchor and confirmation'

## Remediation always takes the delta leg
has "$STATE" \
  'accepted blocker.*candidate-content change.*invalidates.*confirmation.*retain.*Reviewed anchor.*delta' \
  'blocker remediation invalidates confirmation and retains the prior anchor'
has "$STATE" \
  'mechanically exact (direct )?delta.*Reviewed anchor.*current Candidate' \
  'the correction review uses the exact anchor-to-candidate delta'
has "$STATE" \
  'direct.*Reviewed.?anchor.*current Candidate.*two-endpoint tree comparison' \
  'the remediation subject is a direct anchor-to-candidate tree comparison'
has "$STATE" \
  'Standards.*Spec.*closure.*delta.*same exact current candidate' \
  'all delta axes assess one current candidate'
has "$STATE" \
  'advance.*Reviewed anchor only after.*all three.*delta axes.*complete.*same exact candidate' \
  'the anchor advances only after the complete delta gate'
has "$STATE" \
  'Reviewed anchor.*does not mean.*clean.*accepted.*closable.*eligible for closeout' \
  'anchor advancement carries no cleanliness or closeout meaning'
echo 'ok - remediation enters a three-axis exact-delta gate before advancing the anchor'

## The inherited skill routes caller-pinned inputs to the separate adapter
has "$REVIEW" \
  'caller.*pinned.*WORK-ON-REVIEW.md.*instead of the ordinary input discovery' \
  'the inherited skill routes caller-pinned inputs to the separate adapter'
has "$CLOSEOUT" \
  'Neither kind receives the ledger or anyone.s conclusions' \
  'both closure assignments remain blind'
has "$CLOSEOUT" \
  'delta closure is incremental.*does not.*complete cumulative closure table' \
  'the closure delta axis is genuinely incremental'
has "$CLOSEOUT" \
  'final cumulative.*complete.*closure.*table.*backstop' \
  'the final cumulative closure axis retains the complete backstop'
echo 'ok - pinned inputs route to the adapter and closure stays blind'

## Delta is the initial surface; concrete reasons bound context expansion
has "$STATE" \
  'correction delta.*initial review search surface' \
  'delta review starts at the correction rather than reconstructing the candidate'
has "$STATE" \
  'unchanged context.*concrete.*contract question.*changed-mechanism question.*reproduced finding.*#62' \
  'unchanged context requires one recorded concrete reason'
has "$STATE" \
  '#62.*same-mechanism.*same.*criterion.*public flow.*stop.*another criterion.*subsystem.*external boundary.*speculative' \
  '#62 remains reachable with its bounded stop rules'
has "$STATE" \
  'not routin.*(reconstruct|repackage|reread).*full cumulative candidate' \
  'context expansion cannot become a routine cumulative reread'
echo 'ok - delta scope preserves bounded unchanged-context and #62 investigation'

## Clean delta returns to blind cumulative confirmation; another fix repeats both legs
has "$STATE" \
  'clean delta gate.*fresh blind cumulative.*Standards.*Spec.*closure.*full accepted review contract' \
  'a clean delta gate transitions to a fresh three-axis cumulative confirmation'
has "$STATE" \
  'blocker.*final.*cumulative confirmation.*correction.*delta gate.*fresh blind cumulative confirmation' \
  'a final-confirmation blocker returns through correction, delta, and full confirmation'
has "$CLOSEOUT" \
  'initial cumulative gate.*unchanged.*or.*post-remediation.*fresh blind cumulative confirmation' \
  'closeout consumes the applicable confirmation without manufacturing another gate'
echo 'ok - closeout is reached only through the applicable exact cumulative confirmation'

## Invalidation composes with manifest and evidence ownership
has "$STATE" \
  'candidate-content.*or.*governing-input change.*invalidates.*review chain' \
  'candidate or governing-state changes invalidate the chain'
has "$STATE" \
  'post-delegation.*omitted.*Validation-surface manifest.*takes precedence.*(must not|never).*restart' \
  '#103 manifest invalidity takes precedence over review restart'
has "$STATE" \
  'assurance sufficiency.*determines.*execution.*stage transition.*never.*reason.*rerun' \
  '#104 and #122 evidence reuse governs every review transition'
has "$EVIDENCE" \
  'Failing, stale, contradictory, incomplete, identity-invalid, or otherwise inadequate evidence remains blocking' \
  'inadequate evidence remains blocking under its owning policy'
echo 'ok - review invalidation preserves manifest fail-closed and evidence-reuse ownership'

if (( failures > 0 )); then
  printf '\n%s review-state-machine assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll review-state-machine contract assertions held.\n'
