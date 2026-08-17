#!/usr/bin/env bash
set -euo pipefail

# Adapt the generic work-on run registry to a versioned experiment policy and
# publish bounded, immutable control/run transitions to one GitHub results PR.
# The run registry remains the sole lease and run-lifecycle authority.

readonly policy_schema=1
readonly observer_not_applicable=3
readonly token_pattern='^[a-z0-9]+(-[a-z0-9]+)*$'
readonly repository_pattern='^[a-z0-9_.-]+/[a-z0-9_.-]+$'
readonly branch_pattern='^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$'

fail() {
  printf 'control window: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: control-window.sh <subcommand>
  validate --policy FILE
  prepare --policy FILE
  activate --policy FILE
  register --run HANDLE
  finalize (--run HANDLE [--outcome O] | --record FILE --transition ID)
  recover (--run HANDLE | --all) [--outcome O]
  status [--policy FILE] [run-registry status arguments]
  close --policy FILE [--complete]
  applies --repository OWNER/REPOSITORY --issue N

WORK_ON_CONTROL_POLICY may name the absolute manifest used by observer calls.
USAGE
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "requires jq"
command -v git >/dev/null 2>&1 || fail "requires git"

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly registry_script="$script_root/run-registry.sh"

require_absolute_file() {
  local name="$1" path="$2"
  [[ "$path" == /* ]] || fail "$name must be an absolute path"
  [[ -f "$path" ]] || fail "$name does not exist: $path"
}

policy_json=""
policy_path=""
control_id=""
policy_mode=""
load_policy() {
  local path="$1"
  require_absolute_file "policy" "$path"
  policy_json="$(jq -cS . "$path" 2>/dev/null)" \
    || fail "policy is not valid JSON"

  jq -e \
    --argjson schema "$policy_schema" \
    --arg token "$token_pattern" \
    --arg repository "$repository_pattern" \
    --arg branch "$branch_pattern" '
    def token: type == "string" and length > 0 and length <= 64 and test($token);
    def repo: type == "string" and length <= 160 and test($repository);
    def issue: type == "number" and floor == . and . > 0;
    type == "object"
    and (keys == ["arm","control_id","hooks","lease","mode","observer_id","population","results","schema","target"])
    and .schema == $schema
    and (.control_id | token) and (.observer_id | token)
    and (.mode | IN("demo","production"))
    and (.target | type == "object" and keys == ["issue","repository"]
      and (.repository | repo) and (.issue | issue))
    and (.population | type == "object" and keys == ["issues","repositories"]
      and (.repositories | type == "array" and length <= 64 and all(.[]; repo))
      and (.issues | type == "array" and length <= 256 and all(.[]; issue))
      and ((.repositories | unique | length) == (.repositories | length))
      and ((.issues | unique | length) == (.issues | length)))
    and (.hooks | type == "object" and keys == ["classify","match"]
      and (.match | IN("never-v1","repository-issue-set-v1"))
      and .classify == "registry-lifecycle-v1")
    and (.results | type == "object"
      and keys == ["base_branch","branch","pull_request","repository"]
      and (.repository | repo)
      and (.base_branch | type == "string" and test($branch))
      and (.branch | type == "string" and test($branch))
      and .base_branch != .branch
      and .pull_request == {draft:true})
    and (.lease == {authority:"run-registry-v1",scope:"control",maximum_active_runs:1})
    and (.arm | type == "object" and keys == ["configuration","id"]
      and (.id | token) and (.configuration | type == "object"))
    and (if .hooks.match == "never-v1"
      then (.population.repositories | length) == 0 and (.population.issues | length) == 0
      else (.population.repositories | length) > 0 and (.population.issues | length) > 0 end)
    and (if .mode == "demo"
      then (.control_id | startswith("demo-"))
        and (.results.branch | startswith("demo/"))
        and .hooks.match == "never-v1"
      else true end)
  ' <<<"$policy_json" >/dev/null || fail "policy does not match schema 1"

  policy_path="$path"
  control_id="$(jq -r .control_id <<<"$policy_json")"
  policy_mode="$(jq -r .mode <<<"$policy_json")"
  git check-ref-format "refs/heads/$(jq -r .results.base_branch <<<"$policy_json")" \
    >/dev/null 2>&1 || fail "policy base branch is not a valid Git ref"
  git check-ref-format "refs/heads/$(jq -r .results.branch <<<"$policy_json")" \
    >/dev/null 2>&1 || fail "policy results branch is not a valid Git ref"
}

resolve_policy_path() {
  local supplied="${1:-}" candidate descriptor root
  if [[ -n "$supplied" ]]; then
    printf '%s\n' "$supplied"
    return
  fi
  candidate="${WORK_ON_CONTROL_POLICY:-}"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return
  fi
  root="${XDG_CONFIG_HOME:-${HOME:-}/.config}"
  [[ "$root" == /* ]] || fail "XDG_CONFIG_HOME or HOME must resolve to an absolute path"
  descriptor="$root/work-on/control-policy"
  [[ -f "$descriptor" ]] || return 1
  IFS= read -r candidate <"$descriptor"
  [[ -n "$candidate" && "$candidate" == /* \
    && "$(wc -l <"$descriptor")" -eq 1 ]] \
    || fail "configured control policy descriptor is malformed"
  printf '%s\n' "$candidate"
}

state_home() {
  local root="${XDG_STATE_HOME:-${HOME:-}/.local/state}"
  [[ "$root" == /* ]] || fail "XDG_STATE_HOME or HOME must resolve to an absolute path"
  printf '%s/work-on/control-windows\n' "$root"
}

state_file() {
  printf '%s/%s.json\n' "$(state_home)" "$1"
}

read_state() {
  local file
  file="$(state_file "$control_id")"
  [[ -f "$file" ]] || return 1
  cat "$file"
}

sha256_of_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    fail "requires sha256sum or shasum"
  fi
}

public_policy() {
  jq -cS '{schema,control_id,mode,observer_id,target,population,hooks,
    results:{repository:.results.repository,base_branch:.results.base_branch,
      branch:.results.branch},lease,arm:{id:.arm.id}}' <<<"$policy_json"
}

policy_digest() {
  public_policy | sha256_of_stdin
}

manifest_digest() {
  printf '%s' "$policy_json" | sha256_of_stdin
}

transition_with_identity() {
  local body="$1" identity
  identity="$(jq -cS 'del(.transition_id)' <<<"$body" | sha256_of_stdin)"
  jq -cS --arg identity "$identity" '.transition_id = $identity' <<<"$body"
}

prepared_transition() {
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg digest "$(policy_digest)" \
    --arg mode "$policy_mode" \
    --arg repository "$(jq -r .target.repository <<<"$policy_json")" \
    --argjson issue "$(jq -r .target.issue <<<"$policy_json")" '
    {schema:1,control_id:$control,transition_id:null,kind:"control-prepared",
     idempotency_key:("prepare:" + $control),policy_digest:$digest,mode:$mode,
     target_repository:$repository,target_issue:$issue}')"
}

activation_transition() {
  local prepared
  prepared="$(jq -r .transition_id <<<"$(prepared_transition)")"
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg digest "$(policy_digest)" \
    --arg prepared "$prepared" '
    {schema:1,control_id:$control,transition_id:null,kind:"control-activated",
     idempotency_key:("activate:" + $control),policy_digest:$digest,
     prepared_transition:$prepared}')"
}

run_identity_for_handle() {
  printf 'work-on-run\0%s\0%s' "$control_id" "$1" | sha256_of_stdin
}

registration_transition() {
  local record="$1" handle run_identity
  handle="$(jq -r '"\(.run_id)@\(.repository_binding)"' <<<"$record")"
  run_identity="$(run_identity_for_handle "$handle")"
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg run_identity "$run_identity" \
    --arg run_id "$(jq -r .run_id <<<"$record")" \
    --arg repository "$(jq -r .repository <<<"$record")" \
    --argjson issue "$(jq -r .issue <<<"$record")" '
    {schema:1,control_id:$control,transition_id:null,kind:"run-registered",
     idempotency_key:("register:" + $run_identity),run_identity:$run_identity,
     run_id:$run_id,repository:$repository,issue:$issue,telemetry_schema:2}')"
}

finalization_transition() {
  local record="$1" generic_transition="$2" handle run_identity kind
  handle="$(jq -r '"\(.run_id)@\(.repository_binding)"' <<<"$record")"
  run_identity="$(run_identity_for_handle "$handle")"
  kind=run-finalized
  [[ "$(jq -r .outcome <<<"$record")" == failed ]] && kind=run-failed
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg kind "$kind" \
    --arg generic_transition "$generic_transition" \
    --arg run_identity "$run_identity" --arg run_id "$(jq -r .run_id <<<"$record")" \
    --arg repository "$(jq -r .repository <<<"$record")" \
    --argjson issue "$(jq -r .issue <<<"$record")" \
    --arg outcome "$(jq -r .outcome <<<"$record")" \
    --arg summary_sha256 "$(jq -r .summary_sha256 <<<"$record")" '
    {schema:1,control_id:$control,transition_id:null,kind:$kind,
     idempotency_key:("finalize:" + $generic_transition),
     generic_transition:$generic_transition,run_identity:$run_identity,
     run_id:$run_id,repository:$repository,issue:$issue,outcome:$outcome,
     telemetry_schema:2,integrity:"valid",summary_sha256:$summary_sha256}')"
}

failure_transition() {
  local record="$1" kind="$2" handle run_identity code
  handle="$(jq -r '"\(.run_id)@\(.repository_binding)"' <<<"$record")"
  run_identity="$(run_identity_for_handle "$handle")"
  code="$(jq -r '.failure_code // "UNKNOWN"' <<<"$record")"
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg kind "$kind" --arg code "$code" \
    --arg run_identity "$run_identity" --arg run_id "$(jq -r .run_id <<<"$record")" \
    --arg repository "$(jq -r .repository <<<"$record")" \
    --argjson issue "$(jq -r .issue <<<"$record")" \
    --arg lifecycle "$(jq -r .lifecycle <<<"$record")" \
    --arg finalization "$(jq -r .finalization <<<"$record")" \
    --arg outcome "$(jq -r '.outcome // ""' <<<"$record")" '
    def maybe: if . == "" then null else . end;
    {schema:1,control_id:$control,transition_id:null,kind:$kind,
     idempotency_key:($kind + ":" + $run_identity + ":" + $code),
     run_identity:$run_identity,run_id:$run_id,repository:$repository,issue:$issue,
     lifecycle:$lifecycle,finalization:$finalization,outcome:($outcome|maybe),
     failure_code:$code}')"
}

control_transition() {
  local kind="$1" predecessor="$2"
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg kind "$kind" --arg predecessor "$predecessor" '
    {schema:1,control_id:$control,transition_id:null,kind:$kind,
     idempotency_key:($kind + ":" + $control),
     predecessor_transition:$predecessor}')"
}

control_root_path() {
  printf 'control-window/%s\n' "$control_id"
}

transition_path() {
  local transition="$1"
  printf '%s/transitions/%s.json\n' "$(control_root_path)" \
    "$(jq -r .transition_id <<<"$transition")"
}

write_state() {
  local body="$1" root file staged
  root="$(state_home)"
  file="$(state_file "$control_id")"
  (umask 077 && mkdir -p "$root") || fail "could not create control state directory"
  chmod 700 "$root" || fail "could not secure control state directory"
  staged="$file.staged.$$"
  (umask 077 && printf '%s\n' "$body" >"$staged") \
    || fail "could not stage control state"
  chmod 600 "$staged"
  mv -f "$staged" "$file" || fail "could not store control state"
}

install_observer_configuration() {
  local root directory observer_link descriptor existing staged
  root="${XDG_CONFIG_HOME:-${HOME:-}/.config}"
  [[ "$root" == /* ]] || fail "XDG_CONFIG_HOME or HOME must resolve to an absolute path"
  directory="$root/work-on"
  observer_link="$directory/observer"
  descriptor="$directory/control-policy"
  (umask 077 && mkdir -p "$directory") \
    || fail "could not create work-on observer configuration"
  chmod 700 "$directory" || fail "could not secure observer configuration"
  if [[ -e "$observer_link" || -L "$observer_link" ]]; then
    existing="$(readlink -f "$observer_link" 2>/dev/null || true)"
    [[ "$existing" == "$script_root/control-window.sh" ]] \
      || fail "another work-on observer is already configured at $observer_link"
  else
    ln -s "$script_root/control-window.sh" "$observer_link" \
      || fail "could not install the control-window observer"
  fi
  staged="$descriptor.staged.$$"
  (umask 077 && printf '%s\n' "$policy_path" >"$staged") \
    || fail "could not stage the control policy descriptor"
  chmod 600 "$staged"
  mv -f "$staged" "$descriptor" || fail "could not install the control policy descriptor"
}

verify_observer_configuration() {
  local configured selected root
  if [[ -n "${WORK_ON_OBSERVER:-}" ]]; then
    configured="$(readlink -f "$WORK_ON_OBSERVER" 2>/dev/null || true)"
  else
    root="${XDG_CONFIG_HOME:-${HOME:-}/.config}"
    [[ "$root" == /* ]] || fail "XDG_CONFIG_HOME or HOME must resolve to an absolute path"
    configured="$(readlink -f "$root/work-on/observer" 2>/dev/null || true)"
  fi
  [[ "$configured" == "$script_root/control-window.sh" ]] \
    || fail "the generic #72 observer is not configured to use this adapter"
  selected="$(resolve_policy_path)" || fail "no control policy is configured for the observer"
  [[ "$(readlink -f "$selected" 2>/dev/null || true)" == \
    "$(readlink -f "$policy_path")" ]] \
    || fail "the configured observer policy differs from the activation policy"
}

results_remote_url() {
  if [[ -n "${CONTROL_WINDOW_REMOTE_URL:-}" ]]; then
    [[ "$CONTROL_WINDOW_REMOTE_URL" == /* || "$CONTROL_WINDOW_REMOTE_URL" == file://* ]] \
      || fail "CONTROL_WINDOW_REMOTE_URL must be an absolute path or file URL"
    printf '%s\n' "$CONTROL_WINDOW_REMOTE_URL"
  else
    printf 'https://github.com/%s.git\n' "$(jq -r .results.repository <<<"$policy_json")"
  fi
}

checkout_root=""
checkout_cleanup() {
  [[ -z "$checkout_root" ]] || rm -rf "$checkout_root"
  checkout_root=""
}
trap checkout_cleanup EXIT

clone_results_repository() {
  checkout_cleanup
  checkout_root="$(mktemp -d "${TMPDIR:-/tmp}/control-window.XXXXXX")" \
    || fail "could not create publisher checkout"
  git clone -q "$(results_remote_url)" "$checkout_root/repository" \
    || fail "could not clone results repository"
  git -C "$checkout_root/repository" config user.name \
    "${CONTROL_WINDOW_GIT_NAME:-Control Window Publisher}"
  git -C "$checkout_root/repository" config user.email \
    "${CONTROL_WINDOW_GIT_EMAIL:-control-window@invalid.local}"
}

fetch_results_refs() {
  local base branch prepared_base
  base="$(jq -r .results.base_branch <<<"$policy_json")"
  branch="$(jq -r .results.branch <<<"$policy_json")"
  git -C "$checkout_root/repository" fetch -q origin \
    "refs/heads/$base:refs/remotes/origin/control-base-tip" \
    || fail "could not fetch results base branch"
  if git -C "$checkout_root/repository" ls-remote --exit-code --heads origin \
    "refs/heads/$branch" >/dev/null 2>&1; then
    git -C "$checkout_root/repository" fetch -q origin \
      "refs/heads/$branch:refs/remotes/origin/control-results" \
      || fail "could not fetch results branch"
    prepared_base="$(git -C "$checkout_root/repository" merge-base \
      refs/remotes/origin/control-base-tip refs/remotes/origin/control-results)" \
      || fail "results branch shares no ancestry with its configured base"
    git -C "$checkout_root/repository" update-ref \
      refs/remotes/origin/control-base "$prepared_base"
    return 0
  fi
  git -C "$checkout_root/repository" update-ref refs/remotes/origin/control-base \
    "$(git -C "$checkout_root/repository" rev-parse refs/remotes/origin/control-base-tip)"
  return 1
}

validate_linear_history() {
  local base_ref="refs/remotes/origin/control-base"
  local result_ref="refs/remotes/origin/control-results" line commit fields status path
  git -C "$checkout_root/repository" merge-base --is-ancestor "$base_ref" "$result_ref" \
    || fail "results branch no longer descends from its prepared base"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    fields="$(wc -w <<<"$line")"
    [[ "$fields" -eq 2 ]] || fail "results branch contains non-linear history"
    commit="${line%% *}"
    while IFS=$'\t' read -r status path; do
      [[ "$status" == A ]] || fail "results history rewrites a published artifact"
      case "$path" in
        "$(control_root_path)/policy.json"|"$(control_root_path)/transitions/"*.json) ;;
        *) fail "results history contains unexpected content: $path" ;;
      esac
    done < <(git -C "$checkout_root/repository" diff-tree --no-commit-id \
      --name-status -r "$commit")
  done < <(git -C "$checkout_root/repository" rev-list --reverse --parents \
    "$base_ref..$result_ref")
}

validate_remote_transition_set() {
  local ref="refs/remotes/origin/control-results" file content identity name kind
  local idempotency_key
  local prepared_count=0 activated_count=0 closing_count=0 closed_count=0
  local prepared_commit="" activated_commit=""
  declare -A seen_idempotency=()
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    content="$(git -C "$checkout_root/repository" show "$ref:$file" 2>/dev/null \
      | jq -cS .)" || fail "remote transition is not valid JSON: $file"
    identity="$(jq -r '.transition_id // ""' <<<"$content")"
    name="${file##*/}"
    [[ "$name" == "$identity.json" && "$identity" =~ ^[0-9a-f]{64}$ ]] \
      || fail "remote transition identity does not match its path"
    [[ "$(jq -r '.schema // 0' <<<"$content")" == 1 \
      && "$(jq -r '.control_id // ""' <<<"$content")" == "$control_id" ]] \
      || fail "remote transition belongs to another control or schema"
    [[ "$(jq -cS 'del(.transition_id)' <<<"$content" | sha256_of_stdin)" == "$identity" ]] \
      || fail "remote transition content does not match its identity"
    idempotency_key="$(jq -r '.idempotency_key // ""' <<<"$content")"
    [[ -n "$idempotency_key" && -z "${seen_idempotency[$idempotency_key]:-}" ]] \
      || fail "remote transition idempotency identity is missing or duplicated"
    seen_idempotency[$idempotency_key]="$identity"
    kind="$(jq -r '.kind // ""' <<<"$content")"
    case "$kind" in
      control-prepared)
        jq -e 'keys == ["control_id","idempotency_key","kind","mode","policy_digest","schema","target_issue","target_repository","transition_id"]' \
          <<<"$content" >/dev/null || fail "prepared transition has unbounded fields"
        prepared_count=$(( prepared_count + 1 ))
        prepared_commit="$(git -C "$checkout_root/repository" log -1 \
          --format=%H "$ref" -- "$file")"
        ;;
      control-activated)
        jq -e 'keys == ["control_id","idempotency_key","kind","policy_digest","prepared_transition","schema","transition_id"]' \
          <<<"$content" >/dev/null || fail "activation transition has unbounded fields"
        activated_count=$(( activated_count + 1 ))
        activated_commit="$(git -C "$checkout_root/repository" log -1 \
          --format=%H "$ref" -- "$file")"
        ;;
      run-registered|run-finalized|run-failed|run-unreproducible|control-closing|control-closed)
        case "$kind" in
          run-registered)
            jq -e 'keys == ["control_id","idempotency_key","issue","kind","repository","run_id","run_identity","schema","telemetry_schema","transition_id"]
              and (.run_id | test("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$"))
              and (.run_identity | test("^[0-9a-f]{64}$"))
              and .telemetry_schema == 2' <<<"$content" >/dev/null \
              || fail "run registration transition has unbounded fields"
            ;;
          run-finalized)
            jq -e 'keys == ["control_id","generic_transition","idempotency_key","integrity","issue","kind","outcome","repository","run_id","run_identity","schema","summary_sha256","telemetry_schema","transition_id"]
              and (.generic_transition | test("^[0-9a-f]{64}$"))
              and (.run_identity | test("^[0-9a-f]{64}$"))
              and (.summary_sha256 | test("^[0-9a-f]{64}$"))
              and .integrity == "valid" and .telemetry_schema == 2
              and (.outcome | IN("Closes","Progresses","preflight-aborted","abandoned","failed"))
              and .outcome != "failed"' \
              <<<"$content" >/dev/null || fail "run finalization transition has unbounded fields"
            ;;
          run-failed)
            jq -e '
              if has("generic_transition") then
                keys == ["control_id","generic_transition","idempotency_key","integrity","issue","kind","outcome","repository","run_id","run_identity","schema","summary_sha256","telemetry_schema","transition_id"]
                and (.generic_transition | test("^[0-9a-f]{64}$"))
                and (.summary_sha256 | test("^[0-9a-f]{64}$"))
                and .integrity == "valid" and .telemetry_schema == 2
                and .outcome == "failed"
              else
                keys == ["control_id","failure_code","finalization","idempotency_key","issue","kind","lifecycle","outcome","repository","run_id","run_identity","schema","transition_id"]
                and .finalization == "failed"
                and (.failure_code | IN("OUTCOME_UNRESOLVED","OUTCOME_CONFLICT","RESOLVE_FAILED","SEAL_FAILED","INTEGRITY_INCOMPLETE","INTEGRITY_INVALID","SUMMARY_FAILED","IDENTITY_MISMATCH","OBSERVER_IDENTITY_MISMATCH"))
              end
              and (.run_identity | test("^[0-9a-f]{64}$"))' \
              <<<"$content" >/dev/null || fail "failed-run transition has unbounded fields"
            ;;
          run-unreproducible)
            jq -e 'keys == ["control_id","failure_code","finalization","idempotency_key","issue","kind","lifecycle","outcome","repository","run_id","run_identity","schema","transition_id"]
              and .finalization == "unreproducible"
              and (.run_identity | test("^[0-9a-f]{64}$"))
              and (.failure_code | IN("SINK_MISSING","REPOSITORY_MISSING","SUMMARY_FAILED"))' \
              <<<"$content" >/dev/null || fail "unreproducible transition has unbounded fields"
            ;;
          control-closing|control-closed)
            jq -e 'keys == ["control_id","idempotency_key","kind","predecessor_transition","schema","transition_id"]
              and (.predecessor_transition | test("^[0-9a-f]{64}$"))' \
              <<<"$content" >/dev/null || fail "control terminal transition has unbounded fields"
            [[ "$kind" == control-closing ]] \
              && closing_count=$((closing_count + 1)) \
              || closed_count=$((closed_count + 1))
            ;;
        esac
        ;;
      *) fail "remote transition kind is unsupported: $kind" ;;
    esac
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only "$ref" \
    "$(control_root_path)/transitions")
  [[ "$prepared_count" -eq 1 && "$activated_count" -le 1 \
    && "$closing_count" -le 1 && "$closed_count" -le 1 \
    && "$closed_count" -le "$closing_count" ]] \
    || fail "remote control transition counts are invalid"
  if [[ "$activated_count" -eq 1 ]]; then
    git -C "$checkout_root/repository" merge-base --is-ancestor \
      "$prepared_commit" "$activated_commit" \
      || fail "activation does not descend from preparation"
  fi
  validate_remote_state_machine
}

