#!/usr/bin/env bash
set -euo pipefail

# Validate structured closeout facts and render the evidence-oriented sections
# of a pull-request body. Narrative Markdown remains ordinary Markdown and is
# copied under a renderer-owned narrative boundary between the issue mapping
# and the mechanical evidence sections.

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'closeout invalid: %s\n' "$1" >&2
  exit 1
}

[[ "${1:-}" == --run && -n "${2:-}" ]] \
  || fail "usage: render-closeout.sh --run HANDLE <facts.json|-> <narrative.md> (--new-pr | --previous-body <old-body.md>)"
run_id="$2"
shift 2

if [[ "$#" -eq 3 && "$3" == --new-pr ]]; then
  closeout_mode=new
  previous_body=""
elif [[ "$#" -eq 4 && "$3" == --previous-body ]]; then
  closeout_mode=previous
  previous_body="$4"
  [[ -f "$previous_body" ]] || fail "previous body file does not exist: $previous_body"
else
  fail "usage: render-closeout.sh --run HANDLE <facts.json|-> <narrative.md> (--new-pr | --previous-body <old-body.md>)"
fi

facts_source="$1"
narrative_source="$2"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
facts="$fixture/facts.json"

if [[ "$facts_source" == - ]]; then
  cp /dev/stdin "$facts"
elif [[ -f "$facts_source" ]]; then
  cp "$facts_source" "$facts"
else
  fail "facts file does not exist: $facts_source"
fi

jq -e . "$facts" >/dev/null 2>&1 || fail "facts are not valid JSON"
jq -e 'type == "object"' "$facts" >/dev/null || fail "facts must be a JSON object"
jq -e '
  (has("provenance") or has("workflow_provenance")
    or has("runs") or has("phases")) | not
' "$facts" >/dev/null \
  || fail "workflow provenance comes from the run ledger and previous PR body"
jq -e '
  (has("run_telemetry") or has("telemetry_summary")
    or ((.telemetry // {} | if type == "object" then . else {} end)
      | has("telemetry_run") or has("subagent_launches") or has("reviews")
        or has("validation_outcomes") or has("phase_elapsed")
        or has("wall_clock_elapsed") or has("start_to_seal_elapsed")
        or has("implementation_rounds") or has("independent_review_rounds")
        or has("remediation_rounds") or has("validation_executions")
        or has("reviewed_artifact_bytes")
        or has("recorded_validation_duration"))) | not
' "$facts" >/dev/null \
  || fail "run telemetry comes from the run-scoped telemetry sink"

jq -e '.issue_number | type == "number" and . > 0 and floor == .' \
  "$facts" >/dev/null || fail "issue_number must be a positive integer"
issue_number="$(jq -r '.issue_number' "$facts")"
[[ "$issue_number" =~ ^[1-9][0-9]*$ ]] \
  || fail "issue_number must be a positive integer"

outcome="$(jq -r '.outcome // empty' "$facts")"
[[ "$outcome" == Closes || "$outcome" == Progresses ]] \
  || fail "outcome must be Closes or Progresses"

jq -e '.acceptance_criteria | type == "array" and length > 0' \
  "$facts" >/dev/null \
  || fail "acceptance_criteria must be a non-empty array"
invalid_criterion_index="$(
  jq -r '
    .acceptance_criteria
    | [to_entries[]
      | select((.value | type) != "string" or (.value | length) == 0)
      | .key][0] // empty
  ' "$facts"
)"
if [[ -n "$invalid_criterion_index" ]]; then
  fail "acceptance_criteria row $((invalid_criterion_index + 1)) must be a non-empty string"
fi
duplicate_criterion="$(
  jq -r '
    .acceptance_criteria
    | [group_by(.)[]
      | select(length > 1)
      | .[0]][0] // empty
  ' "$facts"
)"
[[ -z "$duplicate_criterion" ]] \
  || fail "acceptance_criteria contains duplicate criterion: $duplicate_criterion"

