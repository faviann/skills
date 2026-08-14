#!/usr/bin/env bash
set -euo pipefail

readonly command_under_test="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-closeout-body.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cat >"$fixture/canonical.md" <<'EOF'
## Issues

Closes #164

## Summary

Readable narrative stays readable.

## Closure gate

| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |
|---|---|---|---|---|
| First criterion | `render-closeout.sh` | Public CLI | Literal output | tested |

## Workflow telemetry

| Field | Observed value |
|---|---|
| Model configuration | gpt-5 |
| Wall-clock elapsed | 42 seconds |
| Implementation rounds | 1 |
| Independent-review rounds | 1 |
| Remediation rounds | 0 |
| Validation executions | 3 |
| Blocking findings resolved | 0 |
| Findings rejected at adjudication | 0 |
| Final workflow outcome | Closes |
| Telemetry run | 20260813T101500Z-0123abcd (schema 1) |
| Subagent launches | 4 (implementation=2, review-standards=1, review-spec=1) |
| Reviews recorded | 2 (readiness=1, full=1, delta=0) |
| Validation executions recorded | 3 (passed=3, failed=0) |
| Measured phase elapsed | implementation=120s, gate=60s |
| Workflow provenance | 1 run |

Run 1: work-on:111111111111 workflow:222222222222 tdd:333333333333 review:444444444444 (example/skills@abcdef123456)
EOF

"$command_under_test" 164 "$fixture/canonical.md"
"$command_under_test" 164 - <"$fixture/canonical.md"

# A body edited through GitHub's web UI reads back with CRLF line endings, in
# both documented input modes.
sed 's/$/\r/' "$fixture/canonical.md" >"$fixture/crlf.md"
"$command_under_test" 164 "$fixture/crlf.md"
"$command_under_test" 164 - <"$fixture/crlf.md"
"$command_under_test" --require-closes 164 "$fixture/crlf.md"

sed \
  -e 's/^Closes #164$/Progresses #164/' \
  -e 's/| Final workflow outcome | Closes |/| Final workflow outcome | Progresses |/' \
  "$fixture/canonical.md" >"$fixture/progresses.md"
"$command_under_test" 164 "$fixture/progresses.md"

if "$command_under_test" --require-closes 164 "$fixture/progresses.md" \
    >"$fixture/require-closes.out" 2>"$fixture/require-closes.err"; then
  printf 'FAIL[require-closes]: Progresses was accepted for unattended closeout\n' >&2
  exit 1
fi
[[ ! -s "$fixture/require-closes.out" ]]
grep -Fqx \
  'closeout body invalid: unattended closeout requires Closes #164; found Progresses #164' \
  "$fixture/require-closes.err"
"$command_under_test" --require-closes 164 "$fixture/canonical.md"

expect_failure() {
  local name="$1" diagnostic="$2" body="${3:-$1}" previous="${4:-}"
  local previous_args=()
  [[ -z "$previous" ]] || previous_args=(--previous "$fixture/$previous.md")
  if "$command_under_test" "${previous_args[@]}" 164 "$fixture/$body.md" \
      >"$fixture/$name.out" 2>"$fixture/$name.err"; then
    printf 'FAIL[%s]: malformed body was accepted\n' "$name" >&2
    exit 1
  fi
  [[ ! -s "$fixture/$name.out" ]]
  grep -Fqx "closeout body invalid: $diagnostic" "$fixture/$name.err" || {
    printf 'FAIL[%s]: expected diagnostic: %s\n' "$name" "$diagnostic" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  }
}

# PR #160 shape: renamed heading/header and bullet telemetry.
sed \
  -e 's/^## Closure gate$/## Acceptance closure/' \
  -e 's/| Acceptance criterion |/| Criterion |/' \
  -e '/^## Workflow telemetry$/,$d' \
  "$fixture/canonical.md" >"$fixture/pr-160.md"
cat >>"$fixture/pr-160.md" <<'EOF'
## Workflow telemetry

- Final workflow outcome: Closes
EOF
expect_failure pr-160 "missing canonical heading: ## Closure gate"

# PR #162 shape: a mechanism trace table exists but has no closure statuses.
sed '/^## Closure gate$/,$d' "$fixture/canonical.md" >"$fixture/pr-162.md"
cat >>"$fixture/pr-162.md" <<'EOF'
## Closure gate

| Mechanism | Acceptance criterion |
|---|---|
| Renderer | First criterion |

## Workflow telemetry

| Field | Observed value |
|---|---|
| Model configuration | gpt-5 |
| Wall-clock elapsed | 42 seconds |
| Implementation rounds | 1 |
| Independent-review rounds | 1 |
| Remediation rounds | 0 |
| Validation executions | 3 |
| Blocking findings resolved | 0 |
| Findings rejected at adjudication | 0 |
| Final workflow outcome | Closes |
| Telemetry run | 20260813T101500Z-0123abcd (schema 1) |
| Subagent launches | 4 (implementation=2, review-standards=1, review-spec=1) |
| Reviews recorded | 2 (readiness=1, full=1, delta=0) |
| Validation executions recorded | 3 (passed=3, failed=0) |
| Measured phase elapsed | implementation=120s, gate=60s |
| Workflow provenance | 1 run |

