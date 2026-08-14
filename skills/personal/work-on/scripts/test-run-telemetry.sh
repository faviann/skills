#!/usr/bin/env bash
set -euo pipefail

# Black-box scenarios for the run-scoped telemetry sink. Every assertion goes
# through the shipped command's public subcommands; nothing reaches into the
# sink's storage layout except to prove what is and is not stored there.

readonly source_script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly command_under_test="$source_script_root/run-telemetry.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

target="$fixture/target"
git init -q -b main "$target"
git -C "$target" config user.name 'Telemetry Test'
git -C "$target" config user.email telemetry@example.invalid
printf 'SYNTHETIC-FILE-CONTENT-MARKER\n' >"$target/first.txt"
git -C "$target" add .
git -C "$target" commit -qm 'first'

telemetry() {
  (cd "$target" && "$command_under_test" "$@")
}
sink_root="$target/.git/work-on-telemetry"

# Visibly synthetic stand-ins for material that must never reach the sink. The
# output markers are assembled at run time so that proving they are absent from
# the sink proves the recorder discarded the command's output, not merely that
# the literal never appeared in an argument.
readonly fake_token='ghp_EXAMPLENOTAREALTOKEN0000000000'
readonly fake_password='SYNTHETIC-NOT-A-REAL-PASSWORD'
readonly stdout_marker='SYNTHETIC-OUTPUT-MARKER'
readonly stderr_marker='SYNTHETIC-DIAGNOSTIC-MARKER'
readonly emit_stdout_marker='printf "SYNTHETIC-%s-MARKER\n" OUTPUT'
readonly emit_stderr_marker='printf "SYNTHETIC-%s-MARKER\n" DIAGNOSTIC >&2'

# 1. A run is created, identified, and kept separate from any other run.
first_run="$(telemetry start)"
[[ "$first_run" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$ ]]
[[ "$(telemetry run-id)" == "$first_run" ]]
telemetry launch --role implementation --phase implementation --round 1
telemetry launch --role readiness --phase checkpoint --round 1

second_run="$(telemetry start)"
[[ "$second_run" != "$first_run" ]]
[[ "$(telemetry run-id)" == "$second_run" ]]
telemetry launch --role review-spec --phase gate --round 2

