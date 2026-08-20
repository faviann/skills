#!/usr/bin/env bash
set -euo pipefail

readonly script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly telemetry_script="$script_root/run-telemetry.sh"
# shellcheck source=run-telemetry-schema.sh
source "$script_root/run-telemetry-schema.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

[[ "$work_on_telemetry_schema_version" -eq 3 ]]
[[ "20260820T000000Z-0123abcd (schema 3, integrity valid)" \
  =~ $work_on_telemetry_run_value_pattern ]]
for schema_consumer in run-telemetry.sh run-registry.sh render-closeout.sh \
    validate-closeout-body.sh; do
  grep -Fq 'source "$script_root/run-telemetry-schema.sh"' \
    "$script_root/$schema_consumer"
done

repo="$fixture/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name 'Schema 3 Test'
git -C "$repo" config user.email schema3@example.invalid
git -C "$repo" remote add origin 'git@github.com:Example/Telemetry.git'
printf 'fixture\n' >"$repo/file.txt"
git -C "$repo" add .
git -C "$repo" commit -qm fixture

telemetry() {
  (cd "$repo" && "$telemetry_script" "$@")
}

run="$(telemetry start --issue 83)"
summary="$(telemetry summary --run "$run")"
[[ "$(jq -r '.schema' <<<"$summary")" -eq 3 ]]

implementation_id="$(telemetry launch --run "$run" \
  --role implementation --phase implementation --round 1)"
readiness_id="$(telemetry review-delegation --run "$run" \
  --role readiness --kind readiness --phase checkpoint --round 1 \
  --base HEAD --worktree)"
standards_id="$(telemetry review-delegation --run "$run" \
  --role review-standards --kind full --phase gate --round 1 \
  --base HEAD --head HEAD)"
closure_id="$(telemetry review-delegation --run "$run" \
  --role closure-sweep --kind full --phase gate --round 1 \
  --base HEAD --head HEAD)"

[[ "$implementation_id" == "${run%%@*}-a001" ]]
[[ "$readiness_id" == "${run%%@*}-a002" ]]
[[ "$standards_id" == "${run%%@*}-a003" ]]
[[ "$closure_id" == "${run%%@*}-a004" ]]

observe() {
  telemetry runtime-observation --run "$run" "$@" \
    --model gpt-test --effort high \
    --total-input 100 --cached-input 70 --cache-write-input 10 \
    --output 20 --reasoning-output 5
}
observe --scope completed-thread --agent-id "$implementation_id"
observe --scope completed-thread --agent-id "$readiness_id"
observe --scope completed-thread --agent-id "$standards_id"
observe --scope completed-thread --agent-id "$closure_id"
observe --scope checkpoint-snapshot

readiness_one="$(telemetry finding-adjudicated --run "$run" \
  --reviewer-agent-id "$readiness_id" --class contract-defect \
  --disposition accepted)"
readiness_two="$(telemetry finding-adjudicated --run "$run" \
  --reviewer-agent-id "$readiness_id" --class contract-defect \
  --disposition accepted)"
telemetry finding-adjudicated --run "$run" \
  --reviewer-agent-id "$standards_id" --class contract-defect \
  --disposition rejected >/dev/null
telemetry finding-adjudicated --run "$run" \
  --reviewer-agent-id "$standards_id" --class evidence-gap \
  --disposition rejected >/dev/null
closure_finding="$(telemetry finding-adjudicated --run "$run" \
  --reviewer-agent-id "$closure_id" --class evidence-gap \
  --disposition accepted)"
telemetry finding-resolved --run "$run" --finding-id "$readiness_one"
telemetry finding-resolved --run "$run" --finding-id "$readiness_two"
telemetry finding-resolved --run "$run" --finding-id "$closure_finding"

summary="$(telemetry summary --run "$run")"
jq -e --arg implementation "$implementation_id" \
  --arg readiness "$readiness_id" --arg standards "$standards_id" '
  .schema == 3
  and ([.agents[].agent_id][0:3]) == [$implementation, $readiness, $standards]
  and .agents[0].role == "implementation"
  and .agents[1].role == "readiness"
  and .agents[2].role == "review-standards"
  and .runtime_observations.completed.coverage == "complete"
  and .runtime_observations.completed.tokens == {
    total_input: 400, cached_input: 280, cache_write_input: 40,
    fresh_input: 80, output: 80, reasoning_output: 20
  }
  and .runtime_observations.completed.by_role.implementation.tokens.fresh_input == 20
  and .runtime_observations.completed.by_agent[0] == {
    agent_id: $implementation, role: "implementation",
    model: "gpt-test", effort: "high",
    tokens: {total_input:100,cached_input:70,cache_write_input:10,
      output:20,reasoning_output:5,fresh_input:20}
  }
  and .runtime_observations.primary.scope == "checkpoint-snapshot"
  and .findings.resolved == 3
  and .findings.rejected == 2
  and .findings.by_reviewer[0].role == "readiness"
  and .findings.by_reviewer[0].accepted == 2
