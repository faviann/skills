#!/usr/bin/env bash
set -euo pipefail

# Black-box schema-2 contract scenarios. Corruption fixtures reach into the
# sink only when the contract being exercised is read-time integrity.

readonly script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly telemetry_script="$script_root/run-telemetry.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

repo="$fixture/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name 'Schema 2 Test'
git -C "$repo" config user.email schema2@example.invalid
git -C "$repo" remote add origin 'git@github.com:Example/Telemetry.git'
printf 'fixture\n' >"$repo/file.txt"
git -C "$repo" add .
git -C "$repo" commit -qm fixture

telemetry() {
  (cd "$repo" && "$telemetry_script" "$@")
}

declare -A integrity_reasons_covered=()

assert_reason() {
  local handle="$1" reason="$2" summary
  summary="$(telemetry summary --run "$handle")"
  [[ "$(jq -r '.integrity.state' <<<"$summary")" == invalid ]]
  jq -e --arg reason "$reason" \
    '.integrity.reasons | index($reason) != null' <<<"$summary" >/dev/null
  integrity_reasons_covered["$reason"]=1
}

assert_incomplete_reason() {
  local handle="$1" reason="$2" summary
  summary="$(telemetry summary --run "$handle")"
  [[ "$(jq -r '.integrity.state' <<<"$summary")" == incomplete ]]
  jq -e --arg reason "$reason" \
    '.integrity.reasons | index($reason) != null' <<<"$summary" >/dev/null
  integrity_reasons_covered["$reason"]=1
}

run="$(telemetry start --issue 71)"
summary="$(telemetry summary --run "$run")"
[[ "$(jq -r '.schema' <<<"$summary")" -eq 2 ]]
[[ "$(jq -r '.repository' <<<"$summary")" == example/telemetry ]]
[[ "$(jq -r '.issue' <<<"$summary")" -eq 71 ]]
[[ "$(jq -r '.started_head' <<<"$summary")" == \
  "$(git -C "$repo" rev-parse HEAD)" ]]
[[ "$(jq -r '.run' <<<"$summary")" == "${run%%@*}" ]]
[[ "$(jq -r '.integrity.state' <<<"$summary")" == incomplete ]]
assert_incomplete_reason "$run" OUTCOME_UNRESOLVED

continued="$(telemetry start --issue 71 --continues-run "$run")"
continued_summary="$(telemetry summary --run "$continued")"
[[ "$(jq -r '.continues_run' <<<"$continued_summary")" == "${run%%@*}" ]]

other_issue="$(telemetry start --issue 72)"
if telemetry start --issue 71 --continues-run "$other_issue" \
    >"$fixture/cross-issue.out" 2>"$fixture/cross-issue.err"; then
  printf 'FAIL[cross-issue]: continuation crossed issue identity\n' >&2
  exit 1
fi
grep -Fq 'continued run belongs to another repository or issue' \
  "$fixture/cross-issue.err"

foreign_repo="$fixture/foreign"
git init -q -b main "$foreign_repo"
git -C "$foreign_repo" config user.name 'Schema 2 Test'
git -C "$foreign_repo" config user.email schema2@example.invalid
git -C "$foreign_repo" remote add origin \
  'https://github.com/example/foreign.git'
printf 'foreign\n' >"$foreign_repo/file.txt"
git -C "$foreign_repo" add .
git -C "$foreign_repo" commit -qm fixture
foreign_run="$(cd "$foreign_repo" && "$telemetry_script" start --issue 71)"
if telemetry start --issue 71 --continues-run "$foreign_run" \
    >"$fixture/cross-repository.out" 2>"$fixture/cross-repository.err"; then
  printf 'FAIL[cross-repository]: continuation crossed repository identity\n' >&2
  exit 1
fi
grep -Fq 'run handle belongs to another repository' \
  "$fixture/cross-repository.err"

review_run="$(telemetry start --issue 71)"
telemetry review-delegation --run "$review_run" \
  --role review-standards --kind full --phase gate --round 1 \
  --base HEAD --head HEAD
telemetry review-delegation --run "$review_run" \
  --role review-spec --kind full --phase gate --round 1 \
  --base HEAD --head HEAD
telemetry review-delegation --run "$review_run" \
  --role closure-sweep --kind full --phase gate --round 1 \
  --base HEAD --head HEAD
