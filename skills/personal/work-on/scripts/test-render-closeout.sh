#!/usr/bin/env bash
set -euo pipefail

readonly source_script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

skills_checkout="$fixture/skills-checkout"
mkdir -p "$skills_checkout/skills/personal" "$skills_checkout/skills/engineering"
cp -R "$source_script_root/.." "$skills_checkout/skills/personal/work-on"
cp -R "$source_script_root/../../../engineering/tdd" \
  "$skills_checkout/skills/engineering/tdd"
cp -R "$source_script_root/../../../engineering/code-review" \
  "$skills_checkout/skills/engineering/code-review"
git -C "$skills_checkout" init -q -b main
git -C "$skills_checkout" config user.name 'Closeout Test'
git -C "$skills_checkout" config user.email closeout@example.invalid
git -C "$skills_checkout" add .
git -C "$skills_checkout" commit -qm fixture
git -C "$skills_checkout" remote add origin \
  'https://github.com/example/skills.git'

readonly command_under_test="$skills_checkout/skills/personal/work-on/scripts/render-closeout.sh"
target_checkout="$fixture/target-checkout"
git init -q -b main "$target_checkout"
git -C "$target_checkout" config user.name 'Closeout Test'
git -C "$target_checkout" config user.email closeout@example.invalid
touch "$target_checkout/.keep"
git -C "$target_checkout" add .
git -C "$target_checkout" commit -qm fixture
ledger="$target_checkout/.git/work-on-provenance.json"
(
  cd "$target_checkout"
  "$(dirname "$command_under_test")/workflow-provenance.sh" capture
)
provenance="$(
  cd "$target_checkout"
  "$(dirname "$command_under_test")/workflow-provenance.sh" verify
)"

# The bounded telemetry rows come from the run-scoped sink, so the renderer
# needs a started run. One event per phase keeps the rendered elapsed values
# deterministic without pinning the fixture to a clock.
telemetry() {
  (cd "$target_checkout" && \
    "$(dirname "$command_under_test")/run-telemetry.sh" "$@")
}
telemetry_dir="$target_checkout/.git/work-on-telemetry"
telemetry_run="$(telemetry start)"
telemetry launch --role implementation --phase implementation --round 1
telemetry launch --role review-standards --phase gate --round 1
telemetry review --kind full --phase gate --round 1 \
  --base HEAD --head HEAD

run_new() {
  (
    cd "$target_checkout"
    "$command_under_test" "$@" --new-pr
  )
}

