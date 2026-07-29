#!/usr/bin/env bash
set -euo pipefail

readonly command_under_test="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/render-closeout.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cat >"$fixture/facts.json" <<'EOF'
{
  "issue_number": 164,
  "outcome": "Closes",
  "acceptance": [
    {
      "criterion": "Canonical closeout is readable",
      "production_path": "`render-closeout.sh`",
      "seam": "Public CLI via a facts file",
      "evidence": "Literal-output scenario",
      "status": "tested"
    }
  ],
  "telemetry": {
    "model_configuration": "gpt-5",
    "wall_clock_elapsed": "42 seconds",
    "implementation_rounds": 1,
    "independent_review_rounds": 1,
    "remediation_rounds": 0,
    "validation_executions": 3,
    "blocking_findings_resolved": 0,
    "findings_rejected_at_adjudication": 0,
    "final_workflow_outcome": "Closes"
  }
}
EOF

cat >"$fixture/narrative.md" <<'EOF'
## Summary

Rendered a readable closeout.

## Validation

- The public CLI scenario passed.

## Finding adjudications

No findings required adjudication.

## Follow-ups

- None.
EOF

cat >"$fixture/expected.md" <<'EOF'
## Issues

Closes #164

## Summary

Rendered a readable closeout.

## Validation

- The public CLI scenario passed.

## Finding adjudications

No findings required adjudication.

## Follow-ups

- None.

## Closure gate

| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |
|---|---|---|---|---|
| Canonical closeout is readable | `render-closeout.sh` | Public CLI via a facts file | Literal-output scenario | tested |

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

"$command_under_test" "$fixture/facts.json" "$fixture/narrative.md" >"$fixture/actual.md"
diff -u "$fixture/expected.md" "$fixture/actual.md"
"$(dirname "$command_under_test")/validate-closeout-body.sh" 164 "$fixture/actual.md"

# stdin is the other documented input mode.
"$command_under_test" - "$fixture/narrative.md" <"$fixture/facts.json" >"$fixture/stdin.md"
diff -u "$fixture/expected.md" "$fixture/stdin.md"

# Table delimiters in free-form facts survive as readable content without
# changing the canonical five-column shape.
jq '.acceptance[0].criterion = "Input | output"' \
  "$fixture/facts.json" >"$fixture/pipe.json"
"$command_under_test" "$fixture/pipe.json" >"$fixture/pipe.md"
grep -Fqx '| Input &#124; output | `render-closeout.sh` | Public CLI via a facts file | Literal-output scenario | tested |' \
  "$fixture/pipe.md"

expect_failure() {
  local name="$1" diagnostic="$2"
  if "$command_under_test" "$fixture/$name.json" >"$fixture/$name.out" 2>"$fixture/$name.err"; then
    printf 'FAIL[%s]: malformed closeout was accepted\n' "$name" >&2
    exit 1
  fi
  [[ ! -s "$fixture/$name.out" ]] || {
    printf 'FAIL[%s]: malformed closeout emitted a body\n' "$name" >&2
    cat "$fixture/$name.out" >&2
    exit 1
  }
  grep -Fqx "closeout invalid: $diagnostic" "$fixture/$name.err" || {
    printf 'FAIL[%s]: expected diagnostic: %s\n' "$name" "$diagnostic" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  }
}

printf '{not json\n' >"$fixture/malformed.json"
expect_failure malformed "facts are not valid JSON"

jq 'del(.acceptance)' "$fixture/facts.json" >"$fixture/missing-acceptance.json"
expect_failure missing-acceptance "acceptance must contain at least one row"

jq '.acceptance[0].status = "instructional"' "$fixture/facts.json" >"$fixture/invalid-status.json"
expect_failure invalid-status 'acceptance row 1 has invalid status: instructional'

jq 'del(.outcome)' "$fixture/facts.json" >"$fixture/missing-outcome.json"
expect_failure missing-outcome "outcome must be Closes or Progresses"

jq '.issue_number = "164"' "$fixture/facts.json" >"$fixture/string-issue.json"
expect_failure string-issue "issue_number must be a positive integer"

jq '.telemetry.final_workflow_outcome = "Progresses"' "$fixture/facts.json" >"$fixture/contradictory-outcome.json"
expect_failure contradictory-outcome "outcome Closes contradicts telemetry outcome Progresses"

jq '.acceptance[0].status = "inferred"' "$fixture/facts.json" >"$fixture/unsupported-close.json"
expect_failure unsupported-close "Closes requires every acceptance row to be tested; row 1 is inferred"

count_fields=(
  implementation_rounds
  independent_review_rounds
  remediation_rounds
  validation_executions
  blocking_findings_resolved
  findings_rejected_at_adjudication
)
for field in "${count_fields[@]}"; do
  jq --arg field "$field" '.telemetry[$field] = "banana"' \
    "$fixture/facts.json" >"$fixture/invalid-$field.json"
  expect_failure "invalid-$field" \
    "telemetry $field must be a nonnegative integer or unknown"
done

jq '
  .telemetry.implementation_rounds = "unknown"
  | .telemetry.independent_review_rounds = "unknown"
  | .telemetry.remediation_rounds = "unknown"
  | .telemetry.validation_executions = "unknown"
  | .telemetry.blocking_findings_resolved = "unknown"
  | .telemetry.findings_rejected_at_adjudication = "unknown"
' "$fixture/facts.json" >"$fixture/unknown-counts.json"
"$command_under_test" "$fixture/unknown-counts.json" >"$fixture/unknown-counts.md"
[[ "$(grep -Fc '| unknown |' "$fixture/unknown-counts.md")" -eq 6 ]]

printf 'work-on closeout renderer black-box scenarios passed\n'