validate_remote_state_machine() {
  local base_ref="refs/remotes/origin/control-base"
  local result_ref="refs/remotes/origin/control-results"
  local phase=none commit path transition kind identity transition_count policy_count
  local change_status
  local open_count=0
  declare -A registered=()
  declare -A terminal=()
  while IFS= read -r commit; do
    [[ -n "$commit" ]] || continue
    transition_count=0
    policy_count=0
    transition=""
    while IFS=$'\t' read -r change_status path; do
      [[ "$change_status" == A ]] || fail "results state machine encountered rewritten content"
      case "$path" in
        "$(control_root_path)/policy.json") policy_count=$((policy_count + 1)) ;;
        "$(control_root_path)/transitions/"*.json)
          transition_count=$((transition_count + 1))
          transition="$(git -C "$checkout_root/repository" show "$commit:$path")"
          ;;
      esac
    done < <(git -C "$checkout_root/repository" diff-tree --no-commit-id \
      --name-status -r "$commit")
    if [[ "$phase" == none ]]; then
      [[ "$policy_count" -eq 1 && "$transition_count" -eq 1 ]] \
        || fail "prepared commit must add one policy and one transition"
    else
      [[ "$policy_count" -eq 0 && "$transition_count" -eq 1 ]] \
        || fail "each later evidence commit must add exactly one transition"
    fi
    kind="$(jq -r .kind <<<"$transition")"
    identity="$(jq -r '.run_identity // ""' <<<"$transition")"
    case "$kind" in
      control-prepared)
        [[ "$phase" == none ]] || fail "control preparation has an incompatible predecessor"
        phase=prepared
        ;;
      control-activated)
        [[ "$phase" == prepared ]] || fail "control activation has an incompatible predecessor"
        phase=active
        ;;
      run-registered)
        [[ "$phase" == active && -z "${registered[$identity]:-}" ]] \
          || fail "run registration has an incompatible predecessor"
        registered[$identity]=true
        open_count=$((open_count + 1))
        ;;
      run-finalized|run-unreproducible)
        [[ -n "${registered[$identity]:-}" && -z "${terminal[$identity]:-}" ]] \
          || fail "run terminal state has an incompatible predecessor"
        terminal[$identity]=true
        open_count=$((open_count - 1))
        ;;
      run-failed)
        [[ -n "${registered[$identity]:-}" && -z "${terminal[$identity]:-}" ]] \
          || fail "failed run state has an incompatible predecessor"
        if [[ "$(jq -r 'has("generic_transition")' <<<"$transition")" == true ]]; then
          terminal[$identity]=true
          open_count=$((open_count - 1))
        fi
        ;;
      control-closing)
        [[ "$phase" == active && "$open_count" -eq 0 ]] \
          || fail "control closing has an incompatible predecessor"
        phase=closing
        ;;
      control-closed)
        [[ "$phase" == closing ]] || fail "control closed has an incompatible predecessor"
        phase=closed
        ;;
    esac
  done < <(git -C "$checkout_root/repository" rev-list --reverse \
    "$base_ref..$result_ref")
}

