#!/usr/bin/env bash
set -euo pipefail

# Normative remediation is one cross-document orchestration contract. Exercise
# its public instruction seam so the trigger, blind package, reader task, and
# workflow routing cannot drift independently.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

SKILL="$skill_dir/SKILL.md"
WORKFLOW="$skill_dir/references/default-workflow.md"
CONTRACT="$skill_dir/references/normative-remediation.md"
# Conditional contracts the default workflow invokes are governing members too,
# so the guards below follow them into their own modules.
WORKFLOW_MODULES=(
  "$skill_dir/references/default-workflow/accepted-blocker-correction-self-check.md"
  "$skill_dir/references/default-workflow/bounded-re-adjudication.md"
  "$skill_dir/references/default-workflow/implementation-mechanism-reset.md"
)
STATE="$skill_dir/references/review-state-machine.md"
CLOSABILITY="$skill_dir/references/closability-gate.md"
EVIDENCE="$skill_dir/references/validation-evidence.md"
GLOSSARY="$skill_dir/../../../CONTEXT.md"
EVAL="$skill_dir/../../../.agents/evals/work-on-normative-remediation.md"
STATIC="$script_dir/test-normative-remediation.sh"

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

if [[ ! -f "$CONTRACT" ]]; then
  fail 'the normative-remediation authority reference exists'
  printf '\n%s normative-remediation assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

## Qualification is object-based, independent of intended meaning or batch age.
has "$SKILL" \
  'every qualifying Corrective batch.*references/normative-remediation.md|references/normative-remediation.md.*every qualifying Corrective batch' \
  'the top-level invariant binds every selected workflow to normative remediation'
has "$WORKFLOW" 'references/normative-remediation.md.*Corrective batch' \
  'the default workflow invokes normative remediation for corrective batches'
has "$CONTRACT" \
  'changes the (words|wording), structure, or placement of a governing proposition or relationship' \
  'qualification turns on the governing object being changed'
has "$CONTRACT" \
  'intended semantic delta.*including `none`.*(never|does not).*gate|including `none`.*(never|does not).*gate.*intended semantic delta' \
  'intended meaning including none cannot suppress the mechanism'
has "$CONTRACT" 'every qualifying Corrective batch.*including the first' \
  'the first qualifying corrective batch is covered'
has "$CONTRACT" 'descriptive and history-only.*does not qualify|descriptive.*history-only.*do not qualify' \
  'file authority alone does not qualify descriptive history'
has "$CONTRACT" 'status and lifecycle markers.*qualify' \
  'status and lifecycle markers remain governing propositions'
echo 'ok - qualification is object-based and independent of expected semantic delta'

## Entitlement follows the correction the delegate actually produced.
has "$CONTRACT" 'qualification before dispatch is provisional' \
  'pre-dispatch qualification is provisional rather than final'
has "$CONTRACT" \
  'entitlement is determined from the actual correction, for the exact current `Candidate identity`' \
  'entitlement is settled against the exact current correction'
has "$CONTRACT" \
  'qualification may inspect the correction to determine which semantic units exist' \
  'qualification may read the correction for which units exist'
has "$CONTRACT" \
  'Authority delta may not use the correction to determine what those units were intended to mean' \
  'the Authority delta may not read the correction for intended meaning'
has "$CONTRACT" \
  'correction from the Reviewed anchor to the exact current `Candidate identity`' \
  'the qualification evidence spans the Reviewed anchor to the current candidate'
has "$CONTRACT" '`Changed:` channel is a locator only.{0,120}primary owns qualification' \
  'the delegate locates changed material without owning the verdict'
has "$CONTRACT" \
  'bounded surrounding or frozen governing authority.{0,200}never becomes a cumulative reread of the candidate' \
  'bounded widening classifies changed material without cumulative review'
echo 'ok - qualification is evaluated against the exact current correction'

## Reconciliation recomputes the qualifying set rather than accumulating it.
has "$CONTRACT" 'recomputational, not additive' \
  'reconciliation recomputes the qualifying set'
