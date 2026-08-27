#!/usr/bin/env bash
set -euo pipefail

# Validation-evidence reuse is instruction behavior: fresh reviewers receive
# raw evidence and independently adjudicate it at the workflow boundary. These
# assertions pin that public contract rather than any private storage helper.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

POLICY="$skill_dir/references/validation-evidence.md"
SKILL="$skill_dir/SKILL.md"
WORKFLOW="$skill_dir/references/default-workflow.md"
CLOSEOUT="$skill_dir/references/github-closeout.md"

failures=0
flat_dir="$(mktemp -d)"
# Fixtures live outside flat_dir so flatten() rewrites them like any other
# source instead of finding flat == source and skipping the rewrite.
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$flat_dir" "$fixture_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

flatten() {
  local source="$1" flat="$flat_dir/$(basename "$1")"
  if [[ ! -f "$source" ]]; then
    : >"$flat"
  elif [[ ! -f "$flat" ]]; then
    awk '
      /^[[:space:]]*$/ { print buf; buf = ""; next }
      { buf = (buf == "" ? $0 : buf " " $0) }
      END { print buf }
    ' "$source" | tr -s ' ' >"$flat"
  fi
  printf '%s' "$flat"
}

requires_contract() {
  local source="$1" description="$2"
  shift 2
  local pattern
  for pattern in "$@"; do
    if ! grep -Eqi -- "$pattern" "$(flatten "$source")"; then
      fail "$description (missing in ${source#"$skill_dir/"}: $pattern)"
      return
    fi
  done
}

forbids_contract() {
  local source="$1" description="$2"
  shift 2
  local pattern status
  for pattern in "$@"; do
    status=0
    grep -Eqi -- "$pattern" "$(flatten "$source")" || status=$?
    if (( status == 0 )); then
      fail "$description (unexpected in ${source#"$skill_dir/"}: $pattern)"
      return
    elif (( status > 1 )); then
      fail "every forbidden pattern compiles here (unusable pattern: $pattern)"
      return
    fi
  done
}

requires_contract "$POLICY" \
  'an unchanged candidate can reuse qualifying raw evidence under fresh judgment' \
  'Candidate identity.*exact repository.*candidate-controlled content' \
  'Validation identity.*exact command.*arguments.*working directory.*check-defining inputs' \
  'Reusable-evidence identity.*Candidate identity.*Validation identity.*environment.*toolchain.*external-input.*artifact' \
  'recoverable source provenance.*execution status.*inspectable raw (output|result artifact)' \
  'fresh Independent judgment.*without inheriting.*conclusions.*adjudications.*dispositions'
echo 'ok - qualifying raw evidence supports fresh judgment for one exact identity'

requires_contract "$POLICY" \
  'only exact unchanged candidate content and qualifying inputs preserve reuse' \
  'conservative exact-candidate rule' \
  'uncommitted state.*content identity.*deterministically captured.*proven identical.*reviewed candidate' \
  'changes to code.*tests.*fixtures.*configuration.*dependency locks.*validation definitions.*generated artifacts.*external inputs.*environment.*toolchain.*invalidate' \
  'irrelevance is not mechanically clear.*affected validation'
echo 'ok - exact content qualifies reuse and relevant identity changes invalidate it'

requires_contract "$POLICY" \
  'unsettled assurance questions trigger the narrowest Independent execution' \
  'Independent execution is required when.*cannot settle a concrete assurance question' \
  'timing.*concurrency.*nondeterminism.*environment.*host.*uncertain identity.*provenance.*suspect evidence.*discriminating reproduction' \
  'inspect.*raw evidence.*static.*inspection.*cheapest.*targeted.*broader' \
  'smallest reproduction.*not.*full-suite rerun' \
  'For confidence.*to be safe.*do not justify another execution'
echo 'ok - concrete uncertainty escalates through the narrowest Independent execution'

requires_contract "$POLICY" \
  'unchanged evidence crosses stages while failures and inadequate evidence block' \
  'later workflow stage.*does not.*stale' \
  'final closeout.*complete Reusable-evidence identity.*unchanged' \
  'final blind confirmation.*exact clean.*candidate.*complete direct evidence' \
  'failing.*stale.*contradictory.*incomplete.*inadequate.*blocking' \
  'rerun-until-green.*adjudicat' \
  'hard-rule violation.*blocking.*does not.*require.*another execution'
