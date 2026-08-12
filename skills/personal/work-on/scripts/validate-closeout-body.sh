#!/usr/bin/env bash
set -euo pipefail

# Validate the canonical closeout sections in a rendered pull-request body.
# This checks shape and consistency only; afk-merge.sh remains responsible for
# independently deciding whether the evidence merits an unattended merge.

require_closes=false
previous_source=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --require-closes)
      require_closes=true
      shift
      ;;
    --previous)
      [[ "$#" -ge 2 ]] || {
        printf 'closeout body invalid: --previous requires a body file\n' >&2
        exit 1
      }
      previous_source="$2"
      shift 2
      ;;
    *)
      printf 'closeout body invalid: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done
issue_number="${1:?usage: validate-closeout-body.sh [--require-closes] [--previous <old-body.md>] <issue-number> [body-file|-]}"
body_source="${2:--}"

fail() {
  printf 'closeout body invalid: %s\n' "$1" >&2
  exit 1
}

decimal_is_less_than() {
  local left="$1" right="$2" LC_ALL=C
  while [[ "${#left}" -gt 1 && "${left:0:1}" == 0 ]]; do
    left="${left:1}"
  done
  while [[ "${#right}" -gt 1 && "${right:0:1}" == 0 ]]; do
    right="${right:1}"
  done
  if [[ "${#left}" -ne "${#right}" ]]; then
    [[ "${#left}" -lt "${#right}" ]]
  else
    [[ "$left" < "$right" ]]
  fi
}

[[ "$issue_number" =~ ^[1-9][0-9]*$ ]] \
  || fail "issue number must be a positive integer"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
body="$fixture/body.md"
# GitHub stores bodies edited through its web UI with CRLF line endings and
# returns them verbatim, so normalize the scratch copy the checks read. Only
# this copy is affected; the validator never re-emits the body.
if [[ "$body_source" == - ]]; then
  sed 's/\r$//' /dev/stdin >"$body"
elif [[ -f "$body_source" ]]; then
  sed 's/\r$//' "$body_source" >"$body"
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
if [[ "$require_closes" == true && "$issue_outcome" != Closes ]]; then
  fail "unattended closeout requires Closes #$issue_number; found $issue_outcome #$issue_number"
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
  "Workflow provenance"
)
telemetry_count_values=()
[[ "${#telemetry_lines[@]}" -ge 12 ]] \
  || fail "workflow telemetry must contain ten canonical rows"

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
      telemetry_count_values+=("$value")
      ;;
  esac
  if [[ "$field" == "Final workflow outcome" ]]; then
    telemetry_outcome="$value"
  fi
  if [[ "$field" == "Workflow provenance" ]]; then
    provenance_value="$value"
  fi
done

[[ "$telemetry_outcome" == Closes || "$telemetry_outcome" == Progresses ]] \
  || fail "workflow telemetry outcome must be Closes or Progresses"
[[ "$telemetry_outcome" == "$issue_outcome" ]] \
  || fail "issue outcome $issue_outcome contradicts telemetry outcome $telemetry_outcome"

canonical_provenance_pattern='^work-on:[0-9a-f]{12}\*?[[:space:]]workflow:[0-9a-f]{12}\*?[[:space:]]tdd:[0-9a-f]{12}\*?[[:space:]]review:[0-9a-f]{12}\*?[[:space:]]\(([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+|unknown)@[0-9a-f]{7,40}\)$'

[[ "$provenance_value" =~ ^([1-9][0-9]*)[[:space:]]runs?$ ]] \
  || fail "workflow provenance is malformed"
run_count="${BASH_REMATCH[1]}"
if [[ "$run_count" -eq 1 ]]; then
  [[ "$provenance_value" == '1 run' ]] || fail "workflow provenance is malformed"
else
  [[ "$provenance_value" == "$run_count runs" ]] \
    || fail "workflow provenance is malformed"
fi
[[ "${#telemetry_lines[@]}" -eq $((12 + run_count)) ]] \
  || fail "workflow provenance run count does not match run lines"

provenance_runs=()
for ((index = 1; index <= run_count; index++)); do
  run_line="${telemetry_lines[$((11 + index))]}"
  run_prefix="Run $index: "
  [[ "$run_line" == "$run_prefix"* ]] \
    || fail "workflow provenance run $index is malformed or out of order"
  run="${run_line#"$run_prefix"}"
  [[ "$run" =~ $canonical_provenance_pattern ]] \
    || fail "workflow provenance run $index is malformed"
  provenance_runs+=("$run")
done

if [[ -n "$previous_source" ]]; then
  [[ -f "$previous_source" ]] \
    || fail "previous body file does not exist: $previous_source"
  previous_body="$fixture/previous.md"
  sed 's/\r$//' "$previous_source" >"$previous_body"
  "$0" "$issue_number" "$previous_body"
  mapfile -t previous_runs < <(awk '
    $0 == "## Workflow telemetry" { in_telemetry = 1; next }
    in_telemetry && /^## / { exit }
    in_telemetry && /^Run [1-9][0-9]*: / {
      sub(/^Run [1-9][0-9]*: /, "")
      print
    }
  ' "$previous_body")
  [[ "${#provenance_runs[@]}" -ge "${#previous_runs[@]}" ]] \
    || fail "workflow provenance dropped previous runs"
  for ((index = 0; index < ${#previous_runs[@]}; index++)); do
    [[ "${provenance_runs[$index]}" == "${previous_runs[$index]}" ]] \
      || fail "workflow provenance rewrote previous run $((index + 1))"
  done
  [[ "${#provenance_runs[@]}" -gt "${#previous_runs[@]}" ]] \
    || fail "workflow provenance must append at least one run"

  mapfile -t previous_count_values < <(awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    $0 == "## Workflow telemetry" { in_telemetry = 1; next }
    in_telemetry && /^## / { exit }
    in_telemetry {
      field = trim($2)
      if (field ~ /^(Implementation rounds|Independent-review rounds|Remediation rounds|Validation executions|Blocking findings resolved|Findings rejected at adjudication)$/) {
        print trim($3)
      }
    }
  ' "$previous_body")
  for ((index = 0; index < ${#telemetry_count_values[@]}; index++)); do
    previous_count="${previous_count_values[$index]}"
    current_count="${telemetry_count_values[$index]}"
    if [[ "$previous_count" =~ ^[0-9]+$ && "$current_count" =~ ^[0-9]+$ ]] \
        && decimal_is_less_than "$current_count" "$previous_count"; then
      fail "workflow telemetry ${telemetry_fields[$((index + 2))]} decreased from $previous_count to $current_count"
    fi
  done
fi
