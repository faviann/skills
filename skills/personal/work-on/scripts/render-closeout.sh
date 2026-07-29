#!/usr/bin/env bash
set -euo pipefail

# Validate structured closeout facts and render the evidence-oriented sections
# of a pull-request body. Narrative Markdown remains ordinary Markdown and is
# copied between the issue mapping and the mechanical evidence sections.

facts_source="${1:--}"
narrative_source="${2:-}"

fail() {
  printf 'closeout invalid: %s\n' "$1" >&2
  exit 1
}

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

jq -e '.issue_number | type == "number" and . > 0 and floor == .' \
  "$facts" >/dev/null || fail "issue_number must be a positive integer"
issue_number="$(jq -r '.issue_number' "$facts")"
[[ "$issue_number" =~ ^[1-9][0-9]*$ ]] \
  || fail "issue_number must be a positive integer"

outcome="$(jq -r '.outcome // empty' "$facts")"
[[ "$outcome" == Closes || "$outcome" == Progresses ]] \
  || fail "outcome must be Closes or Progresses"

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

printf '## Issues\n\n%s #%s\n' "$outcome" "$issue_number"
if [[ -n "$narrative_source" && -s "$narrative_source" ]]; then
  printf '\n'
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
