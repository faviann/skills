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

# The sink records what this workstation's runs did, so nothing under it is
# readable or writable by anyone else.
assert_private() {
  local path mode
  for path in "$@"; do
    mode="$(stat -c '%a' "$path")"
    if [[ ! "$mode" =~ ^[0-7]00$ ]]; then
      printf 'FAIL[sink-permissions]: %s is mode %s\n' "$path" "$mode" >&2
      exit 1
    fi
  done
}
assert_private "$sink_root" "$sink_root/runs" "$sink_root/current-run" \
  "$sink_root/runs/$first_run.jsonl" "$sink_root/runs/$second_run.jsonl"

# A directory an earlier version left readable is tightened rather than reused
# as it is.
chmod 755 "$sink_root" "$sink_root/runs"
loose_run="$(telemetry start)"
assert_private "$sink_root" "$sink_root/runs" "$sink_root/current-run" \
  "$sink_root/runs/$loose_run.jsonl"

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
# toward the measured bundle; a file the repository ignores does not.
review_bytes() {
  telemetry review --kind readiness --phase checkpoint --round 1 \
    --base "$head_sha" --worktree
  jq -r '[.[] | select(.type == "review" and .kind == "readiness")][-1]
    | .input_bytes' -s "$sink"
}
# What one untracked file contributes to the bundle, computed independently of
# the recorder.
untracked_bundle_bytes() {
  # `--no-index` reports a difference with status 1, which is the expected
  # result here rather than a failure.
  { git -C "$target" -c core.quotePath=false --no-pager diff --no-ext-diff \
    --no-color --no-textconv --no-index -- /dev/null "$1" || true; } \
    | wc -c | tr -d ' '
}
tracked_only_bytes="$(review_bytes)"
printf 'SYNTHETIC-UNTRACKED-CONTENT-MARKER\n' >"$target/untracked.txt"
with_untracked_bytes="$(review_bytes)"
# The file is genuinely untracked at the moment it is measured — the recorder
# does not stage or commit anything to make it countable.
[[ "$(git -C "$target" status --porcelain -- untracked.txt)" == '?? untracked.txt' ]]
[[ $(( with_untracked_bytes - tracked_only_bytes )) \
  -eq "$(untracked_bundle_bytes untracked.txt)" ]]
[[ "$(untracked_bundle_bytes untracked.txt)" \
  -gt "$(wc -c <"$target/untracked.txt")" ]]

# A name needing quoting is passed through exactly, not skipped and not
# mismeasured.
quoted_name='needs "quoting" and spaces.txt'
printf 'SYNTHETIC-QUOTED-NAME-CONTENT-MARKER\n' >"$target/$quoted_name"
with_quoted_bytes="$(review_bytes)"
[[ $(( with_quoted_bytes - with_untracked_bytes )) \
  -eq "$(untracked_bundle_bytes "$quoted_name")" ]]

# A tracked change counts whether it is staged or not, and staging an existing
# change does not change what the sweep is measured to have read.
printf 'SYNTHETIC-WORKTREE-CONTENT-MARKER\n' >>"$target/first.txt"
unstaged_bytes="$(review_bytes)"
[[ "$unstaged_bytes" -gt "$with_quoted_bytes" ]]
git -C "$target" add first.txt
[[ "$(review_bytes)" -eq "$unstaged_bytes" ]]

printf 'ignored.txt\n' >"$target/.gitignore"
printf 'SYNTHETIC-IGNORED-CONTENT-MARKER\n' >"$target/ignored.txt"
git -C "$target" add .gitignore
git -C "$target" commit -qm 'ignore fixture'
head_sha="$(git -C "$target" rev-parse HEAD)"
tracked_only_bytes="$(review_bytes)"
printf 'SYNTHETIC-IGNORED-CONTENT-MARKER\n' >>"$target/ignored.txt"
[[ "$(review_bytes)" -eq "$tracked_only_bytes" ]]

