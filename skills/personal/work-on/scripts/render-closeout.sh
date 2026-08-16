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
  || fail "usage: render-closeout.sh --run ID <facts.json|-> <narrative.md> (--new-pr | --previous-body <old-body.md>)"
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
  fail "usage: render-closeout.sh --run ID <facts.json|-> <narrative.md> (--new-pr | --previous-body <old-body.md>)"
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
        or has("validation_outcomes") or has("phase_elapsed"))) | not
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
telemetry_fields=(
  model_configuration
  wall_clock_elapsed
  implementation_rounds
  independent_review_rounds
  remediation_rounds
  validation_executions
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
  implementation_rounds
  independent_review_rounds
  remediation_rounds
  validation_executions
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

# A closeout body reports a finished run. The run resolves its own outcome at
# the closure gate, before any body is rendered, so the three statements of that
# outcome — the issue mapping, the observed telemetry field, and the run's own
# record — must be one statement. A run that never finished has nothing to
# report; a run that finished twice does not have an outcome at all; and a run
# that recorded a different outcome contradicts the body rather than supporting
# it. Each is refused before anything is published.
recorded_finishes="$(jq -r '.finish_events // 0' <<<"$telemetry_summary")"
[[ "$recorded_finishes" =~ ^[0-9]+$ ]] \
  || fail "run telemetry did not report how the run finished"
[[ "$recorded_finishes" -ne 0 ]] \
  || fail "the run has not finished; record run-telemetry.sh finish --run ID at the closure gate"
[[ "$recorded_finishes" -eq 1 ]] \
  || fail "the run recorded $recorded_finishes final outcomes; exactly one is allowed"
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

telemetry_run_value="$(summary_value '"\(.run) (schema \(.schema))"')"
subagent_launches_value="$(summary_value '
  if .subagent_launches.total == 0 then "0"
  else "\(.subagent_launches.total) ("
    + ([.subagent_launches.by_role | to_entries[]
        | select(.value > 0) | "\(.key)=\(.value)"] | join(", "))
    + ")"
  end')"
reviews_value="$(summary_value '
  "\(.reviews.total) (readiness=\(.reviews.by_kind.readiness), "
  + "full=\(.reviews.by_kind.full), delta=\(.reviews.by_kind.delta))"')"
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
  printf '| Wall-clock elapsed | %s |\n' "$(telemetry_value wall_clock_elapsed)"
  printf '| Implementation rounds | %s |\n' "$(telemetry_value implementation_rounds)"
  printf '| Independent-review rounds | %s |\n' "$(telemetry_value independent_review_rounds)"
  printf '| Remediation rounds | %s |\n' "$(telemetry_value remediation_rounds)"
  printf '| Validation executions | %s |\n' "$(telemetry_value validation_executions)"
  printf '| Blocking findings resolved | %s |\n' "$(telemetry_value blocking_findings_resolved)"
  printf '| Findings rejected at adjudication | %s |\n' "$(telemetry_value findings_rejected_at_adjudication)"
  printf '| Final workflow outcome | %s |\n' "$telemetry_outcome"
  printf '| Telemetry run | %s |\n' "$telemetry_run_value"
  printf '| Subagent launches | %s |\n' "$subagent_launches_value"
  printf '| Reviews recorded | %s |\n' "$reviews_value"
  printf '| Validation executions recorded | %s |\n' "$validations_value"
  printf '| Measured phase elapsed | %s |\n' "$phase_elapsed_value"
  printf '| Workflow provenance | %s |\n\n' "$provenance_value"
  for ((index = 0; index < ${#runs[@]}; index++)); do
    printf 'Run %s: %s\n' "$((index + 1))" "${runs[$index]}"
  done
} >"$candidate"

if [[ "$closeout_mode" == previous ]]; then
  "$script_root/validate-closeout-body.sh" \
    --previous "$previous_body" "$issue_number" "$candidate"
else
  "$script_root/validate-closeout-body.sh" "$issue_number" "$candidate"
fi
cat "$candidate"
