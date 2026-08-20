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
readonly closeout_reference="$skills_checkout/skills/personal/work-on/references/github-closeout.md"
grep -Fq 'resolve --run "$RUN_HANDLE" --outcome "$OUTCOME"' \
  "$closeout_reference"
target_checkout="$fixture/target-checkout"
git init -q -b main "$target_checkout"
git -C "$target_checkout" config user.name 'Closeout Test'
git -C "$target_checkout" config user.email closeout@example.invalid
git -C "$target_checkout" remote add origin \
  'https://github.com/example/target.git'
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
# needs a finished run. One event per phase keeps the rendered elapsed values
# deterministic without pinning the fixture to a clock.
telemetry() {
  (cd "$target_checkout" && \
    "$(dirname "$command_under_test")/run-telemetry.sh" "$@")
}
telemetry_dir="$target_checkout/.git/work-on-telemetry"
run_id_from_handle() {
  printf '%s\n' "${1%%@*}"
}
telemetry_sink() {
  printf '%s/runs/%s.jsonl\n' "$telemetry_dir" \
    "$(run_id_from_handle "$1")"
}
telemetry_run="$(telemetry start --issue 164)"
render_run="$telemetry_run"
telemetry launch --run "$render_run" \
  --role implementation --phase implementation --round 1
telemetry review-delegation --run "$render_run" --role review-standards \
  --kind full --phase gate --round 1 \
  --base HEAD --head HEAD
telemetry resolve --run "$render_run" --outcome Closes
telemetry seal --run "$render_run"

run_new() {
  (
    cd "$target_checkout"
    "$command_under_test" --run "$render_run" "$@" --new-pr
  )
}