# The whole measurement is the defined bundle and nothing else: tracked changes
# against the base, then every untracked, non-ignored file.
expected_bundle=$(git -C "$target" -c core.quotePath=false --no-pager diff \
  --no-ext-diff --no-color --no-textconv "$head_sha" | wc -c)
while IFS= read -r -d '' candidate; do
  expected_bundle=$(( expected_bundle + $(untracked_bundle_bytes "$candidate") ))
done < <(git -C "$target" ls-files --others --exclude-standard -z)
[[ "$(review_bytes)" -eq "$expected_bundle" ]]

# The bundle is the repository's, not the caller's working directory's: a review
# recorded from a subdirectory measures the same artifact.
mkdir -p "$target/nested"
printf 'SYNTHETIC-NESTED-CONTENT-MARKER\n' >"$target/nested/nested.txt"
nested_bytes="$(review_bytes)"
(cd "$target/nested" && "$command_under_test" review \
  --kind readiness --phase checkpoint --round 1 --base "$head_sha" --worktree)
[[ "$(jq -r '[.[] | select(.type == "review" and .kind == "readiness")][-1]
  | .input_bytes' -s "$sink")" -eq "$nested_bytes" ]]

# `delta` is recordable even though the workflow does not yet run delta review.
telemetry review --kind delta --phase remediation --round 2 \
  --base "$base_sha" --head "$head_sha"
[[ "$(jq -r '.reviews.by_kind.delta' <<<"$(telemetry summary)")" -eq 1 ]]

# 4. A validation execution gets a stable execution id, a duration, and an
# outcome, and the wrapper is transparent to the command's status and output.
telemetry exec --command-id emit-stdout --phase gate --round 1 -- \
  bash -c "$emit_stdout_marker" >"$fixture/passed.out"
grep -Fqx "$stdout_marker" "$fixture/passed.out"

if telemetry exec --command-id emit-stderr --phase gate --round 1 -- \
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
# The supplied identifier is what makes two executions the same validation: the
# same id twice is one identity, a different id is a different one.
telemetry exec --command-id emit-stdout --phase gate --round 1 -- \
  bash -c "$emit_stdout_marker" >/dev/null
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$sink" \
  | sort -u | wc -l)" -eq 3 ]]
[[ "$(jq -r 'select(.type == "validation_start") | .command_id' "$sink" \
  | sort -u | wc -l)" -eq 2 ]]

# An identifier outside the narrow supplied syntax is refused before the command
# runs, so a path, a URL, an argument, or a credential cannot become one.
refuse missing-command-id exec --phase gate --round 1 -- true
rejected_index=0
for rejected_id in 'Work-On-Tests' 'work_on_tests' './scripts/test.sh' \
    'ghp_EXAMPLENOTAREALTOKEN0000000000' 'https://example.invalid/x' \
    'trailing-' '-leading' '1st-check' 'double--hyphen' 'has space' \
    'aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeeff'; do
  refuse "command-id-$rejected_index" exec --command-id "$rejected_id" \
    --phase gate --round 1 -- true
  rejected_index=$((rejected_index + 1))
done
for accepted_id in a lint work-on-tests npm-check-plugin-version check2 \
    aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeee; do
  telemetry exec --command-id "$accepted_id" --phase gate --round 1 -- true
done
[[ "$(jq -r 'select(.type == "validation_start") | .command_id' "$sink" \
  | sort -u | wc -l)" -eq 8 ]]

# 5. An interrupted validation leaves a controlled, machine-readable record.
telemetry exec --command-id self-terminating --phase gate --round 1 -- \
  bash -c 'kill -TERM $PPID; exit 0' >/dev/null 2>&1 || true
[[ "$(jq -r '.validations.interrupted' <<<"$(telemetry summary)")" -eq 1 ]]

# A wrapper killed outright cannot write its own end record; aggregation must
# still report a controlled `incomplete` execution instead of failing.
telemetry exec --command-id self-killing --phase gate --round 1 -- \
  bash -c 'kill -9 $PPID' >/dev/null 2>&1 || true