review_summary="$(telemetry summary --run "$review_run")"
[[ "$(jq -r '.review_delegations.total' <<<"$review_summary")" -eq 3 ]]
[[ "$(jq -r '.review_delegations.by_role."review-standards"' \
  <<<"$review_summary")" -eq 1 ]]
[[ "$(jq -r '.review_delegations.by_role."review-spec"' \
  <<<"$review_summary")" -eq 1 ]]
[[ "$(jq -r '.review_delegations.by_role."closure-sweep"' \
  <<<"$review_summary")" -eq 1 ]]
for role in review-standards review-spec closure-sweep; do
  [[ "$(jq -r --arg role "$role" '.subagent_launches.by_role[$role]' \
    <<<"$review_summary")" -eq \
    "$(jq -r --arg role "$role" '.review_delegations.by_role[$role]' \
    <<<"$review_summary")" ]]
done

expect_refusal() {
  local label="$1"
  shift
  if telemetry "$@" >"$fixture/$label.out" 2>"$fixture/$label.err"; then
    printf 'FAIL[%s]: telemetry accepted invalid operation\n' "$label" >&2
    exit 1
  fi
}

expect_refusal review-launch launch --run "$review_run" \
  --role review-spec --phase gate --round 2
expect_refusal split-review review --run "$review_run" \
  --kind full --phase gate --round 2 --base HEAD --head HEAD
expect_refusal readiness-full review-delegation --run "$review_run" \
  --role readiness --kind full --phase checkpoint --round 1 \
  --base HEAD --worktree
expect_refusal standards-readiness review-delegation --run "$review_run" \
  --role review-standards --kind readiness --phase gate --round 1 \
  --base HEAD --head HEAD
expect_refusal readiness-gate review-delegation --run "$review_run" \
  --role readiness --kind readiness --phase gate --round 1 \
  --base HEAD --worktree

parallel_run="$(telemetry start --issue 71)"
parallel_sync="$fixture/parallel-review-sync"
parallel_git_bin="$parallel_sync/bin"
parallel_release="$parallel_sync/release"
mkdir -p "$parallel_git_bin"
real_git="$(command -v git)"
cat >"$parallel_git_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

for argument in "$@"; do
  if [[ "$argument" == diff ]]; then
    : "${REVIEW_SYNC_ENTERED:?}"
    : "${REVIEW_SYNC_RELEASE:?}"
    touch "$REVIEW_SYNC_ENTERED"
    while [[ ! -e "$REVIEW_SYNC_RELEASE" ]]; do sleep 0.01; done
    break
  fi
done
exec "${REVIEW_REAL_GIT:?}" "$@"
EOF
chmod +x "$parallel_git_bin/git"
parallel_pids=()
for role in review-standards review-spec closure-sweep; do
  (
    export PATH="$parallel_git_bin:$PATH"
    export REVIEW_REAL_GIT="$real_git"
    export REVIEW_SYNC_ENTERED="$parallel_sync/$role.entered"
    export REVIEW_SYNC_RELEASE="$parallel_release"
    telemetry review-delegation --run "$parallel_run" \
      --role "$role" --kind full --phase gate --round 1 \
      --base HEAD --head HEAD
  ) &
  parallel_pids+=("$!")
done
for ((attempt = 0; attempt < 500; attempt++)); do
  entered_count="$(find "$parallel_sync" -name '*.entered' -type f | wc -l)"
  [[ "$entered_count" -eq 3 ]] && break
  sleep 0.01
done
[[ "$entered_count" -eq 3 ]]
for pid in "${parallel_pids[@]}"; do
  kill -0 "$pid"
done
touch "$parallel_release"
for pid in "${parallel_pids[@]}"; do
  wait "$pid"
done
parallel_summary="$(telemetry summary --run "$parallel_run")"
[[ "$(jq -r '.review_delegations.total' <<<"$parallel_summary")" -eq 3 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$parallel_summary")" -eq 3 ]]
for role in readiness review-standards review-spec closure-sweep; do
  expected=1
  [[ "$role" == readiness ]] && expected=0
  [[ "$(jq -r --arg role "$role" \
    '.review_delegations.by_role[$role]' <<<"$parallel_summary")" \
    -eq "$expected" ]]
