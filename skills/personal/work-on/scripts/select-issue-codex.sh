#!/usr/bin/env bash
# Run issue selection in a fresh, low-cost Codex process.
set -euo pipefail

readonly model="gpt-5.3-codex-spark"
readonly mode="${1:-manual}"

case "$mode" in
  manual)
    selection_request='Use $select-issue in manual mode. Return its selection and discard trace. Never begin issue work.'
    ;;
  afk)
    selection_request='Use $select-issue in AFK mode. Consider only open issues carrying both ready-for-agent and Sandcastle. Return its selection and discard trace. Never begin issue work.'
    ;;
  *)
    echo "usage: select-issue-codex.sh [manual | afk]" >&2
    exit 2
    ;;
esac

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
  cat "$result_file"
else
  status=$?
  echo "select-issue Codex process failed with exit status $status" >&2
  tail -40 "$log_file" >&2
  exit "$status"
fi