interrupted_summary="$(telemetry summary)"
[[ "$(jq -r '.validations.incomplete' <<<"$interrupted_summary")" -eq 1 ]]
[[ "$(jq -r '.validations.total' <<<"$interrupted_summary")" -eq 11 ]]
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

# 7/8. Secrets, command output, and repository content stay out of the sink,
# while the command itself is unaffected by being wrapped.
argv_echo="$fixture/argv-echo.sh"
cat >"$argv_echo" <<'EOF'
#!/usr/bin/env bash
printf 'ARGV:%s\n' "$@"
printf 'SYNTHETIC-%s-MARKER\n' DIAGNOSTIC >&2
exit 7
EOF
chmod +x "$argv_echo"

# Every shape the wrapper must never persist: a header value, a bearer token in
# a script's arguments, an environment assignment, a filesystem path, and
# source-shaped text.
sensitive_argv=(
  --header "Authorization: Bearer $fake_token"
  --bearer "$fake_token"
  "AWS_SECRET_ACCESS_KEY=$fake_password"
  /home/example/.config/credential-store.yml
  'const apiKey = "SYNTHETIC-SOURCE-SHAPED-SECRET";'
)
argv_status=0
telemetry exec --command-id argv-passthrough --phase gate --round 1 -- \
  "$argv_echo" "${sensitive_argv[@]}" \
  >"$fixture/argv.out" 2>"$fixture/argv.err" || argv_status=$?

# The command received its arguments exactly, and its stdout, stderr, and exit
# status reached the caller unchanged.
printf 'ARGV:%s\n' "${sensitive_argv[@]}" >"$fixture/argv.expected"
diff -u "$fixture/argv.expected" "$fixture/argv.out"
grep -Fqx "$stderr_marker" "$fixture/argv.err"
[[ "$argv_status" -eq 7 ]]

# Arbitrary inline shell, an environment-assignment prefix, and a command that
# reads repository files are all recorded the same way: by name only.
telemetry exec --command-id shell-inline --phase gate --round 1 -- \
  bash -c 'printf "SYNTHETIC-%s-MARKER\n" INLINE-SHELL; cat first.txt' \
  >/dev/null 2>&1 || true
telemetry exec --command-id prefixed-assignment --phase gate --round 1 -- \
  env "GH_TOKEN=$fake_token" bash -c "$emit_stdout_marker; $emit_stderr_marker" \
  >/dev/null 2>&1
telemetry exec --command-id repository-reader --phase gate --round 1 -- \
  cat first.txt second.txt third.txt >/dev/null 2>&1 || true

for secret in "$fake_token" "$fake_password" "$stdout_marker" \
    "$stderr_marker" SYNTHETIC-INLINE-SHELL-MARKER \
    SYNTHETIC-SOURCE-SHAPED-SECRET SYNTHETIC-FILE-CONTENT-MARKER \
    SYNTHETIC-DIFF-CONTENT-MARKER SYNTHETIC-WORKTREE-CONTENT-MARKER \
    SYNTHETIC-UNTRACKED-CONTENT-MARKER SYNTHETIC-IGNORED-CONTENT-MARKER \
    SYNTHETIC-QUOTED-NAME-CONTENT-MARKER SYNTHETIC-NESTED-CONTENT-MARKER \
    'needs "quoting" and spaces.txt'; do
  if grep -Fqr -- "$secret" "$sink_root"; then
    printf 'FAIL[sink-secrets]: %s reached the telemetry sink\n' "$secret" >&2
    exit 1
  fi
done