first_summary="$(telemetry summary --run "$first_run")"
second_summary="$(telemetry summary --run "$second_run")"
[[ "$(jq -r '.subagent_launches.total' <<<"$first_summary")" -eq 2 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$second_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role."review-spec"' <<<"$first_summary")" -eq 0 ]]
[[ "$(jq -r '.subagent_launches.by_role.implementation' <<<"$second_summary")" -eq 0 ]]
[[ "$(jq -r '.run' <<<"$first_summary")" == "$first_run" ]]

# The sink lives inside the git directory, so it is untracked by construction
# and no telemetry command dirties the worktree.
[[ -z "$(git -C "$target" status --porcelain)" ]]
[[ -d "$sink_root" ]]

# 2. A launch retains its role, phase, and round.
work_run="$(telemetry start)"
telemetry launch --role implementation --phase implementation --round 1
telemetry launch --role review-standards --phase gate --round 2
telemetry launch --role review-spec --phase gate --round 2
telemetry launch --role closure-sweep --phase closeout --round 2
sink="$sink_root/runs/$work_run.jsonl"
launch_rows="$(jq -c 'select(.type == "subagent_launch")
  | [.role, .phase, .round]' "$sink")"
grep -Fqx '["implementation","implementation",1]' <<<"$launch_rows"
grep -Fqx '["review-standards","gate",2]' <<<"$launch_rows"
grep -Fqx '["closure-sweep","closeout",2]' <<<"$launch_rows"

# An unknown role, phase, kind, or round is refused rather than recorded.
refuse() {
  local label="$1"
  shift
  if telemetry "$@" >"$fixture/$label.out" 2>"$fixture/$label.err"; then
    printf 'FAIL[%s]: telemetry accepted %s\n' "$label" "$*" >&2
    exit 1
  fi
  [[ ! -s "$fixture/$label.out" ]]
}
refuse bad-role launch --role reviewer --phase gate --round 1
refuse bad-phase launch --role implementation --phase deploy --round 1
refuse bad-round launch --role implementation --phase gate --round -1
refuse bad-kind review --kind smoke --phase gate --round 1 --base HEAD --worktree
refuse bad-outcome finish --outcome merged

# 3. A review retains kind, compared SHAs, and input byte count.
base_sha="$(git -C "$target" rev-parse HEAD)"
printf 'SYNTHETIC-DIFF-CONTENT-MARKER\n' >"$target/second.txt"
git -C "$target" add .
git -C "$target" commit -qm 'second'
head_sha="$(git -C "$target" rev-parse HEAD)"
expected_bytes="$(git -C "$target" diff "$base_sha...$head_sha" | wc -c | tr -d ' ')"
[[ "$expected_bytes" -gt 0 ]]

telemetry review --kind full --phase gate --round 1 \
  --base "$base_sha" --head "$head_sha"
full_review="$(jq -c 'select(.type == "review" and .kind == "full")' "$sink")"
[[ "$(jq -r '.base' <<<"$full_review")" == "$base_sha" ]]
[[ "$(jq -r '.head' <<<"$full_review")" == "$head_sha" ]]
[[ "$(jq -r '.input_bytes' <<<"$full_review")" -eq "$expected_bytes" ]]
[[ "$(jq -r '.head_is_worktree' <<<"$full_review")" == false ]]
[[ "$(jq -r '.phase' <<<"$full_review")" == gate ]]
[[ "$(jq -r '.round' <<<"$full_review")" -eq 1 ]]

# A readiness sweep reads the worktree before the first commit, so its compared
# material is the uncommitted diff against the recorded base.
printf 'SYNTHETIC-WORKTREE-CONTENT-MARKER\n' >"$target/third.txt"
git -C "$target" add third.txt
worktree_bytes="$(git -C "$target" diff "$head_sha" | wc -c | tr -d ' ')"
[[ "$worktree_bytes" -gt 0 ]]
telemetry review --kind readiness --phase checkpoint --round 1 \
  --base "$head_sha" --worktree
readiness_review="$(jq -c 'select(.type == "review" and .kind == "readiness")' "$sink")"
[[ "$(jq -r '.head_is_worktree' <<<"$readiness_review")" == true ]]
[[ "$(jq -r '.input_bytes' <<<"$readiness_review")" -eq "$worktree_bytes" ]]

# A file git does not track yet is still material the sweep reads, so it counts
# toward the compared bytes; a file the repository ignores does not.
review_bytes() {
  telemetry review --kind readiness --phase checkpoint --round 1 \
    --base "$head_sha" --worktree
  jq -r '[.[] | select(.type == "review" and .kind == "readiness")][-1]
    | .input_bytes' -s "$sink"
}
tracked_only_bytes="$(review_bytes)"
printf 'SYNTHETIC-UNTRACKED-CONTENT-MARKER\n' >"$target/untracked.txt"
with_untracked_bytes="$(review_bytes)"
[[ "$with_untracked_bytes" -gt "$tracked_only_bytes" ]]
[[ $(( with_untracked_bytes - tracked_only_bytes )) -ge \
  $(wc -c <"$target/untracked.txt") ]]

printf 'ignored.txt\n' >"$target/.gitignore"
printf 'SYNTHETIC-IGNORED-CONTENT-MARKER\n' >"$target/ignored.txt"
git -C "$target" add .gitignore
git -C "$target" commit -qm 'ignore fixture'
head_sha="$(git -C "$target" rev-parse HEAD)"
tracked_only_bytes="$(review_bytes)"
printf 'SYNTHETIC-IGNORED-CONTENT-MARKER\n' >>"$target/ignored.txt"
[[ "$(review_bytes)" -eq "$tracked_only_bytes" ]]

# `delta` is recordable even though the workflow does not yet run delta review.
telemetry review --kind delta --phase remediation --round 2 \
  --base "$base_sha" --head "$head_sha"
[[ "$(jq -r '.reviews.by_kind.delta' <<<"$(telemetry summary)")" -eq 1 ]]

# 4. A validation execution gets a stable execution id, a duration, and an
# outcome, and the wrapper is transparent to the command's status and output.
telemetry exec --phase gate --round 1 -- \
  bash -c "$emit_stdout_marker" >"$fixture/passed.out"
grep -Fqx "$stdout_marker" "$fixture/passed.out"

if telemetry exec --phase gate --round 1 -- \
    bash -c "$emit_stderr_marker; exit 3" \
    >"$fixture/failed.out" 2>"$fixture/failed.err"; then
  printf 'FAIL[exec-status]: a failing command reported success\n' >&2
  exit 1
fi
grep -Fqx "$stderr_marker" "$fixture/failed.err"

passed_id="$(jq -r 'select(.type == "validation_end" and .outcome == "passed")
  | .exec_id' "$sink")"
failed_id="$(jq -r 'select(.type == "validation_end" and .outcome == "failed")
  | .exec_id' "$sink")"
[[ "$passed_id" != "$failed_id" ]]
# The id is stable across the execution: its start and end carry the same one.
[[ "$(jq -r "select(.exec_id == \"$passed_id\") | .type" "$sink" | sort | tr '\n' ' ')" \
  == 'validation_end validation_start ' ]]
[[ "$(jq -r "select(.type == \"validation_end\" and .exec_id == \"$failed_id\")
  | .exit_status" "$sink")" -eq 3 ]]
jq -e 'select(.type == "validation_end")
  | .duration_ms | type == "number" and . >= 0' "$sink" >/dev/null
# The same command text keeps one command identity across executions, and a
# different command gets a different one.
telemetry exec --phase gate --round 1 -- \
  bash -c "$emit_stdout_marker" >/dev/null
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$sink" \
  | sort -u | wc -l)" -eq 3 ]]
[[ "$(jq -r 'select(.type == "validation_start") | .command_id' "$sink" \
  | sort -u | wc -l)" -eq 2 ]]

# 5. An interrupted validation leaves a controlled, machine-readable record.
telemetry exec --phase gate --round 1 -- \
  bash -c 'kill -TERM $PPID; exit 0' >/dev/null 2>&1 || true
[[ "$(jq -r '.validations.interrupted' <<<"$(telemetry summary)")" -eq 1 ]]

# A wrapper killed outright cannot write its own end record; aggregation must
# still report a controlled `incomplete` execution instead of failing.
telemetry exec --phase gate --round 1 -- \
  bash -c 'kill -9 $PPID' >/dev/null 2>&1 || true
interrupted_summary="$(telemetry summary)"
[[ "$(jq -r '.validations.incomplete' <<<"$interrupted_summary")" -eq 1 ]]
[[ "$(jq -r '.validations.total' <<<"$interrupted_summary")" -eq 5 ]]
[[ "$(jq -r '.malformed_lines' <<<"$interrupted_summary")" -eq 0 ]]

# The sink survives the interruption: every line is still one JSON event and
# later recording continues in the same run.
jq -e . "$sink" >/dev/null
telemetry launch --role implementation --phase remediation --round 3
[[ "$(jq -r '.subagent_launches.total' <<<"$(telemetry summary)")" -eq 5 ]]

# A line the recorder did not write is ignored rather than corrupting the run.
printf 'not json\n' >>"$sink"
truncated_summary="$(telemetry summary)"
[[ "$(jq -r '.malformed_lines' <<<"$truncated_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$truncated_summary")" -eq 5 ]]

# 6. Token counts are optional at every stage.
[[ "$(jq -r '.tokens.coverage' <<<"$truncated_summary")" == none ]]
[[ "$(jq -r '.tokens.input' <<<"$truncated_summary")" -eq 0 ]]
telemetry launch --role review-standards --phase gate --round 3 \
  --tokens-in 1200 --tokens-out 340
partial_summary="$(telemetry summary)"
[[ "$(jq -r '.tokens.coverage' <<<"$partial_summary")" == partial ]]
[[ "$(jq -r '.tokens.input' <<<"$partial_summary")" -eq 1200 ]]
[[ "$(jq -r '.tokens.output' <<<"$partial_summary")" -eq 340 ]]

token_free_run="$(telemetry start)"
telemetry launch --role implementation --phase implementation --round 1
token_free_summary="$(telemetry summary)"
[[ "$(jq -r '.tokens.coverage' <<<"$token_free_summary")" == none ]]
[[ "$(jq -r '.run' <<<"$token_free_summary")" == "$token_free_run" ]]

# 7/8. Secrets, command output, and repository content stay out of the sink.
telemetry exec --phase gate --round 1 -- \
  env "GH_TOKEN=$fake_token" bash -c "$emit_stdout_marker; $emit_stderr_marker" \
  >/dev/null 2>&1
telemetry exec --phase gate --round 1 -- \
  ./login.sh --password "$fake_password" >/dev/null 2>&1 || true
telemetry exec --phase gate --round 1 -- \
  ./login.sh "--api-key=$fake_token" >/dev/null 2>&1 || true
telemetry exec --phase gate --round 1 -- \
  ./login.sh "$fake_token" >/dev/null 2>&1 || true
telemetry exec --phase gate --round 1 -- \
  cat first.txt second.txt third.txt >/dev/null 2>&1 || true

for secret in "$fake_token" "$fake_password" "$stdout_marker" \
    "$stderr_marker" SYNTHETIC-FILE-CONTENT-MARKER \
    SYNTHETIC-DIFF-CONTENT-MARKER SYNTHETIC-WORKTREE-CONTENT-MARKER \
    SYNTHETIC-UNTRACKED-CONTENT-MARKER SYNTHETIC-IGNORED-CONTENT-MARKER; do
  if grep -Fqr -- "$secret" "$sink_root"; then
    printf 'FAIL[sink-secrets]: %s reached the telemetry sink\n' "$secret" >&2
    exit 1
  fi
done

# No argument reaches the sink at all — not the secret ones, and not the
# innocuous ones either. Only the program's own name is legible.
secret_sink="$sink_root/runs/$(telemetry run-id).jsonl"
for argument in GH_TOKEN --password --api-key ./login.sh \
    first.txt second.txt third.txt redacted; do
  if grep -Fq -- "$argument" "$secret_sink"; then
    printf 'FAIL[sink-argv]: argument %s reached the telemetry sink\n' \
      "$argument" >&2
    exit 1
  fi
done
for program in '"program":"cat"' '"program":"env"' '"program":"login.sh"'; do
  grep -Fq "$program" "$secret_sink"
done

# A secret is not in the identifier's input either: the same command run with
# two different credentials keeps one command identity.
telemetry exec --phase gate --round 1 -- \
  ./login.sh --password 'SYNTHETIC-FIRST-NOT-A-REAL-PASSWORD' >/dev/null 2>&1 || true
telemetry exec --phase gate --round 1 -- \
  ./login.sh --password 'SYNTHETIC-SECOND-NOT-A-REAL-PASSWORD' >/dev/null 2>&1 || true
[[ "$(jq -r 'select(.type == "validation_start" and .program == "login.sh")
  | .command_id' "$secret_sink" | tail -2 | sort -u | wc -l)" -eq 1 ]]

# The recorder has no field for a prompt, a diff, a file body, or output: every
# recorded key comes from this closed set.
readonly allowed_keys='["at","base","command_id","duration_ms","epoch_ms","exec_id","exit_status","head","head_is_worktree","input_bytes","kind","outcome","phase","program","role","round","run","schema","seq","tokens_in","tokens_out","type","workflow"]'
for run_sink in "$sink_root"/runs/*.jsonl; do
  unexpected="$(jq -r -R --argjson allowed "$allowed_keys" '
    fromjson? // empty | keys[]
    | . as $key | select(($allowed | index($key)) == null)
  ' <"$run_sink" | sort -u)"
  [[ -z "$unexpected" ]] || {
    printf 'FAIL[sink-keys]: unexpected key(s) in %s: %s\n' \
      "$run_sink" "$unexpected" >&2
    exit 1
  }
done

# 9. Aggregation is a deterministic function of the sink.
repeat_one="$(telemetry summary)"
repeat_two="$(telemetry summary)"
repeat_three="$(telemetry summary --run "$(telemetry run-id)")"
[[ "$repeat_one" == "$repeat_two" ]]
[[ "$repeat_one" == "$repeat_three" ]]

# The final workflow outcome is recorded and aggregated.
[[ "$(jq -r '.final_workflow_outcome' <<<"$repeat_one")" == null ]]
telemetry finish --outcome Progresses
[[ "$(jq -r '.final_workflow_outcome' <<<"$(telemetry summary)")" == Progresses ]]

# Phase elapsed is reported only for phases that actually recorded events, in a
# fixed order. This run touched implementation and gate and nothing else.
phase_keys="$(jq -r '.phase_elapsed_ms | keys_unsorted | join(",")' \
  <<<"$(telemetry summary)")"
[[ "$phase_keys" == implementation,gate ]]

# 10. Concurrent writers do not lose, fuse, or duplicate events. Several
# subagents and validation wrappers recording at once is the ordinary case.
concurrent_run="$(telemetry start)"
concurrent_sink="$sink_root/runs/$concurrent_run.jsonl"
readonly writers=12
for ((writer = 0; writer < writers; writer++)); do
  telemetry launch --role implementation --phase gate --round 1 &
  telemetry exec --phase gate --round 1 -- true >/dev/null &
done
wait

concurrent_summary="$(telemetry summary --run "$concurrent_run")"
[[ "$(jq -r '.malformed_lines' <<<"$concurrent_summary")" -eq 0 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$concurrent_summary")" -eq "$writers" ]]
[[ "$(jq -r '.validations.total' <<<"$concurrent_summary")" -eq "$writers" ]]
[[ "$(jq -r '.validations.passed' <<<"$concurrent_summary")" -eq "$writers" ]]
[[ "$(jq -r '.validations.incomplete' <<<"$concurrent_summary")" -eq 0 ]]
# One run_start, one launch per writer, and a start plus an end per execution.
[[ "$(wc -l <"$concurrent_sink")" -eq $((1 + writers * 3)) ]]
# Every line parsed, so no append landed inside another.
[[ "$(jq -r '.events' <<<"$concurrent_summary")" -eq $((1 + writers * 3)) ]]
# Sequence numbers and execution ids are allocated exactly once each.
[[ "$(jq -r '.seq' "$concurrent_sink" | sort -u | wc -l)" \
  -eq $((1 + writers * 3)) ]]
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$concurrent_sink" \
  | sort -u | wc -l)" -eq "$writers" ]]

# 11. A writer killed mid-append leaves a line with no terminator. The next
# append closes it off rather than fusing with it, so one torn line costs one
# malformed line and nothing else.
torn_run="$(telemetry start)"
torn_sink="$sink_root/runs/$torn_run.jsonl"
printf '{"schema":1,"run":"%s","seq":2,"type":"subagent_lau' "$torn_run" \
  >>"$torn_sink"
telemetry launch --role other --phase closeout --round 1
torn_summary="$(telemetry summary --run "$torn_run")"
[[ "$(jq -r '.malformed_lines' <<<"$torn_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$torn_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role.other' <<<"$torn_summary")" -eq 1 ]]
# The recovered event is a whole line of its own, and the torn one still ends
# where it was cut.
[[ "$(wc -l <"$torn_sink")" -eq 3 ]]
grep -Fqx '{"schema":1,"run":"'"$torn_run"'","seq":2,"type":"subagent_lau' \
  "$torn_sink"
[[ "$(jq -R -r 'fromjson? // empty
  | select(.type == "subagent_launch") | .seq' "$torn_sink")" -eq 3 ]]

# Recording outside a started run is refused rather than silently dropped.
bare="$fixture/bare"
git init -q -b main "$bare"
if (cd "$bare" && "$command_under_test" launch \
    --role implementation --phase gate --round 1) \
    >"$fixture/bare.out" 2>"$fixture/bare.err"; then
  printf 'FAIL[bare]: telemetry recorded without a started run\n' >&2
  exit 1
fi
[[ ! -s "$fixture/bare.out" ]]
grep -Fq 'no active telemetry run' "$fixture/bare.err"

# Telemetry requires a Git-backed target repository.
if (cd "$fixture" && "$command_under_test" start) \
    >"$fixture/non-git.out" 2>"$fixture/non-git.err"; then
  printf 'FAIL[non-git]: telemetry started outside a repository\n' >&2
  exit 1
fi
[[ ! -s "$fixture/non-git.out" ]]

printf 'work-on run telemetry black-box scenarios passed\n'