assert_transition_allowed() {
  local transition="$1" kind run_identity registered terminal activated closing closed
  kind="$(jq -r .kind <<<"$transition")"
  activated=0
  closing=0
  closed=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    remote="$(git -C "$checkout_root/repository" show \
      "refs/remotes/origin/control-results:$file")"
    [[ "$(jq -r .kind <<<"$remote")" == control-activated ]] && activated=$((activated + 1))
    [[ "$(jq -r .kind <<<"$remote")" == control-closing ]] && closing=$((closing + 1))
    [[ "$(jq -r .kind <<<"$remote")" == control-closed ]] && closed=$((closed + 1))
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions")
  case "$kind" in
    control-activated)
      [[ "$activated" -eq 0 && "$closing" -eq 0 ]] \
        || fail "control cannot activate from its remote predecessor state"
      ;;
    run-registered)
      [[ "$activated" -eq 1 && "$closing" -eq 0 ]] \
        || fail "run registration requires an active remote control"
      run_identity="$(jq -r .run_identity <<<"$transition")"
      registered="$(remote_run_transition_count "$run_identity" run-registered)"
      terminal="$(remote_run_terminal_count "$run_identity")"
      [[ "$registered" -eq 0 && "$terminal" -eq 0 ]] \
        || fail "run already has a registration or terminal transition"
      ;;
    run-finalized|run-failed|run-unreproducible)
      run_identity="$(jq -r .run_identity <<<"$transition")"
      registered="$(remote_run_transition_count "$run_identity" run-registered)"
      terminal="$(remote_run_terminal_count "$run_identity")"
      [[ "$registered" -eq 1 && "$terminal" -eq 0 ]] \
        || fail "run terminal transition has an incompatible predecessor"
      ;;
    control-closing)
      [[ "$activated" -eq 1 && "$closing" -eq 0 && "$closed" -eq 0 ]] \
        || fail "control cannot begin closing from its remote predecessor state"
      open_runs="$(remote_open_run_count)"
      [[ "$open_runs" -eq 0 ]] || fail "control cannot close with registered runs outstanding"
      ;;
    control-closed)
      [[ "$closing" -eq 1 && "$closed" -eq 0 ]] \
        || fail "control cannot close from its remote predecessor state"
      ;;
  esac
}