' <<<"$summary" >/dev/null

expect_refusal() {
  local label="$1"
  shift
  if telemetry "$@" >"$fixture/$label.out" 2>"$fixture/$label.err"; then
    printf 'FAIL[%s]: telemetry accepted invalid operation\n' "$label" >&2
    exit 1
  fi
}

expect_refusal unknown-agent runtime-observation --run "$run" \
  --scope completed-thread --agent-id "${run%%@*}-a999" \
  --model gpt-test --effort high
expect_refusal duplicate-observation runtime-observation --run "$run" \
  --scope completed-thread --agent-id "$implementation_id" \
  --model gpt-test --effort high
expect_refusal bad-token-arithmetic runtime-observation --run "$run" \
  --scope completed-thread --agent-id "$implementation_id" \
  --total-input 10 --cached-input 8 --cache-write-input 3 \
  --output 1 --reasoning-output 0
expect_refusal non-reviewer-origin finding-adjudicated --run "$run" \
  --reviewer-agent-id "$implementation_id" --class contract-defect \
  --disposition accepted

rejected_finding="$(telemetry finding-adjudicated --run "$run" \
  --reviewer-agent-id "$standards_id" --class contract-defect \
  --disposition rejected)"
expect_refusal resolve-rejected finding-resolved --run "$run" \
  --finding-id "$rejected_finding"
expect_refusal duplicate-resolution finding-resolved --run "$run" \
  --finding-id "$readiness_one"

# Allocation is sink-locked, so concurrent writers receive one contiguous,
# unique identity sequence.
parallel_run="$(telemetry start --issue 83)"
parallel_pids=()
for index in {1..8}; do
  (telemetry launch --run "$parallel_run" --role implementation \
    --phase implementation --round "$index" >"$fixture/agent-$index") &
  parallel_pids+=("$!")
done
for pid in "${parallel_pids[@]}"; do wait "$pid"; done
mapfile -t allocated_ids < <(sort "$fixture"/agent-*)
[[ "${#allocated_ids[@]}" -eq 8 ]]
[[ "$(printf '%s\n' "${allocated_ids[@]}" | sort -u | wc -l)" -eq 8 ]]
[[ "${allocated_ids[0]}" == "${parallel_run%%@*}-a001" ]]
[[ "${allocated_ids[7]}" == "${parallel_run%%@*}-a008" ]]

partial_run="$(telemetry start --issue 83)"
partial_one="$(telemetry launch --run "$partial_run" \
  --role implementation --phase implementation --round 1)"
telemetry launch --run "$partial_run" \
  --role implementation --phase implementation --round 2 >/dev/null
telemetry runtime-observation --run "$partial_run" \
  --scope completed-thread --agent-id "$partial_one" \
  --model gpt-test --effort high \
  --total-input 10 --cached-input 5 --cache-write-input 0 \
  --output 2 --reasoning-output 1
partial_summary="$(telemetry summary --run "$partial_run")"
jq -e '.runtime_observations.completed.coverage == "partial"
  and .runtime_observations.completed.observed == 1
  and .runtime_observations.completed.total_agents == 2' \
  <<<"$partial_summary" >/dev/null

none_run="$(telemetry start --issue 83)"
telemetry launch --run "$none_run" \
  --role implementation --phase implementation --round 1 >/dev/null
jq -e '.runtime_observations.completed.coverage == "none"' \
  <<<"$(telemetry summary --run "$none_run")" >/dev/null

model_only_run="$(telemetry start --issue 83)"
model_only_agent="$(telemetry launch --run "$model_only_run" \
  --role implementation --phase implementation --round 1)"
telemetry runtime-observation --run "$model_only_run" \
  --scope completed-thread --agent-id "$model_only_agent" \
  --model gpt-test --effort high
jq -e '.runtime_observations.completed.coverage == "none"
  and .runtime_observations.completed.observed == 0
  and .runtime_observations.completed.runtime_observed == 1' \
  <<<"$(telemetry summary --run "$model_only_run")" >/dev/null

sink_for() {
  printf '%s/.git/work-on-telemetry/runs/%s.jsonl\n' "$repo" "${1%%@*}"
}
assert_integrity_reason() {
  local target_run="$1" reason="$2"
  jq -e --arg reason "$reason" '
    .integrity.state == "invalid"
    and (.integrity.reasons | index($reason) != null)
  ' <<<"$(telemetry summary --run "$target_run")" >/dev/null
}