acceptance_count="$(jq -r 'if (.acceptance | type) == "array" then (.acceptance | length) else 0 end' "$facts")"
[[ "$acceptance_count" -gt 0 ]] \
  || fail "acceptance must contain at least one row"

for ((index = 0; index < acceptance_count; index++)); do
  row_number=$((index + 1))
  for field in criterion production_path seam evidence status; do
    jq -e --argjson index "$index" --arg field "$field" \
      '.acceptance[$index][$field] | type == "string" and length > 0' \
      "$facts" >/dev/null \
      || fail "acceptance row $row_number requires non-empty $field"
  done
  status="$(jq -r --argjson index "$index" '.acceptance[$index].status' "$facts")"
  case "$status" in
    tested|failing|inferred|unverified) ;;
    *) fail "acceptance row $row_number has invalid status: $status" ;;
  esac
  if [[ "$outcome" == Closes && "$status" != tested ]]; then
    fail "Closes requires every acceptance row to be tested; row $row_number is $status"
  fi
done

duplicate_acceptance_criterion="$(
  jq -r '
    [.acceptance[].criterion]
    | [group_by(.)[]
      | select(length > 1)
      | .[0]][0] // empty
  ' "$facts"
)"
[[ -z "$duplicate_acceptance_criterion" ]] \
  || fail "acceptance contains duplicate criterion: $duplicate_acceptance_criterion"

extra_acceptance_criterion="$(
  jq -r '
    .acceptance_criteria as $criteria
    | [.acceptance[].criterion
      | select(. as $criterion | ($criteria | index($criterion)) == null)][0] // empty
  ' "$facts"
)"
[[ -z "$extra_acceptance_criterion" ]] \
  || fail "acceptance contains criterion not in acceptance_criteria: $extra_acceptance_criterion"

missing_acceptance_criterion="$(
  jq -r '
    [.acceptance[].criterion] as $rows
    | [.acceptance_criteria[]
      | select(. as $criterion | ($rows | index($criterion)) == null)][0] // empty
  ' "$facts"
)"
[[ -z "$missing_acceptance_criterion" ]] \
  || fail "acceptance is missing criterion: $missing_acceptance_criterion"

jq -e '.telemetry | type == "object"' "$facts" >/dev/null \
  || fail "telemetry must be an object"
# Only the three primary-reported observations and the outcome consistency
# assertion are still supplied here; every other row is sink-derived below.
telemetry_fields=(
  model_configuration
  blocking_findings_resolved
  findings_rejected_at_adjudication
  final_workflow_outcome
)
for field in "${telemetry_fields[@]}"; do
  jq -e --arg field "$field" \
    '.telemetry[$field] |
      (type == "string" and length > 0) or
      (type == "number" and . >= 0)' "$facts" >/dev/null \
    || fail "telemetry requires a non-empty value for $field"
done

telemetry_count_fields=(
  blocking_findings_resolved
  findings_rejected_at_adjudication
)
for field in "${telemetry_count_fields[@]}"; do
  jq -e --arg field "$field" \
    '.telemetry[$field] |
      (type == "number" and . >= 0 and floor == .) or
      (type == "string" and . == "unknown")' "$facts" >/dev/null \
    || fail "telemetry $field must be a nonnegative integer or unknown"
done

telemetry_outcome="$(jq -r '.telemetry.final_workflow_outcome' "$facts")"
[[ "$telemetry_outcome" == Closes || "$telemetry_outcome" == Progresses ]] \
  || fail "telemetry final_workflow_outcome must be Closes or Progresses"
[[ "$telemetry_outcome" == "$outcome" ]] \
  || fail "outcome $outcome contradicts telemetry outcome $telemetry_outcome"

if [[ -n "$narrative_source" && ! -f "$narrative_source" ]]; then
  fail "narrative file does not exist: $narrative_source"
fi