cat >"$fixture/facts.json" <<'EOF'
{
  "repository": "example/target",
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
| Model configuration | primary=unknown |
| Start-to-seal elapsed | START_TO_SEAL |
| Implementation rounds | 1 |
| Independent-review rounds | 1 |
| Remediation rounds | 0 |
| Validation executions | 0 |
| Blocking findings resolved | 0 |
| Findings rejected at adjudication | 0 |
| Finding adjudications by reviewer | none |
| Primary token checkpoint snapshot | unknown |
| Completed subagent usage | total input=0, cached input=0, cache-write input=0, fresh input=0, output=0, reasoning output=0 |
| Completed subagent usage by role | none |
| Token coverage | none (0/2 completed subagents); primary checkpoint snapshot=none |
| Final workflow outcome | Closes |
| Telemetry run | TELEMETRY_RUN (schema 3, integrity valid) |
| Subagent launches | 2 (implementation=1, review-standards=1) |
| Reviews recorded | 1 (readiness=0, full=1, delta=0) |
| Reviewed artifact bytes | 0 bytes |
| Validation executions recorded | 0 (passed=0, failed=0) |
| Recorded validation duration | 0 ms |
| Measured phase elapsed | implementation=0s, gate=0s |
| Workflow provenance | 1 run |

> **Source note:** Run telemetry is sink-derived; Final workflow outcome is also asserted by structured closeout facts. Workflow provenance is verified from the frozen run ledger.

Run 1: PROVENANCE
EOF
awk -v provenance="$provenance" \
  -v telemetry_run="$(run_id_from_handle "$telemetry_run")" \
  '{ sub(/PROVENANCE/, provenance); sub(/TELEMETRY_RUN/, telemetry_run); print }' \
  "$fixture/expected.md" >"$fixture/expected.with-provenance.md"
mv "$fixture/expected.with-provenance.md" "$fixture/expected.md"

run_new "$fixture/facts.json" "$fixture/narrative.md" >"$fixture/actual.md"
# Start-to-seal is the one row a wall clock decides. Its shape is asserted here
# and normalized out of the literal-body diff, so the diff stays exact.
grep -Eqx '\| Start-to-seal elapsed \| [0-9]+ ms \|' "$fixture/actual.md" || {
  printf 'FAIL[start-to-seal]: the elapsed row is not a recorded millisecond count\n' >&2
  grep -F '| Start-to-seal elapsed |' "$fixture/actual.md" >&2
  exit 1
}
normalize_elapsed() {
  sed -E 's/^\| Start-to-seal elapsed \| [0-9]+ ms \|$/| Start-to-seal elapsed | START_TO_SEAL |/' \
    "$1"
}
diff -u "$fixture/expected.md" <(normalize_elapsed "$fixture/actual.md")
"$(dirname "$command_under_test")/validate-closeout-body.sh" 164 "$fixture/actual.md"

# The renderer forwards the repository-bound handle to summary. A wrong
# binding is refused even when its run-id component names a local sink.
local_render_binding="${render_run#*@}"
if [[ "${local_render_binding:0:1}" == 0 ]]; then
  foreign_render_binding="1${local_render_binding:1}"
else
  foreign_render_binding="0${local_render_binding:1}"
fi
foreign_render_run="$(run_id_from_handle "$render_run")@$foreign_render_binding"
if (
  cd "$target_checkout"
  "$command_under_test" --run "$foreign_render_run" \
    "$fixture/facts.json" "$fixture/narrative.md" --new-pr
) >"$fixture/foreign-binding.out" 2>"$fixture/foreign-binding.err"; then
  printf 'FAIL[foreign-binding]: renderer accepted another repository binding\n' >&2
  exit 1
fi
[[ ! -s "$fixture/foreign-binding.out" ]]
grep -Fq 'run handle belongs to another repository' \
  "$fixture/foreign-binding.err"

# stdin is the other documented input mode.
run_new - "$fixture/narrative.md" <"$fixture/facts.json" >"$fixture/stdin.md"
diff -u "$fixture/expected.md" <(normalize_elapsed "$fixture/stdin.md")

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
[[ "$(telemetry_section "$fixture/actual.md" | wc -l)" -eq 26 ]]

grown_run="$(telemetry start --issue 164)"
render_run="$grown_run"
telemetry launch --run "$render_run" \
  --role implementation --phase implementation --round 1
telemetry review-delegation --run "$render_run" --role review-standards \
  --kind full --phase gate --round 1 --base HEAD --head HEAD
telemetry review-delegation --run "$render_run" --role review-spec \
  --kind full --phase gate --round 1 --base HEAD --head HEAD
telemetry review-delegation --run "$render_run" --role closure-sweep \
  --kind full --phase gate --round 1 --base HEAD --head HEAD
telemetry review-delegation --run "$render_run" --role readiness \
  --kind readiness --phase checkpoint --round 1 \
  --base HEAD --worktree
telemetry exec --run "$render_run" \
  --command-id passing-check --phase closeout --round 1 -- true
telemetry exec --run "$render_run" \
  --command-id failing-check --phase closeout --round 1 -- false \
  || true
telemetry resolve --run "$render_run" --outcome Closes
telemetry seal --run "$render_run"
run_new "$fixture/facts.json" "$fixture/narrative.md" >"$fixture/grown.md"
[[ "$(telemetry_section "$fixture/grown.md" | wc -l)" -eq 26 ]]
grep -Fqx '| Subagent launches | 5 (implementation=1, readiness=1, review-standards=1, review-spec=1, closure-sweep=1) |' \
  "$fixture/grown.md"
grep -Fqx '| Reviews recorded | 4 (readiness=1, full=3, delta=0) |' \
  "$fixture/grown.md"
grep -Fqx '| Validation executions recorded | 2 (passed=1, failed=1) |' \
  "$fixture/grown.md"
grep -Fqx "| Telemetry run | $(run_id_from_handle "$grown_run") (schema 3, integrity valid) |" \
  "$fixture/grown.md"

# The mechanical aggregates come from the same sink as the bounded totals.
# Standards, Spec, and the gate closure sweep shared round 1, so they are one
# independent-review round rather than three; the readiness checkpoint and the
# closeout-phase executions contribute no round at all.
grep -Fqx '| Implementation rounds | 1 |' "$fixture/grown.md"
grep -Fqx '| Independent-review rounds | 1 |' "$fixture/grown.md"
grep -Fqx '| Remediation rounds | 0 |' "$fixture/grown.md"
grep -Fqx '| Validation executions | 2 |' "$fixture/grown.md"
grep -Eqx '\| Reviewed artifact bytes \| [0-9]+ bytes \|' "$fixture/grown.md"
grep -Eqx '\| Recorded validation duration \| [0-9]+ ms \|' "$fixture/grown.md"

# No per-launch or per-command event material reaches the body.
target_head="$(git -C "$target_checkout" rev-parse HEAD)"
for leaked in exec_id command_id validation_start subagent_launch epoch_ms \
    passing-check failing-check "$grown_run-e001" "$target_head"; do
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
# The permitted facts keys are an allowlist, so a sink-owned aggregate is
# refused under the renderer's own row names, under the summary JSON's names,
# and under a name nobody has invented yet. A denylist would cover only the
# first group, and only until the sink grew a field.
for supplied in telemetry_run subagent_launches reviews validation_outcomes \
    phase_elapsed wall_clock_elapsed start_to_seal_elapsed \
    implementation_rounds independent_review_rounds remediation_rounds \
    validation_executions reviewed_artifact_bytes \
    recorded_validation_duration \
    start_to_seal_ms rounds validations phase_elapsed_ms \
    review_delegations integrity unrecognized_bookkeeping; do
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
grep -Fq 'repository binding is missing' "$fixture/no-telemetry.err"

# A closeout body reports a finished run whose recorded outcome is the body's
# outcome. Anything else — no outcome, two outcomes, or a different one — is
# refused before a body is published.
expect_run_failure() {
  local label="$1" diagnostic="$2" facts="${3:-$fixture/facts.json}"
  if run_new "$facts" "$fixture/narrative.md" \
      >"$fixture/$label.out" 2>"$fixture/$label.err"; then
    printf 'FAIL[%s]: renderer accepted a closeout it should refuse\n' \
      "$label" >&2
    exit 1
  fi
  [[ ! -s "$fixture/$label.out" ]]
  if ! grep -Fqx "$diagnostic" "$fixture/$label.err"; then
    printf 'FAIL[%s]: expected diagnostic: %s\n' "$label" "$diagnostic" >&2
    cat "$fixture/$label.err" >&2
    exit 1
  fi
}

seed_event() {
  local handle="$1" type="$2" extra="${3:-}" sink seq
  [[ -n "$extra" ]] || extra='{}'
  sink="$(telemetry_sink "$handle")"
  seq=$(( $(wc -l <"$sink") + 1 ))
  jq -cn --arg run "$(run_id_from_handle "$handle")" --arg type "$type" \
    --argjson seq "$seq" --argjson extra "$extra" \
    '{schema: 3, run: $run, seq: $seq, at: "2026-08-14T00:00:00Z",
      epoch_ms: 1755000000000, type: $type} + $extra' >>"$sink"
}