bad_agent_run="$(telemetry start --issue 83)"
telemetry launch --run "$bad_agent_run" \
  --role implementation --phase implementation --round 1 >/dev/null
bad_agent_sink="$(sink_for "$bad_agent_run")"
jq -c 'if .type == "subagent_launch"
  then .agent_id = (.run + "-a002") else . end' "$bad_agent_sink" \
  >"$fixture/bad-agent.jsonl"
mv "$fixture/bad-agent.jsonl" "$bad_agent_sink"
assert_integrity_reason "$bad_agent_run" AGENT_IDENTITY_INVALID

bad_runtime_run="$(telemetry start --issue 83)"
bad_runtime_agent="$(telemetry launch --run "$bad_runtime_run" \
  --role implementation --phase implementation --round 1)"
telemetry runtime-observation --run "$bad_runtime_run" \
  --scope completed-thread --agent-id "$bad_runtime_agent" \
  --model gpt-test --effort high
bad_runtime_sink="$(sink_for "$bad_runtime_run")"
jq -c 'if .type == "runtime_observation"
  then .agent_id = (.run + "-a999") else . end' "$bad_runtime_sink" \
  >"$fixture/bad-runtime.jsonl"
mv "$fixture/bad-runtime.jsonl" "$bad_runtime_sink"
assert_integrity_reason "$bad_runtime_run" RUNTIME_OBSERVATION_INVALID

bad_adjudication_run="$(telemetry start --issue 83)"
bad_adjudication_reviewer="$(telemetry review-delegation \
  --run "$bad_adjudication_run" --role readiness --kind readiness \
  --phase checkpoint --round 1 --base HEAD --head HEAD)"
telemetry finding-adjudicated --run "$bad_adjudication_run" \
  --reviewer-agent-id "$bad_adjudication_reviewer" --class evidence-gap \
  --disposition accepted >/dev/null
bad_adjudication_sink="$(sink_for "$bad_adjudication_run")"
jq -c 'if .type == "finding_adjudicated"
  then .finding_id = (.run + "-f002") else . end' "$bad_adjudication_sink" \
  >"$fixture/bad-adjudication.jsonl"
mv "$fixture/bad-adjudication.jsonl" "$bad_adjudication_sink"
assert_integrity_reason "$bad_adjudication_run" FINDING_ADJUDICATION_INVALID

bad_resolution_run="$(telemetry start --issue 83)"
bad_resolution_reviewer="$(telemetry review-delegation \
  --run "$bad_resolution_run" --role readiness --kind readiness \
  --phase checkpoint --round 1 --base HEAD --head HEAD)"
bad_resolution_finding="$(telemetry finding-adjudicated \
  --run "$bad_resolution_run" \
  --reviewer-agent-id "$bad_resolution_reviewer" --class contract-defect \
  --disposition rejected)"
bad_resolution_sink="$(sink_for "$bad_resolution_run")"
jq -cn --arg run "${bad_resolution_run%%@*}" \
  --arg finding_id "$bad_resolution_finding" \
  '{schema: 3, run: $run, seq: 4, at: "2026-08-20T00:00:00Z",
    epoch_ms: 1, type: "finding_resolved", finding_id: $finding_id}' \
  >>"$bad_resolution_sink"
assert_integrity_reason "$bad_resolution_run" FINDING_RESOLUTION_INVALID

wrong_schema_run="$(telemetry start --issue 83)"
wrong_schema_sink="$(sink_for "$wrong_schema_run")"
jq -c '.schema = 2' "$wrong_schema_sink" >"$fixture/wrong-schema.jsonl"
mv "$fixture/wrong-schema.jsonl" "$wrong_schema_sink"
if telemetry summary --run "$wrong_schema_run" \
    >"$fixture/wrong-schema-summary.out" \
    2>"$fixture/wrong-schema-summary.err"; then
  printf 'FAIL[wrong-schema-summary]: schema-2 sink remained readable\n' >&2
  exit 1
fi
[[ ! -s "$fixture/wrong-schema-summary.out" ]]
grep -Fq 'schema-3 summary requires a schema-3 run' \
  "$fixture/wrong-schema-summary.err"
if telemetry launch --run "$wrong_schema_run" \
    --role implementation --phase implementation --round 1 \
    >"$fixture/wrong-schema-write.out" \
    2>"$fixture/wrong-schema-write.err"; then
  printf 'FAIL[wrong-schema-write]: schema-3 writer accepted a schema-2 sink\n' >&2
  exit 1
fi
[[ ! -s "$fixture/wrong-schema-write.out" ]]
grep -Fq 'schema-3 writer requires a schema-3 run' \
  "$fixture/wrong-schema-write.err"

printf 'work-on schema-3 scenarios passed\n'