has "$CONTRACT" \
  'qualifies only because of what the delegate actually changed enters it' \
  'implementation-induced qualifying units enter the reconciled set'
has "$CONTRACT" \
  'provisionally predicted unit the actual correction does not change leaves it' \
  'an unrealized predicted unit leaves the reconciled set'
has "$CONTRACT" \
  'removal of a provisionally predicted unit establishes only that the actual correction does not change that unit' \
  'removal is not evidence that a blocker or directive was satisfied'
echo 'ok - reconciliation is recomputational and removal proves nothing about resolution'

## One reconciliation, bound to one exact comparison, gates every commit.
has "$CONTRACT" \
  'any change to `Candidate identity` after the latest qualification reconciliation makes that reconciliation stale' \
  'a changed candidate invalidates the previous reconciliation'
has "$CONTRACT" \
  'every commit of the batch, `Progresses` hand-backs included' \
  'the commit condition covers Progresses hand-backs'
has "$CONTRACT" \
  'reconciliation bound to the exact pair of Reviewed anchor and current `Candidate identity`' \
  'the reconciliation binds one exact comparison'
has "$CONTRACT" \
  'non-empty.{0,240}Authority delta.{0,140}covers the actual qualifying set.{0,140}semantic challenge has completed' \
  'a non-empty reconciled set needs a covering Authority delta and a completed challenge'
has "$CONTRACT" \
  'empty.{0,200}no semantic-reader package or semantic challenge is required' \
  'an empty reconciled set needs no package or challenge'
has "$CONTRACT" 'no justification for the empty set is required' \
  'the empty verdict needs no per-correction explanation'
for source in "$WORKFLOW" "${WORKFLOW_MODULES[@]}"; do
  lacks "$source" 'launch one fresh semantic reader|launch a (new|fresh) (semantic )?reader' \
    'the workflow never creates a reader itself, so staleness cannot compose into a second one'
done
has "$CONTRACT" 'one fresh (semantic )?reader per.*batch' \
  'reader lifecycle stays owned by the reference'
echo 'ok - one reconciliation per exact Reviewed-anchor/candidate pair gates every commit'

## Intended semantics come from authority, never from the delegate.s answer.
has "$CONTRACT" \
  'every creation or revision of.{0,160}intended resulting meaning.{0,160}derives from the adjudicated directive and the governing authority at the Reviewed anchor, never from the correction' \
  'intended semantics derive from directive and Reviewed-anchor authority, on creation and revision'
has "$CONTRACT" \
  'determinately requires no semantic change.{0,160}preservation of that unit.s Reviewed-anchor meaning is the intended semantic position' \
  'preservation is the default only where the directive determinately requires no change'
has "$CONTRACT" 'selects nothing where.{0,180}several materially defensible consequences' \
  'the preservation default does not resolve genuine ambiguity by fiat'
lacks "$CONTRACT" 'immutable|mandatory restoration|must be restored' \
  'no immutability or mandatory-restoration rule is introduced'
echo 'ok - intended semantics are derived from authority rather than ratified from the correction'

## Provisional state stays primary-side and the reader package is unchanged.
has "$CONTRACT" \
  'provisional qualification state and reconciliation history.{0,300}never enter the semantic-reader package' \
  'provisional state and reconciliation history stay primary-side working material'
echo 'ok - blindness and the existing reader and Authority-delta concepts are preserved'

## The Authority delta is complete without claiming open-ended site discovery.
for required in \
  'governing proposition or relationship.*location' \
  'governing meaning at the Reviewed anchor' \
  'intended resulting meaning.*including `none`' \
  'constraints expected to survive' \
  'related governing sites considered.*how they were identified'; do
  has "$CONTRACT" "$required" "the Authority delta records $required"
done
has "$CONTRACT" 'open-ended semantic search.*record.*claim(s)? no completeness|open-ended semantic search.*do not claim completeness' \
  'open-ended site discovery is disclosed without a completeness claim'