done
parallel_head="$(git -C "$repo" rev-parse HEAD)"
jq -s -e --arg head "$parallel_head" '
  [.[] | select(.type == "review_delegation")] as $reviews
  | ($reviews | length) == 3
    and ([$reviews[].role] | sort
      == ["closure-sweep", "review-spec", "review-standards"])
    and ([$reviews[].seq] | unique | length) == 3
    and all($reviews[];
      .kind == "full" and .phase == "gate" and .round == 1
      and .base == $head and .head == $head
      and .head_is_worktree == false and .input_bytes == 0)
' "$repo/.git/work-on-telemetry/runs/${parallel_run%%@*}.jsonl" >/dev/null

resolve_and_seal() {
  local handle="$1" outcome="$2"
  telemetry resolve --run "$handle" --outcome "$outcome"
  telemetry seal --run "$handle"
}

preflight_run="$(telemetry start --issue 71)"
unresolved_seal_run="$(telemetry start --issue 71)"
expect_refusal seal-before-resolution seal --run "$unresolved_seal_run"
resolve_and_seal "$preflight_run" preflight-aborted
[[ "$(jq -r '.integrity.state' \
  <<<"$(telemetry summary --run "$preflight_run")")" == valid ]]

late_implementation="$(telemetry start --issue 71)"
telemetry launch --run "$late_implementation" \
  --role implementation --phase implementation --round 1
expect_refusal late-preflight-implementation resolve \
  --run "$late_implementation" --outcome preflight-aborted

late_review="$(telemetry start --issue 71)"
telemetry review-delegation --run "$late_review" \
  --role readiness --kind readiness --phase checkpoint --round 1 \
  --base HEAD --worktree
expect_refusal late-preflight-review resolve \
  --run "$late_review" --outcome preflight-aborted

for outcome in abandoned failed Closes Progresses; do
  lifecycle_run="$(telemetry start --issue 71)"
  telemetry launch --run "$lifecycle_run" \
    --role implementation --phase implementation --round 1
  resolve_and_seal "$lifecycle_run" "$outcome"
  lifecycle_summary="$(telemetry summary --run "$lifecycle_run")"
  [[ "$(jq -r '.final_workflow_outcome' <<<"$lifecycle_summary")" == \
    "$outcome" ]]
  [[ "$(jq -r '.integrity.state' <<<"$lifecycle_summary")" == valid ]]
done

closeout_run="$(telemetry start --issue 71)"
telemetry launch --run "$closeout_run" \
  --role implementation --phase implementation --round 1
telemetry resolve --run "$closeout_run" --outcome Closes
telemetry exec --run "$closeout_run" \
  --command-id final-check --phase closeout --round 1 -- true
[[ "$(jq -r '.integrity.state' \
  <<<"$(telemetry summary --run "$closeout_run")")" == incomplete ]]
assert_incomplete_reason "$closeout_run" RUN_UNSEALED
telemetry seal --run "$closeout_run"
[[ "$(jq -r '.integrity.state' \
  <<<"$(telemetry summary --run "$closeout_run")")" == valid ]]
expect_refusal duplicate-resolution resolve --run "$closeout_run" \
  --outcome Closes
expect_refusal duplicate-seal seal --run "$closeout_run"
expect_refusal write-after-seal launch --run "$closeout_run" \
  --role other --phase closeout --round 2

sink_for() {
  printf '%s/.git/work-on-telemetry/runs/%s.jsonl\n' "$repo" "${1%%@*}"
}

append_raw_event() {
  local handle="$1" type="$2" extra="${3:-}" sink seq
  [[ -n "$extra" ]] || extra='{}'
  sink="$(sink_for "$handle")"
  seq=$(( $(wc -l <"$sink") + 1 ))
  jq -cn --arg run "${handle%%@*}" --arg type "$type" \
    --argjson seq "$seq" --argjson extra "$extra" \
    '{schema: 2, run: $run, seq: $seq, at: "2026-08-16T00:00:00Z",
      epoch_ms: 1786838400000, type: $type} + $extra' >>"$sink"
}

