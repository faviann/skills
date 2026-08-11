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

if [[ "$#" -eq 3 && "$3" == --new-pr ]]; then
  closeout_mode=new
  previous_body=""
elif [[ "$#" -eq 4 && "$3" == --previous-body ]]; then
  closeout_mode=previous
  previous_body="$4"
  [[ -f "$previous_body" ]] || fail "previous body file does not exist: $previous_body"
else
  fail "usage: render-closeout.sh <facts.json|-> <narrative.md> (--new-pr | --previous-body <old-body.md>)"
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
jq -e '(has("provenance") or has("workflow_provenance") or has("phases")) | not' \
  "$facts" >/dev/null \
  || fail "workflow provenance comes from the run ledger and previous PR body"

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
telemetry_count_labels=(
  'Implementation rounds'
  'Independent-review rounds'
  'Remediation rounds'
  'Validation executions'
  'Blocking findings resolved'
  'Findings rejected at adjudication'
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

git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)" \
  || fail "target repository git directory is unavailable"
ledger="$git_dir/work-on-provenance.json"
[[ -f "$ledger" ]] || fail "work-on provenance ledger is missing: $ledger"
ledger_canonical="$(jq -er '.canonical | select(type == "string" and length > 0)' \
  "$ledger" 2>/dev/null)" \
  || fail "work-on provenance ledger is invalid"

current_provenance="$fixture/current-provenance.json"
"$script_root/workflow-provenance.sh" >"$current_provenance"
current_canonical="$(jq -er '.canonical | select(type == "string" and length > 0)' \
  "$current_provenance" 2>/dev/null)" \
  || fail "current workflow provenance is invalid"

phases=()
append_phase() {
  local candidate_phase="$1" last_index
  if [[ "${#phases[@]}" -eq 0 ]]; then
    phases+=("$candidate_phase")
    return
  fi
  last_index=$((${#phases[@]} - 1))
  [[ "${phases[$last_index]}" == "$candidate_phase" ]] \
    || phases+=("$candidate_phase")
}

if [[ "$closeout_mode" == previous ]]; then
  normalized_previous_body="$fixture/previous-body.md"
  sed 's/\r$//' "$previous_body" >"$normalized_previous_body"
  "$script_root/validate-closeout-body.sh" "$issue_number" "$normalized_previous_body"
  for ((index = 0; index < ${#telemetry_count_fields[@]}; index++)); do
    field="${telemetry_count_fields[$index]}"
    label="${telemetry_count_labels[$index]}"
    previous_count="$(awk -F'|' -v wanted="$label" '
      $0 == "## Workflow telemetry" { in_telemetry = 1; next }
      in_telemetry && /^## / { exit }
      in_telemetry {
        field = $2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", field)
        if (field == wanted) {
          value = $3
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
          print value
          exit
        }
      }
    ' "$normalized_previous_body")"
    current_count="$(jq -r --arg field "$field" \
      '.telemetry[$field] | tostring' "$facts")"
    if [[ "$previous_count" =~ ^[0-9]+$ && "$current_count" =~ ^[0-9]+$ ]] \
        && (( 10#$current_count < 10#$previous_count )); then
      fail "telemetry $field decreased from $previous_count to $current_count"
    fi
  done
  previous_value="$(awk -F'|' '
    $0 == "## Workflow telemetry" { in_telemetry = 1; next }
    in_telemetry && /^## / { exit }
    in_telemetry && $2 ~ /^[[:space:]]*Workflow provenance[[:space:]]*$/ {
      value = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$normalized_previous_body")"
  if [[ "$previous_value" =~ ^mixed[[:space:]]\(([1-9][0-9]*)[[:space:]]phases\)$ ]]; then
    mapfile -t previous_phases < <(awk '
      $0 == "## Workflow telemetry" { in_telemetry = 1; next }
      in_telemetry && /^## / { exit }
      in_telemetry && /^Phase [1-9][0-9]*: / {
        sub(/^Phase [1-9][0-9]*: /, "")
        print
      }
    ' "$normalized_previous_body")
    for phase in "${previous_phases[@]}"; do
      phases+=("$phase")
    done
  else
    phases+=("$previous_value")
  fi
fi
if [[ "$closeout_mode" == previous ]]; then
  # A resumed run is a new phase even when it loaded the same fingerprint; the
  # phase boundary itself is part of the pull-request history.
  last_index=$((${#phases[@]} - 1))
  if [[ "${phases[$last_index]}" != "$ledger_canonical" \
      || "$ledger_canonical" == "$current_canonical" ]]; then
    phases+=("$ledger_canonical")
  fi
else
  append_phase "$ledger_canonical"
fi
append_phase "$current_canonical"

if [[ "${#phases[@]}" -eq 1 ]]; then
  provenance_value="${phases[0]}"
else
  provenance_value="mixed (${#phases[@]} phases)"
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
  printf '| Workflow provenance | %s |\n' "$provenance_value"
  if [[ "${#phases[@]}" -gt 1 ]]; then
    printf '\n'
    for ((index = 0; index < ${#phases[@]}; index++)); do
      printf 'Phase %s: %s\n' "$((index + 1))" "${phases[$index]}"
    done
  fi
} >"$candidate"

if [[ "$closeout_mode" == previous ]]; then
  "$script_root/validate-closeout-body.sh" \
    --previous "$previous_body" "$issue_number" "$candidate"
else
  "$script_root/validate-closeout-body.sh" "$issue_number" "$candidate"
fi
cat "$candidate"