jq '.outcome = "Progresses" | .telemetry.final_workflow_outcome = "Progresses"' \
  "$fixture/facts.json" >"$fixture/progresses-facts.json"

# A run that never finished has nothing to report.
unfinished_run="$(telemetry start --issue 164)"
render_run="$unfinished_run"
expect_run_failure unfinished \
  'closeout invalid: run telemetry integrity is incomplete; schema-3 closeout requires valid'

# The sink says Progresses while the facts say Closes.
telemetry resolve --run "$render_run" --outcome Progresses
telemetry seal --run "$render_run"
expect_run_failure sink-progresses \
  'closeout invalid: outcome Closes contradicts recorded run outcome Progresses'

# The sink says Closes while the facts say Progresses.
render_run="$(telemetry start --issue 164)"
telemetry resolve --run "$render_run" --outcome Closes
telemetry seal --run "$render_run"
expect_run_failure sink-closes \
  'closeout invalid: outcome Progresses contradicts recorded run outcome Closes' \
  "$fixture/progresses-facts.json"

# Two recorded outcomes are not an outcome.
duplicate_run="$render_run"
seed_event "$duplicate_run" outcome_resolved '{"outcome": "Closes"}'
expect_run_failure duplicate-finish \
  'closeout invalid: run telemetry integrity is invalid; schema-3 closeout requires valid'

# A resolution record with no outcome is invalid telemetry.
render_run="$(telemetry start --issue 164)"
seed_event "$render_run" outcome_resolved '{}'
seed_event "$render_run" run_sealed
expect_run_failure outcomeless-finish \
  'closeout invalid: run telemetry integrity is invalid; schema-3 closeout requires valid'