echo 'ok - cross-stage reuse preserves final confirmation and hard blocking failures'

requires_contract "$POLICY" \
  'sensitive evidence stays safe and reuse reasoning stays in ordinary reports' \
  'never persist.*credential.*secret values' \
  'privacy.*redaction.*retention.*access-control' \
  'safe (identifier|identity|hash)|opaque.*hash' \
  'safe provenance locator.*access-controlled source evidence' \
  'unsafe or unrecoverable.*non-reusable.*safe qualifying evidence' \
  'ordinary reviewer report.*Reusable-evidence identity.*provenance locator.*Independent.*judgment' \
  'execution claimed as necessary for Independent assurance.*assurance question.*insufficient.*narrowest adequate' \
  'Do not copy raw (output|evidence).*Run telemetry sink.*another.*subsystem'
echo 'ok - privacy constraints govern reuse and reports carry only safe reasoning'

requires_contract "$SKILL" \
  'every selected workflow applies the validation-evidence policy' \
  'references/validation-evidence.md.*implementation.*readiness.*Standards.*Spec.*closure.*primary'
requires_contract "$WORKFLOW" \
  'the public delegate and reviewer briefs receive qualifying evidence and policy' \
  'Validation evidence:.*qualifying raw evidence.*validation-evidence.md' \
  'readiness.*Standards.*Spec.*closure.*qualifying raw validation evidence.*validation-evidence.md'
requires_contract "$CLOSEOUT" \
  'the closure gate adjudicates evidence under the reuse policy' \
  'validation-evidence.md.*reuse.*Independent execution'
echo 'ok - implementation, every reviewer stage, primary, and closeout receive the policy'

requires_contract "$POLICY" \
  'evidence reuse composes with the frozen direct-evidence population' \
  'frozen Validation-surface manifest remains the complete population of direct evidence' \
  'this policy decides whether qualifying evidence.*must be executed again'
requires_contract "$WORKFLOW" \
  'both primary focused-check sites and closeout follow candidate/check identity' \
  'Inspect the worktree and, unless qualifying evidence for the exact current Candidate and Validation identity already settles their assurance question, run affected focused checks' \
  'Run affected focused checks under the same Candidate and Validation identity rule, applying .references/validation-evidence.md' \
  'At Closeout, reuse qualifying full-regression evidence for the exact final Candidate and Validation identity.*otherwise execute the full regression there' \
  'Never pre-produce it earlier to be reused'
forbids_contract "$CLOSEOUT" \
  'closure does not automatically rerun checks for generic risk confidence' \
  'Rerun the highest-risk checks yourself'
forbids_contract "$POLICY" \
  'the policy does not absorb excluded workflow or evidence machinery' \
  'delta remediation|Convergence guard|readiness removal|reviewer fan-out|dependency analysis|provider analytics|evidence telemetry|pilot bookkeeping|Moraine'
echo 'ok - frozen surfaces compose with reuse and closeout avoids automatic duplication'

requires_contract "$POLICY" \
  'producer role cannot substitute for identity or required Independent execution' \
  'validity depends on identity and provenance, not producer role' \
  'documented contract or hard rule.*requires re-execution.*cannot otherwise be resolved' \
  'assurance question itself requires an Independent context.*implementation-context execution does not satisfy it.*fresh Independent review context'
echo 'ok - identity governs reuse and explicit reproduction contracts still execute'

# Need determines required execution; cost only suppresses unnecessary
# materially costly repetition. The guardrail is unreachable until sufficiency
# is settled, so misclassifying cost wastes effort but never skips assurance.
requires_contract "$POLICY" \
  'assurance sufficiency alone decides whether another execution is required' \
  'Assurance sufficiency alone determines whether another execution is required' \
  'settles the concrete assurance question, another execution is not required' \
  'When it does not, execute the narrowest check that settles it' \
  'workflow-stage transition is never itself a reason to execute again'
echo 'ok - sufficiency alone requires execution and stage transitions never do'

requires_contract "$POLICY" \
  'commands are vehicles while independently meaningful observations are the sufficiency unit' \
  'command is a vehicle, not the unit of sufficiency' \
  'one execution produces several independently meaningful observations.*identity and sufficiency rules.*observation level' \
  'narrowest documented invocation set.*owed members.*qualifying evidence is absent or invalid.*exact current Candidate identity' \
  'Documented.*repository.s own authority.*agent-facing docs.*test-runner interface.*manifest.s.*named validation action' \
  'never infer.*discover.*construct.*addressing scheme'