lacks "$CONTRACT" 'semantic reader.*(prove|establish|verify|ensure).*authority-site completeness' \
  'P1-shaped site completeness never becomes the semantic reader.s duty'
has "$CONTRACT" 'fresh reader is not responsible for proving.*every (governing )?site|site discovery.*primary' \
  'site discovery remains the primary.s responsibility'
site_completeness_pattern='(semantic )?reader.{0,160}(must|shall|required to|is responsible for).{0,160}(all|every|complete(ness)?).{0,160}(authority|governing).{0,80}(site|source)|(must|shall|required to).{0,160}(prove|establish|verify|ensure).{0,160}(authority|governing).{0,80}(site|source).{0,80}(complete(ness)?|all|every)'
for source in "$SKILL" "$WORKFLOW" "${WORKFLOW_MODULES[@]}" "$CONTRACT" "$EVAL"; do
  lacks "$source" "$site_completeness_pattern" \
    'no frozen member makes authority-site completeness the reader.s obligation'
done
echo 'ok - the Authority delta records its bounded semantic model without laundering site completeness'

## The retained implementation owner drafts; one new blind reader challenges.
has "$CONTRACT" \
  'an Authority delta entry exists at dispatch, the retained implementation delegate drafts the correction under it' \
  'the retained implementation owner drafts under an Authority delta that exists at dispatch'
has "$CONTRACT" \
  'first discovered as qualifying during qualification.{0,180}drafted before its Authority delta entry existed' \
  'a newly discovered qualifying unit is not held to an impossible drafting precondition'
has "$CONTRACT" \
  'records that entry from the adjudicated directive and Reviewed-anchor authority before the unit enters the semantic challenge' \
  'a newly discovered unit.s Authority delta entry precedes its semantic challenge'
has "$CONTRACT" 'the `Risks:` channel and authority relationship the corrective dispatch preserves' \
  'the reference defers the retained-delegate Risks channel to the common corrective dispatch'
has "$CONTRACT" 'not asked to (pre-answer|perform).*entitlement' \
  'the implementation owner does not pre-answer the challenge'
has "$CONTRACT" 'one fresh (semantic )?reader per.*batch.*every.*qualifying unit.*one invocation' \
  'one fresh reader handles every qualifying unit in a batch'
has "$CONTRACT" 'new agent each batch|never retained across batches' \
  'reader context is never carried across batches'
lacks "$CONTRACT" 'cross-batch (reader|semantic-reader) (state|memory|ledger|history)' \
  'M4-shaped cross-batch reader state is not introduced'
lacks "$WORKFLOW" \
  'apply `references/normative-remediation.md` to determine whether the Corrective batch contains at least one qualifying unit' \
  'the pre-dispatch pass no longer settles reader entitlement'
has "$WORKFLOW" \
  'before dispatching the accepted blockers.{0,400}`references/normative-remediation.md` to predict provisionally' \
  'the pre-dispatch qualification pass is explicitly provisional'
has "$WORKFLOW" 'identify every predicted unit and record its Authority delta' \
  'the dispatch-time delta still covers every predicted unit'
has "$WORKFLOW" \
  'references/normative-remediation.md.*provisional.*Authority delta.*not ask the delegate to pre-answer the entitlement analysis' \
  'the normative branch prepares only the Authority delta and entitlement boundary'
has "$WORKFLOW" \
  'before committing the exact current candidate, perform qualification reconciliation.{0,300}non-empty, satisfy that reference.s semantic checkpoint for every qualifying unit before commit' \
  'the pre-commit checkpoint is invoked, and gated on the reconciled qualifying set'
has "$WORKFLOW" \
  'set is empty, proceed without a semantic-reader package or semantic challenge' \
  'an empty reconciled set keeps the cheap remediation path'
has "$WORKFLOW" 'never widens into general remediation review' \
  'the normative branch never becomes general remediation review'
