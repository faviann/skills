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
REVIEW_ADAPTER="$skill_dir/../../engineering/code-review/WORK-ON-REVIEW.md"
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

lacks() {
  if grep -Eqi -- "$2" "$1"; then
    fail "$3 (unexpected: $2)"
  fi
}

code_block_after() {
  local source="$1" heading="$2" output="$3"
  awk -v heading="$heading" '
    $0 == heading { section = 1; next }
    section && $0 == "```text" { inside = 1; next }
    inside && $0 == "```" { exit }
    inside { print }
  ' "$source" >"$output"
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
  'reuse.*exact frozen Standards input.*cumulative.*delta.*never rediscover' \
  'every review gate reuses one Standards input instead of live discovery'
has "$STATE" \
  'initial.*cumulative.*Standards.*Spec.*closure.*same exact Candidate identity' \
  'the initial cumulative gate binds all three axes to one candidate'
has "$STATE" \
  'Reviewed anchor only after.*Standards.*Spec.*closure.*complete.*same exact candidate' \
  'the initial anchor waits for all three axes'
has "$STATE" \
  'clean.*initial cumulative gate.*unchanged.*satisfies.*fresh blind cumulative confirmation.*no second' \
  'a clean unchanged initial gate is not duplicated at closeout'
cumulative_package="$fixture_dir/cumulative-package.txt"
code_block_after "$STATE" '### Cumulative-review package' "$cumulative_package"
for required in \
  'Comparison-base identity' \
  'Exact current Candidate identity' \
  'Mechanically exact cumulative diff' \
  'Full trusted contract' \
  'Binding Standards input' \
  'Validation-surface manifest' \
  'Qualifying raw validation evidence'; do
  grep -Fqi -- "$required" "$cumulative_package" \
    || fail "cumulative-review package includes $required"
done
lacks "$cumulative_package" '\.\.\.' \
  'caller-pinned cumulative review also uses its exact supplied endpoints'
grep -Eqi -- 'git diff[^.]*comparison-base[^.]*candidate' "$cumulative_package" \
  || fail 'the cumulative package uses its two exact endpoints directly'
has "$STATE" \
  'same exact package to Standards, Spec, and closure' \
  'every cumulative axis receives one frozen package without live discovery'
has "$STATE" \
  'package is authoritative.*no axis refetches or rediscovers a governing input' \
  'cumulative package mode preserves frozen governing inputs'
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

## The reviewer package is exact and blind
package="$fixture_dir/delta-package.txt"
code_block_after "$STATE" '### Delta-review package' "$package"
for required in \
  'Previous Reviewed-anchor identity' \
  'Exact current Candidate identity' \
  'Mechanically exact delta' \
  'Full trusted contract' \
  'Binding Standards input' \
  'Qualifying raw validation evidence' \
  'Review scope'; do
  grep -Fqi -- "$required" "$package" \
    || fail "delta-review package includes $required"
done
lacks "$package" '\.\.\.' \
  'the exact remediation subject never silently becomes a merge-base range'
grep -Eqi -- 'git diff[^.]*previous-anchor[^.]*current-candidate' "$package" \
  || fail 'the exact remediation package uses two direct endpoints'
lacks "$package" \
  'remediation rationale|prior finding|prior report|accepted directive|adjudication|disposition|ledger|fixes [A-Z0-9#]' \
  'the delta-review package is blind to prior conclusions and repair rationale'
grep -Eqi -- \
  'exact correction delta.*unchanged context.*concrete contract question.*changed-mechanism question.*reproduced finding.*#62.*same mechanism.*governing criterion.*public flow.*stop before another criterion.*subsystem.*external boundary.*speculative defense.*not routinely reconstruct.*full cumulative candidate' \
  "$(flatten "$package")" \
  || fail 'the transported package carries bounded unchanged-context and #62 rules'
has "$REVIEW" \
  'caller.*pinned.*WORK-ON-REVIEW.md.*instead of the ordinary input discovery' \
  'the inherited skill routes caller-pinned inputs to the separate adapter'
lacks "$REVIEW" \
  'Delta-package mode|delta-review package replaces steps|never resolve an independent `HEAD`' \
  'the upstream-derived skill does not inline its work-on exception'
has "$REVIEW_ADAPTER" \
  'pinned inputs replace `SKILL.md` steps 1 through 3 and the generic input bullets in step 4' \
  'pinned invocation replaces generic cumulative discovery'
has "$REVIEW_ADAPTER" \
  'comparison Candidate identity.*current Candidate identity.*frozen.*contract.*frozen Standards input.*raw validation evidence.*caller-supplied review-scope' \
  'the adapter exposes one complete caller-pinned review interface'
has "$REVIEW_ADAPTER" \
  'supplied identities and frozen sources are authoritative.*never resolve an independent `HEAD`.*build or pass a commit list.*discover or refetch a spec.*discover live standards' \
  'package mode cannot leak commit rationale or substitute live governing inputs'
has "$REVIEW_ADAPTER" \
  'Construct each prompt from exactly two inputs' \
  'the composed delta prompt contains no convenience inputs'
has "$REVIEW_ADAPTER" \
  'Standards.*complete frozen Standards input.*repository standards.*Fowler smell baseline.*repo-overrides.*judgement-call' \
  'the Standards package preserves its complete existing contract'
lacks "$REVIEW_ADAPTER" \
  'Reviewed anchor|anchor advancement|cumulative confirmation|delta gate|#62|work-on owns|work-on supplies' \
  'the adapter carries no work-on review-state semantics'
lacks "$REVIEW_ADAPTER" \
  'work-on' \
  'the pinned adapter does not need to know its caller'

prompt_template="$fixture_dir/work-on-prompt-template.txt"
code_block_after "$REVIEW_ADAPTER" '## Prompt composition' "$prompt_template"
[[ "$(grep -cve '^[[:space:]]*$' "$prompt_template")" == 2 ]] \
  || fail 'the work-on review adapter permits exactly package plus axis brief'
mapfile -t axis_briefs < <(sed -n 's/^- The brief: "\(.*\)"$/\1/p' "$REVIEW")
[[ "${#axis_briefs[@]}" == 2 ]] \
  || fail 'both code-review axis briefs are mechanically identifiable'
for axis in "${!axis_briefs[@]}"; do
  composed="$fixture_dir/composed-$axis.txt"
  { cat "$package"; printf '%s\n' "${axis_briefs[$axis]}"; } >"$composed"
  lacks "$composed" \
    'remediation rationale|prior finding|prior report|accepted directive|adjudication|disposition|ledger|commit list|issue reference' \
    "composed delta axis $axis contains only neutral permitted inputs"
done
standards_composed="$fixture_dir/composed-standards.txt"
{ cat "$package"; printf '%s\n' "${axis_briefs[0]}"; } >"$standards_composed"
grep -Eqi -- 'Binding Standards input.*repository standards.*exact.*content' \
  "$(flatten "$standards_composed")" \
  || fail 'the composed Standards prompt carries exact repository standards content'
grep -Eqi -- 'Binding Standards input.*Fowler smell baseline.*repo[- ]overrides.*judgement[- ]call' \
  "$(flatten "$standards_composed")" \
  || fail 'the composed Standards prompt carries the Fowler baseline and semantics'
has "$CLOSEOUT" \
  'delta closure axis receives.*identical neutral.*review package' \
  'the closure delta axis receives the same blind package'
has "$CLOSEOUT" \
  'Neither kind receives the ledger or anyone.s conclusions' \
  'both closure assignments remain blind'
has "$CLOSEOUT" \
  'delta closure is incremental.*does not.*complete cumulative closure table' \
  'the closure delta axis is genuinely incremental'
has "$CLOSEOUT" \
  'final cumulative.*complete.*closure.*table.*backstop' \
  'the final cumulative closure axis retains the complete backstop'
echo 'ok - delta reviewers receive the exact neutral package and no prior conclusions'

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
  'new qualifying raw evidence.*exact unchanged candidate.*does not.*invalidate' \
  'new evidence alone does not invalidate review'
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