# A finish record carrying something outside the outcome enum contradicts the
# body rather than being read as agreement.
render_run="$(telemetry start --issue 164)"
seed_event "$render_run" outcome_resolved '{"outcome": "merged"}'
seed_event "$render_run" run_sealed
expect_run_failure unrecognized-finish \
  'closeout invalid: run telemetry integrity is invalid; schema-3 closeout requires valid'

# A finished run whose recorded outcome matches renders.
matching_run="$(telemetry start --issue 164)"
render_run="$matching_run"
telemetry launch --run "$render_run" \
  --role implementation --phase implementation --round 1
OUTCOME=Closes
telemetry resolve --run "$render_run" --outcome "$OUTCOME"
telemetry seal --run "$render_run"
run_new "$fixture/facts.json" "$fixture/narrative.md" >"$fixture/matching.md"
grep -Fqx "| Telemetry run | $(run_id_from_handle "$matching_run") (schema 3, integrity valid) |" \
  "$fixture/matching.md"
grep -Fqx '| Final workflow outcome | Closes |' "$fixture/matching.md"

progresses_run="$(telemetry start --issue 164)"
render_run="$progresses_run"
telemetry launch --run "$render_run" \
  --role implementation --phase implementation --round 1
OUTCOME=Progresses
telemetry resolve --run "$render_run" --outcome "$OUTCOME"
telemetry seal --run "$render_run"
run_new "$fixture/progresses-facts.json" "$fixture/narrative.md" \
  >"$fixture/matching-progresses.md"
grep -Fqx '| Final workflow outcome | Progresses |' \
  "$fixture/matching-progresses.md"
grep -Fqx "| Telemetry run | $(run_id_from_handle "$progresses_run") (schema 3, integrity valid) |" \
  "$fixture/matching-progresses.md"

render_run="$matching_run"

jq '.repository = "example/another"' "$fixture/facts.json" \
  >"$fixture/wrong-repository-facts.json"
expect_run_failure wrong-repository \
  'closeout invalid: repository example/another contradicts recorded run repository example/target' \
  "$fixture/wrong-repository-facts.json"
jq '.issue_number = 165' "$fixture/facts.json" \
  >"$fixture/wrong-issue-facts.json"
expect_run_failure wrong-issue \
  'closeout invalid: issue 165 contradicts recorded run issue 164' \
  "$fixture/wrong-issue-facts.json"

[[ "$unfinished_run" != "$matching_run" ]]

rm -rf "$telemetry_dir"
mv "$fixture/saved-telemetry" "$telemetry_dir"
render_run="$grown_run"

# A seal stamped before its own start describes no interval. The body reports
# `unknown` with a bounded warning rather than a clamped or fabricated value,
# and unavailability of one aggregate is not a telemetry-integrity failure: the
# rest of the closeout renders and hand-back is not blocked.
backwards_run="$(telemetry start --issue 164)"
saved_render_run="$render_run"
render_run="$backwards_run"
telemetry launch --run "$render_run" \
  --role implementation --phase implementation --round 1
telemetry resolve --run "$render_run" --outcome Closes
telemetry seal --run "$render_run"
backwards_sink="$(telemetry_sink "$render_run")"
jq -c 'if .type == "run_sealed" then .epoch_ms = 0 else . end' \
  "$backwards_sink" >"$fixture/backwards.jsonl"
cp "$fixture/backwards.jsonl" "$backwards_sink"
(
  cd "$target_checkout"
  "$command_under_test" --run "$render_run" \
    "$fixture/facts.json" "$fixture/narrative.md" --new-pr
) >"$fixture/backwards.md" 2>"$fixture/backwards.err"
grep -Fqx '| Start-to-seal elapsed | unknown |' "$fixture/backwards.md"
grep -Fqx '| Implementation rounds | 1 |' "$fixture/backwards.md"
grep -Fqx "| Telemetry run | $(run_id_from_handle "$backwards_run") (schema 3, integrity valid) |" \
  "$fixture/backwards.md"
grep -Fqx \
  "warning: start-to-seal elapsed unavailable for run $(run_id_from_handle "$backwards_run"); rendered as unknown" \
  "$fixture/backwards.err"
[[ "$(wc -l <"$fixture/backwards.err")" -eq 1 ]]
render_run="$saved_render_run"