for owned in 'recomputational' 'may not use the correction to determine'; do
  lacks "$WORKFLOW" "$owned" \
    'the workflow invokes the reference instead of restating its invariant'
done
has "$WORKFLOW" \
  'Batch all accepted blockers.*retained implementation delegate keeps its `Risks:` channel and authority relationship' \
  'the common corrective dispatch owns the retained-delegate Risks and authority invariant'
cross_batch_state_pattern='(must|shall|required to).{0,120}(retain|reuse|persist|carry|share).{0,120}(semantic )?reader.{0,80}(across|between).{0,40}batch|cross-batch.{0,80}(semantic[- ]reader|reader).{0,80}(state|memory|ledger|history)'
for source in "$SKILL" "$WORKFLOW" "${WORKFLOW_MODULES[@]}" "$CONTRACT" "$EVAL"; do
  lacks "$source" "$cross_batch_state_pattern" \
    'no frozen member introduces cross-batch semantic-reader state'
done
echo 'ok - drafting stays with the retained owner and interpretation goes to one fresh reader per batch'

## Semantic units preserve binding force without expanding to cumulative review.
has "$CONTRACT" 'smallest bounded BEFORE/AFTER.*local structure or placement.*binding force' \
  'the semantic unit preserves the proposition and its local binding structure'
for treatment in \
  'ordinary rule.*paragraph or block' \
  'table.*row or cell.*headers.*legend' \
  'ordered authority list.*entry.*order.*precedence' \
  'status banner.*document title.*status context' \
  'relocation.*source and destination' \
  'deletion.*no adjacent proposition absorbed the obligation' \
  'coupled propositions.*smallest coupled set'; do
  has "$CONTRACT" "$treatment" "the semantic-unit rules settle $treatment"
done
has "$CONTRACT" 'structural edit.*(does not|never).*whole section or document' \
  'structure alone does not widen the unit to a whole authority source'
echo 'ok - semantic units are the smallest bounded representations that preserve binding force'

## Package and withhold sets keep interpretation blind.
for supplied in \
  'BEFORE text' \
  'proposed AFTER text|bounded normative diff' \
  'file and section identity' \
  'bounded raw governing-authority context' \
  'objective authority relationship' \
  'concrete passages forming the task boundary'; do
  has "$CONTRACT" "$supplied" "the reader package supplies $supplied"
done
for withheld in \
  'expected BEFORE.*AFTER semantics.*including `none`' \
  'preserved-invariant claims' \
  'remediation rationale' \
  'accepted finding.*adjudication' \
  'prior reviewer findings.*dispositions' \
  'related-sites list.*assertion of completeness'; do
  has "$CONTRACT" "withheld until after interpretation.*$withheld|$withheld.*withheld until after interpretation" \
    "the reader is blind to $withheld until interpretation completes"
done
has "$CONTRACT" 'does not receive.*full candidate diff.*cumulative review package.*full trusted contract.*Validation-surface manifest.*validation execution.*subdelegation' \
  'the semantic-only package excludes review, contract, validation, and delegation payloads'
echo 'ok - the bounded package supplies raw authority while withholding anchored conclusions'

## The reader derives governing consequences and reports only material deltas.
has "$CONTRACT" 'independently derives BEFORE and AFTER.*permitted.*required.*prohibited.*scope.*precedence.*authority relationship' \
  'the reader derives both sides of the full governing consequence'
has "$CONTRACT" 'draft.s own characterization.*not.*proof|does not treat.*characterization.*proof' \
  'self-description is authority text to analyze rather than proof'
has "$CONTRACT" 'permitted.*required.*prohibited.*where an obligation( or prohibition)? applies.*which exception.*precedence.*governing authority.*binding.*advisory.*historical.*superseded' \
  'materiality enumerates the settled governing consequences'
has "$CONTRACT" 'Otherwise (return )?`NO_MATERIAL_SEMANTIC_DELTA`' \
  'non-material differences receive the settled verdict'