well_framed_run="$(telemetry start --issue 71)"
resolve_and_seal "$well_framed_run" Closes
well_framed_summary="$(telemetry summary --run "$well_framed_run")"
[[ "$(jq -r '.integrity.state' <<<"$well_framed_summary")" == valid ]]
well_framed_id="${well_framed_run%%@*}"
if telemetry summary --run "$well_framed_id" \
    >"$fixture/bare-schema2-summary.out" \
    2>"$fixture/bare-schema2-summary.err"; then
  printf 'FAIL[bare-schema2-summary]: summary accepted an unbound schema-2 id\n' >&2
  exit 1
fi
[[ ! -s "$fixture/bare-schema2-summary.out" ]]
grep -Fq 'schema-2 summary requires a repository-bound handle' \
  "$fixture/bare-schema2-summary.err"

blank_line_run="$(telemetry start --issue 71)"
resolve_and_seal "$blank_line_run" Closes
printf '\n' >>"$(sink_for "$blank_line_run")"
blank_line_summary="$(telemetry summary --run "$blank_line_run")"
[[ "$(jq -r '.malformed_lines' <<<"$blank_line_summary")" -eq 1 ]]
assert_reason "$blank_line_run" MALFORMED_LINE

missing_newline_run="$(telemetry start --issue 71)"
resolve_and_seal "$missing_newline_run" Closes
truncate -s -1 "$(sink_for "$missing_newline_run")"
missing_newline_summary="$(telemetry summary --run "$missing_newline_run")"
[[ "$(jq -r '.events' <<<"$missing_newline_summary")" -eq 3 ]]
assert_reason "$missing_newline_run" TERMINAL_NEWLINE_MISSING

malformed_run="$(telemetry start --issue 71)"
resolve_and_seal "$malformed_run" failed
printf 'not-json\n' >>"$(sink_for "$malformed_run")"
assert_reason "$malformed_run" MALFORMED_LINE

mixed_run="$(telemetry start --issue 71)"
resolve_and_seal "$mixed_run" failed
printf '%s\n' \
  '{"schema":1,"run":"legacy","seq":4,"at":"2026-08-16T00:00:00Z","epoch_ms":1786838400000,"type":"run_start","workflow":"work-on"}' \
  >>"$(sink_for "$mixed_run")"
assert_reason "$mixed_run" MIXED_SCHEMA

post_seal_run="$(telemetry start --issue 71)"
resolve_and_seal "$post_seal_run" failed
append_raw_event "$post_seal_run" subagent_launch \
  '{"role":"other","phase":"closeout","round":1}'
assert_reason "$post_seal_run" EVENT_AFTER_SEAL

bad_review_run="$(telemetry start --issue 71)"
head_sha="$(git -C "$repo" rev-parse HEAD)"
append_raw_event "$bad_review_run" review_delegation \
  "{\"role\":\"readiness\",\"kind\":\"full\",\"phase\":\"checkpoint\",\"round\":1,\"base\":\"$head_sha\",\"head\":\"$head_sha\",\"head_is_worktree\":true,\"input_bytes\":0}"
assert_reason "$bad_review_run" REVIEW_DELEGATION_INVALID

malformed_review_run="$(telemetry start --issue 71)"
append_raw_event "$malformed_review_run" review_delegation \
  "{\"role\":\"review-spec\",\"kind\":\"full\",\"phase\":\"gate\",\"round\":1,\"base\":\"$head_sha\",\"head\":\"$head_sha\",\"head_is_worktree\":false,\"input_bytes\":\"attacker-controlled-text\"}"
malformed_review_summary="$(telemetry summary --run "$malformed_review_run")"
[[ "$(jq -r '.review_delegations.input_bytes' \
  <<<"$malformed_review_summary")" -eq 0 ]]
[[ "$malformed_review_summary" != *attacker-controlled-text* ]]
assert_reason "$malformed_review_run" EVENT_SHAPE_INVALID

mixed_review_run="$(telemetry start --issue 71)"
append_raw_event "$mixed_review_run" review_delegation \
  "{\"role\":\"review-standards\",\"kind\":\"full\",\"phase\":\"gate\",\"round\":1,\"base\":\"$head_sha\",\"head\":\"$head_sha\",\"head_is_worktree\":false,\"input_bytes\":37}"
append_raw_event "$mixed_review_run" review_delegation \
  "{\"role\":\"review-spec\",\"kind\":\"full\",\"phase\":\"gate\",\"round\":1,\"base\":\"$head_sha\",\"head\":\"$head_sha\",\"head_is_worktree\":false,\"input_bytes\":\"attacker-controlled-text\"}"