echo 'ok - sufficiency is evaluated at independently meaningful observations'

requires_contract "$POLICY" \
  'observation-level reuse fails conservative unless the affected set is positively established' \
  'Narrow reuse is permitted only when.*positively establish.*candidate change.*validation definitions.*repository authority.*remain qualifying.*invalidated' \
  'cannot be established with sufficient confidence.*does not guess.*invent.*dependency mapping.*broader adequate check' \
  'fail conservative.*waste execution.*never fail aggressive.*required evidence.*unexecuted'
echo 'ok - narrow reuse requires a positively established affected set'

requires_contract "$POLICY" \
  'the broad vehicle is assurance-required in all four fallback conditions' \
  'broad vehicle is assurance-required.*no adequate narrower addressing' \
  'narrower invocations cannot cover every owed unqualified member' \
  'cannot establish which owed members remain qualifying.*invalidated' \
  'distinct assurance question.*documented hard rule.*exact command.*requires.*broad execution' \
  'assurance sufficiency alone determines what execution is required.*cost is considered only afterward'
forbids_contract "$POLICY" \
  'cost cannot relabel the broad vehicle as the narrowest adequate check' \
  'broad vehicle is (the )?narrowest adequate check[^.]{0,160}(cost|cheap|cheaper|materially)' \
  '(cost|cheap|cheaper|materially)[^.]{0,160}makes the broad vehicle (the )?narrowest adequate check'
echo 'ok - assurance requires the broad fallback before cost is considered'

requires_contract "$POLICY" \
  'the cost guardrail is an efficiency directive reachable only after sufficiency' \
  'Only after sufficiency is established.*do not repeat materially costly deterministic validation already covered by qualifying evidence that settles the current assurance question' \
  'Materially costly means repeating the validation would meaningfully add workflow latency or consume a scarce resource' \
  'never consult or build a duration threshold, timing history, telemetry-based classification, cost database, or persistent resource metadata' \
  'efficiency directive, not an assurance invariant' \
  'never a reason to skip an execution sufficiency requires' \
  'Trivially cheap checks stay at reviewer discretion' \
  'Do not move or pre-produce validation merely to create reusable evidence' \
  'discretionary cheap check owes no justification record'
# Cost may describe waste; it may never decide whether validation runs. These
# shapes are forbidden on every governing instruction surface, not only the
# policy, so a cost predicate cannot re-enter through a neighbouring file.
cost_predicates=(
  'expensive deterministic|additional expensive execution|expensive duplicate'
  '(materially costly|expensive|costly)[^.]{0,120}(is the default|at most one|once per)'
  '(one|a single) qualifying execution[^.]{0,120}default'
  '(materially costly|expensive|costly|slow)[^.]{0,100}(skip|omit|forgo|bypass|waive)'
  '(skip|omit|forgo|bypass|waive)[^.]{0,100}(materially costly|expensive|costly|slow)'
  '(classify|decide|determine)[^.]{0,80}(recorded|prior|measured|telemetry)'
  '(duration|telemetry)[^.]{0,60}(decides whether|determines whether|classifies)'
  '(recorded|prior|measured) (duration|runtime|run time)[^.]{0,60}(decid|determin|classif)'
  '(over|under|exceeds|exceeding|more than|less than|longer than) (a|an|one|[0-9]+) (minute|minutes|second|seconds|ms|millisecond)'
  'use (a |the )?duration threshold[^.]{0,120}(decid|select|determin)[^.]{0,80}(validation|vehicle|runs?)'
  'consult[^.]{0,80}(timing|history)[^.]{0,80}(prior|previous|earlier) executions[^.]{0,80}(decid|select|determin)[^.]{0,80}(validation|vehicle)'
  '(build|consult) (a |the )?cost database[^.]{0,100}(decid|select|determin)[^.]{0,80}(validation|vehicle)'
)

# The surfaces that can impose, override, or contradict re-execution. Telemetry
# and the registry are excluded on their own terms — each records the run and
# never decides what it does — and they are where sanctioned duration
# measurement legitimately lives.
governing_surfaces=(
  "$SKILL"
  "$POLICY"
  "$WORKFLOW"
  "$CLOSEOUT"
  "$skill_dir/references/closability-gate.md"
)
for surface in "${governing_surfaces[@]}"; do
  if [[ ! -f "$surface" ]]; then
    fail "every governing surface is present to guard (missing: ${surface#"$skill_dir/"})"
    continue
  fi
  forbids_contract "$surface" \
    'no runtime predicate decides validation from cost, duration, or telemetry' \
    "${cost_predicates[@]}"