has "$CONTRACT" 'style, tone, (prose )?elegance, emphasis, readability.*not reported' \
  'non-consequential prose qualities are excluded'
has "$CONTRACT" 'ambiguity is material only when.*plausible readings.*different governing consequences' \
  'ambiguity is material only at a concrete consequence split'
has "$CONTRACT" 'No output-count cap' \
  'material reporting has no count cap'
echo 'ok - independent interpretation uses the concrete governing-consequence materiality rule'

## Context supplementation fails closed without ratcheting to cumulative input.
has "$CONTRACT" '`INSUFFICIENT_CONTEXT`.*specific unresolved semantic dimension.*minimum concrete governing context' \
  'an inadequate package produces a finite named context request'
has "$CONTRACT" 'primary supplies.*or declines.*decline reaches.*availability.*never.*judgment' \
  'a declined supplement preserves blindness'
has "$CONTRACT" 'same fresh reader.*still blind' \
  'finite supplementation returns to the same reader'
has "$CONTRACT" 'still cannot safely derive|cannot complete.*challenge is unresolved' \
  'a reader that remains unable to interpret leaves the challenge unresolved'
has "$CONTRACT" 'open-ended discovery|cannot be reduced to finite named context' \
  'open-ended supplementation is an unresolved under-slice'
has "$CONTRACT" 'unresolved.*correction is not committed as though.*(satisfied|passed).*escalation.*`Progresses`.*`failed`' \
  'an unresolved challenge takes the settled non-success route before commit'
has "$CONTRACT" 'No numeric supplementation limit' \
  'supplementation is bounded semantically rather than by an arbitrary count'
has "$CONTRACT" 'never ratchets toward the full trusted contract' \
  'supplementation cannot become cumulative contract disclosure'
echo 'ok - insufficient context is concrete, blind, and fail-closed'

## Reconciliation is a blocking pre-commit checkpoint, not review lifecycle.
has "$WORKFLOW" 'normative-remediation.md' \
  'the remediation sequence invokes the normative-remediation authority'
has "$WORKFLOW" 'before.*commit.*candidate.*next.*delta gate' \
  'the workflow places the challenge before the next delta candidate commit'
has "$SKILL" 'blocking checkpoint.*before.*committed.*candidate.*next.*delta gate' \
  'custom workflows remain bound to the pre-candidate checkpoint'
has "$CONTRACT" \
  'only after interpretation.*compare.*expected.*derived|compare.*expected.*derived.*only after interpretation' \
  'the primary compares expected and derived meaning only after interpretation'
has "$CONTRACT" \
  'reconcile every material semantic mismatch.*delegate revises before\s*commit' \
  'material mismatches return to the implementation owner before commit'
has "$CONTRACT" 'cannot state.*semantic change.*does not dispatch exact wording' \
  'exact wording cannot substitute for the primary.s understanding'
has "$CONTRACT" \
  'complete the slice, open a follow-up Issue and flag it at closeout, or escalate genuine maintainer wording judgment' \
  'the existing deferral route is unchanged'
has "$CONTRACT" 'named acceptance criterion.*false or unverifiable.*`Progresses` or `failed`' \
  'required contract work cannot be deferred to a silent follow-up'
has "$WORKFLOW" 'unresolved challenge.*not committed.*escalation.*`Progresses`.*`failed`' \
  'the default workflow preserves unresolved-challenge nondeferral'
has "$CONTRACT" 'second (semantic )?reader.*only.*unresolved material ambiguity.*never routine' \
  'a second reader is escalation rather than fan-out'
has "$CONTRACT" 'blocking pre-commit' \
  'the semantic challenge is a blocking pre-commit checkpoint'
has "$CONTRACT" 'no `review-state-machine.md` gate.*no Reviewed anchor.*no durable lifecycle state' \
  'the checkpoint does not become review-chain or lifecycle state'
echo 'ok - reconciliation blocks candidate commit without becoming a review gate'

## Existing assurance systems remain independent of the challenge.
has "$CONTRACT" 'no change to.*#103.*#104/#122.*#105' \
  'the manifest, evidence, and review-chain decisions remain unchanged'
