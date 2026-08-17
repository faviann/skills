#!/usr/bin/env bash
set -euo pipefail

# Adapt the generic work-on run registry to a versioned experiment policy and
# publish bounded, immutable control/run transitions to one GitHub results PR.
# The run registry remains the sole admission and run-lifecycle authority.

readonly policy_schema=1
readonly observer_not_applicable=3
readonly token_pattern='^[a-z0-9]+(-[a-z0-9]+)*$'
readonly repository_pattern='^[a-z0-9_.-]+/[a-z0-9_.-]+$'
readonly branch_pattern='^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$'
readonly publisher_name='Control Window Publisher'
readonly publisher_email='control-window@invalid.local'

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
command -v flock >/dev/null 2>&1 || fail "requires flock"

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly registry_script="$script_root/run-registry.sh"
readonly telemetry_script="$script_root/run-telemetry.sh"

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
    and (keys == ["arm","control_id","controller","hooks","mode","observer_id","population","results","schema","target"])
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
    and (.controller | type == "object"
      and keys == ["binding_sha256","scope","top_level_runs"]
      and .scope == "single-xdg-domain"
      and .top_level_runs == "sequential"
      and (.binding_sha256 | type == "string" and test("^[0-9a-f]{64}$")))
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
  local supplied="${1:-}" candidate descriptor
  if [[ -n "$supplied" ]]; then
    printf '%s\n' "$supplied"
    return
  fi
  candidate="${WORK_ON_CONTROL_POLICY:-}"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return
  fi
  descriptor="$(configured_policy_descriptor)"
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

