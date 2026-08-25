#!/usr/bin/env bash
set -euo pipefail

root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

projection_digest="$(sha256sum "$root/projection.mjs" | cut -d' ' -f1)"
common='"recorded_at":"2026-08-25T23:59:00Z","protocol_commit":"0000000000000000000000000000000000000000","projection_version":"3.0.0","projection_digest":"'"$projection_digest"'","workflow_provenance":"work-on:a9ebf0ae3a77 workflow:1b3cf6d962ac tdd:aa54f63292bf review:1dc4289fabb7 (faviann/skills@000000000000)","source_locators":["fixture:1"]'

write_run() {
  local id="$1" repo="$2" issue="$3" cells="$4" correction="$5" qualifying="$6" commitment="$7" validation="$8"
  printf '{"entry_id":"%s","subject_id":"%s","kind":"attempt-closeout",%s,"repository":"%s","issue":%s,"started":true,"completed":true,"cells":%s,"eligibility":{"eligible":true,"facts":["fixture"]},"substitution":null,"run_identities":["fixture-run"],"base_identity":"fixture-base","candidate_identity":"fixture-candidate","findings":[],"corrective_batches":[],"blocker_lineage":[],"convergence":{},"cost":{},"evidence_usable":true,"exact_provenance":true,"gate1_failures":[],"gate2_adverse":[],"validation_surface":{"complete_before_delegation":true,"frozen":true,"all_members_directly_evidenced":true,"post_delegation_amendment":false,"review_and_neighborhood_unrestricted":true},"validation":%s,"delta":{"accepted_corrections":%s,"all_fresh_delta_axes":true,"routine_cumulative_reread":false,"mechanism_neighborhood_reachable":true,"valid_final_blind_confirmation":true},"normative":{"qualifying_batches":%s,"qualification_misses":0,"semantic_challenge_failures":0,"disproportionate_cost_or_false_positive":false,"blindness_breach":false,"review_package_contamination":false,"substituted_for_review_axis":false},"natural_exposure":[{"required":true,"observed":true}],"behavioral_commitment":%s}\n' \
    "$id" "$id" "$common" "$repo" "$issue" "$cells" "$validation" "$correction" "$qualifying" "$commitment"
}

write_scenarios() {
  local destination="$1" scenario
  for scenario in validation-surface-omission normative-remediation-semantics; do
    printf '{"entry_id":"scenario-%s","subject_id":"scenario-%s","kind":"controlled-scenario",%s,"scenario":"%s","arms":["fixture"],"passed":true,"gate1_failures":[]}\n' "$scenario" "$scenario" "$common" "$scenario" >>"$destination"
  done
}

good_validation='{"obligations":[{"obligation_id":"full","owning_phase":"closeout","resolved_before_delegation":true,"owed":true,"discharged":true,"execution_ids":["e-closeout"]}],"executions":[{"execution_id":"e-closeout","phase":"closeout","duration_seconds":120,"duplicate_class":"none","workflow_attributable":true,"additional":false,"assurance_reason":"required owning-phase execution","timing_cause":"selected-workflow"}],"populations":[{"population_id":"cases","owning_phase":"post-stabilization","complete_at_phase":"post-stabilization","invalidated_member_ids":["B","D"],"rerun_member_ids":["B","D"],"independently_required_member_ids":[]}],"reuse_events":[{"qualifying":true,"duration_seconds":120}],"assurance_questions":[]}'
bad_phase='{"obligations":[{"obligation_id":"full","owning_phase":"closeout","resolved_before_delegation":true,"owed":true,"discharged":true,"execution_ids":["e-early","e-closeout"]}],"executions":[{"execution_id":"e-early","phase":"implementation","duration_seconds":120,"duplicate_class":"none","workflow_attributable":true,"additional":false,"assurance_reason":null,"timing_cause":"repository-baseline"},{"execution_id":"e-closeout","phase":"closeout","duration_seconds":120,"duplicate_class":"unjustified-workflow","workflow_attributable":true,"additional":true,"assurance_reason":null,"timing_cause":"selected-workflow"}],"populations":[{"population_id":"cases","owning_phase":"post-stabilization","complete_at_phase":"implementation","invalidated_member_ids":["B","D"],"rerun_member_ids":["B","D"],"independently_required_member_ids":[]}],"reuse_events":[{"qualifying":true,"duration_seconds":120}],"assurance_questions":[]}'
bad_members='{"obligations":[{"obligation_id":"full","owning_phase":"closeout","resolved_before_delegation":true,"owed":true,"discharged":true,"execution_ids":["e-closeout"]}],"executions":[{"execution_id":"e-closeout","phase":"closeout","duration_seconds":120,"duplicate_class":"none","workflow_attributable":true,"additional":false,"assurance_reason":"required owning-phase execution","timing_cause":"selected-workflow"}],"populations":[{"population_id":"cases","owning_phase":"post-stabilization","complete_at_phase":"post-stabilization","invalidated_member_ids":["B","D"],"rerun_member_ids":["A","B","C","D"],"independently_required_member_ids":[]}],"reuse_events":[{"qualifying":true,"duration_seconds":120}],"assurance_questions":[]}'