# The frozen run's canonical value is opaque here: workflow-provenance.sh
# owns capture, verification, and its shape.
run_value="$("$script_root/workflow-provenance.sh" verify)" \
  || fail "workflow provenance verification failed"

# The bounded run-telemetry rows are aggregated from the run-scoped sink, never
# from the facts file. run-telemetry.sh owns the sink, its schema, and the
# aggregation; this renderer only formats the summary it returns.
telemetry_summary="$("$script_root/run-telemetry.sh" summary --run "$run_id")" \
  || fail "run telemetry summary failed"

# Schema-2 successful closeout fails closed on the sink evaluator. Facts name
# the same repository and issue so a valid run cannot be rendered for another
# closeout. Schema-1 forensic rendering retains its historical outcome checks.
recorded_schema="$(jq -r '.schema // empty' <<<"$telemetry_summary")"
integrity_state="$(jq -r '.integrity.state // empty' <<<"$telemetry_summary")"
if [[ "$recorded_schema" == 2 ]]; then
  [[ "$integrity_state" == valid ]] \
    || fail "run telemetry integrity is ${integrity_state:-invalid}; schema-2 closeout requires valid"
  recorded_resolutions="$(jq -r '.outcome_resolution_events // 0' \
    <<<"$telemetry_summary")"
  recorded_seals="$(jq -r '.seal_events // 0' <<<"$telemetry_summary")"
  [[ "$recorded_resolutions" -eq 1 && "$recorded_seals" -eq 1 ]] \
    || fail "schema-2 closeout requires one outcome resolution and one seal"
  facts_repository="$(jq -r '.repository // empty' "$facts")"
  [[ "$facts_repository" =~ ^[a-z0-9_.-]+/[a-z0-9_.-]+$ ]] \
    || fail "repository must be a normalized GitHub owner/repository"
  recorded_repository="$(jq -r '.repository // empty' <<<"$telemetry_summary")"
  recorded_issue="$(jq -r '.issue // empty' <<<"$telemetry_summary")"
  [[ "$facts_repository" == "$recorded_repository" ]] \
    || fail "repository $facts_repository contradicts recorded run repository $recorded_repository"
  [[ "$issue_number" == "$recorded_issue" ]] \
    || fail "issue $issue_number contradicts recorded run issue $recorded_issue"
elif [[ "$recorded_schema" == 1 ]]; then
  recorded_finishes="$(jq -r '.finish_events // 0' <<<"$telemetry_summary")"
  [[ "$recorded_finishes" =~ ^[0-9]+$ ]] \
    || fail "run telemetry did not report how the run finished"
  [[ "$recorded_finishes" -ne 0 ]] \
    || fail "the legacy run has not finished"
  [[ "$recorded_finishes" -eq 1 ]] \
    || fail "the legacy run recorded $recorded_finishes final outcomes; exactly one is allowed"
else
  fail "run telemetry schema is unsupported"
fi
recorded_outcome="$(jq -r '.final_workflow_outcome // empty' \
  <<<"$telemetry_summary")"
[[ -n "$recorded_outcome" ]] \
  || fail "the run recorded no final outcome"
[[ "$recorded_outcome" == "$outcome" ]] \
  || fail "outcome $outcome contradicts recorded run outcome $recorded_outcome"
[[ "$recorded_outcome" == "$telemetry_outcome" ]] \
  || fail "telemetry outcome $telemetry_outcome contradicts recorded run outcome $recorded_outcome"

summary_value() {
  jq -r "($1) | tostring"' | gsub("\\|"; "&#124;") | gsub("\\r?\\n"; "<br>")' \
    <<<"$telemetry_summary"
}

telemetry_run_value="$(summary_value '
  "\(.run) (schema \(.schema), integrity \(.integrity.state))"')"