# Published identity is the repository context, the issue, and the bare run ID.
# The owner-only repository binding selects the sink and never leaves the
# workstation, so no rendered body may contain it.
for rendered in "$fixture/actual.md" "$fixture/grown.md" "$fixture/backwards.md"; do
  if grep -Fq -- "${render_run#*@}" "$rendered"; then
    printf 'FAIL[binding]: the repository binding reached %s\n' "$rendered" >&2
    exit 1
  fi
done
if grep -Fq -- "$render_run" "$fixture/grown.md"; then
  printf 'FAIL[binding]: the rendered body carries the bound handle\n' >&2
  exit 1
fi
grep -Fqx "| Telemetry run | $(run_id_from_handle "$render_run") (schema 3, integrity valid) |" \
  "$fixture/grown.md"

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
    "$drifted_script_root/render-closeout.sh" --run "$render_run" \
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

# The table describes the latest run, not the pull request's cumulative
# history, so a later run may legitimately report smaller counts. The previous
# body recorded one implementation round; a run that launched no implementer
# reports zero, and that is an accepted observation rather than a lost bound.
smaller_run="$(telemetry start --issue 164)"
saved_render_run="$render_run"
render_run="$smaller_run"
telemetry resolve --run "$render_run" --outcome Closes
telemetry seal --run "$render_run"
(
  cd "$target_checkout"
  "$command_under_test" --run "$render_run" \
    "$fixture/facts.json" "$fixture/narrative.md" \
    --previous-body "$fixture/actual.md" \
    >"$fixture/smaller-counts.md"
)
grep -Fqx '| Implementation rounds | 0 |' "$fixture/smaller-counts.md"
grep -Fqx '| Independent-review rounds | 0 |' "$fixture/smaller-counts.md"
grep -Fqx '| Workflow provenance | 2 runs |' "$fixture/smaller-counts.md"
render_run="$saved_render_run"

# Resuming an existing pull request appends the current run even when its
# governing fingerprint matches the previous run.
(
  cd "$target_checkout"
  "$command_under_test" --run "$render_run" \
    "$fixture/facts.json" "$fixture/narrative.md" \
    --previous-body "$fixture/actual.md" >"$fixture/resumed.md"
)
grep -Fqx '| Workflow provenance | 2 runs |' "$fixture/resumed.md"
[[ "$(grep -Fxc "Run 1: $provenance" "$fixture/resumed.md")" -eq 1 ]]
[[ "$(grep -Fxc "Run 2: $provenance" "$fixture/resumed.md")" -eq 1 ]]

# Every prior run remains byte-for-byte and the resumed run appends a third
# run even when all three governing fingerprints are equal.
(
  cd "$target_checkout"
  "$command_under_test" --run "$render_run" \
    "$fixture/facts.json" "$fixture/narrative.md" \
    --previous-body "$fixture/resumed.md" >"$fixture/resumed-again.md"
)
grep -Fqx '| Workflow provenance | 3 runs |' \
  "$fixture/resumed-again.md"
for run_number in 1 2 3; do
  grep -Fqx "Run $run_number: $provenance" "$fixture/resumed-again.md"
done

# Schema 3 owns model, finding, and token rows mechanically. The facts object
# carries only the final outcome consistency assertion.
telemetry3() {
  (cd "$target_checkout" && \
    "$(dirname "$command_under_test")/run-telemetry.sh" "$@")
}
schema3_run="$(telemetry3 start --issue 164)"
schema3_implementation="$(telemetry3 launch --run "$schema3_run" \
  --role implementation --phase implementation --round 1)"
schema3_reviewer="$(telemetry3 review-delegation --run "$schema3_run" \
  --role review-standards --kind full --phase gate --round 1 \
  --base HEAD --head HEAD)"
for agent_id in "$schema3_implementation" "$schema3_reviewer"; do
  telemetry3 runtime-observation --run "$schema3_run" \
    --scope completed-thread --agent-id "$agent_id" \
    --model gpt-test --effort high --total-input 100 --cached-input 70 \
    --cache-write-input 10 --output 20 --reasoning-output 5
done
accepted_finding="$(telemetry3 finding-adjudicated --run "$schema3_run" \
  --reviewer-agent-id "$schema3_reviewer" --class evidence-gap \
  --disposition accepted)"
telemetry3 finding-adjudicated --run "$schema3_run" \
  --reviewer-agent-id "$schema3_reviewer" --class contract-defect \
  --disposition rejected >/dev/null
