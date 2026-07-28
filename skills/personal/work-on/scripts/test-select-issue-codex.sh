#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wrapper="$script_dir/select-issue-codex.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin"
cat >"$fixture/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
schema_file=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --output-last-message)
      output_file="$2"
      shift 2
      ;;
    --output-schema)
      schema_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$output_file" ]]

if [[ -z "$schema_file" ]]; then
  printf '%s\n' \
    'Selected issue: https://github.com/faviann/overmind/issues/144  ' \
    'Selection trace: discarded.' \
    'No issue work was started.' \
    >"$output_file"
  exit
fi

jq -e '
  .required == ["summary", "selected_issue_url"]
  and .properties.selected_issue_url.type == ["string", "null"]
' "$schema_file" >/dev/null

case "${CODEX_BEHAVIOR:-output}" in
  output) printf '%s\n' "${CODEX_OUTPUT:?}" >"$output_file" ;;
  missing_output) ;;
  failure) exit 42 ;;
esac
EOF
chmod +x "$fixture/bin/codex"

run_wrapper() {
  PATH="$fixture/bin:$PATH" \
    CODEX_OUTPUT="${1:-}" \
    CODEX_BEHAVIOR="${2:-output}" \
    "$wrapper" afk
}

selected="$(run_wrapper \
  '{"summary":"Selected #144 for its bounded critical path.","selected_issue_url":"https://github.com/faviann/overmind/issues/144"}')"
expected_selected="$(
  printf '%s\n' \
    'Selection reason: Selected #144 for its bounded critical path.' \
    'Selected issue: https://github.com/faviann/overmind/issues/144'
)"
[[ "$selected" == "$expected_selected" ]] || {
  printf 'selected output mismatch\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_selected" "$selected" >&2
  exit 1
}

none="$(run_wrapper \
  '{"summary":"No eligible issue remains.","selected_issue_url":null}')"
[[ "$none" == 'Selection reason: No eligible issue remains.' ]] || {
  printf 'empty output mismatch: %s\n' "$none" >&2
  exit 1
}

assert_rejected() {
  local name="$1"
  local output="$2"
  local behavior="${3:-output}"
  local actual
  if actual="$(run_wrapper "$output" "$behavior" 2>/dev/null)"; then
    printf 'fixture unexpectedly succeeded: %s\n' "$name" >&2
    exit 1
  fi
  if [[ -n "$actual" ]]; then
    printf 'fixture emitted stdout on failure: %s\n' "$name" >&2
    exit 1
  fi
}

assert_rejected malformed '{"summary":'
assert_rejected missing_summary \
  '{"selected_issue_url":"https://github.com/faviann/overmind/issues/144"}'
assert_rejected empty_summary '{"summary":"","selected_issue_url":null}'
assert_rejected multiline_summary \
  '{"summary":"First line\n","selected_issue_url":null}'
assert_rejected missing_selected_issue '{"summary":"A selection was considered."}'
assert_rejected empty_selected_issue \
  '{"summary":"A selection was considered.","selected_issue_url":""}'
assert_rejected invalid_selected_issue_type \
  '{"summary":"A selection was considered.","selected_issue_url":144}'
assert_rejected invalid_selected_issue_url \
  '{"summary":"A selection was considered.","selected_issue_url":"https://github.com/faviann/overmind/issues/144  "}'
assert_rejected multiline_selected_issue_url \
  '{"summary":"A selection was considered.","selected_issue_url":"https://github.com/faviann/overmind/issues/144\n"}'
assert_rejected extra_property \
  '{"summary":"No issue remains.","selected_issue_url":null,"trace":"discarded"}'
assert_rejected missing_output '' missing_output
assert_rejected codex_failure '' failure

printf 'select-issue Codex wrapper scenarios passed\n'
