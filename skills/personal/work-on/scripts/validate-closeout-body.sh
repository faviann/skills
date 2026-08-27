#!/usr/bin/env bash
set -euo pipefail

# Validate only the mechanically owned facts the rendered body states.

require_closes=false
previous_source=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --require-closes) require_closes=true; shift ;;
    --previous)
      [[ "$#" -ge 2 ]] || { printf 'closeout body invalid: --previous requires a body file\n' >&2; exit 1; }
      previous_source="$2"; shift 2
      ;;
    *) printf 'closeout body invalid: unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done
issue_number="${1:?usage: validate-closeout-body.sh [--require-closes] [--previous <old-body.md>] <issue-number> [body-file|-]}"
body_source="${2:--}"
fail() { printf 'closeout body invalid: %s\n' "$1" >&2; exit 1; }
[[ "$issue_number" =~ ^[1-9][0-9]*$ ]] || fail 'issue number must be a positive integer'

fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
body="$fixture/body.md"
if [[ "$body_source" == - ]]; then sed 's/\r$//' /dev/stdin >"$body"; elif [[ -f "$body_source" ]]; then sed 's/\r$//' "$body_source" >"$body"; else fail "body file does not exist: $body_source"; fi

for heading in '## Issues' '## Closure gate' '## Work-on'; do
  [[ "$(grep -Fxc "$heading" "$body" || true)" -eq 1 ]] || fail "missing canonical heading: $heading"
done
issues_line="$(grep -Fn '## Issues' "$body" | cut -d: -f1)"
gate_line="$(grep -Fn '## Closure gate' "$body" | cut -d: -f1)"
work_on_line="$(grep -Fn '## Work-on' "$body" | cut -d: -f1)"
(( issues_line < gate_line && gate_line < work_on_line )) || fail 'canonical closeout headings are out of order'

section() {
  awk -v heading="$1" '$0 == heading { found = 1; next } found && /^## / { exit } found { print }' "$2"
}
mapfile -t issue_lines < <(section '## Issues' "$body" | sed '/^[[:space:]]*$/d')
[[ "${#issue_lines[@]}" -eq 1 ]] || fail 'Issues section must contain exactly one issue outcome'
if [[ "${issue_lines[0]}" =~ ^(Closes|Progresses)[[:space:]]#${issue_number}$ ]]; then issue_outcome="${BASH_REMATCH[1]}"; else fail "Issues section must map exactly Closes #$issue_number or Progresses #$issue_number"; fi
if [[ "$require_closes" == true && "$issue_outcome" != Closes ]]; then fail "unattended closeout requires Closes #$issue_number; found $issue_outcome #$issue_number"; fi

mapfile -t gate_lines < <(section '## Closure gate' "$body" | sed '/^[[:space:]]*$/d')
readonly gate_header='| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |'
readonly gate_separator='|---|---|---|---|---|'
[[ "${gate_lines[0]:-}" == "$gate_header" ]] || fail 'missing canonical closure gate table header'
[[ "${gate_lines[1]:-}" == "$gate_separator" ]] || fail 'missing canonical closure gate table separator'
[[ "${#gate_lines[@]}" -gt 2 ]] || fail 'closure gate must contain at least one acceptance row'
for ((index=2; index<${#gate_lines[@]}; index++)); do
  row_number=$((index - 1)); row="${gate_lines[$index]}"
  [[ "$row" =~ ^\|.*\|$ && "$(awk -F'|' '{print NF}' <<<"$row")" -eq 7 ]] || fail "closure gate row $row_number must contain five columns"
  for column in {2..6}; do
    value="$(awk -F'|' -v column="$column" '{value=$column; gsub(/^[ \t]+|[ \t]+$/, "", value); print value}' <<<"$row")"
    [[ -n "$value" ]] || fail "closure gate row $row_number has an empty column"
  done
  status="$(awk -F'|' '{value=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", value); print value}' <<<"$row")"
  case "$status" in tested|failing|inferred|unverified) ;; *) fail "closure gate row $row_number has invalid status: $status" ;; esac
  [[ "$issue_outcome" != Closes || "$status" == tested ]] || fail "Closes requires every closure gate row to be tested; row $row_number is $status"
done

canonical='work-on:[0-9a-f]{12}\*? workflow:[0-9a-f]{12}\*? tdd:[0-9a-f]{12}\*? review:[0-9a-f]{12}\*? \(([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+|unknown)@[0-9a-f]{7,40}\)'
mapfile -t entries < <(section '## Work-on' "$body" | sed '/^[[:space:]]*$/d')
[[ "${#entries[@]}" -gt 0 ]] || fail 'Work-on section must contain at least one run'
declare -A seen=()
for ((index=0; index<${#entries[@]}; index++)); do
  line="${entries[$index]}"
  if [[ "$line" =~ ^Run[[:space:]]([A-Za-z0-9._-]{8,64}):[[:space:]]($canonical)$ ]]; then
    identity="${BASH_REMATCH[1]}"
    [[ -z "${seen[$identity]:-}" ]] || fail "Work-on Run identity is duplicated: $identity"
    seen[$identity]=1
  elif [[ "$line" =~ ^Legacy[[:space:]]run:[[:space:]]($canonical)$ ]]; then
    :
  else
    fail "Work-on line $((index + 1)) is malformed"
  fi
done

if [[ -n "$previous_source" ]]; then
  [[ -f "$previous_source" ]] || fail "previous body file does not exist: $previous_source"
  previous="$fixture/previous.md"; sed 's/\r$//' "$previous_source" >"$previous"
  previous_entries=()
  last_gate_line="$(awk '$0 == "## Closure gate" { line = NR } END { print line + 0 }' "$previous")"
  mapfile -t previous_entries < <(awk -v gate_line="$last_gate_line" '
    ! gate_line || NR <= gate_line { next }
    ! selected && $0 == "## Work-on" { selected = "current"; next }
    ! selected && $0 == "## Workflow telemetry" { selected = "legacy"; next }
    selected && /^## / { exit }
    selected == "current" && /^[[:space:]]*$/ { next }
    selected == "current" { print }
    selected == "legacy" && /^Run [1-9][0-9]*: / {
      sub(/^Run [1-9][0-9]*: /, "Legacy run: "); print
    }
  ' "$previous")
  [[ "${#entries[@]}" -ge "${#previous_entries[@]}" ]] || fail 'Work-on history dropped previous entries'
  for ((index=0; index<${#previous_entries[@]}; index++)); do
    [[ "${entries[$index]}" == "${previous_entries[$index]}" ]] || fail "Work-on history rewrote previous entry $((index + 1))"
  done
  appended=$((${#entries[@]} - ${#previous_entries[@]}))
  (( appended <= 1 )) || fail 'Work-on history appended more than one run'
  if (( appended == 1 )); then
    [[ "${entries[-1]}" == Run\ * ]] || fail 'Work-on history appended a non-Run entry'
  fi
fi