telemetry3 finding-resolved --run "$schema3_run" \
  --finding-id "$accepted_finding"
telemetry3 runtime-observation --run "$schema3_run" \
  --scope checkpoint-snapshot --model gpt-test --effort high \
  --total-input 50 --cached-input 30 --cache-write-input 5 \
  --output 10 --reasoning-output 2
telemetry3 resolve --run "$schema3_run" --outcome Closes
telemetry3 seal --run "$schema3_run"
jq '.telemetry = {final_workflow_outcome: "Closes"}' \
  "$fixture/facts.json" >"$fixture/schema3-facts.json"
(
  cd "$target_checkout"
  "$command_under_test" --run "$schema3_run" \
    "$fixture/schema3-facts.json" "$fixture/narrative.md" --new-pr
) >"$fixture/schema3.md"
grep -Fqx '| Model configuration | primary=gpt-test (high); implementation=gpt-test (high); review-standards=gpt-test (high) |' "$fixture/schema3.md"
grep -Fqx '| Blocking findings resolved | 1 |' "$fixture/schema3.md"
grep -Fqx '| Findings rejected at adjudication | 1 |' "$fixture/schema3.md"
grep -Fqx '| Finding adjudications by reviewer | review-standards: accepted=1, rejected=1, follow-up=0, unresolved=0 |' "$fixture/schema3.md"
grep -Fqx '| Primary token checkpoint snapshot | total input=50, cached input=30, cache-write input=5, fresh input=15, output=10, reasoning output=2 |' "$fixture/schema3.md"
grep -Fqx '| Completed subagent usage | total input=200, cached input=140, cache-write input=20, fresh input=40, output=40, reasoning output=10 |' "$fixture/schema3.md"
grep -Fqx '| Token coverage | complete (2/2 completed subagents); primary checkpoint snapshot=observed |' "$fixture/schema3.md"
grep -Fqx '> **Source note:** Run telemetry is sink-derived; Final workflow outcome is also asserted by structured closeout facts. Workflow provenance is verified from the frozen run ledger.' "$fixture/schema3.md"

schema3_model_only_run="$(telemetry3 start --issue 164)"
telemetry3 runtime-observation --run "$schema3_model_only_run" \
  --scope checkpoint-snapshot --model gpt-test --effort high
telemetry3 resolve --run "$schema3_model_only_run" --outcome Closes
telemetry3 seal --run "$schema3_model_only_run"
(
  cd "$target_checkout"
  "$command_under_test" --run "$schema3_model_only_run" \
    "$fixture/schema3-facts.json" "$fixture/narrative.md" --new-pr
) >"$fixture/schema3-model-only.md"
grep -Fqx '| Model configuration | primary=gpt-test (high) |' \
  "$fixture/schema3-model-only.md"
grep -Fqx '| Primary token checkpoint snapshot | unknown |' \
  "$fixture/schema3-model-only.md"
grep -Fqx '| Token coverage | none (0/0 completed subagents); primary checkpoint snapshot=none |' \
  "$fixture/schema3-model-only.md"

jq '.telemetry.model_configuration = "forged"' \
  "$fixture/schema3-facts.json" >"$fixture/schema3-forged-facts.json"
if (
  cd "$target_checkout"
  "$command_under_test" --run "$schema3_run" \
    "$fixture/schema3-forged-facts.json" "$fixture/narrative.md" --new-pr
) >"$fixture/schema3-forged.out" 2>"$fixture/schema3-forged.err"; then
  printf 'FAIL[schema3-forged]: renderer accepted sink-owned facts\n' >&2
  exit 1
fi
grep -Fq 'run telemetry comes from the run-scoped telemetry sink' \
  "$fixture/schema3-forged.err"

# A declared instruction input changed after capture fails verification without
# emitting a body in either renderer mode.
printf 'mid-run change\n' \
  >>"$(dirname "$command_under_test")/../references/github-closeout.md"
if (
  cd "$target_checkout"
  "$command_under_test" --run "$render_run" \
    "$fixture/facts.json" "$fixture/narrative.md" \
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
    "$command_under_test" --run "$render_run" \
      "$fixture/facts.json" "$fixture/narrative.md") \
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