mixed_review_summary="$(telemetry summary --run "$mixed_review_run")"
[[ "$(jq -r '.review_delegations.input_bytes' \
  <<<"$mixed_review_summary")" -eq 37 ]]
[[ "$mixed_review_summary" != *attacker-controlled-text* ]]
assert_reason "$mixed_review_run" EVENT_SHAPE_INVALID

late_abort_sink_run="$(telemetry start --issue 71)"
telemetry launch --run "$late_abort_sink_run" \
  --role implementation --phase implementation --round 1
append_raw_event "$late_abort_sink_run" outcome_resolved \
  '{"outcome":"preflight-aborted"}'
telemetry seal --run "$late_abort_sink_run"
assert_reason "$late_abort_sink_run" PREFLIGHT_ABORT_AFTER_WORK

bad_transition_run="$(telemetry start --issue 71)"
telemetry resolve --run "$bad_transition_run" --outcome Closes
append_raw_event "$bad_transition_run" review_delegation \
  "{\"role\":\"review-spec\",\"kind\":\"full\",\"phase\":\"gate\",\"round\":1,\"base\":\"$head_sha\",\"head\":\"$head_sha\",\"head_is_worktree\":false,\"input_bytes\":0}"
append_raw_event "$bad_transition_run" run_sealed
assert_reason "$bad_transition_run" LIFECYCLE_TRANSITION_INVALID

validation_mismatch_run="$(telemetry start --issue 71)"
exec_id="${validation_mismatch_run%%@*}-e001"
append_raw_event "$validation_mismatch_run" validation_start \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check-one\",\"phase\":\"gate\",\"round\":1}"
append_raw_event "$validation_mismatch_run" validation_end \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check-two\",\"phase\":\"gate\",\"round\":1,\"outcome\":\"passed\",\"exit_status\":0,\"duration_ms\":1}"
assert_reason "$validation_mismatch_run" VALIDATION_IDENTITY_MISMATCH

validation_completion_run="$(telemetry start --issue 71)"
exec_id="${validation_completion_run%%@*}-e001"
append_raw_event "$validation_completion_run" validation_start \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check\",\"phase\":\"gate\",\"round\":1}"
append_raw_event "$validation_completion_run" validation_end \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check\",\"phase\":\"gate\",\"round\":1,\"outcome\":\"passed\",\"exit_status\":1,\"duration_ms\":1}"
assert_reason "$validation_completion_run" VALIDATION_COMPLETION_INVALID

validation_incomplete_run="$(telemetry start --issue 71)"
exec_id="${validation_incomplete_run%%@*}-e001"
append_raw_event "$validation_incomplete_run" validation_start \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check\",\"phase\":\"gate\",\"round\":1}"
incomplete_summary="$(telemetry summary --run "$validation_incomplete_run")"
[[ "$(jq -r '.integrity.state' <<<"$incomplete_summary")" == incomplete ]]
jq -e '.integrity.reasons | index("VALIDATION_INCOMPLETE") != null' \
  <<<"$incomplete_summary" >/dev/null
assert_incomplete_reason "$validation_incomplete_run" VALIDATION_INCOMPLETE

bad_shape_run="$(telemetry start --issue 71)"
append_raw_event "$bad_shape_run" subagent_launch \
  '{"role":"implementation","phase":"implementation","round":"one"}'
assert_reason "$bad_shape_run" EVENT_SHAPE_INVALID

bad_sequence_run="$(telemetry start --issue 71)"
append_raw_event "$bad_sequence_run" subagent_launch \
  '{"role":"implementation","phase":"implementation","round":1}'
sed -i '2s/"seq":2/"seq":9/' "$(sink_for "$bad_sequence_run")"
assert_reason "$bad_sequence_run" SEQUENCE_INVALID

duplicate_resolution_run="$(telemetry start --issue 71)"
resolve_and_seal "$duplicate_resolution_run" failed
append_raw_event "$duplicate_resolution_run" outcome_resolved \
  '{"outcome":"abandoned"}'
assert_reason "$duplicate_resolution_run" OUTCOME_RESOLUTION_COUNT_INVALID

duplicate_seal_run="$(telemetry start --issue 71)"
resolve_and_seal "$duplicate_seal_run" failed
append_raw_event "$duplicate_seal_run" run_sealed
assert_reason "$duplicate_seal_run" SEAL_COUNT_INVALID