remote_open_run_count() {
  local file remote identity count=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    remote="$(git -C "$checkout_root/repository" show \
      "refs/remotes/origin/control-results:$file")"
    [[ "$(jq -r .kind <<<"$remote")" == run-registered ]] || continue
    identity="$(jq -r .run_identity <<<"$remote")"
    [[ "$(remote_run_terminal_count "$identity")" -gt 0 ]] || count=$((count + 1))
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions")
  printf '%s\n' "$count"
}

remote_run_transition_count() {
  local run_identity="$1" wanted="$2" count=0 file remote
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    remote="$(git -C "$checkout_root/repository" show \
      "refs/remotes/origin/control-results:$file")"
    if [[ "$(jq -r '.run_identity // ""' <<<"$remote")" == "$run_identity" \
      && "$(jq -r .kind <<<"$remote")" == "$wanted" ]]; then
      count=$((count + 1))
    fi
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions")
  printf '%s\n' "$count"
}

remote_run_terminal_count() {
  local run_identity="$1" count=0 file remote kind
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    remote="$(git -C "$checkout_root/repository" show \
      "refs/remotes/origin/control-results:$file")"
    [[ "$(jq -r '.run_identity // ""' <<<"$remote")" == "$run_identity" ]] || continue
    kind="$(jq -r .kind <<<"$remote")"
    case "$kind" in
      run-finalized|run-unreproducible) count=$((count + 1)) ;;
      run-failed)
        [[ "$(jq -r 'has("generic_transition")' <<<"$remote")" == true ]] \
          && count=$((count + 1))
        ;;
    esac
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions")
  printf '%s\n' "$count"
}