Run 1: work-on:111111111111 workflow:222222222222 tdd:333333333333 review:444444444444 (example/skills@abcdef123456)
EOF
expect_failure pr-162 "missing canonical closure gate table header"

sed 's/| tested |$/| instructional |/' "$fixture/canonical.md" >"$fixture/invalid-status.md"
expect_failure invalid-status "closure gate row 1 has invalid status: instructional"

for status in failing inferred unverified; do
  sed "s/| tested |\$/| $status |/" "$fixture/canonical.md" \
    >"$fixture/closes-$status.md"
  expect_failure "closes-$status" \
    "Closes requires every closure gate row to be tested; row 1 is $status"
done

sed 's/| Final workflow outcome | Closes |/| Final workflow outcome | Progresses |/' \
  "$fixture/canonical.md" >"$fixture/contradiction.md"
expect_failure contradiction "issue outcome Closes contradicts telemetry outcome Progresses"

sed '/| First criterion /d' "$fixture/canonical.md" >"$fixture/missing-row.md"
expect_failure missing-row "closure gate must contain at least one acceptance row"

count_fields=(
  "Implementation rounds"
  "Independent-review rounds"
  "Remediation rounds"
  "Validation executions"
  "Blocking findings resolved"
  "Findings rejected at adjudication"
)
for ((index = 0; index < ${#count_fields[@]}; index++)); do
  field="${count_fields[$index]}"
  sed "s/| $field | [^|]* |/| $field | banana |/" \
    "$fixture/canonical.md" >"$fixture/invalid-count-$index.md"
  expect_failure "invalid-count-$index" \
    "workflow telemetry $field must be a nonnegative integer or unknown"
done

cp "$fixture/canonical.md" "$fixture/unknown-counts.md"
for field in "${count_fields[@]}"; do
  sed "s/| $field | [^|]* |/| $field | unknown |/" \
    "$fixture/unknown-counts.md" >"$fixture/unknown-counts.next"
  mv "$fixture/unknown-counts.next" "$fixture/unknown-counts.md"
done
"$command_under_test" 164 "$fixture/unknown-counts.md"

sed -e '/| Workflow provenance |/d' -e '/^Run 1: /d' "$fixture/canonical.md" \
  >"$fixture/short-telemetry-table.md"
expect_failure short-telemetry-table \
  "workflow telemetry must contain fifteen canonical rows"

# The sink-derived rows are mechanically rendered, so a hand-written value in
# any of them is rejected rather than published as observed telemetry.
sink_rows=(
  "Telemetry run|not-a-run-id (schema 1)"
  "Telemetry run|20260813T101500Z-0123abcd"
  "Subagent launches|four"
  "Subagent launches|4 (implementation=2"
  "Reviews recorded|2 (readiness=1, full=1)"
  "Reviews recorded|several"
  "Validation executions recorded|3"
  "Validation executions recorded|3 (passed=3, failed=0, flaky=1)"
  "Measured phase elapsed|implementation=120"
  "Measured phase elapsed|about two minutes"
)
for ((index = 0; index < ${#sink_rows[@]}; index++)); do
  field="${sink_rows[$index]%%|*}"
  value="${sink_rows[$index]#*|}"
  awk -v field="$field" -v value="$value" -F'|' '
    {
      cell = $2
      gsub(/^[ \t]+|[ \t]+$/, "", cell)
      if (cell == field) { printf "| %s | %s |\n", field, value; next }
      print
    }
  ' "$fixture/canonical.md" >"$fixture/malformed-sink-$index.md"
  expect_failure "malformed-sink-$index" \
    "workflow telemetry $field is malformed"
done

# A run that recorded nothing in any phase still renders a valid row.
sed 's/| Measured phase elapsed | [^|]* |/| Measured phase elapsed | unknown |/' \
  "$fixture/canonical.md" >"$fixture/unmeasured-phases.md"
"$command_under_test" 164 "$fixture/unmeasured-phases.md"

# A run with no launches renders a bare zero rather than an empty breakdown.
sed 's/| Subagent launches | [^|]* |/| Subagent launches | 0 |/' \
  "$fixture/canonical.md" >"$fixture/no-launches.md"
"$command_under_test" 164 "$fixture/no-launches.md"

sed 's/work-on:111111111111/work-on:NOT-A-DIGEST/' \
  "$fixture/canonical.md" >"$fixture/malformed-provenance.md"
expect_failure malformed-provenance "workflow provenance run 1 is malformed"

sed $'/^Run 1: /s/ /\t/3g' \
  "$fixture/canonical.md" >"$fixture/tab-separated-provenance.md"
expect_failure tab-separated-provenance "workflow provenance run 1 is malformed"

# The trailing pointer always carries a commit, and the workflow digest never
# carries a repository suffix.
sed 's/(example\/skills@abcdef123456)/(example\/skills)/' \
  "$fixture/canonical.md" >"$fixture/pointer-without-sha.md"
expect_failure pointer-without-sha "workflow provenance run 1 is malformed"
sed 's/workflow:222222222222/workflow:222222222222@example\/target/' \
  "$fixture/canonical.md" >"$fixture/workflow-suffix.md"
expect_failure workflow-suffix "workflow provenance run 1 is malformed"

# An unknown skills origin still carries a commit.
sed 's/(example\/skills@abcdef123456)/(unknown@abcdef123456)/' \
  "$fixture/canonical.md" >"$fixture/unknown-pointer.md"
"$command_under_test" 164 "$fixture/unknown-pointer.md"

# The run count agrees with its plural and with the number of run lines.
for malformed_count in '0 runs' '1 runs' 'mixed (2 phases)'; do
  sed "s/| Workflow provenance |.*|/| Workflow provenance | $malformed_count |/" \
    "$fixture/canonical.md" >"$fixture/malformed-count.md"
  expect_failure malformed-count "workflow provenance is malformed"
done

sed 's/| Workflow provenance |.*|/| Workflow provenance | 2 runs |/' \
  "$fixture/canonical.md" >"$fixture/run-count.md"
expect_failure run-count \
  "workflow provenance run count does not match run lines"

sed 's/| Workflow provenance |.*|/| Workflow provenance | 2 runs |/' \
  "$fixture/canonical.md" >"$fixture/two-runs.md"
cat >>"$fixture/two-runs.md" <<'EOF'
Run 2: work-on:aaaaaaaaaaaa* workflow:bbbbbbbbbbbb* tdd:cccccccccccc* review:dddddddddddd* (example/skills@123456789abc)
EOF
"$command_under_test" --previous "$fixture/canonical.md" 164 "$fixture/two-runs.md"

sed 's/^Run 2: /Run 3: /' "$fixture/two-runs.md" >"$fixture/out-of-order.md"
expect_failure out-of-order \
  "workflow provenance run 2 is malformed or out of order"

sed 's/| Workflow provenance |.*|/| Workflow provenance | 10 runs |/' \
  "$fixture/canonical.md" >"$fixture/ten-runs.md"
sed -i '/^Run 1: /d' "$fixture/ten-runs.md"
for run_number in {1..10}; do
  printf 'Run %s: work-on:111111111111 workflow:222222222222 tdd:333333333333 review:444444444444 (example/skills@abcdef123456)\n' \
    "$run_number" >>"$fixture/ten-runs.md"
done
"$command_under_test" 164 "$fixture/ten-runs.md"

expect_failure unchanged-body \
  "workflow provenance must append exactly one run" canonical canonical

# One root run appends one entry. Two at once cannot have come from a single
# ledger, so the extra entry is unattributable.
sed 's/| Workflow provenance |.*|/| Workflow provenance | 3 runs |/' \
  "$fixture/two-runs.md" >"$fixture/three-runs.md"
cat >>"$fixture/three-runs.md" <<'EOF'
Run 3: work-on:eeeeeeeeeeee workflow:ffffffffffff tdd:111111111111 review:222222222222 (example/skills@456789abcdef)
EOF
"$command_under_test" 164 "$fixture/three-runs.md"
expect_failure two-appended \
  "workflow provenance must append exactly one run" three-runs canonical

# `unknown` is a permitted starting state, but replacing a known count with it
# discards a lower bound the pull request had already established.
sed 's/| Validation executions | 3 |/| Validation executions | unknown |/' \
  "$fixture/two-runs.md" >"$fixture/count-to-unknown.md"
expect_failure count-to-unknown \
  "workflow telemetry Validation executions became unknown after 3" \
  count-to-unknown canonical

# An unknown count may still stay unknown, and may become known.
sed -e 's/| Validation executions | 3 |/| Validation executions | unknown |/' \
  "$fixture/canonical.md" >"$fixture/unknown-previous.md"
"$command_under_test" --previous "$fixture/unknown-previous.md" \
  164 "$fixture/two-runs.md"
sed 's/| Validation executions | 3 |/| Validation executions | unknown |/' \
  "$fixture/two-runs.md" >"$fixture/unknown-both.md"
"$command_under_test" --previous "$fixture/unknown-previous.md" \
  164 "$fixture/unknown-both.md"

sed 's/| Validation executions | 3 |/| Validation executions | 2 |/' \
  "$fixture/two-runs.md" >"$fixture/decreased-count.md"
expect_failure decreased-count \
  "workflow telemetry Validation executions decreased from 3 to 2" \
  decreased-count canonical

expect_failure dropped-runs \
  "workflow provenance dropped previous runs" canonical two-runs

sed 's/^Run 1: work-on:111111111111/Run 1: work-on:999999999999/' \
  "$fixture/two-runs.md" >"$fixture/rewritten.md"
expect_failure rewritten-run \
  "workflow provenance rewrote previous run 1" rewritten two-runs

printf 'work-on closeout body validator black-box scenarios passed\n'
