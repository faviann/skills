#!/usr/bin/env bash
set -euo pipefail

fail() {
  jq -cn --arg error "$1" '{status: "malformed", error: $error}'
  exit 0
}

command -v jq >/dev/null 2>&1 || {
  printf '%s\n' '{"status":"malformed","error":"JQ_UNAVAILABLE"}'
  exit 0
}

request="$(cat)"
jq -e '
  type == "object"
  and ((keys - ["agent_path", "sessions_root", "target"]) | length == 0)
  and (.target == "current" or .target == "delegate")
  and (.sessions_root | type == "string" and length > 0)
  and (if .target == "delegate"
    then (.agent_path | type == "string"
      and test("^/root/[a-z0-9][a-z0-9_-]{0,63}$"))
    else has("agent_path") | not end)
' <<<"$request" >/dev/null 2>&1 || fail INVALID_REQUEST

sessions_root="$(jq -r '.sessions_root' <<<"$request")"
target="$(jq -r '.target' <<<"$request")"
if [[ "$target" == current ]]; then
  thread_id="${CODEX_THREAD_ID:-}"
  [[ -n "$thread_id" ]] || fail CURRENT_THREAD_ID_MISSING
else
  root_thread_id="${CODEX_SESSION_ID:-}"
  agent_path="$(jq -r '.agent_path' <<<"$request")"
  [[ -n "$root_thread_id" ]] || fail ROOT_THREAD_ID_MISSING
fi
[[ -d "$sessions_root" ]] || {
  jq -cn '{status: "missing", error: "SESSIONS_ROOT_MISSING"}'
  exit 0
}

matches=()
while IFS= read -r -d '' rollout; do
  if [[ "$target" == current ]] && jq -Rn -e --arg id "$thread_id" \
      '[inputs | fromjson? // empty
        | select(.type == "session_meta" and .payload.id == $id)]
        | length > 0' <"$rollout" >/dev/null; then
    matches+=("$rollout")
  elif [[ "$target" == delegate ]] && jq -Rn -e \
      --arg root "$root_thread_id" --arg path "$agent_path" \
      '[inputs | fromjson? // empty
        | select(.type == "session_meta"
          and (.payload.source | type == "object")
          and .payload.source.subagent.thread_spawn.parent_thread_id == $root
          and .payload.source.subagent.thread_spawn.depth == 1
          and .payload.source.subagent.thread_spawn.agent_path == $path)]
        | length > 0' <"$rollout" >/dev/null; then
    matches+=("$rollout")
  fi
done < <(find "$sessions_root" -type f -name '*.jsonl' -print0)

case "${#matches[@]}" in
  0) jq -cn '{status: "missing", error: "ROLLOUT_NOT_FOUND"}'; exit 0 ;;
  1) ;;
  *) jq -cn '{status: "ambiguous", error: "ROLLOUT_AMBIGUOUS"}'; exit 0 ;;
esac

rollout="${matches[0]}"
jq -e '.' "$rollout" >/dev/null 2>&1 || {
  jq -cn '{status: "malformed", error: "ROLLOUT_MALFORMED"}'
  exit 0
}

if [[ "$target" == current ]]; then
  identity_count="$(jq -s --arg id "$thread_id" '[.[]
    | select(.type == "session_meta" and .payload.id == $id)] | length' "$rollout")"
else
  identity_count="$(jq -s --arg root "$root_thread_id" --arg path "$agent_path" '[.[]
    | select(.type == "session_meta"
      and (.payload.source | type == "object")
      and .payload.source.subagent.thread_spawn.parent_thread_id == $root
      and .payload.source.subagent.thread_spawn.depth == 1
      and .payload.source.subagent.thread_spawn.agent_path == $path)] | length' "$rollout")"
fi
[[ "$identity_count" -eq 1 ]] || {
  jq -cn '{status: "malformed", error: "SESSION_IDENTITY_INVALID"}'
  exit 0
}

observation="$(jq -sc '
  def nonnegative: type == "number" and floor == . and . >= 0;
  ([.[] | select(.type == "turn_context") | .payload]
    | last // null) as $context
  | ([.[] | select(.type == "event_msg" and .payload.type == "token_count")
      | .payload.info.total_token_usage | select(type == "object")]
    | last // null) as $usage
  | ($usage.cache_write_input_tokens // $usage.cache_creation_input_tokens // null)
    as $cache_write
  | if $context == null or $usage == null
      or ([$context.model, $context.effort, $usage.input_tokens,
            $usage.cached_input_tokens, $cache_write, $usage.output_tokens,
            $usage.reasoning_output_tokens] | any(. == null))
    then "incomplete"
    elif ($context.model | type != "string" or length == 0 or length > 64
          or test("^[A-Za-z0-9][A-Za-z0-9._-]*$") | not)
      or ($context.effort | type != "string"
          or IN("none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra") | not)
      or ([$usage.input_tokens, $usage.cached_input_tokens, $cache_write,
            $usage.output_tokens, $usage.reasoning_output_tokens]
          | all(nonnegative) | not)
      or ($usage.cached_input_tokens + $cache_write
          > $usage.input_tokens)
      or ($usage.reasoning_output_tokens > $usage.output_tokens)
    then false
    else {
      status: "complete",
      model: $context.model,
      effort: $context.effort,
      tokens: {
        total_input: $usage.input_tokens,
        cached_input: $usage.cached_input_tokens,
        cache_write_input: $cache_write,
        output: $usage.output_tokens,
        reasoning_output: $usage.reasoning_output_tokens
      }
    } end
' "$rollout")"

if [[ "$observation" == '"incomplete"' ]]; then
  jq -cn '{status: "incomplete", error: "OBSERVATION_INCOMPLETE"}'
elif [[ "$observation" == false ]]; then
  jq -cn '{status: "malformed", error: "OBSERVATION_FIELDS_INVALID"}'
else
  printf '%s\n' "$observation"
fi