verify_prepared_branch() {
  local expected_policy expected_transition policy_path transition_path_value count
  expected_policy="$(public_policy)"
  expected_transition="$(prepared_transition)"
  policy_path="$(control_root_path)/policy.json"
  transition_path_value="$(transition_path "$expected_transition")"
  validate_linear_history
  validate_remote_transition_set
  [[ "$(git -C "$checkout_root/repository" show \
    "refs/remotes/origin/control-results:$policy_path" 2>/dev/null | jq -cS .)" \
    == "$expected_policy" ]] || fail "remote policy projection differs"
  [[ "$(git -C "$checkout_root/repository" show \
    "refs/remotes/origin/control-results:$transition_path_value" 2>/dev/null | jq -cS .)" \
    == "$expected_transition" ]] || fail "remote prepared transition differs"
  count="$(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions" | wc -l)"
  [[ "$count" -ge 1 ]] || fail "results branch has no prepared transition"
}

refresh_results_ref() {
  local branch
  branch="$(jq -r .results.branch <<<"$policy_json")"
  git -C "$checkout_root/repository" update-ref -d \
    refs/remotes/origin/control-results >/dev/null 2>&1 || true
  git -C "$checkout_root/repository" fetch -q origin \
    "+refs/heads/$branch:refs/remotes/origin/control-results" \
    || fail "could not read back results branch"
}

verify_state_against_remote() {
  local state="$1" last remote_head
  [[ "$(jq -r .schema <<<"$state")" == 1 \
    && "$(jq -r .control_id <<<"$state")" == "$control_id" \
    && "$(jq -r .policy_digest <<<"$state")" == "$(policy_digest)" \
    && "$(jq -r .manifest_sha256 <<<"$state")" == "$(manifest_digest)" ]] \
    || fail "local control state does not match the policy"
  last="$(jq -r .last_verified_head <<<"$state")"
  remote_head="$(git -C "$checkout_root/repository" rev-parse \
    refs/remotes/origin/control-results)"
  git -C "$checkout_root/repository" merge-base --is-ancestor "$last" "$remote_head" \
    || fail "results branch was rewritten behind the last verified head"
  [[ "$(jq -r .base_sha <<<"$state")" == \
    "$(git -C "$checkout_root/repository" rev-parse refs/remotes/origin/control-base)" ]] \
    || fail "results base moved after preparation"
}

