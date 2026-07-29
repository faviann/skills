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
  local name="$1" diagnostic="$2"
  if "$command_under_test" 164 "$fixture/$name.md" >"$fixture/$name.out" 2>"$fixture/$name.err"; then
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

printf 'work-on closeout body validator black-box scenarios passed\n'