configuration_root() {
  local root="${XDG_CONFIG_HOME:-${HOME:-}/.config}"
  [[ "$root" == /* ]] || fail "XDG_CONFIG_HOME or HOME must resolve to an absolute path"
  printf '%s/work-on\n' "$root"
}

configured_policy_descriptor() {
  printf '%s/control-policy\n' "$(configuration_root)"
}

admission_lock_fd=""
lock_control_admission() {
  local directory lock
  directory="$(configuration_root)"
  lock="$directory/control-window.lock"
  (umask 077 && mkdir -p "$directory") \
    || fail "could not create control admission lock directory"
  chmod 700 "$directory" || fail "could not secure control admission lock directory"
  (umask 077 && touch "$lock") || fail "could not create control admission lock"
  chmod 600 "$lock" || fail "could not secure control admission lock"
  exec {admission_lock_fd}>>"$lock"
  flock -x "$admission_lock_fd" || fail "could not lock control admission"
}

unlock_control_admission() {
  [[ -n "$admission_lock_fd" ]] || return 0
  exec {admission_lock_fd}>&-
  admission_lock_fd=""
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

controller_binding_file() {
  printf '%s/controller-binding\n' "$(configuration_root)"
}

controller_binding_state_marker() {
  local root="${XDG_STATE_HOME:-${HOME:-}/.local/state}"
  [[ "$root" == /* ]] || fail "XDG_STATE_HOME or HOME must resolve to an absolute path"
  printf '%s/work-on/controller-binding.sha256\n' "$root"
}

verify_controller_binding() {
  local file marker binding expected actual mode owner marker_mode marker_owner
  [[ "$policy_mode" == production ]] || return 0
  file="$(controller_binding_file)"
  [[ -f "$file" && ! -L "$file" ]] \
    || fail "controller binding is missing from the designated XDG domain"
  mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
  owner="$(stat -c '%u' "$file" 2>/dev/null || true)"
  [[ "$mode" == 600 && "$owner" == "$(id -u)" ]] \
    || fail "controller binding is not owner-only"
  IFS= read -r binding <"$file" || true
  [[ "$binding" =~ ^[0-9a-f]{64}$ && "$(wc -l <"$file")" -eq 1 \
    && "$(wc -c <"$file")" -eq 65 ]] \
    || fail "controller binding is malformed"
  expected="$(jq -r .controller.binding_sha256 <<<"$policy_json")"
  actual="$(printf '%s' "$binding" | sha256_of_stdin)"
  [[ "$actual" == "$expected" ]] \
    || fail "controller binding does not own this control"
  marker="$(controller_binding_state_marker)"
  [[ -f "$marker" && ! -L "$marker" ]] \
    || fail "controller binding does not designate this XDG state domain"
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null || true)"
  marker_owner="$(stat -c '%u' "$marker" 2>/dev/null || true)"
  [[ "$marker_mode" == 600 && "$marker_owner" == "$(id -u)" \
    && "$(cat "$marker")" == "$expected" \
    && "$(wc -l <"$marker")" -eq 1 && "$(wc -c <"$marker")" -eq 65 ]] \
    || fail "controller binding does not designate this XDG state domain"
}

public_policy() {
  jq -cS '{schema,control_id,mode,observer_id,target,population,hooks,
    results:{repository:.results.repository,base_branch:.results.base_branch,
      branch:.results.branch},controller,arm:{id:.arm.id}}' <<<"$policy_json"
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
  local prepared pr_number
  prepared="$(jq -r .transition_id <<<"$(prepared_transition)")"
  [[ -n "${prepared_pr_json:-}" ]] \
    || fail "activation requires an exactly verified prepared PR identity"
  pr_number="$(jq -r '.number // 0' <<<"$prepared_pr_json")"
  [[ "$pr_number" =~ ^[1-9][0-9]*$ ]] \
    || fail "activation requires an exactly verified prepared PR identity"
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg digest "$(policy_digest)" \
    --arg prepared "$prepared" --argjson pr_number "$pr_number" '
    {schema:1,control_id:$control,transition_id:null,kind:"control-activated",
     idempotency_key:("activate:" + $control),policy_digest:$digest,
     prepared_transition:$prepared,prepared_pr_number:$pr_number}')"
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

evidence_loss_transition() {
  local record="$1" predecessor="$2" handle run_identity code
  handle="$(jq -r '"\(.run_id)@\(.repository_binding)"' <<<"$record")"
  run_identity="$(run_identity_for_handle "$handle")"
  code="$(jq -r '.failure_code // "UNKNOWN"' <<<"$record")"
  transition_with_identity "$(jq -cn \
    --arg control "$control_id" --arg predecessor "$predecessor" \
    --arg code "$code" --arg run_identity "$run_identity" \
    --arg run_id "$(jq -r .run_id <<<"$record")" \
    --arg repository "$(jq -r .repository <<<"$record")" \
    --argjson issue "$(jq -r .issue <<<"$record")" \
    --arg lifecycle "$(jq -r .lifecycle <<<"$record")" \
    --arg outcome "$(jq -r '.outcome // ""' <<<"$record")" '
    def maybe: if . == "" then null else . end;
    {schema:1,control_id:$control,transition_id:null,kind:"run-evidence-lost",
     idempotency_key:("evidence-lost:" + $run_identity + ":" + $predecessor + ":" + $code),
     predecessor_transition:$predecessor,run_identity:$run_identity,run_id:$run_id,
     repository:$repository,issue:$issue,lifecycle:$lifecycle,
     finalization:"unreproducible",outcome:($outcome|maybe),failure_code:$code}')"
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
  local directory observer_link descriptor existing staged
  directory="$(configuration_root)"
  observer_link="$directory/observer"
  descriptor="$(configured_policy_descriptor)"
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
    root="$(configuration_root)"
    configured="$(readlink -f "$root/observer" 2>/dev/null || true)"
  fi
  [[ "$configured" == "$script_root/control-window.sh" ]] \
    || fail "the generic #72 observer is not configured to use this adapter"
  selected="$(resolve_policy_path)" || fail "no control policy is configured for the observer"
  [[ "$(readlink -f "$selected" 2>/dev/null || true)" == \
    "$(readlink -f "$policy_path")" ]] \
    || fail "the configured observer policy differs from the activation policy"
}

assert_policy_slot_available() {
  local descriptor configured configured_real requested_real status phase
  [[ "$policy_mode" == production ]] || return 0
  descriptor="$(configured_policy_descriptor)"
  [[ -f "$descriptor" ]] || return 0
  IFS= read -r configured <"$descriptor"
  [[ -n "$configured" && "$configured" == /* \
    && "$(wc -l <"$descriptor")" -eq 1 ]] \
    || fail "configured control policy descriptor is malformed"
  configured_real="$(readlink -f "$configured" 2>/dev/null || true)"
  requested_real="$(readlink -f "$policy_path" 2>/dev/null || true)"
  [[ -n "$configured_real" ]] \
    || fail "configured control policy cannot be resolved"
  [[ "$configured_real" != "$requested_real" ]] || return 0
  status="$("$script_root/control-window.sh" status --policy "$configured_real")" \
    || fail "could not reconcile the configured production control"
  phase="$(jq -r .phase <<<"$status")"
  [[ "$phase" == closed ]] \
    || fail "configured production control is still $phase; close it before preparing another"
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
  git -C "$checkout_root/repository" config user.name "$publisher_name"
  git -C "$checkout_root/repository" config user.email "$publisher_email"
}

commit_evidence() {
  local message="$1" hooks_directory
  hooks_directory="$(mktemp -d "$checkout_root/empty-hooks.XXXXXX")" \
    || fail "could not create empty publisher hooks directory"
  hooks_directory="$(cd "$hooks_directory" && pwd -P)"
  chmod 700 "$hooks_directory" \
    || fail "could not secure empty publisher hooks directory"
  GIT_AUTHOR_NAME="$publisher_name" \
  GIT_AUTHOR_EMAIL="$publisher_email" \
  GIT_COMMITTER_NAME="$publisher_name" \
  GIT_COMMITTER_EMAIL="$publisher_email" \
    git -c user.name="$publisher_name" -c user.email="$publisher_email" \
      -c commit.gpgsign=false -c core.hooksPath="$hooks_directory" \
      -C "$checkout_root/repository" \
      commit -qm "$message"
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
  local transition_file kind expected_message
  git -C "$checkout_root/repository" merge-base --is-ancestor "$base_ref" "$result_ref" \
    || fail "results branch no longer descends from its prepared base"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    fields="$(wc -w <<<"$line")"
    [[ "$fields" -eq 2 ]] || fail "results branch contains non-linear history"
    commit="${line%% *}"
    [[ "$(git -C "$checkout_root/repository" show -s --format=%an "$commit")" \
        == "$publisher_name" \
      && "$(git -C "$checkout_root/repository" show -s --format=%ae "$commit")" \
        == "$publisher_email" \
      && "$(git -C "$checkout_root/repository" show -s --format=%cn "$commit")" \
        == "$publisher_name" \
      && "$(git -C "$checkout_root/repository" show -s --format=%ce "$commit")" \
        == "$publisher_email" ]] \
      || fail "results history contains unbounded publisher identity metadata"
    transition_file=""
    while IFS=$'\t' read -r status path; do
      [[ "$status" == A ]] || fail "results history rewrites a published artifact"
      case "$path" in
        "$(control_root_path)/policy.json") ;;
        "$(control_root_path)/transitions/"*.json) transition_file="$path" ;;
        *) fail "results history contains unexpected content: $path" ;;
      esac
    done < <(git -C "$checkout_root/repository" diff-tree --no-commit-id \
      --name-status -r "$commit")
    [[ -n "$transition_file" ]] || fail "results commit contains no transition artifact"
    kind="$(git -C "$checkout_root/repository" show "$commit:$transition_file" \
      | jq -r '.kind // ""')"
    if [[ "$kind" == control-prepared ]]; then
      expected_message="Prepare control results: $control_id"
    else
      expected_message="Append $kind: $control_id"
    fi
    [[ "$(git -C "$checkout_root/repository" show -s --format=%s "$commit")" \
        == "$expected_message" \
      && -z "$(git -C "$checkout_root/repository" show -s --format=%b "$commit")" ]] \
      || fail "results history contains unbounded commit message metadata"
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
        jq -e 'keys == ["control_id","idempotency_key","kind","policy_digest","prepared_pr_number","prepared_transition","schema","transition_id"]
          and (.prepared_pr_number | type == "number" and floor == . and . > 0)' \
          <<<"$content" >/dev/null || fail "activation transition has unbounded fields"
        activated_count=$(( activated_count + 1 ))
        activated_commit="$(git -C "$checkout_root/repository" log -1 \
          --format=%H "$ref" -- "$file")"
        ;;
      run-registered|run-finalized|run-failed|run-unreproducible|run-evidence-lost|control-closing|control-closed)
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
          run-evidence-lost)
            jq -e 'keys == ["control_id","failure_code","finalization","idempotency_key","issue","kind","lifecycle","outcome","predecessor_transition","repository","run_id","run_identity","schema","transition_id"]
              and .finalization == "unreproducible"
              and (.run_identity | test("^[0-9a-f]{64}$"))
              and (.predecessor_transition | test("^[0-9a-f]{64}$"))
              and (.failure_code | IN("SINK_MISSING","REPOSITORY_MISSING","SUMMARY_FAILED"))' \
              <<<"$content" >/dev/null || fail "evidence-loss transition has unbounded fields"
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
  declare -A evidence_lost=()
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
        [[ "$open_count" -eq 0 ]] \
          || fail "remote history contains two unresolved run registrations"
        registered[$identity]=true
        open_count=$((open_count + 1))
        ;;
      run-finalized|run-unreproducible)
        [[ -n "${registered[$identity]:-}" && -z "${terminal[$identity]:-}" ]] \
          || fail "run terminal state has an incompatible predecessor"
        terminal[$identity]="$(jq -r .transition_id <<<"$transition")"
        open_count=$((open_count - 1))
        ;;
      run-failed)
        [[ -n "${registered[$identity]:-}" && -z "${terminal[$identity]:-}" ]] \
          || fail "failed run state has an incompatible predecessor"
        if [[ "$(jq -r 'has("generic_transition")' <<<"$transition")" == true ]]; then
          terminal[$identity]="$(jq -r .transition_id <<<"$transition")"
          open_count=$((open_count - 1))
        fi
        ;;
      run-evidence-lost)
        [[ -n "${terminal[$identity]:-}" && -z "${evidence_lost[$identity]:-}" \
          && "$(jq -r .predecessor_transition <<<"$transition")" \
            == "${terminal[$identity]}" ]] \
          || fail "run evidence-loss correction has an incompatible predecessor"
        evidence_lost[$identity]="$(jq -r .transition_id <<<"$transition")"
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
  local remote open_runs
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
      [[ "$(remote_open_run_count)" -eq 0 ]] \
        || fail "remote history already contains an unresolved run registration"
      ;;
    run-finalized|run-failed|run-unreproducible)
      run_identity="$(jq -r .run_identity <<<"$transition")"
      registered="$(remote_run_transition_count "$run_identity" run-registered)"
      terminal="$(remote_run_terminal_count "$run_identity")"
      [[ "$registered" -eq 1 && "$terminal" -eq 0 ]] \
        || fail "run terminal transition has an incompatible predecessor"
      ;;
    run-evidence-lost)
      run_identity="$(jq -r .run_identity <<<"$transition")"
      registered="$(remote_run_transition_count "$run_identity" run-registered)"
      terminal="$(remote_run_terminal_count "$run_identity")"
      [[ "$registered" -eq 1 && "$terminal" -eq 1 \
        && "$(remote_run_transition_count "$run_identity" run-evidence-lost)" -eq 0 \
        && "$(jq -r .predecessor_transition <<<"$transition")" \
          == "$(remote_run_terminal_transition_id "$run_identity")" ]] \
        || fail "run evidence-loss correction has an incompatible predecessor"
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

remote_run_terminal_transition_id() {
  local run_identity="$1" file remote kind
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    remote="$(git -C "$checkout_root/repository" show \
      "refs/remotes/origin/control-results:$file")"
    [[ "$(jq -r '.run_identity // ""' <<<"$remote")" == "$run_identity" ]] || continue
    kind="$(jq -r .kind <<<"$remote")"
    case "$kind" in
      run-finalized|run-unreproducible)
        jq -r .transition_id <<<"$remote"
        return 0
        ;;
      run-failed)
        if [[ "$(jq -r 'has("generic_transition")' <<<"$remote")" == true ]]; then
          jq -r .transition_id <<<"$remote"
          return 0
        fi
        ;;
    esac
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions")
  return 1
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
    commit_evidence "Append $(jq -r .kind <<<"$transition"): $control_id"
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

remote_transition_count_for_kind() {
  local wanted="$1" count=0 file remote
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    remote="$(git -C "$checkout_root/repository" show \
      "refs/remotes/origin/control-results:$file")"
    [[ "$(jq -r .kind <<<"$remote")" == "$wanted" ]] && count=$((count + 1))
  done < <(git -C "$checkout_root/repository" ls-tree -r --name-only \
    refs/remotes/origin/control-results "$(control_root_path)/transitions")
  printf '%s\n' "$count"
}

require_exact_remote_transition() {
  local transition="$1" path remote
  path="$(transition_path "$transition")"
  git -C "$checkout_root/repository" cat-file -e \
    "refs/remotes/origin/control-results:$path" 2>/dev/null \
    || fail "remote control phase transition has unexpected identity"
  remote="$(git -C "$checkout_root/repository" show \
    "refs/remotes/origin/control-results:$path" | jq -cS .)"
  [[ "$remote" == "$transition" ]] \
    || fail "remote control phase transition has unexpected content"
}

derive_remote_control_phase() {
  local activation closing closed
  remote_phase=prepared
  remote_activation_transition=""
  remote_closing_transition=""
  remote_closed_transition=""
  if [[ "$(remote_transition_count_for_kind control-activated)" -eq 1 ]]; then
    activation="$(activation_transition)"
    require_exact_remote_transition "$activation"
    remote_phase=active
    remote_activation_transition="$(jq -r .transition_id <<<"$activation")"
  fi
  if [[ "$(remote_transition_count_for_kind control-closing)" -eq 1 ]]; then
    [[ -n "$remote_activation_transition" ]] \
      || fail "remote closing transition has no activation predecessor"
    closing="$(control_transition control-closing "$remote_activation_transition")"
    require_exact_remote_transition "$closing"
    remote_phase=closing
    remote_closing_transition="$(jq -r .transition_id <<<"$closing")"
  fi
  if [[ "$(remote_transition_count_for_kind control-closed)" -eq 1 ]]; then
    [[ -n "$remote_closing_transition" ]] \
      || fail "remote closed transition has no closing predecessor"
    closed="$(control_transition control-closed "$remote_closing_transition")"
    require_exact_remote_transition "$closed"
    remote_phase=closed
    remote_closed_transition="$(jq -r .transition_id <<<"$closed")"
  fi
}

reconcile_state_in_checkout() {
  local prior_state="${1:-}" head base transition
  verify_prepared_branch
  [[ -z "$prior_state" ]] || verify_state_against_remote "$prior_state"
  ensure_prepared_pr false
  if [[ -n "$prior_state" ]]; then
    [[ "$(jq -r .pr_number <<<"$prior_state")" == \
        "$(jq -r .number <<<"$prepared_pr_json")" \
      && "$(jq -r .pr_url <<<"$prior_state")" == \
        "$(jq -r .url <<<"$prepared_pr_json")" ]] \
      || fail "prepared results PR identity changed after preparation"
  fi
  derive_remote_control_phase
  head="$(git -C "$checkout_root/repository" rev-parse \
    refs/remotes/origin/control-results)"
  base="$(git -C "$checkout_root/repository" rev-parse \
    refs/remotes/origin/control-base)"
  transition="$(prepared_transition)"
  reconciled_state="$(jq -cn \
    --arg control "$control_id" --arg policy_path "$policy_path" \
    --arg policy_digest "$(policy_digest)" \
    --arg manifest_sha256 "$(manifest_digest)" \
    --arg base "$base" --arg head "$head" --arg phase "$remote_phase" \
    --arg prepared "$(jq -r .transition_id <<<"$transition")" \
    --arg activation "$remote_activation_transition" \
    --arg closing "$remote_closing_transition" --arg closed "$remote_closed_transition" \
    --argjson pr_number "$(jq -r .number <<<"$prepared_pr_json")" \
    --arg pr_url "$(jq -r .url <<<"$prepared_pr_json")" '
    def maybe: if . == "" then null else . end;
    {schema:1,control_id:$control,policy_path:$policy_path,
     policy_digest:$policy_digest,manifest_sha256:$manifest_sha256,
     base_sha:$base,last_verified_head:$head,phase:$phase,
     prepared_transition:$prepared,activation_transition:($activation|maybe),
     closing_transition:($closing|maybe),closed_transition:($closed|maybe),
     pr_number:$pr_number,pr_url:$pr_url}')"
  write_state "$reconciled_state"
}

reconcile_control_state() {
  local prior_state="${1:-}"
  clone_results_repository
  fetch_results_refs || fail "prepared results branch is missing"
  reconcile_state_in_checkout "$prior_state"
}

activate_control() {
  local state transition
  verify_controller_binding
  lock_control_admission
  assert_policy_slot_available
  state="$(read_state 2>/dev/null || true)"
  reconcile_control_state "$state"
  state="$reconciled_state"
  verify_observer_configuration
  if [[ "$(jq -r .phase <<<"$state")" == active ]]; then
    unlock_control_admission
    jq -r .activation_transition <<<"$state"
    return 0
  fi
  [[ "$(jq -r .phase <<<"$state")" == prepared ]] \
    || fail "control is not in prepared state"
  transition="$(activation_transition)"
  append_transition "$transition" "$state"
  refresh_results_ref
  reconcile_state_in_checkout "$state"
  unlock_control_admission
  jq -r .transition_id <<<"$transition"
}

register_run() {
  local handle="$1" registry_output record selected state transition summary
  selected="$(resolve_policy_path)" || {
    "$registry_script" register --run "$handle"
    return $?
  }
  load_policy "$selected"
  summary="$("$telemetry_script" summary --run "$handle" 2>/dev/null)" \
    || fail "could not read the run identity before control admission"
  if ! policy_matches "$(jq -r .repository <<<"$summary")" \
      "$(jq -r .issue <<<"$summary")"; then
    "$registry_script" register --run "$handle"
    return $?
  fi
  verify_controller_binding
  lock_control_admission
  state="$(read_state 2>/dev/null || true)"
  reconcile_control_state "$state"
  state="$reconciled_state"
  [[ "$(jq -r .phase <<<"$state")" == active ]] \
    || fail "matching control is not open for registration"
  registry_output="$("$registry_script" register --run "$handle")" \
    || return $?
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
  [[ "$(jq -r .finalization <<<"$record")" == pending ]] \
    || fail "newly registered run is not pending"
  clone_results_repository
  fetch_results_refs || fail "active results branch is missing"
  transition="$(registration_transition "$record")"
  append_transition "$transition" "$state"
  write_state "$(jq -c --arg head "$appended_head" \
    '.last_verified_head = $head' <<<"$state")"
  unlock_control_admission
  printf 'registered %s\n' "${handle%@*}"
}

load_governed_policy_and_state() {
  local selected state
  selected="$(resolve_policy_path)" || fail "no control policy is configured"
  load_policy "$selected"
  verify_controller_binding
  state="$(read_state 2>/dev/null || true)"
  reconcile_control_state "$state"
  state="$reconciled_state"
  [[ "$(jq -r .phase <<<"$state")" =~ ^(active|closing|closed)$ ]] \
    || fail "control has not opened"
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
  load_governed_policy_and_state
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

# The obligation belongs to the control the row registered with, which is not
# always the control configured now. Publication therefore selects that
# historical control's own owner-only state and policy in this controller
# domain; a missing, malformed, or disowned one fails visibly rather than
# dropping a required transition. This is historical publication for one
# controller domain, not a second active policy.
load_historical_policy_and_state() {
  local control="$1" file state selected
  [[ "$control" =~ $token_pattern ]] \
    || fail "registry row names a malformed control"
  file="$(printf '%s/%s.json' "$(state_home)" "$control")"
  [[ -f "$file" && ! -L "$file" ]] \
    || fail "control $control has no local state in this controller domain"
  state="$(jq -c . "$file" 2>/dev/null)" \
    || fail "control $control has malformed local state"
  selected="$(jq -r '.policy_path // ""' <<<"$state")"
  [[ "$selected" == /* ]] \
    || fail "control $control records no absolute policy path"
  load_policy "$selected"
  [[ "$control_id" == "$control" ]] \
    || fail "control $control does not own the policy recorded for it"
  [[ "$(jq -r '.policy_digest // ""' <<<"$state")" == "$(policy_digest)" \
    && "$(jq -r '.manifest_sha256 // ""' <<<"$state")" == "$(manifest_digest)" ]] \
    || fail "control $control no longer matches the policy recorded for it"
  verify_controller_binding
  reconcile_control_state "$state"
  state="$reconciled_state"
  [[ "$(jq -r .phase <<<"$state")" =~ ^(active|closing|closed)$ ]] \
    || fail "control $control has not opened"
  active_state="$state"
}

publish_failed_registry_state() {
  local handle="$1" record kind transition run_identity predecessor row_control
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
  row_control="$(jq -r '.control_id // ""' <<<"$record")"
  [[ -n "$row_control" ]] || return 0
  load_historical_policy_and_state "$row_control"
  if [[ "$kind" == run-unreproducible ]]; then
    run_identity="$(run_identity_for_handle "$handle")"
    predecessor="$(remote_run_terminal_transition_id "$run_identity" || true)"
    if [[ -n "$predecessor" ]]; then
      transition="$(evidence_loss_transition "$record" "$predecessor")"
    else
      transition="$(failure_transition "$record" "$kind")"
    fi
  else
    transition="$(failure_transition "$record" "$kind")"
  fi
  append_transition "$transition" "$active_state"
  write_state "$(jq -c --arg head "$appended_head" \
    '.last_verified_head = $head' <<<"$active_state")"
}

# Hand-back by run handle is #72's operation, and a run nothing observes owes
# this adapter nothing. Requiring the configured control's binding here would
# make an unrelated ordinary run unable to hand back or recover whenever a
# production policy happens to be configured, so the binding is verified where a
# governed obligation is actually discharged instead: #72 re-checks the stored
# observer/control pair through `applies`, and both the observer callback and
# the failure publication above verify the binding themselves.
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
  local complete="$1" state transition predecessor pending
  verify_controller_binding
  lock_control_admission
  state="$(read_state 2>/dev/null || true)"
  reconcile_control_state "$state"
  state="$reconciled_state"
  if [[ "$complete" == false ]]; then
    if [[ "$(jq -r .phase <<<"$state")" == closing ]]; then
      unlock_control_admission
      jq -r .closing_transition <<<"$state"
      return 0
    fi
    [[ "$(jq -r .phase <<<"$state")" == active ]] \
      || fail "only an active control can begin closing"
    pending="$("$registry_script" status --pending 2>/dev/null | jq -s \
      --arg control "$control_id" '[.[] | select(.control_id == $control)] | length')"
    [[ "$pending" -eq 0 ]] || fail "control has pending run obligations"
    predecessor="$(jq -r .activation_transition <<<"$state")"
    transition="$(control_transition control-closing "$predecessor")"
  else
    if [[ "$(jq -r .phase <<<"$state")" == closed ]]; then
      unlock_control_admission
      jq -r .closed_transition <<<"$state"
      return 0
    fi
    [[ "$(jq -r .phase <<<"$state")" == closing ]] \
      || fail "control must be closing before it can close"
    predecessor="$(jq -r .closing_transition <<<"$state")"
    transition="$(control_transition control-closed "$predecessor")"
  fi
  clone_results_repository
  fetch_results_refs || fail "results branch is missing"
  append_transition "$transition" "$state"
  refresh_results_ref
  reconcile_state_in_checkout "$state"
  unlock_control_admission
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
  commit_evidence "Prepare control results: $control_id"
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
    verify_controller_binding
    command -v gh >/dev/null 2>&1 || fail "prepare requires gh"
    [[ "$policy_mode" == demo ]] || lock_control_admission
    assert_policy_slot_available
    prior_state="$(read_state 2>/dev/null || true)"
    clone_results_repository
    if fetch_results_refs; then
      verify_prepared_branch
      if [[ "$(remote_transition_count_for_kind control-activated)" -eq 0 ]]; then
        ensure_prepared_pr true
      else
        ensure_prepared_pr false
      fi
      reconcile_state_in_checkout "$prior_state"
    else
      [[ -z "$prior_state" ]] \
        || fail "prepared results branch disappeared after local preparation"
      prepare_remote_branch
      ensure_prepared_pr true
      store_prepared_state
    fi
    [[ "$policy_mode" == demo ]] || install_observer_configuration
    [[ "$policy_mode" == demo ]] || unlock_control_admission
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
      verify_controller_binding
      state="$(read_state 2>/dev/null || true)"
      reconcile_control_state "$state"
      printf '%s\n' "$reconciled_state"
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
    policy_matches "$repository" "$issue" || exit "$observer_not_applicable"
    verify_controller_binding
    state="$(read_state 2>/dev/null || true)"
    reconcile_control_state "$state"
    state="$reconciled_state"
    [[ "$(jq -r '.phase' <<<"$state")" =~ ^(active|closing|closed)$ ]] \
      || exit "$observer_not_applicable"
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