write_run r1 faviann/homelab-iac 204 '["ordinary-clean-expensive-validation"]' 0 0 '{"answer":"YES","reason":"fixture"}' "$good_validation" >"$tmp/good.jsonl"
write_run r2 faviann/dotfiles 73 '["contract-dense-remediation-opportunity"]' 1 1 null "$good_validation" >>"$tmp/good.jsonl"
write_run r3 faviann/homelab-iac 88 '["timing-concurrency-environment-sensitive"]' 0 0 null "$good_validation" >>"$tmp/good.jsonl"
write_run r4 faviann/dotfiles 96 '["collection-valued-validation-surface"]' 0 0 null "$good_validation" >>"$tmp/good.jsonl"
write_scenarios "$tmp/good.jsonl"

node "$root/projection.mjs" "$tmp/good.jsonl" >"$tmp/good.out"
[[ "$(jq -r .result "$tmp/good.out")" == PASS ]]

# #129 shape 1: eventual baseline and a complete population execute before the
# selected workflow's stabilized owning phase. The frozen projection must make
# this a conclusive validation/reuse failure.
write_run r1 faviann/homelab-iac 204 '["ordinary-clean-expensive-validation"]' 0 0 '{"answer":"YES","reason":"fixture"}' "$bad_phase" >"$tmp/bad-phase.jsonl"
write_run r2 faviann/dotfiles 73 '["contract-dense-remediation-opportunity"]' 1 1 null "$good_validation" >>"$tmp/bad-phase.jsonl"
write_run r3 faviann/homelab-iac 88 '["timing-concurrency-environment-sensitive"]' 0 0 null "$good_validation" >>"$tmp/bad-phase.jsonl"
write_run r4 faviann/dotfiles 96 '["collection-valued-validation-surface"]' 0 0 null "$good_validation" >>"$tmp/bad-phase.jsonl"
write_scenarios "$tmp/bad-phase.jsonl"
node "$root/projection.mjs" "$tmp/bad-phase.jsonl" >"$tmp/bad-phase.out"
[[ "$(jq -r .result "$tmp/bad-phase.out")" == "DO NOT RESUME" ]]
[[ "$(jq -r '.mechanisms.validation_reuse_and_phase_ownership' "$tmp/bad-phase.out")" == FAILED ]]

# #129 shape 2: only two member identities change, but unchanged population
# members rerun. This must also fail rather than disappearing into total counts.
write_run r1 faviann/homelab-iac 204 '["ordinary-clean-expensive-validation"]' 0 0 '{"answer":"YES","reason":"fixture"}' "$bad_members" >"$tmp/bad-members.jsonl"
write_run r2 faviann/dotfiles 73 '["contract-dense-remediation-opportunity"]' 1 1 null "$good_validation" >>"$tmp/bad-members.jsonl"
write_run r3 faviann/homelab-iac 88 '["timing-concurrency-environment-sensitive"]' 0 0 null "$good_validation" >>"$tmp/bad-members.jsonl"
write_run r4 faviann/dotfiles 96 '["collection-valued-validation-surface"]' 0 0 null "$good_validation" >>"$tmp/bad-members.jsonl"
write_scenarios "$tmp/bad-members.jsonl"
node "$root/projection.mjs" "$tmp/bad-members.jsonl" >"$tmp/bad-members.out"
[[ "$(jq -r .result "$tmp/bad-members.out")" == "DO NOT RESUME" ]]

echo "projection fixtures: pass"
