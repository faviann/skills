#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"
repo_dir="$(cd "$skill_dir/../../.." && pwd)"

skill="$skill_dir/SKILL.md"
workflow="$skill_dir/references/default-workflow.md"
policy="$skill_dir/references/validation-evidence.md"
gate="$skill_dir/references/closability-gate.md"
eval_file="$repo_dir/.agents/evals/work-on-evidence-phase-ownership.md"
failures=0
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

require_text() {
  local file="$1" label="$2" pattern="$3"
  if ! tr '\n' ' ' <"$file" | grep -Eqi -- "$pattern"; then
    printf 'not ok - %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

forbid_text() {
  local file="$1" label="$2" text="$3"
  if grep -Fq -- "$text" "$file"; then
    printf 'not ok - %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

eval_contract_accepts() {
  local file="$1" content
  content="$(tr '\n' ' ' <"$file")"
  grep -Eqi -- \
    'must load.*all four exact measured candidate instruction files' \
    <<<"$content" \
    && grep -Eqi -- \
      'MEASURED AUTHORITY:.*candidate-derived' <<<"$content" \
    && grep -Eqi -- \
      'STATUS:.*SCHEDULE.*CONTRACT_GAP' <<<"$content" \
    && grep -Eqi -- \
      'absent or contradictory.*CONTRACT_GAP' <<<"$content" \
    && grep -Eqi -- \
      'scenario facts alone.*cannot.*scor' <<<"$content" \
    && ! grep -Eqi -- \
      '(may|can) (skip|omit).*measured candidate instruction|scenario facts.*without loading' \
      <<<"$content"
}

bundle_accepts() {
  local bundle="$1" content
  content="$(tr '\n' ' ' <"$bundle/SKILL.md")"
  if ! grep -Eqi -- \
    '6\..*Done when.*every definitely owed.*obligation.*deterministically resolved.*owning phase' \
    <<<"$content"; then
    return 1
  fi
  if grep -Eqi -- \
    '6\..*Done when.*delegation may proceed.*(unresolved|unknown).*owning phase' \
    <<<"$content"; then
    return 1
  fi
  content="$(tr '\n' ' ' <"$bundle/default-workflow.md")"
  if grep -Eqi -- \
    '(Every|All) required command.*(executes|runs) during Implementation.*owning phase.*Closeout' \
    <<<"$content"; then
    return 1
  fi
  if grep -Eqi -- \
    'Required commands:.*(baseline|full regression).*Completion:.*run (every|all).*required command' \
    <<<"$content"; then
    return 1
  fi
  content="$(tr '\n' ' ' <"$bundle/SKILL.md")"
  if grep -Eqi -- \
    'Manifest.*acceptance-evidence.*(execute|run).*Implementation.*(regardless|despite).*selected-workflow' \
    <<<"$content"; then
    return 1
  fi
  content="$(tr '\n' ' ' <"$bundle/closability-gate.md")"
  if grep -Eqi -- \
    'unresolved owning phase (defaults|is assigned) to (Implementation|Closeout|Review|Planning|Preflight|Verification)' \
    <<<"$content"; then
    return 1
  fi
  content="$(tr '\n' ' ' <"$bundle/validation-evidence.md")"
  if grep -Eqi -- \
    'Candidate and Validation identities (determine|choose|select|set) the execution phase' \
    <<<"$content"; then
    return 1
  fi
  return 0
}

prepare_bundle() {
  local label="$1" test_bundle
  test_bundle="$fixture_dir/$label"
  mkdir -p "$test_bundle"
  cp "$skill" "$test_bundle/SKILL.md"
  cp "$workflow" "$test_bundle/default-workflow.md"
  cp "$policy" "$test_bundle/validation-evidence.md"
  cp "$gate" "$test_bundle/closability-gate.md"
  printf '%s' "$test_bundle"
}

assert_rejected() {
  local label="$1" target="$2" contradiction="$3" test_bundle
  test_bundle="$(prepare_bundle "$label")"
  printf '\n%s\n' "$contradiction" >>"$test_bundle/$target"
  if bundle_accepts "$test_bundle"; then
    printf 'not ok - %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

assert_rejected later-phase-command-override default-workflow.md \
  'Every required command executes during Implementation, including commands whose owning phase is Closeout.'
assert_rejected manifest-overrides-workflow SKILL.md \
  'Manifest and acceptance-evidence obligations execute during Implementation regardless of selected-workflow ownership.'
assert_rejected unresolved-phase-default closability-gate.md \
  'An unresolved owning phase defaults to Implementation.'
assert_rejected evidence-identity-schedules validation-evidence.md \
  'Candidate and Validation identities determine the execution phase.'
assert_rejected flat-required-command-list default-workflow.md \
  'Required commands: focused check and repository baseline. Completion: run every required command, then stop.'

missing_step_six_bundle="$(prepare_bundle missing-step-six-phase-completion)"
sed -i \
  '/materialized as a finite frozen Validation surface, and every definitely owed/{N;s/, and every definitely owed\n   obligation has a deterministically resolved owning phase//;}' \
  "$missing_step_six_bundle/SKILL.md"
if bundle_accepts "$missing_step_six_bundle"; then
  printf 'not ok - Step 6 omission of exhaustive phase resolution is rejected\n' >&2
  failures=$((failures + 1))
fi

contradictory_step_six_bundle="$(prepare_bundle contradictory-step-six-completion)"
sed -i \
  '/materialized as a finite frozen Validation surface, and every definitely owed/{N;s/materialized as a finite frozen Validation surface, and every definitely owed\n   obligation has a deterministically resolved owning phase/materialized as a finite frozen Validation surface; delegation may proceed with an unresolved owning phase/;}' \
  "$contradictory_step_six_bundle/SKILL.md"
if bundle_accepts "$contradictory_step_six_bundle"; then
  printf 'not ok - contradictory Step 6 completion is rejected\n' >&2
  failures=$((failures + 1))
fi

compliant_step_six_bundle="$(prepare_bundle compliant-step-six-completion)"
if ! bundle_accepts "$compliant_step_six_bundle"; then
  printf 'not ok - compliant Step 6 phase-resolution completion is accepted\n' >&2
  failures=$((failures + 1))
fi

visible_bundle="$(prepare_bundle visible-deferred)"
printf '\nThe Closeout-owned baseline remains visible and deferred after Implementation.\n' \
  >>"$visible_bundle/default-workflow.md"
if ! bundle_accepts "$visible_bundle"; then
  printf 'not ok - visible deferred obligation remains accepted\n' >&2
  failures=$((failures + 1))
fi

require_text "$skill" 'evidence authorities own what while workflow owns when' \
  'manifest.*acceptance-evidence.*what.*owed.*selected workflow.*when.*executed'
require_text "$skill" 'later-phase evidence cannot be pulled forward' \
  'cannot.*earlier phase.*implementation-completion prerequisite'
require_text "$skill" 'Step 6 completion exhausts owed phase resolution' \
  '6\..*Done when.*every definitely owed.*obligation.*deterministically resolved.*owning phase'

require_text "$gate" 'preflight resolves every owed obligation phase' \
  'every definitely owed.*command.*evidence obligation.*owning phase.*selected workflow'
require_text "$gate" 'unresolved ownership aborts without a default' \
  'unresolved.*phase.*abort.*Infer no implementation.*earliest.*next-gate.*Closeout default'

require_text "$workflow" 'delegate receives obligation phase pairs' \
  'Required commands and evidence obligations:.*owning phase.*selected workflow'
require_text "$workflow" 'delegate completion is implementation-relative' \
  'Completion:.*implementation-owned obligations.*later-phase obligations.*visible.*owed'
require_text "$workflow" 'development uses focused evidence' \
  'implementation-owned focused evidence.*needed for development'
require_text "$workflow" 'population runs only after readiness stabilization' \
  'readiness corrections.*stabilizes.*Candidate and Validation identity.*remaining direct evidence.*pre-gate or initial-gate'
require_text "$workflow" 'later corrections rerun only invalidated population members' \
  'remediation commit stabilizes.*Candidate and Validation identity.*only invalidated members.*reuse every unchanged qualifying member'
require_text "$workflow" 'full regression remains Closeout-only' \
  'Closeout.*full regression.*Never pre-produce it earlier'
forbid_text "$workflow" 'flat required-command field is absent' \
  'Required commands: <targeted and baseline checks>'

require_text "$policy" 'evidence policy owns identity semantics only' \
  'owns evidence identity.*sufficiency.*invalidation.*reuse.*does not decide.*workflow phase'
require_text "$policy" 'selected workflow owns timing' \
  'selected workflow owns.*timing'

for case_name in \
  later-phase-baseline-visible \
  narrow-development-then-complete-population \
  population-two-identities-change
do
  require_text "$eval_file" "eval includes $case_name" \
    "## Case: $case_name"
done
require_text "$eval_file" 'eval transport is bounded to four instruction files' \
  'filesystem read access.*solely.*four measured-instruction files'
require_text "$eval_file" 'eval forbids other reads, tools, and delegation' \
  'Any other tool use, repository-file read, or subdelegation invalidates'

if ! eval_contract_accepts "$eval_file"; then
  printf 'not ok - valid required-load candidate-authority protocol is accepted\n' >&2
  failures=$((failures + 1))
fi

permissive_eval="$fixture_dir/permissive-eval.md"
cp "$eval_file" "$permissive_eval"
printf '\nThe reader may skip measured candidate instruction files.\n' \
  >>"$permissive_eval"
if eval_contract_accepts "$permissive_eval"; then
  printf 'not ok - permissive candidate-instruction loading is rejected\n' >&2
  failures=$((failures + 1))
fi

no_load_eval="$fixture_dir/no-load-eval.md"
cp "$eval_file" "$no_load_eval"
printf '\nScenario facts may determine the schedule without loading candidate instructions.\n' \
  >>"$no_load_eval"
if eval_contract_accepts "$no_load_eval"; then
  printf 'not ok - scenario-only scheduling is rejected\n' >&2
  failures=$((failures + 1))
fi

missing_authority_eval="$fixture_dir/missing-authority-eval.md"
sed '/^MEASURED AUTHORITY:/d' "$eval_file" >"$missing_authority_eval"
if eval_contract_accepts "$missing_authority_eval"; then
  printf 'not ok - result contract without candidate-derived authority is rejected\n' >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s evidence-phase ownership assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'All evidence-phase ownership assertions held.\n'