append_transition() {
  local transition="$1" state="$2" path branch attempt remote_content
  local remote_by_key
  path="$(transition_path "$transition")"
  branch="$(jq -r .results.branch <<<"$policy_json")"
  for attempt in 1 2; do
    refresh_results_ref
    verify_prepared_branch
    verify_state_against_remote "$state"
    if git -C "$checkout_root/repository" cat-file -e \
      "refs/remotes/origin/control-results:$path" 2>/dev/null; then
      remote_content="$(git -C "$checkout_root/repository" show \
        "refs/remotes/origin/control-results:$path" | jq -cS .)"
      [[ "$remote_content" == "$transition" ]] \
        || fail "remote idempotency identity has conflicting content"
      appended_head="$(git -C "$checkout_root/repository" rev-parse \
        refs/remotes/origin/control-results)"
      return 0
    fi
    remote_by_key="$(remote_transition_for_idempotency \
      "$(jq -r .idempotency_key <<<"$transition")" || true)"
    if [[ -n "$remote_by_key" ]]; then
      [[ "$(jq -cS . <<<"$remote_by_key")" == "$transition" ]] \
        || fail "remote idempotency identity has conflicting content"
      appended_head="$(git -C "$checkout_root/repository" rev-parse \
        refs/remotes/origin/control-results)"
      return 0
    fi
    assert_transition_allowed "$transition"
    git -C "$checkout_root/repository" switch -q --detach \
      refs/remotes/origin/control-results
    mkdir -p "$(dirname "$checkout_root/repository/$path")"
    jq -S . <<<"$transition" >"$checkout_root/repository/$path"
    git -C "$checkout_root/repository" add -- "$path"
    git -C "$checkout_root/repository" commit -qm \
      "Append $(jq -r .kind <<<"$transition"): $control_id"
    if git -C "$checkout_root/repository" push -q origin \
      "HEAD:refs/heads/$branch"; then
      refresh_results_ref
      verify_prepared_branch
      remote_content="$(git -C "$checkout_root/repository" show \
        "refs/remotes/origin/control-results:$path" | jq -cS .)"
      [[ "$remote_content" == "$transition" ]] \
        || fail "published transition failed exact read-back"
      appended_head="$(git -C "$checkout_root/repository" rev-parse \
        refs/remotes/origin/control-results)"
      return 0
    fi
    # A failed client response may still follow a successful remote write.
    # Refetch and adopt only exact content; otherwise retry once from the newly
    # verified head (ordinary optimistic-concurrency rejection).
    refresh_results_ref
    verify_prepared_branch
    if git -C "$checkout_root/repository" cat-file -e \
      "refs/remotes/origin/control-results:$path" 2>/dev/null; then
      remote_content="$(git -C "$checkout_root/repository" show \
        "refs/remotes/origin/control-results:$path" | jq -cS .)"
      [[ "$remote_content" == "$transition" ]] \
        || fail "remote idempotency identity has conflicting content"
      appended_head="$(git -C "$checkout_root/repository" rev-parse \
        refs/remotes/origin/control-results)"
      return 0
    fi
    state="$(jq -c --arg head "$(git -C "$checkout_root/repository" rev-parse \
      refs/remotes/origin/control-results)" '.last_verified_head = $head' <<<"$state")"
  done
  fail "transition publication did not succeed or read back"
}

remote_transition_for_idempotency() {
  local wanted="$1" file remote
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    remote="$(git -C "$checkout_root/repository" show \
      "refs/remotes/origin/control-results:$file")"
    if [[ "$(jq -r .idempotency_key <<<"$remote")" == "$wanted" ]]; then
      printf '%s\n' "$remote"
      return 0
    fi
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions")
  return 1
}

activate_control() {
  local state transition
  state="$(read_state)" || fail "control is not prepared"
  [[ "$(jq -r .phase <<<"$state")" == prepared ]] \
    || fail "control is not in prepared state"
  clone_results_repository
  fetch_results_refs || fail "prepared results branch is missing"
  verify_prepared_branch
  verify_state_against_remote "$state"
  ensure_prepared_pr false
  [[ "$(jq -r .number <<<"$prepared_pr_json")" == "$(jq -r .pr_number <<<"$state")" \
    && "$(jq -r .url <<<"$prepared_pr_json")" == "$(jq -r .pr_url <<<"$state")" ]] \
    || fail "prepared results PR identity changed after preparation"
  verify_observer_configuration
  transition="$(activation_transition)"
  append_transition "$transition" "$state"
  write_state "$(jq -c --arg head "$appended_head" \
    --arg activation "$(jq -r .transition_id <<<"$transition")" '
    .last_verified_head = $head | .phase = "active"
    | .activation_transition = $activation' <<<"$state")"
  jq -r .transition_id <<<"$transition"
}

register_run() {
  local handle="$1" registry_output record selected state transition
  registry_output="$("$registry_script" register --run "$handle")" \
    || return $?
  selected="$(resolve_policy_path)" || {
    printf '%s\n' "$registry_output"
    return 0
  }
  load_policy "$selected"
  record="$("$registry_script" status --run "$handle")" \
    || fail "could not read back the registered run"
  [[ -n "$record" ]] || {
    printf '%s\n' "$registry_output"
    return 0
  }
  [[ "$(jq -r '.control_id // ""' <<<"$record")" == "$control_id" ]] || {
    printf '%s\n' "$registry_output"
    return 0
  }
  state="$(read_state)" || fail "matching control has no prepared local state"
  [[ "$(jq -r .phase <<<"$state")" == active ]] \
    || fail "matching control is not active"
  [[ "$(jq -r .finalization <<<"$record")" == pending ]] \
    || fail "newly registered run is not pending"
  clone_results_repository
  fetch_results_refs || fail "active results branch is missing"
  transition="$(registration_transition "$record")"
  append_transition "$transition" "$state"
  write_state "$(jq -c --arg head "$appended_head" \
    '.last_verified_head = $head' <<<"$state")"
  printf 'registered %s\n' "${handle%@*}"
}

load_active_policy_and_state() {
  local selected state
  selected="$(resolve_policy_path)" || fail "no control policy is configured"
  load_policy "$selected"
  state="$(read_state)" || fail "control has no local state"
  [[ "$(jq -r .phase <<<"$state")" == active ]] \
    || fail "control is not active"
  active_state="$state"
}