reversed_pair_run="$(telemetry start --issue 71)"
exec_id="${reversed_pair_run%%@*}-e001"
append_raw_event "$reversed_pair_run" validation_end \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check\",\"phase\":\"gate\",\"round\":1,\"outcome\":\"passed\",\"exit_status\":0,\"duration_ms\":1}"
append_raw_event "$reversed_pair_run" validation_start \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check\",\"phase\":\"gate\",\"round\":1}"
assert_reason "$reversed_pair_run" VALIDATION_PAIR_INVALID

orphan_end_run="$(telemetry start --issue 71)"
exec_id="${orphan_end_run%%@*}-e001"
append_raw_event "$orphan_end_run" validation_end \
  "{\"exec_id\":\"$exec_id\",\"command_id\":\"check\",\"phase\":\"gate\",\"round\":1,\"outcome\":\"passed\",\"exit_status\":0,\"duration_ms\":1}"
assert_reason "$orphan_end_run" VALIDATION_PAIR_INVALID

wrong_run="$(telemetry start --issue 71)"
append_raw_event "$wrong_run" subagent_launch \
  '{"role":"implementation","phase":"implementation","round":1}'
sed -i '2s/"run":"[^"]*"/"run":"20000101T000000Z-00000000"/' \
  "$(sink_for "$wrong_run")"
assert_reason "$wrong_run" RUN_IDENTITY_MISMATCH

duplicate_start_run="$(telemetry start --issue 71)"
append_raw_event "$duplicate_start_run" run_start \
  "{\"workflow\":\"work-on\",\"repository\":\"example/telemetry\",\"issue\":71,\"head\":\"$head_sha\",\"run_identity\":\"${duplicate_start_run%%@*}\"}"
assert_reason "$duplicate_start_run" RUN_START_COUNT_INVALID

wrong_repository_run="$(telemetry start --issue 71)"
sed -i '1s#"repository":"example/telemetry"#"repository":"example/another"#' \
  "$(sink_for "$wrong_repository_run")"
assert_reason "$wrong_repository_run" RUN_START_IDENTITY_INVALID

bad_outcome_run="$(telemetry start --issue 71)"
append_raw_event "$bad_outcome_run" outcome_resolved '{"outcome":"merged"}'
append_raw_event "$bad_outcome_run" run_sealed
assert_reason "$bad_outcome_run" OUTCOME_RESOLUTION_INVALID

seal_first_run="$(telemetry start --issue 71)"
append_raw_event "$seal_first_run" run_sealed
append_raw_event "$seal_first_run" outcome_resolved '{"outcome":"failed"}'
assert_reason "$seal_first_run" LIFECYCLE_TRANSITION_INVALID

# Mechanical aggregates are derived from recorded events only. Rounds are
# distinct observed round numbers rather than event counts, so the three
# reviewers of one gate round are one independent-review round.
rounds_run="$(telemetry start --issue 71)"
telemetry launch --run "$rounds_run" \
  --role implementation --phase implementation --round 1
telemetry review-delegation --run "$rounds_run" \
  --role readiness --kind readiness --phase checkpoint --round 1 \
  --base HEAD --head HEAD
telemetry review-delegation --run "$rounds_run" \
  --role review-standards --kind full --phase gate --round 1 \
  --base HEAD --head HEAD
telemetry review-delegation --run "$rounds_run" \
  --role review-spec --kind full --phase gate --round 1 \
  --base HEAD --head HEAD
telemetry review-delegation --run "$rounds_run" \
  --role closure-sweep --kind full --phase gate --round 1 \
  --base HEAD --head HEAD
rounds_summary="$(telemetry summary --run "$rounds_run")"
[[ "$(jq -r '.rounds.implementation' <<<"$rounds_summary")" -eq 1 ]]
[[ "$(jq -r '.rounds.independent_review' <<<"$rounds_summary")" -eq 1 ]]
[[ "$(jq -r '.rounds.remediation' <<<"$rounds_summary")" -eq 0 ]]

# A second gate round is a second independent-review round. Delta remediation
# review and the closeout-phase closure sweep are excluded by their phase and
# kind, and a remediation implementer is a remediation round rather than an
# implementation one.
telemetry launch --run "$rounds_run" \
  --role implementation --phase remediation --round 2
