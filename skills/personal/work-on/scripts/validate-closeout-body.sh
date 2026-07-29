#!/usr/bin/env bash
set -euo pipefail

# Validate the canonical closeout sections in a rendered pull-request body.
# This checks shape and consistency only; afk-merge.sh remains responsible for
# independently deciding whether the evidence merits an unattended merge.

issue_number="${1:?usage: validate-closeout-body.sh <issue-number> [body-file|-]}"
body_source="${2:--}"

fail() {
  printf 'closeout body invalid: %s\n' "$1" >&2
  exit 1
}

[[ "$issue_number" =~ ^[1-9][0-9]*$ ]] \
  || fail "issue number must be a positive integer"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
body="$fixture/body.md"
if [[ "$body_source" == - ]]; then
  cp /dev/stdin "$body"
elif [[ -f "$body_source" ]]; then
  cp "$body_source" "$body"
else
  fail "body file does not exist: $body_source"
fi

for heading in "## Issues" "## Closure gate" "## Workflow telemetry"; do
  heading_count="$(grep -Fxc "$heading" "$body" || true)"
  [[ "$heading_count" -eq 1 ]] || fail "missing canonical heading: $heading"
done
issues_line="$(grep -Fn '## Issues' "$body" | cut -d: -f1)"
gate_line="$(grep -Fn '## Closure gate' "$body" | cut -d: -f1)"
telemetry_line="$(grep -Fn '## Workflow telemetry' "$body" | cut -d: -f1)"
(( issues_line < gate_line && gate_line < telemetry_line )) \
  || fail "canonical closeout headings are out of order"

section() {
  local heading="$1"
  awk -v heading="$heading" '
    $0 == heading { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$body"
}

mapfile -t issue_lines < <(section "## Issues" | sed '/^[[:space:]]*$/d')
[[ "${#issue_lines[@]}" -eq 1 ]] \
  || fail "Issues section must contain exactly one issue outcome"
if [[ "${issue_lines[0]}" =~ ^(Closes|Progresses)[[:space:]]#${issue_number}$ ]]; then
  issue_outcome="${BASH_REMATCH[1]}"
else
  fail "Issues section must map exactly Closes #$issue_number or Progresses #$issue_number"
fi

mapfile -t gate_lines < <(section "## Closure gate" | sed '/^[[:space:]]*$/d')
readonly gate_header='| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |'
readonly gate_separator='|---|---|---|---|---|'
[[ "${gate_lines[0]:-}" == "$gate_header" ]] \
  || fail "missing canonical closure gate table header"
[[ "${gate_lines[1]:-}" == "$gate_separator" ]] \
  || fail "missing canonical closure gate table separator"
[[ "${#gate_lines[@]}" -gt 2 ]] \
  || fail "closure gate must contain at least one acceptance row"

for ((index = 2; index < ${#gate_lines[@]}; index++)); do
  row_number=$((index - 1))
  row="${gate_lines[$index]}"
  [[ "$row" =~ ^\|.*\|$ ]] \
    || fail "closure gate row $row_number is not a Markdown table row"
  field_count="$(awk -F'|' '{ print NF }' <<<"$row")"
  [[ "$field_count" -eq 7 ]] \
    || fail "closure gate row $row_number must contain five columns"
  for column in {2..6}; do
    value="$(awk -F'|' -v column="$column" '{
      value = $column
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      print value
    }' <<<"$row")"
    [[ -n "$value" ]] \
      || fail "closure gate row $row_number has an empty column"
  done
  status="$(awk -F'|' '{
    value = $(NF - 1)
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    print value
  }' <<<"$row")"
  case "$status" in
    tested|failing|inferred|unverified) ;;
    *) fail "closure gate row $row_number has invalid status: $status" ;;
  esac
  if [[ "$issue_outcome" == Closes && "$status" != tested ]]; then
    fail "Closes requires every closure gate row to be tested; row $row_number is $status"
  fi
done

mapfile -t telemetry_lines < <(section "## Workflow telemetry" | sed '/^[[:space:]]*$/d')
readonly telemetry_header='| Field | Observed value |'
readonly telemetry_separator='|---|---|'
[[ "${telemetry_lines[0]:-}" == "$telemetry_header" ]] \
  || fail "missing canonical workflow telemetry table header"
[[ "${telemetry_lines[1]:-}" == "$telemetry_separator" ]] \
  || fail "missing canonical workflow telemetry table separator"

telemetry_fields=(
  "Model configuration"
  "Wall-clock elapsed"
  "Implementation rounds"
  "Independent-review rounds"
  "Remediation rounds"
  "Validation executions"
  "Blocking findings resolved"
  "Findings rejected at adjudication"
  "Final workflow outcome"
)
[[ "${#telemetry_lines[@]}" -eq 11 ]] \
  || fail "workflow telemetry must contain exactly nine canonical rows"

for ((index = 0; index < ${#telemetry_fields[@]}; index++)); do
  row="${telemetry_lines[$((index + 2))]}"
  [[ "$row" =~ ^\|.*\|$ && "$(awk -F'|' '{ print NF }' <<<"$row")" -eq 4 ]] \
    || fail "workflow telemetry row $((index + 1)) must contain two columns"
  field="$(awk -F'|' '{
    value = $2
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    print value
  }' <<<"$row")"
  value="$(awk -F'|' '{
    value = $3
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    print value
  }' <<<"$row")"
  [[ "$field" == "${telemetry_fields[$index]}" ]] \
    || fail "workflow telemetry row $((index + 1)) must be ${telemetry_fields[$index]}"
  [[ -n "$value" ]] \
    || fail "workflow telemetry row $((index + 1)) has an empty observed value"
  case "$field" in
    "Implementation rounds"|"Independent-review rounds"|"Remediation rounds"|"Validation executions"|"Blocking findings resolved"|"Findings rejected at adjudication")
      [[ "$value" == unknown || "$value" =~ ^[0-9]+$ ]] \
        || fail "workflow telemetry $field must be a nonnegative integer or unknown"
      ;;
  esac
  if [[ "$field" == "Final workflow outcome" ]]; then
    telemetry_outcome="$value"
  fi
done

[[ "$telemetry_outcome" == Closes || "$telemetry_outcome" == Progresses ]] \
  || fail "workflow telemetry outcome must be Closes or Progresses"
[[ "$telemetry_outcome" == "$issue_outcome" ]] \
  || fail "issue outcome $issue_outcome contradicts telemetry outcome $telemetry_outcome"