validate_observer_record() {
  local record="$1" transition="$2"
  jq -e --arg control "$control_id" --arg transition "$transition" '
    type == "object"
    and .schema == 1 and .telemetry_schema == 2
    and (.run_id | type == "string" and test("^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$"))
    and (.repository_binding | type == "string" and test("^[0-9a-f]{32}$"))
    and (.repository | type == "string" and test("^[a-z0-9_.-]+/[a-z0-9_.-]+$"))
    and (.issue | type == "number" and floor == . and . > 0)
    and .control_id == $control and .finalization == "finalizing"
    and .lifecycle == "sealed"
    and (.outcome | IN("Closes","Progresses","preflight-aborted","abandoned","failed"))
    and (.summary_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
    and .finalization_id == $transition
  ' <<<"$record" >/dev/null || fail "observer record is not a bounded finalized #72 record"
}

observer_finalize() {
  local record_path="$1" generic_transition="$2" record transition
  [[ "$record_path" == /* && -f "$record_path" ]] \
    || fail "observer finalize requires an absolute registry record"
  [[ "$generic_transition" =~ ^[0-9a-f]{64}$ ]] \
    || fail "observer transition identity is malformed"
  load_active_policy_and_state
  record="$(jq -c . "$record_path" 2>/dev/null)" \
    || fail "observer record is not valid JSON"
  validate_observer_record "$record" "$generic_transition"
  transition="$(finalization_transition "$record" "$generic_transition")"
  clone_results_repository
  fetch_results_refs || fail "active results branch is missing"
  append_transition "$transition" "$active_state"
  write_state "$(jq -c --arg head "$appended_head" \
    '.last_verified_head = $head' <<<"$active_state")"
}

publish_failed_registry_state() {
  local handle="$1" record kind transition
  record="$("$registry_script" status --run "$handle" 2>/dev/null || true)"
  [[ -n "$record" ]] || return 0
  case "$(jq -r .finalization <<<"$record")" in
    unreproducible) kind=run-unreproducible ;;
    failed)
      [[ "$(jq -r '.failure_code // ""' <<<"$record")" != OBSERVER_FAILED ]] \
        || return 0
      kind=run-failed
      ;;
    *) return 0 ;;
  esac
  [[ -n "$(jq -r '.control_id // ""' <<<"$record")" ]] || return 0
  load_active_policy_and_state
  [[ "$(jq -r '.control_id // ""' <<<"$record")" == "$control_id" ]] || return 0
  transition="$(failure_transition "$record" "$kind")"
  clone_results_repository
  fetch_results_refs || fail "active results branch is missing"
  append_transition "$transition" "$active_state"
  write_state "$(jq -c --arg head "$appended_head" \
    '.last_verified_head = $head' <<<"$active_state")"
}

drive_registry_finalization() {
  local operation="$1" handle="$2" outcome="$3" status=0 output
  local -a args
  args=("$operation" --run "$handle")
  [[ -z "$outcome" ]] || args+=(--outcome "$outcome")
  output="$("$registry_script" "${args[@]}" 2>&1)" || status=$?
  publish_failed_registry_state "$handle" || status=1
  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" >&2
    return "$status"
  fi
  printf '%s\n' "$output"
}

close_control() {
  local complete="$1" state transition predecessor next_phase pending
  state="$(read_state)" || fail "control has no local state"
  if [[ "$complete" == false ]]; then
    [[ "$(jq -r .phase <<<"$state")" == active ]] \
      || fail "only an active control can begin closing"
    pending="$("$registry_script" status --pending 2>/dev/null | jq -s \
      --arg control "$control_id" '[.[] | select(.control_id == $control)] | length')"
    [[ "$pending" -eq 0 ]] || fail "control has pending run obligations"
    predecessor="$(jq -r .activation_transition <<<"$state")"
    transition="$(control_transition control-closing "$predecessor")"
    next_phase=closing
  else
    [[ "$(jq -r .phase <<<"$state")" == closing ]] \
      || fail "control must be closing before it can close"
    predecessor="$(jq -r .closing_transition <<<"$state")"
    transition="$(control_transition control-closed "$predecessor")"
    next_phase=closed
  fi
  clone_results_repository
  fetch_results_refs || fail "results branch is missing"
  append_transition "$transition" "$state"
  if [[ "$next_phase" == closing ]]; then
    state="$(jq -c --arg head "$appended_head" \
      --arg identity "$(jq -r .transition_id <<<"$transition")" '
      .last_verified_head = $head | .phase = "closing"
      | .closing_transition = $identity' <<<"$state")"
  else
    state="$(jq -c --arg head "$appended_head" \
      --arg identity "$(jq -r .transition_id <<<"$transition")" '
      .last_verified_head = $head | .phase = "closed"
      | .closed_transition = $identity' <<<"$state")"
  fi
  write_state "$state"
  jq -r .transition_id <<<"$transition"
}

prepare_remote_branch() {
  local branch policy_file transition transition_file
  branch="$(jq -r .results.branch <<<"$policy_json")"
  transition="$(prepared_transition)"
  policy_file="$checkout_root/repository/$(control_root_path)/policy.json"
  transition_file="$checkout_root/repository/$(transition_path "$transition")"
  git -C "$checkout_root/repository" switch -q --detach \
    refs/remotes/origin/control-base
  git -C "$checkout_root/repository" switch -q -c "$branch"
  mkdir -p "$(dirname "$policy_file")" "$(dirname "$transition_file")"
  public_policy | jq -S . >"$policy_file"
  jq -S . <<<"$transition" >"$transition_file"
  git -C "$checkout_root/repository" add -- \
    "$(control_root_path)/policy.json" "$(transition_path "$transition")"
  git -C "$checkout_root/repository" commit -qm \
    "Prepare control results: $control_id"
  git -C "$checkout_root/repository" push -q origin \
    "HEAD:refs/heads/$branch" || fail "could not publish prepared results branch"
  git -C "$checkout_root/repository" fetch -q origin \
    "refs/heads/$branch:refs/remotes/origin/control-results"
  verify_prepared_branch
}

ensure_prepared_pr() {
  local allow_create="${1:-true}"
  local repository branch base title body existing url view body_file
  local target_repository target_issue
  repository="$(jq -r .results.repository <<<"$policy_json")"
  branch="$(jq -r .results.branch <<<"$policy_json")"
  base="$(jq -r .results.base_branch <<<"$policy_json")"
  target_repository="$(jq -r .target.repository <<<"$policy_json")"
  target_issue="$(jq -r .target.issue <<<"$policy_json")"
  title="[PREPARED] Control results: $control_id"
  printf -v body 'PREPARED / NON-OBSERVING\n\nControl: `%s`\nMode: `%s`\nTarget: `%s#%s`\n\nPreparation does not activate or match observation work.' \
    "$control_id" "$policy_mode" "$target_repository" "$target_issue"
  existing="$(gh pr list -R "$repository" --head "$branch" --state all \
    --json number,url,isDraft,baseRefName,headRefName,title,body,state)" \
    || fail "could not inspect the prepared results PR"
  url="$(jq -r --arg branch "$branch" \
    '[.[] | select(.headRefName == $branch and .state == "OPEN")][0].url // ""' \
    <<<"$existing")"
  if [[ -z "$url" ]]; then
    [[ "$allow_create" == true ]] \
      || fail "the prepared results PR is missing or no longer open"
    body_file="$checkout_root/prepared-pr-body.md"
    printf '%s' "$body" >"$body_file"
    gh pr create -R "$repository" --base "$base" --head "$branch" \
      --title "$title" --body-file "$body_file" --draft >/dev/null 2>&1 || true
    existing="$(gh pr list -R "$repository" --head "$branch" --state all \
      --json number,url,isDraft,baseRefName,headRefName,title,body,state)" \
      || fail "could not recover the prepared results PR after creation"
    url="$(jq -r --arg branch "$branch" \
      '[.[] | select(.headRefName == $branch and .state == "OPEN")][0].url // ""' \
      <<<"$existing")"
  fi
  [[ -n "$url" ]] || fail "no open prepared results PR exists"
  view="$(gh pr view "$url" -R "$repository" \
    --json number,url,isDraft,baseRefName,headRefName,title,body,state)" \
    || fail "could not read back the prepared results PR"
  jq -e --arg base "$base" --arg branch "$branch" --arg title "$title" \
    --arg body "$body" '
    .state == "OPEN" and .isDraft == true and .baseRefName == $base
    and .headRefName == $branch and .title == $title and .body == $body
    and (.number | type == "number" and . > 0)
    and (.url | type == "string" and length > 0)
  ' <<<"$view" >/dev/null || fail "prepared results PR read-back differs"
  prepared_pr_json="$view"
}

store_prepared_state() {
  local head base transition
  head="$(git -C "$checkout_root/repository" rev-parse \
    refs/remotes/origin/control-results)"
  base="$(git -C "$checkout_root/repository" rev-parse \
    refs/remotes/origin/control-base)"
  transition="$(prepared_transition)"
  write_state "$(jq -cn \
    --arg control "$control_id" --arg policy_path "$policy_path" \
    --arg policy_digest "$(policy_digest)" \
    --arg manifest_sha256 "$(manifest_digest)" \
    --arg base "$base" --arg head "$head" \
    --arg prepared "$(jq -r .transition_id <<<"$transition")" \
    --argjson pr_number "$(jq -r .number <<<"$prepared_pr_json")" \
    --arg pr_url "$(jq -r .url <<<"$prepared_pr_json")" '
    {schema:1,control_id:$control,policy_path:$policy_path,
     policy_digest:$policy_digest,manifest_sha256:$manifest_sha256,
     base_sha:$base,last_verified_head:$head,
     phase:"prepared",prepared_transition:$prepared,activation_transition:null,
     pr_number:$pr_number,pr_url:$pr_url}')"
}

policy_matches() {
  local repository="$1" issue="$2"
  [[ "$policy_mode" == production ]] || return 1
  [[ "$(jq -r '.hooks.match' <<<"$policy_json")" == repository-issue-set-v1 ]] \
    || return 1
  jq -e --arg repository "$repository" --argjson issue "$issue" '
    (.population.repositories | index($repository)) != null
    and (.population.issues | index($issue)) != null
  ' <<<"$policy_json" >/dev/null
}

subcommand="${1:-}"
[[ -n "$subcommand" ]] || usage
shift || true

case "$subcommand" in
  validate)
    [[ "${1:-}" == --policy && "$#" -eq 2 ]] || usage
    load_policy "$2"
    printf 'valid %s schema=%s mode=%s\n' "$control_id" "$policy_schema" "$policy_mode"
    ;;
  prepare)
    [[ "${1:-}" == --policy && "$#" -eq 2 ]] || usage
    load_policy "$2"
    command -v gh >/dev/null 2>&1 || fail "prepare requires gh"
    prior_state="$(read_state 2>/dev/null || true)"
    if [[ -n "$prior_state" ]]; then
      [[ "$(jq -r .phase <<<"$prior_state")" == prepared ]] \
        || fail "preparation cannot replace a control that already left prepared state"
    fi
    clone_results_repository
    if fetch_results_refs; then
      verify_prepared_branch
      [[ -z "$prior_state" ]] || verify_state_against_remote "$prior_state"
    else
      [[ -z "$prior_state" ]] \
        || fail "prepared results branch disappeared after local preparation"
      prepare_remote_branch
    fi
    ensure_prepared_pr true
    store_prepared_state
    [[ "$policy_mode" == demo ]] || install_observer_configuration
    jq -r .url <<<"$prepared_pr_json"
    ;;
  register)
    handle=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    [[ -n "$handle" ]] || usage
    register_run "$handle"
    ;;
  finalize)
    handle=""
    outcome=""
    record=""
    generic_transition=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        --outcome) outcome="${2:?--outcome requires a value}"; shift 2 ;;
        --record) record="${2:?--record requires a value}"; shift 2 ;;
        --transition) generic_transition="${2:?--transition requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    if [[ -n "$record" || -n "$generic_transition" ]]; then
      [[ -n "$record" && -n "$generic_transition" \
        && -z "$handle" && -z "$outcome" ]] || usage
      observer_finalize "$record" "$generic_transition"
    else
      [[ -n "$handle" ]] || usage
      drive_registry_finalization finalize "$handle" "$outcome"
    fi
    ;;
  recover)
    handle=""
    outcome=""
    recover_all=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) handle="${2:?--run requires a value}"; shift 2 ;;
        --outcome) outcome="${2:?--outcome requires a value}"; shift 2 ;;
        --all) recover_all=true; shift ;;
        *) usage ;;
      esac
    done
    if [[ "$recover_all" == true ]]; then
      [[ -z "$handle" ]] || usage
      status=0
      while IFS= read -r pending_handle; do
        [[ -n "$pending_handle" ]] || continue
        drive_registry_finalization recover "$pending_handle" "$outcome" \
          || status=1
      done < <("$registry_script" status --pending | jq -r \
        '"\(.run_id)@\(.repository_binding)"')
      exit "$status"
    fi
    [[ -n "$handle" ]] || usage
    drive_registry_finalization recover "$handle" "$outcome"
    ;;
  status)
    if [[ "${1:-}" == --policy ]]; then
      [[ "$#" -eq 2 ]] || usage
      load_policy "$2"
      read_state || fail "control has no local state"
    else
      "$registry_script" status "$@"
    fi
    ;;
  close)
    policy=""
    complete=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --policy) policy="${2:?--policy requires a value}"; shift 2 ;;
        --complete) complete=true; shift ;;
        *) usage ;;
      esac
    done
    [[ -n "$policy" ]] || usage
    load_policy "$policy"
    [[ "$policy_mode" == production ]] \
      || fail "demo controls do not enter a real closing lifecycle"
    close_control "$complete"
    ;;
  applies)
    repository=""
    issue=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repository) repository="${2:?--repository requires a value}"; shift 2 ;;
        --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    [[ "$repository" =~ $repository_pattern && "$issue" =~ ^[1-9][0-9]*$ ]] \
      || fail "applies requires a normalized repository and positive issue"
    selected="$(resolve_policy_path)" || exit "$observer_not_applicable"
    load_policy "$selected"
    state="$(read_state)" || exit "$observer_not_applicable"
    [[ "$(jq -r '.phase' <<<"$state")" == active ]] \
      || exit "$observer_not_applicable"
    policy_matches "$repository" "$issue" || exit "$observer_not_applicable"
    printf 'observer=%s\ncontrol=%s\n' \
      "$(jq -r .observer_id <<<"$policy_json")" "$control_id"
    ;;
  activate)
    [[ "${1:-}" == --policy && "$#" -eq 2 ]] || usage
    load_policy "$2"
    [[ "$policy_mode" == production ]] \
      || fail "demo policies are mechanically non-activatable"
    activate_control
    ;;
  *) usage ;;
esac
