#!/usr/bin/env bash
# Run issue selection in a fresh, low-cost Codex process.
set -euo pipefail

readonly model="gpt-5.3-codex-spark"
readonly mode="${1:-manual}"
readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly output_schema="$script_dir/select-issue-output.schema.json"

case "$mode" in
  manual)
    selection_request='Use $select-issue in manual mode.'
    ;;
  afk)
    selection_request='Use $select-issue in AFK mode. Consider only open issues carrying both ready-for-agent and Sandcastle.'
    ;;
  *)
    echo "usage: select-issue-codex.sh [manual | afk]" >&2
    exit 2
    ;;
esac
selection_request+=' Return the result through the required JSON schema: selected_issue_url is the one canonical selected URL, or null when nothing survives; summary is one short single-line reason. Discard trace. Never begin issue work.'

if ! command -v jq >/dev/null 2>&1; then
  echo "select-issue Codex wrapper requires jq" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
result_file="$(mktemp)"
log_file="$(mktemp)"
trap 'rm -f "$result_file" "$log_file"' EXIT

if codex exec \
  --ignore-user-config \
  --ephemeral \
  --model "$model" \
  --cd "$repo_root" \
  --color never \
  --output-schema "$output_schema" \
  --output-last-message "$result_file" \
  --config 'default_permissions="select-issue"' \
  --config 'permissions.select-issue.filesystem={":root"="read"}' \
  --config 'permissions.select-issue.network.enabled=true' \
  "$selection_request" \
  >"$log_file" 2>&1
then
  if [[ ! -s "$result_file" ]]; then
    echo "select-issue Codex process returned no final message" >&2
    exit 1
  fi
  if ! jq -ers '
    select(length == 1) | .[0]
    | select(type == "object" and keys == ["selected_issue_url", "summary"])
    | select(.summary | type == "string" and length > 0 and length <= 500
        and (test("[\r\n]") | not))
    | select(.selected_issue_url == null
        or (.selected_issue_url | type == "string"
          and (test("[\r\n]") | not)
          and test("^https://github\\.com/[A-Za-z0-9-]+/[A-Za-z0-9._-]+/issues/[0-9]+$")))
    | "Selection reason: \(.summary)",
      (if .selected_issue_url == null then empty
       else "Selected issue: \(.selected_issue_url)" end)
  ' "$result_file"; then
    echo "select-issue Codex process returned invalid structured output" >&2
    exit 1
  fi
else
  status=$?
  echo "select-issue Codex process failed with exit status $status" >&2
  tail -40 "$log_file" >&2
  exit "$status"
fi