cat >"$fixture/facts.json" <<'EOF'
{
  "issue_number": 164,
  "outcome": "Closes",
  "acceptance_criteria": [
    "Canonical closeout is readable"
  ],
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

## Narrative

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
| Telemetry run | TELEMETRY_RUN (schema 1) |
| Subagent launches | 2 (implementation=1, review-standards=1) |
| Reviews recorded | 1 (readiness=0, full=1, delta=0) |
| Validation executions recorded | 0 (passed=0, failed=0) |
| Measured phase elapsed | implementation=0s, gate=0s |
| Workflow provenance | 1 run |

Run 1: PROVENANCE
EOF
awk -v provenance="$provenance" -v telemetry_run="$telemetry_run" \
  '{ sub(/PROVENANCE/, provenance); sub(/TELEMETRY_RUN/, telemetry_run); print }' \
  "$fixture/expected.md" >"$fixture/expected.with-provenance.md"
mv "$fixture/expected.with-provenance.md" "$fixture/expected.md"

run_new "$fixture/facts.json" "$fixture/narrative.md" >"$fixture/actual.md"
diff -u "$fixture/expected.md" "$fixture/actual.md"
"$(dirname "$command_under_test")/validate-closeout-body.sh" 164 "$fixture/actual.md"

# stdin is the other documented input mode.
run_new - "$fixture/narrative.md" <"$fixture/facts.json" >"$fixture/stdin.md"
diff -u "$fixture/expected.md" "$fixture/stdin.md"

# The pull-request body carries bounded summaries of the run-scoped sink, never
# its individual events. Growing the sink changes the summarized values and
# leaves the section's shape alone.
telemetry_section() {
  awk '
    $0 == "## Workflow telemetry" { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$1" | sed '/^[[:space:]]*$/d'
}
[[ "$(telemetry_section "$fixture/actual.md" | wc -l)" -eq 18 ]]

telemetry launch --role review-spec --phase gate --round 1
telemetry launch --role closure-sweep --phase closeout --round 1
telemetry review --kind readiness --phase checkpoint --round 1 \
  --base HEAD --worktree
telemetry exec --phase closeout --round 1 -- true
telemetry exec --phase closeout --round 1 -- false || true
telemetry finish --outcome Closes
run_new "$fixture/facts.json" "$fixture/narrative.md" >"$fixture/grown.md"
[[ "$(telemetry_section "$fixture/grown.md" | wc -l)" -eq 18 ]]
grep -Fqx '| Subagent launches | 4 (implementation=1, review-standards=1, review-spec=1, closure-sweep=1) |' \
  "$fixture/grown.md"
grep -Fqx '| Reviews recorded | 2 (readiness=1, full=1, delta=0) |' \
  "$fixture/grown.md"
grep -Fqx '| Validation executions recorded | 2 (passed=1, failed=1) |' \
  "$fixture/grown.md"
grep -Fqx "| Telemetry run | $telemetry_run (schema 1) |" "$fixture/grown.md"

# No per-launch or per-command event material reaches the body.
target_head="$(git -C "$target_checkout" rev-parse HEAD)"
for leaked in exec_id command_id validation_start subagent_launch epoch_ms \
    "$telemetry_run-e001" "$target_head"; do
  if grep -Fq -- "$leaked" "$fixture/grown.md"; then
    printf 'FAIL[bounded-body]: %s reached the pull-request body\n' "$leaked" >&2
    exit 1
  fi
done

# Facts cannot hand-compose the mechanically owned run-telemetry rows.
for supplied in run_telemetry telemetry_summary; do
  jq --arg key "$supplied" '.[$key] = "supplied by facts"' \
    "$fixture/facts.json" >"$fixture/sink-$supplied.json"
  if run_new "$fixture/sink-$supplied.json" "$fixture/narrative.md" \
      >"$fixture/sink-$supplied.out" 2>"$fixture/sink-$supplied.err"; then
    printf 'FAIL[sink-%s]: facts supplied run telemetry\n' "$supplied" >&2
    exit 1
  fi
  [[ ! -s "$fixture/sink-$supplied.out" ]]
  grep -Fqx 'closeout invalid: run telemetry comes from the run-scoped telemetry sink' \
    "$fixture/sink-$supplied.err"
done
for supplied in telemetry_run subagent_launches reviews validation_outcomes \
    phase_elapsed; do
  jq --arg key "$supplied" '.telemetry[$key] = "supplied by facts"' \
    "$fixture/facts.json" >"$fixture/sink-field-$supplied.json"
  if run_new "$fixture/sink-field-$supplied.json" "$fixture/narrative.md" \
      >"$fixture/sink-field-$supplied.out" 2>"$fixture/sink-field-$supplied.err"; then
    printf 'FAIL[sink-field-%s]: facts supplied run telemetry\n' "$supplied" >&2
    exit 1
  fi
  [[ ! -s "$fixture/sink-field-$supplied.out" ]]
  grep -Fqx 'closeout invalid: run telemetry comes from the run-scoped telemetry sink' \
    "$fixture/sink-field-$supplied.err"
done

# Closeout requires a run-scoped sink, the same way it requires a frozen ledger.
mv "$telemetry_dir" "$fixture/saved-telemetry"
if run_new "$fixture/facts.json" "$fixture/narrative.md" \
    >"$fixture/no-telemetry.out" 2>"$fixture/no-telemetry.err"; then
  printf 'FAIL[no-telemetry]: renderer accepted a closeout without a run\n' >&2
  exit 1
fi
[[ ! -s "$fixture/no-telemetry.out" ]]
grep -Fq 'no active telemetry run' "$fixture/no-telemetry.err"

# The run records its own outcome. A body claiming a different one contradicts
# the run that produced it and is refused before anything is published.
telemetry start >/dev/null
telemetry finish --outcome Progresses
if run_new "$fixture/facts.json" "$fixture/narrative.md" \
    >"$fixture/outcome-clash.out" 2>"$fixture/outcome-clash.err"; then
  printf 'FAIL[outcome-clash]: renderer accepted a contradicted outcome\n' >&2
  exit 1
fi
[[ ! -s "$fixture/outcome-clash.out" ]]
grep -Fqx \
  'closeout invalid: outcome Closes contradicts recorded run outcome Progresses' \
  "$fixture/outcome-clash.err"

rm -rf "$telemetry_dir"
mv "$fixture/saved-telemetry" "$telemetry_dir"

# A paragraph-first narrative must be placed behind a renderer-owned H2
# boundary so it remains outside the mechanically owned Issues section.
cat >"$fixture/paragraph-narrative.md" <<'EOF'
Implemented the closeout renderer.

### Validation details

The public CLI scenario passed.
EOF
cat >"$fixture/paragraph-narrative-expected.md" <<'EOF'
## Narrative

Implemented the closeout renderer.

### Validation details

The public CLI scenario passed.

EOF
run_new "$fixture/facts.json" "$fixture/paragraph-narrative.md" \
  >"$fixture/paragraph-narrative-body.md"
awk '
  $0 == "## Narrative" { found = 1 }
  found && $0 == "## Closure gate" { exit }
  found { print }
' "$fixture/paragraph-narrative-body.md" >"$fixture/paragraph-narrative-actual.md"
diff -u \
  "$fixture/paragraph-narrative-expected.md" \
  "$fixture/paragraph-narrative-actual.md"
"$(dirname "$command_under_test")/validate-closeout-body.sh" \
  164 "$fixture/paragraph-narrative-body.md"

# List- and code-shaped Markdown is also ordinary narrative content and must
# survive rendering verbatim behind the same boundary.
cat >"$fixture/list-code-narrative.md" <<'EOF'
- Renderer scenario passed.
- Validator scenario passed.

```text
validation output stays literal
```
EOF
cat >"$fixture/list-code-narrative-expected.md" <<'EOF'
## Narrative

- Renderer scenario passed.
- Validator scenario passed.

```text
validation output stays literal
```

EOF
run_new "$fixture/facts.json" "$fixture/list-code-narrative.md" \
  >"$fixture/list-code-narrative-body.md"
awk '
  $0 == "## Narrative" { found = 1 }
  found && $0 == "## Closure gate" { exit }
  found { print }
' "$fixture/list-code-narrative-body.md" >"$fixture/list-code-narrative-actual.md"
diff -u \
  "$fixture/list-code-narrative-expected.md" \
  "$fixture/list-code-narrative-actual.md"
"$(dirname "$command_under_test")/validate-closeout-body.sh" \
  164 "$fixture/list-code-narrative-body.md"

# The renderer must not publish a candidate that its shipped validator rejects.
cp -R "$skills_checkout" "$fixture/drifted-checkout"
drifted_script_root="$fixture/drifted-checkout/skills/personal/work-on/scripts"
cat >"$drifted_script_root/validate-closeout-body.sh" <<'EOF'
#!/usr/bin/env bash
printf 'closeout body invalid: scripted renderer-validator contract drift\n' >&2
exit 1
EOF
chmod +x "$drifted_script_root/"*.sh
cp "$ledger" "$fixture/original-ledger.json"
(
  cd "$target_checkout"
  "$drifted_script_root/workflow-provenance.sh" capture
)
if (cd "$target_checkout" && \
    "$drifted_script_root/render-closeout.sh" \
      "$fixture/facts.json" "$fixture/narrative.md" --new-pr) \
    >"$fixture/drifted.out" 2>"$fixture/drifted.err"; then
  printf 'FAIL[validator-drift]: renderer emitted a rejected candidate\n' >&2
  exit 1
fi
[[ ! -s "$fixture/drifted.out" ]]
grep -Fqx \
  'closeout body invalid: scripted renderer-validator contract drift' \
  "$fixture/drifted.err"
cp "$fixture/original-ledger.json" "$ledger"

# Table delimiters in free-form facts survive as readable content without
# changing the canonical five-column shape.
jq '
  .acceptance_criteria[0] = "Input | output"
  | .acceptance[0].criterion = "Input | output"
' \
  "$fixture/facts.json" >"$fixture/pipe.json"
run_new "$fixture/pipe.json" "$fixture/narrative.md" >"$fixture/pipe.md"
grep -Fqx '| Input &#124; output | `render-closeout.sh` | Public CLI via a facts file | Literal-output scenario | tested |' \
  "$fixture/pipe.md"

expect_failure() {
  local name="$1" diagnostic="$2"
  if run_new "$fixture/$name.json" "$fixture/narrative.md" \
      >"$fixture/$name.out" 2>"$fixture/$name.err"; then
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

for supplied in provenance workflow_provenance runs phases; do
  jq --arg key "$supplied" '.[$key] = "supplied by facts"' \
    "$fixture/facts.json" >"$fixture/supplied-$supplied.json"
  expect_failure "supplied-$supplied" \
    "workflow provenance comes from the run ledger and previous PR body"
done

jq 'del(.acceptance_criteria)' "$fixture/facts.json" >"$fixture/missing-criteria.json"
expect_failure missing-criteria "acceptance_criteria must be a non-empty array"

jq '.acceptance_criteria[0] = ""' "$fixture/facts.json" >"$fixture/empty-criterion.json"
expect_failure empty-criterion "acceptance_criteria row 1 must be a non-empty string"

jq '.acceptance_criteria += [.acceptance_criteria[0]]' \
  "$fixture/facts.json" >"$fixture/duplicate-criterion.json"
expect_failure duplicate-criterion \
  "acceptance_criteria contains duplicate criterion: Canonical closeout is readable"

jq '.acceptance_criteria += ["Criterion without closure evidence"]' \
  "$fixture/facts.json" >"$fixture/missing-criterion-row.json"
expect_failure missing-criterion-row \
  "acceptance is missing criterion: Criterion without closure evidence"

jq '.acceptance += [{
  "criterion": "Unexpected criterion",
  "production_path": "renderer",
  "seam": "CLI",
  "evidence": "output",
  "status": "tested"
}]' "$fixture/facts.json" >"$fixture/extra-criterion-row.json"
expect_failure extra-criterion-row \
  "acceptance contains criterion not in acceptance_criteria: Unexpected criterion"

jq '.acceptance += [.acceptance[0]]' \
  "$fixture/facts.json" >"$fixture/duplicate-criterion-row.json"
expect_failure duplicate-criterion-row \
  "acceptance contains duplicate criterion: Canonical closeout is readable"

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
run_new "$fixture/unknown-counts.json" "$fixture/narrative.md" \
  >"$fixture/unknown-counts.md"
[[ "$(grep -Fc '| unknown |' "$fixture/unknown-counts.md")" -eq 6 ]]

# A resumed closeout keeps numeric telemetry cumulative. Equal values and
# increases are both valid handoffs.
jq '
  .telemetry.implementation_rounds = 2
  | .telemetry.independent_review_rounds = 1
  | .telemetry.remediation_rounds = 1
  | .telemetry.validation_executions = 4
  | .telemetry.blocking_findings_resolved = 1
  | .telemetry.findings_rejected_at_adjudication = 0
' "$fixture/facts.json" >"$fixture/cumulative-counts.json"
(
  cd "$target_checkout"
  "$command_under_test" \
    "$fixture/cumulative-counts.json" "$fixture/narrative.md" \
    --previous-body "$fixture/actual.md" \
    >"$fixture/cumulative-counts.md"
)
grep -Fqx '| Implementation rounds | 2 |' "$fixture/cumulative-counts.md"
grep -Fqx '| Independent-review rounds | 1 |' \
  "$fixture/cumulative-counts.md"

jq '.telemetry.implementation_rounds = 0' \
  "$fixture/facts.json" >"$fixture/decreased-count.json"
if (
  cd "$target_checkout"
  "$command_under_test" \
    "$fixture/decreased-count.json" "$fixture/narrative.md" \
    --previous-body "$fixture/actual.md"
) >"$fixture/decreased-count.out" 2>"$fixture/decreased-count.err"; then
  printf 'FAIL[decreased-count]: renderer accepted decreasing telemetry\n' >&2
  exit 1
fi
[[ ! -s "$fixture/decreased-count.out" ]]
grep -Fqx \
  'closeout body invalid: workflow telemetry Implementation rounds decreased from 1 to 0' \
  "$fixture/decreased-count.err"

# Resuming an existing pull request appends the current run even when its
# governing fingerprint matches the previous run.
(
  cd "$target_checkout"
  "$command_under_test" "$fixture/facts.json" "$fixture/narrative.md" \
    --previous-body "$fixture/actual.md" >"$fixture/resumed.md"
)
grep -Fqx '| Workflow provenance | 2 runs |' "$fixture/resumed.md"
[[ "$(grep -Fxc "Run 1: $provenance" "$fixture/resumed.md")" -eq 1 ]]
[[ "$(grep -Fxc "Run 2: $provenance" "$fixture/resumed.md")" -eq 1 ]]

# Every prior run remains byte-for-byte and the resumed run appends a third
# run even when all three governing fingerprints are equal.
(
  cd "$target_checkout"
  "$command_under_test" "$fixture/facts.json" "$fixture/narrative.md" \
    --previous-body "$fixture/resumed.md" >"$fixture/resumed-again.md"
)
grep -Fqx '| Workflow provenance | 3 runs |' \
  "$fixture/resumed-again.md"
for run_number in 1 2 3; do
  grep -Fqx "Run $run_number: $provenance" "$fixture/resumed-again.md"
done

# A declared instruction input changed after capture fails verification without
# emitting a body in either renderer mode.
printf 'mid-run change\n' \
  >>"$(dirname "$command_under_test")/../references/github-closeout.md"
if (
  cd "$target_checkout"
  "$command_under_test" "$fixture/facts.json" "$fixture/narrative.md" \
    --previous-body "$fixture/actual.md"
) >"$fixture/previous-mismatch.out" 2>"$fixture/previous-mismatch.err"; then
  printf 'FAIL[previous-mismatch]: renderer accepted changed provenance\n' >&2
  exit 1
fi
[[ ! -s "$fixture/previous-mismatch.out" ]]
grep -Fqx \
  'workflow provenance: work-on instructions changed since capture' \
  "$fixture/previous-mismatch.err"

if run_new "$fixture/facts.json" "$fixture/narrative.md" \
    >"$fixture/new-mismatch.out" 2>"$fixture/new-mismatch.err"; then
  printf 'FAIL[new-mismatch]: renderer accepted changed provenance\n' >&2
  exit 1
fi
[[ ! -s "$fixture/new-mismatch.out" ]]
grep -Fqx \
  'workflow provenance: work-on instructions changed since capture' \
  "$fixture/new-mismatch.err"

# A mode is mandatory, and the frozen-run ledger is mandatory at closeout.
if (cd "$target_checkout" && \
    "$command_under_test" "$fixture/facts.json" "$fixture/narrative.md") \
    >"$fixture/no-mode.out" 2>"$fixture/no-mode.err"; then
  printf 'FAIL[no-mode]: renderer accepted a mode-less closeout\n' >&2
  exit 1
fi
[[ ! -s "$fixture/no-mode.out" ]]

mv "$ledger" "$fixture/saved-ledger.json"
if run_new "$fixture/facts.json" "$fixture/narrative.md" \
    >"$fixture/no-ledger.out" 2>"$fixture/no-ledger.err"; then
  printf 'FAIL[no-ledger]: renderer accepted a closeout without a ledger\n' >&2
  exit 1
fi
[[ ! -s "$fixture/no-ledger.out" ]]

printf 'work-on closeout renderer black-box scenarios passed\n'
