#!/usr/bin/env bash
set -euo pipefail

# Render the mechanically owned pull-request sections from authored facts and
# the exact provenance captured in Run custody.

script_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
fail() { printf 'closeout invalid: %s\n' "$1" >&2; exit 1; }
usage='usage: render-closeout.sh --run ID <facts.json|-> <narrative.md> (--new-pr | --previous-body <old-body.md>)'
[[ "${1:-}" == --run && -n "${2:-}" ]] || fail "$usage"
run_identity="$2"
[[ "$run_identity" =~ ^[A-Za-z0-9._-]{8,64}$ ]] || fail 'Run identity is malformed'
shift 2
if [[ "$#" -eq 3 && "$3" == --new-pr ]]; then mode=new; previous_body=""; elif [[ "$#" -eq 4 && "$3" == --previous-body ]]; then mode=previous; previous_body="$4"; [[ -f "$previous_body" ]] || fail "previous body file does not exist: $previous_body"; else fail "$usage"; fi
facts_source="$1"; narrative_source="$2"

fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
facts="$fixture/facts.json"
if [[ "$facts_source" == - ]]; then cp /dev/stdin "$facts"; elif [[ -f "$facts_source" ]]; then cp "$facts_source" "$facts"; else fail "facts file does not exist: $facts_source"; fi
jq -e 'type == "object"' "$facts" >/dev/null 2>&1 || fail 'facts must be a JSON object'
jq -e '((keys - ["issue_number","outcome","acceptance_criteria","acceptance"]) | length) == 0' "$facts" >/dev/null || fail 'facts may contain only issue_number, outcome, acceptance_criteria, and acceptance'
jq -e 'has("telemetry") | not' "$facts" >/dev/null || fail 'telemetry material is not accepted'

jq -e '.issue_number | type == "number" and . > 0 and floor == .' "$facts" >/dev/null || fail 'issue_number must be a positive integer'
issue_number="$(jq -r '.issue_number' "$facts")"
outcome="$(jq -r '.outcome // empty' "$facts")"
[[ "$outcome" == Closes || "$outcome" == Progresses ]] || fail 'outcome must be Closes or Progresses'
jq -e '.acceptance_criteria | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' "$facts" >/dev/null || fail 'acceptance_criteria must be a non-empty array of non-empty strings'
jq -e '.acceptance | type == "array" and length > 0' "$facts" >/dev/null || fail 'acceptance must contain at least one row'
duplicate="$(jq -r '.acceptance_criteria | [group_by(.)[] | select(length>1) | .[0]][0] // empty' "$facts")"
[[ -z "$duplicate" ]] || fail "acceptance_criteria contains duplicate criterion: $duplicate"
acceptance_count="$(jq -r '.acceptance | length' "$facts")"
for ((index=0; index<acceptance_count; index++)); do
  row=$((index+1))
  for field in criterion production_path seam evidence status; do jq -e --argjson i "$index" --arg f "$field" '.acceptance[$i][$f] | type=="string" and length>0' "$facts" >/dev/null || fail "acceptance row $row requires non-empty $field"; done
  status="$(jq -r --argjson i "$index" '.acceptance[$i].status' "$facts")"
  case "$status" in tested|failing|inferred|unverified) ;; *) fail "acceptance row $row has invalid status: $status" ;; esac
  [[ "$outcome" != Closes || "$status" == tested ]] || fail "Closes requires every acceptance row to be tested; row $row is $status"
done
jq -e '([.acceptance_criteria[]] | sort) == ([.acceptance[].criterion] | sort) and ([.acceptance[].criterion] | unique | length) == (.acceptance | length)' "$facts" >/dev/null || fail 'acceptance rows must match acceptance_criteria exactly once'
if [[ -n "$narrative_source" && ! -f "$narrative_source" ]]; then fail "narrative file does not exist: $narrative_source"; fi

# `read` validates complete custody but deliberately does not compare live
# instructions; the capture governs this uninterrupted invocation.
"$script_root/manifest-identity.sh" read --run "$run_identity" >/dev/null || fail 'complete Run custody verification failed'
provenance="$($script_root/workflow-provenance.sh read --run "$run_identity")" || fail 'captured workflow provenance read failed'
current_line="Run $run_identity: $provenance"

entries=()
if [[ "$mode" == previous ]]; then
  normalized_previous="$fixture/previous.md"; sed 's/\r$//' "$previous_body" >"$normalized_previous"
  if grep -Fqx '## Work-on' "$normalized_previous"; then
    mapfile -t entries < <(awk '$0=="## Work-on"{inside=1;next} inside&&/^## /{exit} inside&&/^[[:space:]]*$/{next} inside{print}' "$normalized_previous")
  else
    mapfile -t entries < <(awk '$0=="## Workflow telemetry"{inside=1;next} inside&&/^## /{exit} inside&&/^Run [1-9][0-9]*: /{sub(/^Run [1-9][0-9]*: /,"Legacy run: "); print}' "$normalized_previous")
  fi
fi
found=false
for entry in "${entries[@]}"; do
  if [[ "$entry" == "Run $run_identity: "* ]]; then
    [[ "$entry" == "$current_line" ]] || fail "Run identity $run_identity already has contradictory provenance"
    found=true
  fi
done
[[ "$found" == true ]] || entries+=("$current_line")

table_rows="$(jq -r 'def cell: tostring|gsub("\\|";"&#124;")|gsub("\\r?\\n";"<br>"); .acceptance[] | "| \(.criterion|cell) | \(.production_path|cell) | \(.seam|cell) | \(.evidence|cell) | \(.status|cell) |"' "$facts")"
candidate="$fixture/candidate.md"
{
  printf '## Issues\n\n%s #%s\n' "$outcome" "$issue_number"
  if [[ -n "$narrative_source" && -s "$narrative_source" ]]; then
    printf '\n## Narrative\n\n'
    awk '{lines[NR]=$0} END{last=NR; while(last>0&&lines[last]=="")last--; for(i=1;i<=last;i++)print lines[i]}' "$narrative_source"
  fi
  printf '\n## Closure gate\n\n| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |\n|---|---|---|---|---|\n%s\n' "$table_rows"
  printf '\n## Work-on\n\n'
  printf '%s\n' "${entries[@]}"
} >"$candidate"

if [[ "$mode" == previous ]]; then "$script_root/validate-closeout-body.sh" --previous "$previous_body" "$issue_number" "$candidate"; else "$script_root/validate-closeout-body.sh" "$issue_number" "$candidate"; fi
cat "$candidate"