subagent_launches_value="$(summary_value '
  if .subagent_launches.total == 0 then "0"
  else "\(.subagent_launches.total) ("
    + ([.subagent_launches.by_role | to_entries[]
        | select(.value > 0) | "\(.key)=\(.value)"] | join(", "))
    + ")"
  end')"
reviews_value="$(summary_value '
  (.review_delegations // .reviews) as $reviews
  | "\($reviews.total) (readiness=\($reviews.by_kind.readiness), "
  + "full=\($reviews.by_kind.full), delta=\($reviews.by_kind.delta))"')"
validations_value="$(summary_value '
  "\(.validations.total) (passed=\(.validations.passed), "
  + "failed=\(.validations.failed)"
  + (if .validations.interrupted > 0
     then ", interrupted=\(.validations.interrupted)" else "" end)
  + (if .validations.incomplete > 0
     then ", incomplete=\(.validations.incomplete)" else "" end)
  + ")"')"
phase_elapsed_value="$(summary_value '
  ([.phase_elapsed_ms | to_entries[] | "\(.key)=\(.value / 1000 | floor)s"]
    | join(", ")) as $measured
  | if $measured == "" then "unknown" else $measured end')"

# A mechanical aggregate the sink cannot supply renders `unknown` and warns.
# Unavailability of one aggregate is not a telemetry-integrity failure and
# never blocks hand-back; only a fabricated value would be a defect.
bare_run="$(jq -r '.run' <<<"$telemetry_summary")"
derived_value() {
  local label="$1" filter="$2" unit="${3:-}" value
  value="$(jq -r "
    ($filter)
    | select(type == \"number\" and floor == . and . >= 0)
    | tostring" <<<"$telemetry_summary")"
  if [[ -z "$value" ]]; then
    printf 'warning: %s unavailable for run %s; rendered as unknown\n' \
      "$label" "$bare_run" >&2
    printf 'unknown'
  else
    printf '%s%s' "$value" "$unit"
  fi
}

start_to_seal_value="$(derived_value 'start-to-seal elapsed' \
  '.start_to_seal_ms' ' ms')"
implementation_rounds_value="$(derived_value 'implementation rounds' \
  '.rounds.implementation')"
independent_review_rounds_value="$(derived_value 'independent-review rounds' \
  '.rounds.independent_review')"
remediation_rounds_value="$(derived_value 'remediation rounds' \
  '.rounds.remediation')"
validation_executions_value="$(derived_value 'validation executions' \
  '.validations.total')"
reviewed_artifact_bytes_value="$(derived_value 'reviewed artifact bytes' \
  '(.review_delegations // .reviews).input_bytes' ' bytes')"
validation_duration_value="$(derived_value 'recorded validation duration' \
  '.validations.duration_ms' ' ms')"

runs=()
if [[ "$closeout_mode" == previous ]]; then
  mapfile -t runs < <(sed 's/\r$//' "$previous_body" | awk '
    $0 == "## Workflow telemetry" { in_telemetry = 1; next }
    in_telemetry && /^## / { exit }
    in_telemetry && /^Run [1-9][0-9]*: / {
      sub(/^Run [1-9][0-9]*: /, "")
      print
    }
  ')
fi
# Every render appends exactly one frozen root run. An update keeps the
# previous pull-request runs as an immutable prefix, even when the new run has
# the same fingerprint as the one before it.
runs+=("$run_value")

if [[ "${#runs[@]}" -eq 1 ]]; then
  provenance_value='1 run'
else
  provenance_value="${#runs[@]} runs"
fi

# Markdown table cells are kept single-line and escaped without changing the
# facts themselves. Narrative Markdown is copied byte-for-byte (apart from
# normalizing the final blank-line boundary).
table_rows="$(
  jq -r '
    def cell:
      tostring
      | gsub("\\\\"; "\\\\")
      | gsub("\\|"; "&#124;")
      | gsub("\\r?\\n"; "<br>");
    .acceptance[]
    | "| \(.criterion | cell) | \(.production_path | cell) | \(.seam | cell) | \(.evidence | cell) | \(.status | cell) |"
  ' "$facts"
)"

telemetry_value() {
  jq -r --arg field "$1" '.telemetry[$field] | tostring | gsub("\\|"; "&#124;") | gsub("\\r?\\n"; "<br>")' "$facts"
}

# The source note is mechanically owned and exact. validate-closeout-body.sh
# holds the same literal and rejects any body whose note differs, so the two
# cannot drift silently: every render validates its own candidate below.
readonly source_note='> **Source note:** Model configuration, Blocking findings resolved, and Findings rejected at adjudication are primary-reported. The remaining run telemetry is sink-derived; workflow provenance is verified from the frozen run ledger.'

candidate="$fixture/candidate.md"
{
  printf '## Issues\n\n%s #%s\n' "$outcome" "$issue_number"
  if [[ -n "$narrative_source" && -s "$narrative_source" ]]; then
    printf '\n## Narrative\n\n'
    awk '
      { lines[NR] = $0 }
      END {
        last = NR
        while (last > 0 && lines[last] == "") last--
        for (line = 1; line <= last; line++) print lines[line]
      }
    ' "$narrative_source"
  fi
  printf '\n## Closure gate\n\n'
  printf '| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |\n'
  printf '|---|---|---|---|---|\n'
  printf '%s\n' "$table_rows"
  printf '\n## Workflow telemetry\n\n'
  printf '| Field | Observed value |\n'
  printf '|---|---|\n'
  printf '| Model configuration | %s |\n' "$(telemetry_value model_configuration)"
  printf '| Start-to-seal elapsed | %s |\n' "$start_to_seal_value"
  printf '| Implementation rounds | %s |\n' "$implementation_rounds_value"
  printf '| Independent-review rounds | %s |\n' "$independent_review_rounds_value"
  printf '| Remediation rounds | %s |\n' "$remediation_rounds_value"
  printf '| Validation executions | %s |\n' "$validation_executions_value"
  printf '| Blocking findings resolved | %s |\n' "$(telemetry_value blocking_findings_resolved)"
  printf '| Findings rejected at adjudication | %s |\n' "$(telemetry_value findings_rejected_at_adjudication)"
  printf '| Final workflow outcome | %s |\n' "$telemetry_outcome"
  printf '| Telemetry run | %s |\n' "$telemetry_run_value"
  printf '| Subagent launches | %s |\n' "$subagent_launches_value"
  printf '| Reviews recorded | %s |\n' "$reviews_value"
  printf '| Reviewed artifact bytes | %s |\n' "$reviewed_artifact_bytes_value"
  printf '| Validation executions recorded | %s |\n' "$validations_value"
  printf '| Recorded validation duration | %s |\n' "$validation_duration_value"
  printf '| Measured phase elapsed | %s |\n' "$phase_elapsed_value"
  printf '| Workflow provenance | %s |\n\n' "$provenance_value"
  printf '%s\n\n' "$source_note"
  for ((index = 0; index < ${#runs[@]}; index++)); do
    printf 'Run %s: %s\n' "$((index + 1))" "${runs[$index]}"
  done
} >"$candidate"

# Published identity is the repository context, the issue, and the bare run ID.
# The owner-only repository binding is a local authority value: it selects the
# sink and proves the handle belongs here, and it is never published. This
# checks the rendered artifact rather than the intent of the rows above.
if [[ "$run_id" == *@* ]]; then
  binding="${run_id##*@}"
  if [[ -n "$binding" ]] && grep -Fq -- "$binding" "$candidate"; then
    fail "the rendered body contains the local repository binding"
  fi
fi

if [[ "$closeout_mode" == previous ]]; then
  "$script_root/validate-closeout-body.sh" \
    --previous "$previous_body" "$issue_number" "$candidate"
else
  "$script_root/validate-closeout-body.sh" "$issue_number" "$candidate"
fi
cat "$candidate"
