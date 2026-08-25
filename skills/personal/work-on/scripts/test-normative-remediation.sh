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
STATE="$skill_dir/references/review-state-machine.md"
CLOSABILITY="$skill_dir/references/closability-gate.md"
EVIDENCE="$skill_dir/references/validation-evidence.md"
TELEMETRY="$skill_dir/references/run-telemetry.md"
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
  if grep -Eqi -- "$2" "$1"; then
    fail "$3 (unexpected in ${1#"$skill_dir/"}: $2)"
  fi
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

## The Authority delta is complete without claiming open-ended site discovery.
for required in \
  'governing proposition or relationship.*location' \
  'current governing meaning' \
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
echo 'ok - the Authority delta records its bounded semantic model without laundering site completeness'

## The retained implementation owner drafts; one new blind reader challenges.
has "$CONTRACT" 'retained implementation delegate.*drafts.*Authority delta' \
  'the retained implementation owner drafts under the Authority delta'
has "$CONTRACT" 'retains.*`Risks:`.*authority relationship' \
  'the implementation owner retains its Risks channel and authority relationship'
has "$CONTRACT" 'not asked to (pre-answer|perform).*entitlement' \
  'the implementation owner does not pre-answer the challenge'
has "$CONTRACT" 'one fresh (semantic )?reader per.*batch.*every.*qualifying unit.*one invocation' \
  'one fresh reader handles every qualifying unit in a batch'
has "$CONTRACT" 'new agent each batch|never retained across batches' \
  'reader context is never carried across batches'
lacks "$CONTRACT" 'cross-batch (reader|semantic-reader) (state|memory|ledger|history)' \
  'M4-shaped cross-batch reader state is not introduced'
has "$WORKFLOW" \
  'if the batch contains at least one qualifying unit, launch one fresh semantic reader.*handling every qualifying unit in one invocation' \
  'reader launch is conditional on a qualifying batch and covers all its units'
has "$WORKFLOW" \
  'no qualifying unit.*without an Authority delta, semantic-reader package, or semantic challenge.*never widens into general remediation review' \
  'a non-qualifying batch proceeds without an empty challenge or general review'
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
has "$CONTRACT" \
  'only after interpretation.*compare.*expected.*derived|compare.*expected.*derived.*only after interpretation' \
  'the primary compares expected and derived meaning only after interpretation'
has "$CONTRACT" \
  'reconcile.*material mismatch.*delegate revises.*before commit|material mismatch.*reconcile.*delegate revises.*before commit' \
  'material mismatches return to the implementation owner before commit'
has "$CONTRACT" 'cannot state.*semantic change.*does not dispatch exact wording' \
  'exact wording cannot substitute for the primary.s understanding'
has "$CONTRACT" 'named acceptance criterion.*false or unverifiable.*`Progresses` or `failed`' \
  'required contract work cannot be deferred to a silent follow-up'
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
has "$CONTRACT" 'No telemetry schema change|no new telemetry kind' \
  'the mechanism introduces no telemetry semantics'
for protected in "$STATE" "$CLOSABILITY" "$EVIDENCE" "$TELEMETRY"; do
  lacks "$protected" 'Authority delta|Pre-candidate semantic challenge|normative-remediation' \
    'the mechanism does not enter protected authority'
done
echo 'ok - the semantic challenge does not modify review, manifest, evidence, or telemetry authority'

## Domain language is named without turning sequencing prose into a term.
has "$GLOSSARY" '^\*\*Authority delta\*\*:' \
  'the glossary defines Authority delta'
has "$GLOSSARY" '^\*\*Pre-candidate semantic challenge\*\*:' \
  'the glossary defines Pre-candidate semantic challenge'
lacks "$GLOSSARY" '^\*\*Before the normative correction is committed' \
  'the sequencing boundary is ordinary prose rather than a glossary headword'
echo 'ok - the two mechanism names have normal glossary treatment'

## This mechanism stays distinct from the controlled policy scenario.
lacks "$CONTRACT" 'controlled policy scenario|frozen pilot provenance|protocol revision 2' \
  'the normative-remediation contract does not absorb issue 102.s controlled scenario'

if (( failures > 0 )); then
  printf '\n%s normative-remediation assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll normative-remediation contract assertions held.\n'