has "$CONTRACT" 'never reuse.*review-axis agent' \
  'the semantic reader is never reused in a review lane'
has "$CONTRACT" 'existence and output never enter.*cumulative or delta package' \
  'the semantic reader is fenced from the review chain'
for protected in "$STATE" "$CLOSABILITY" "$EVIDENCE"; do
  lacks "$protected" 'Authority delta|Pre-candidate semantic challenge|normative-remediation' \
    'the mechanism does not enter protected authority'
done
echo 'ok - the semantic challenge does not modify review, manifest, or evidence authority'

## Domain language is named without turning sequencing prose into a term.
has "$GLOSSARY" '^\*\*Authority delta\*\*:' \
  'the glossary defines Authority delta'
has "$GLOSSARY" '^\*\*Pre-candidate semantic challenge\*\*:' \
  'the glossary defines Pre-candidate semantic challenge'
lacks "$GLOSSARY" '^\*\*Before the normative correction is committed' \
  'the sequencing boundary is ordinary prose rather than a glossary headword'
lacks "$GLOSSARY" '\*\*Authority delta\*\*:.{0,140}pre-dispatch' \
  'the Authority delta is no longer defined by dispatch sequencing'
has "$GLOSSARY" \
  '\*\*Authority delta\*\*:.{0,400}adjudicated directive and the authority at the \*\*Reviewed anchor\*\*, never from the correction' \
  'the Authority delta carries the derivation-source guarantee instead'
lacks "$GLOSSARY" '\*\*Authority delta\*\*:.{0,500}independently derived' \
  'the Authority delta avoids colliding with the Independent judgment and execution headwords'
echo 'ok - the two mechanism names have normal glossary treatment'

## The static and behavioral instruments stay distinct from issue 102.
contract_scenario_pattern='controlled[[:space:]]+policy[[:space:]]+scenario'
lacks "$CONTRACT" "$contract_scenario_pattern" \
  'the normative contract does not absorb the controlled scenario'
scenario_pattern="frozen[[:space:]]+pilot[[:space:]]+provenance|end-to-end[[:space:]]+enforcement[[:space:]]+(under|against)|mechanism-specific[[:space:]]+success[[:space:]]+(rule|threshold)|protocol[[:space:]]+revision[[:space:]]+2"
for instrument in "$CONTRACT" "$EVAL" "$STATIC"; do
  lacks "$instrument" "$scenario_pattern" \
    'the normative-remediation instruments do not duplicate issue 102.s scenario'
done

## The eval identity and Primary oracles cover their complete frozen inputs.
has "$EVAL" '### Canonical byte recipe' \
  'the eval defines one canonical byte recipe'
has "$EVAL" 'measured-instruction hash.*per-case instrument-input hash' \
  'the eval names both identities governed by the canonical recipe'
has "$EVAL" 'sha256sum "\$stream"' \
  'the measured-instruction identity has an exact SHA-256 command'
has "$EVAL" 'canonical_hash.*case_id.bytes' \
  'the per-case identity has an exact SHA-256 command'
for case_name in 'P1-e11-h1-none-trigger' 'P2-k1-m1-obligation-weakening'; do
  case_section="$fixture_dir/$case_name"
  extract_section "$EVAL" "### \`$case_name\`" "$case_section"
  has "$case_section" \
    'governing proposition or relationship.*location.*current governing meaning.*intended resulting meaning.*constraints expected to survive.*related governing sites considered.*how they were identified.*no completeness' \
    "$case_name requires the complete Authority delta and bounded site treatment"
  has "$case_section" \
    'only after interpretation.*compare.*retained implementation delegate.*revis(e|es).*fresh.*challenge.*before commit' \
    "$case_name requires compare, delegate revision, and rechallenge before commit"
done

if (( failures > 0 )); then
  printf '\n%s normative-remediation assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll normative-remediation contract assertions held.\n'