done

# Observational duration legitimately exists in telemetry and in the rendered
# closeout. What may not exist is an executable decision keyed to it.
script_cost_predicates=(
  'expensive'
  'materially costly'
  'materially_costly'
  '(skip|reuse|rerun|classify).{0,80}(duration|elapsed|timing|telemetry)'
  '(duration|elapsed|timing|telemetry).{0,80}(skip|reuse|rerun|classify)'
)
for candidate_script in "$skill_dir"/scripts/*.sh; do
  case "$(basename "$candidate_script")" in test-*) continue ;; esac
  for pattern in "${script_cost_predicates[@]}"; do
    if grep -Eqi -- "$pattern" "$candidate_script"; then
      fail "no work-on script decides validation from cost or duration (${candidate_script##*/}: $pattern)"
    fi
  done
done

# The guard has teeth only if the rule #122 rejects actually trips it: skipping
# unresolved required validation because prior telemetry called it costly.
counterfactual="$fixture_dir/rejected-cost-rule.md"
cat >"$counterfactual" <<'REJECTED'
## Cost exemption

When a validation is materially costly, skip it and accept the existing
evidence, even when the assurance question is unresolved. Classify each
validation as cheap or materially costly from its recorded prior run duration
in the run telemetry sink before deciding.
REJECTED
counterfactual_caught=0
for pattern in "${cost_predicates[@]}"; do
  if grep -Eqi -- "$pattern" "$(flatten "$counterfactual")"; then
    counterfactual_caught=1
  fi
done
if (( counterfactual_caught == 0 )); then
  fail 'the forbidden-predicate patterns catch a telemetry-driven skip rule'
fi

# The positive prohibition must not mask a later competing rule that makes
# duration, prior-run history, or a cost database select the validation vehicle.
duration_threshold_rule="$fixture_dir/rejected-duration-threshold-rule.md"
cat >"$duration_threshold_rule" <<'REJECTED'
Never consult or build a duration threshold, timing history, or cost database.
Use a duration threshold to select whether the suite vehicle or targeted
validation runs.
REJECTED
timing_history_rule="$fixture_dir/rejected-timing-history-rule.md"
cat >"$timing_history_rule" <<'REJECTED'
Never consult or build a duration threshold, timing history, or cost database.
Consult the timing history of prior executions to select the validation vehicle.
REJECTED
cost_database_rule="$fixture_dir/rejected-cost-database-rule.md"
cat >"$cost_database_rule" <<'REJECTED'
Never consult or build a duration threshold, timing history, or cost database.
Build a cost database to select the validation vehicle.
REJECTED

selection_counterfactuals=(
  "$duration_threshold_rule:duration-threshold selection"
  "$timing_history_rule:prior-execution timing selection"
  "$cost_database_rule:cost-database selection"
)
for entry in "${selection_counterfactuals[@]}"; do
  fixture="${entry%%:*}"
  description="${entry#*:}"
  fixture_caught=0
  for pattern in "${cost_predicates[@]}"; do
    if grep -Eqi -- "$pattern" "$(flatten "$fixture")"; then
      fixture_caught=1
    fi
  done
  if (( fixture_caught == 0 )); then
    fail "the forbidden-predicate patterns catch $description rules"
  fi
done

# The guardrail is reachable only after sufficiency, and clause order is the
# whole mitigation for reading it as licence to skip a required execution. A
# cost rule that migrates above the sufficiency rule must fail here.
required_at="$(grep -n '^## Required execution$' "$POLICY" | cut -d: -f1)"
guardrail_at="$(grep -n '^## Repetition guardrail$' "$POLICY" | cut -d: -f1)"
if [[ -z "$required_at" || -z "$guardrail_at" ]]; then
  fail 'the policy states required execution and the repetition guardrail as sections'
elif (( required_at >= guardrail_at )); then
  fail 'sufficiency is settled before the repetition guardrail becomes reachable'
fi
echo 'ok - cost suppresses repetition without becoming a correctness predicate'

if (( failures > 0 )); then
  printf '\n%s validation-evidence contract assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll validation-evidence contract assertions held.\n'
