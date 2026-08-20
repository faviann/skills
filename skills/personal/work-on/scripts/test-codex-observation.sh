#!/usr/bin/env bash
set -euo pipefail

readonly script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly command_under_test="$script_root/codex-observation.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

sessions="$fixture/sessions"
mkdir -p "$sessions/2026/08/20"

cat >"$sessions/2026/08/20/rollout-primary.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"root-thread","source":"cli"}}
{"type":"turn_context","payload":{"model":"old-model","effort":"low"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":2,"reasoning_output_tokens":1,"total_tokens":12}}}}
{"type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":30,"cached_input_tokens":20,"cache_write_input_tokens":3,"output_tokens":7,"reasoning_output_tokens":2,"total_tokens":37}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1}}}}
EOF

# A child mentions the root id in metadata; exact session identity must keep it
# from winning a textual or parent-id search for the current rollout.
cat >"$sessions/2026/08/20/rollout-child.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"child-thread","source":{"subagent":{"thread_spawn":{"parent_thread_id":"root-thread","depth":1,"agent_path":"/root/issue-83-implementation-1"}}}}}
{"type":"turn_context","payload":{"model":"wrong-child-model","effort":"medium"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":99,"cached_input_tokens":90,"cache_write_input_tokens":0,"output_tokens":9,"reasoning_output_tokens":4,"total_tokens":108}}}}
EOF

actual="$(
  CODEX_THREAD_ID=root-thread \
    "$command_under_test" <<EOF
{"target":"current","sessions_root":"$sessions"}
EOF
)"

jq -e '
  . == {
    status: "complete",
    model: "gpt-test",
    effort: "high",
    tokens: {
      total_input: 30,
      cached_input: 20,
      cache_write_input: 3,
      output: 7,
      reasoning_output: 2
    }
  }
' <<<"$actual" >/dev/null

delegate="$(
  CODEX_SESSION_ID=root-thread \
    "$command_under_test" <<EOF
{"target":"delegate","agent_path":"/root/issue-83-implementation-1","sessions_root":"$sessions"}
EOF
)"
jq -e '.status == "complete" and .model == "wrong-child-model"
  and .tokens.total_input == 99' <<<"$delegate" >/dev/null

cat >"$sessions/2026/08/20/rollout-duplicate.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"duplicate","source":"cli"}}
{"type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1}}}}
EOF
cp "$sessions/2026/08/20/rollout-duplicate.jsonl" \
  "$sessions/2026/08/20/rollout-duplicate-copy.jsonl"
ambiguous="$(
  CODEX_THREAD_ID=duplicate "$command_under_test" <<EOF
{"target":"current","sessions_root":"$sessions"}
EOF
)"
jq -e '. == {status:"ambiguous", error:"ROLLOUT_AMBIGUOUS"}' \
  <<<"$ambiguous" >/dev/null

missing="$(
  CODEX_THREAD_ID=absent "$command_under_test" <<EOF
{"target":"current","sessions_root":"$sessions"}
EOF
)"
jq -e '. == {status:"missing", error:"ROLLOUT_NOT_FOUND"}' \
  <<<"$missing" >/dev/null

cat >"$sessions/2026/08/20/rollout-incomplete.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"incomplete","source":"cli"}}
{"type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
EOF
incomplete="$(
  CODEX_THREAD_ID=incomplete "$command_under_test" <<EOF
{"target":"current","sessions_root":"$sessions"}
EOF
)"
jq -e '. == {status:"incomplete", error:"OBSERVATION_INCOMPLETE"}' \
  <<<"$incomplete" >/dev/null

cat >"$sessions/2026/08/20/rollout-missing-dimension.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"missing-dimension","source":"cli"}}
{"type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":2,"reasoning_output_tokens":1}}}}
EOF
missing_dimension="$(
  CODEX_THREAD_ID=missing-dimension "$command_under_test" <<EOF
{"target":"current","sessions_root":"$sessions"}
EOF
)"
jq -e '. == {status:"incomplete", error:"OBSERVATION_INCOMPLETE"}' \
  <<<"$missing_dimension" >/dev/null

cat >"$sessions/2026/08/20/rollout-malformed-interior.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"malformed-interior","source":"cli"}}
not-json
{"type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":4,"cache_write_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":1}}}}
EOF
malformed_interior="$(
  CODEX_THREAD_ID=malformed-interior "$command_under_test" <<EOF
{"target":"current","sessions_root":"$sessions"}
EOF
)"
jq -e '. == {status:"malformed", error:"ROLLOUT_MALFORMED"}' \
  <<<"$malformed_interior" >/dev/null

cat >"$sessions/2026/08/20/rollout-truncated.jsonl" <<'EOF'
{"type":"session_meta","payload":{"id":"truncated","source":"cli"}}
{"type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1
EOF
truncated="$(
  CODEX_THREAD_ID=truncated "$command_under_test" <<EOF
{"target":"current","sessions_root":"$sessions"}
EOF
)"
jq -e '. == {status:"malformed", error:"ROLLOUT_MALFORMED"}' \
  <<<"$truncated" >/dev/null

printf 'codex observation scenarios passed\n'