# Nothing of the command line reaches the sink: not an argument, not a flag, not
# a path, and not the program either. Only the supplied identifier is stored.
secret_sink="$sink_root/runs/$(telemetry run-id).jsonl"
for fragment in Authorization Bearer --header --bearer \
    AWS_SECRET_ACCESS_KEY GH_TOKEN /home/example apiKey \
    first.txt second.txt third.txt argv-echo.sh \
    bash env cat redacted; do
  if grep -Fq -- "$fragment" "$secret_sink"; then
    printf 'FAIL[sink-argv]: command material %s reached the telemetry sink\n' \
      "$fragment" >&2
    exit 1
  fi
done
for identifier in argv-passthrough shell-inline prefixed-assignment \
    repository-reader; do
  grep -Fq "\"command_id\":\"$identifier\"" "$secret_sink"
done

# The recorder has no field for a prompt, a diff, a file body, a command line,
# or output: every recorded key comes from this closed set.
readonly allowed_keys='["at","base","command_id","duration_ms","epoch_ms","exec_id","exit_status","head","head_is_worktree","input_bytes","kind","outcome","phase","role","round","run","schema","seq","tokens_in","tokens_out","type","workflow"]'
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

# A run resolves its outcome exactly once. A second `finish` is refused rather
# than leaving the run holding two answers.
finished_summary="$(telemetry summary)"
[[ "$(jq -r '.finish_events' <<<"$finished_summary")" -eq 1 ]]
[[ "$(jq -r '.events_after_finish' <<<"$finished_summary")" -eq 0 ]]
refuse second-finish finish --outcome Closes
grep -Fq 'already recorded its final outcome' "$fixture/second-finish.err"
[[ "$(telemetry summary)" == "$finished_summary" ]]

# A finished run's summary is final, not a snapshot: work recorded afterwards is
# reported separately instead of changing counts a published body already
# carried.
telemetry launch --role other --phase closeout --round 9
telemetry exec --command-id after-finish --phase closeout --round 9 -- true
after_finish_summary="$(telemetry summary)"
[[ "$(jq -r '.events_after_finish' <<<"$after_finish_summary")" -eq 3 ]]
for unchanged in .subagent_launches.total .validations.total .events \
    .final_workflow_outcome .finished_at .phase_elapsed_ms; do
  [[ "$(jq -c "$unchanged" <<<"$after_finish_summary")" \
    == "$(jq -c "$unchanged" <<<"$finished_summary")" ]]
done

# 10. Concurrent writers do not lose, fuse, or duplicate events. Several
# subagents and validation wrappers recording at once is the ordinary case.
concurrent_run="$(telemetry start)"
concurrent_sink="$sink_root/runs/$concurrent_run.jsonl"
readonly writers=12
for ((writer = 0; writer < writers; writer++)); do
  telemetry launch --role implementation --phase gate --round 1 &
  telemetry exec --command-id concurrent-check --phase gate --round 1 -- true \
    >/dev/null &
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
# Every retained line is one whole JSON event, so no append landed inside
# another and nothing was lost.
jq -e . "$concurrent_sink" >/dev/null
[[ "$(jq -r '.events' <<<"$concurrent_summary")" -eq $((1 + writers * 3)) ]]
# Sequence numbers and execution ids are allocated exactly once each.
[[ "$(jq -r '.seq' "$concurrent_sink" | sort -u | wc -l)" \
  -eq $((1 + writers * 3)) ]]
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$concurrent_sink" \
  | sort -u | wc -l)" -eq "$writers" ]]
# Every start is closed by exactly one end carrying the same execution id, and
# no end belongs to a start that was never written.
[[ "$(jq -r 'select(.type == "validation_end") | .exec_id' "$concurrent_sink" \
  | sort -u | wc -l)" -eq "$writers" ]]
[[ "$(jq -r 'select(.type | startswith("validation_")) | .exec_id' \
  "$concurrent_sink" | sort | uniq -c | awk '$1 != 2' | wc -l)" -eq 0 ]]
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$concurrent_sink" \
  | sort)" == "$(jq -r 'select(.type == "validation_end") | .exec_id' \
  "$concurrent_sink" | sort)" ]]
assert_private "$concurrent_sink"

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