telemetry review-delegation --run "$rounds_run" \
  --role review-standards --kind delta --phase remediation --round 2 \
  --base HEAD --head HEAD
telemetry review-delegation --run "$rounds_run" \
  --role review-standards --kind full --phase gate --round 2 \
  --base HEAD --head HEAD
telemetry review-delegation --run "$rounds_run" \
  --role closure-sweep --kind full --phase closeout --round 2 \
  --base HEAD --head HEAD
rounds_summary="$(telemetry summary --run "$rounds_run")"
[[ "$(jq -r '.rounds.implementation' <<<"$rounds_summary")" -eq 1 ]]
[[ "$(jq -r '.rounds.independent_review' <<<"$rounds_summary")" -eq 2 ]]
[[ "$(jq -r '.rounds.remediation' <<<"$rounds_summary")" -eq 1 ]]
# An `other` launch never becomes an implementation round, whatever its phase.
telemetry launch --run "$rounds_run" \
  --role other --phase implementation --round 3
[[ "$(jq -r '.rounds.implementation' \
  <<<"$(telemetry summary --run "$rounds_run")")" -eq 1 ]]

# Start-to-seal is the recorded interval between the two lifecycle stamps.
telemetry resolve --run "$rounds_run" --outcome Closes
telemetry seal --run "$rounds_run"
rounds_summary="$(telemetry summary --run "$rounds_run")"
[[ "$(jq -r '.integrity.state' <<<"$rounds_summary")" == valid ]]
[[ "$(jq -r '.start_to_seal_ms | type' <<<"$rounds_summary")" == number ]]
[[ "$(jq -r '.start_to_seal_ms >= 0' <<<"$rounds_summary")" == true ]]

# A seal stamped before its own start describes no interval. The aggregate is
# unavailable rather than clamped, estimated, or fabricated — and unavailability
# is not a telemetry-integrity failure.
backwards_clock_run="$(telemetry start --issue 71)"
telemetry resolve --run "$backwards_clock_run" --outcome Closes
telemetry seal --run "$backwards_clock_run"
backwards_sink="$(sink_for "$backwards_clock_run")"
jq -c 'if .type == "run_sealed" then .epoch_ms = 0 else . end' \
  "$backwards_sink" >"$fixture/backwards.jsonl"
cp "$fixture/backwards.jsonl" "$backwards_sink"
backwards_summary="$(telemetry summary --run "$backwards_clock_run")"
[[ "$(jq -r '.integrity.state' <<<"$backwards_summary")" == valid ]]
[[ "$(jq -r '.start_to_seal_ms' <<<"$backwards_summary")" == null ]]

# Every bounded reason declared by the evaluator must have reached the public
# telemetry summary through one of the fixtures above. Extracting the closed
# vocabulary makes a new reason fail this matrix until its case is added.
mapfile -t declared_integrity_reasons < <(
  grep -oE '"[A-Z][A-Z_]+"' "$telemetry_script" \
    | tr -d '"' | sort -u
)
mapfile -t covered_integrity_reasons < <(
  printf '%s\n' "${!integrity_reasons_covered[@]}" | sort
)
[[ "${#declared_integrity_reasons[@]}" -eq 21 ]]
if ! diff -u \
    <(printf '%s\n' "${declared_integrity_reasons[@]}") \
    <(printf '%s\n' "${covered_integrity_reasons[@]}"); then
  printf 'FAIL[integrity-reason-matrix]: summary coverage drifted\n' >&2
  exit 1
fi

if telemetry start --issue 0 >"$fixture/zero.out" 2>"$fixture/zero.err"; then
  printf 'FAIL[zero-issue]: start accepted a non-positive issue\n' >&2
  exit 1
fi
grep -Fq 'issue must be a positive integer' "$fixture/zero.err"

git -C "$repo" remote set-url origin 'https://example.invalid/not-github.git'
if telemetry start --issue 71 \
    >"$fixture/bad-repository.out" 2>"$fixture/bad-repository.err"; then
  printf 'FAIL[bad-repository]: start accepted malformed repository identity\n' >&2
  exit 1
fi
grep -Fq 'origin must identify a GitHub owner/repository' \
  "$fixture/bad-repository.err"

printf 'work-on schema-2 identity scenarios passed\n'
