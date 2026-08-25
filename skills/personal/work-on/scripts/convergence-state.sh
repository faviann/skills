#!/usr/bin/env bash
set -euo pipefail

# Own the semantic authority for one issue's Convergence lifecycles. The file is
# keyed by issue, not by run, so session and telemetry boundaries cannot mint a
# fresh Corrective-batch budget.

shopt -s lastpipe

staged=""
lock_dir=""
cleanup() {
  [[ -z "$staged" ]] || rm -f -- "$staged"
  [[ -z "$lock_dir" ]] || rmdir -- "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  printf 'convergence state: %s\n' "$1" >&2
  exit 1
}

usage() {
  fail 'usage: convergence-state.sh candidate | begin --issue N --run HANDLE --candidate ID | recover --issue N --run HANDLE --candidate ID | authorize --issue N --lifecycle ID --candidate ID | complete --issue N --lifecycle ID --correction ID --source ID --result ID | advance --issue N --lifecycle ID --kind synchronization|governing-state-restart --source ID --result ID | exhaust --issue N --lifecycle ID --candidate ID --outcome Progresses|failed --blockers-file FILE --reentry-condition TEXT | end --issue N --lifecycle ID --candidate ID --outcome Closes|Progresses|failed [--reentry-condition TEXT] | reenter --issue N --run HANDLE --candidate ID --condition TEXT --evidence TEXT'
}

command -v git >/dev/null 2>&1 || fail 'git is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'

repository_slug() {
  local origin slug
  origin="$(git remote get-url origin 2>/dev/null)" \
    || fail 'origin is required to identify the Candidate repository'
  origin="${origin%.git}"
  [[ "$origin" =~ ^([A-Za-z][A-Za-z0-9+.-]*://([^/@]+@)?github\.com(:[0-9]+)?/|([^/:@]+@)?github\.com:)(.*)$ ]] \
    || fail 'origin must identify a GitHub repository'
  slug="${BASH_REMATCH[5]}"
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || fail 'origin repository identity is malformed'
  printf '%s\n' "$slug"
}

candidate_identity() {
  local dirty tree
  dirty="$(git status --porcelain=v1 --untracked-files=all 2>/dev/null)" \
    || fail 'run from the target Git repository'
  [[ -z "$dirty" ]] \
    || fail 'Candidate identity requires a clean worktree including untracked files'
  tree="$(git rev-parse --verify 'HEAD^{tree}' 2>/dev/null)" \
    || fail 'Candidate identity requires a committed HEAD'
  [[ "$tree" =~ ^[0-9a-f]{40,64}$ ]] || fail 'Candidate tree identity is malformed'
  printf 'repo:%s;tree:%s\n' "$(repository_slug)" "$tree"
}

new_id() {
  od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
}

valid_issue() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
valid_candidate() {
  [[ "$1" =~ ^repo:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\;tree:[0-9a-f]{40,64}$ ]]
}
valid_token() { [[ -n "$1" && ! "$1" =~ [[:space:]] ]]; }

require_current_candidate() {
  local supplied="$1" observed
  valid_candidate "$supplied" || usage
  observed="$(candidate_identity)"
  [[ "$supplied" == "$observed" ]] \
    || fail 'supplied Candidate identity does not match the exact current Candidate'
}

subcommand="${1:-}"
shift || true
if [[ "$subcommand" == candidate ]]; then
  (( $# == 0 )) || usage
  candidate_identity
  exit 0
fi

issue="" run="" candidate="" lifecycle="" correction="" source="" result=""
kind="" outcome="" blockers_file="" reentry_condition="" evidence=""
while (( $# > 0 )); do
  case "$1" in
    --issue) issue="${2:-}"; shift 2 ;;
    --run) run="${2:-}"; shift 2 ;;
    --candidate) candidate="${2:-}"; shift 2 ;;
    --lifecycle) lifecycle="${2:-}"; shift 2 ;;
    --correction) correction="${2:-}"; shift 2 ;;
    --source) source="${2:-}"; shift 2 ;;
    --result) result="${2:-}"; shift 2 ;;
    --kind) kind="${2:-}"; shift 2 ;;
    --outcome) outcome="${2:-}"; shift 2 ;;
    --blockers-file) blockers_file="${2:-}"; shift 2 ;;
    --reentry-condition|--condition) reentry_condition="${2:-}"; shift 2 ;;
    --evidence) evidence="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

valid_issue "$issue" || usage
common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || fail 'run from the target Git repository'
state_dir="$common_dir/work-on-convergence"
state_file="$state_dir/issue-$issue.json"
if [[ ! -e "$state_dir" ]]; then
  (umask 077 && mkdir -p -- "$state_dir")
fi
[[ -d "$state_dir" && ! -L "$state_dir" ]] || fail 'state directory is unsafe'
chmod 700 "$state_dir"
lock_dir="$state_dir/.issue-$issue.lock"
mkdir -- "$lock_dir" 2>/dev/null || fail 'state is busy; retry after its current owner finishes'

write_state() {
  chmod 700 "$state_dir"
  staged="$(umask 077 && mktemp "$state_dir/.state.XXXXXX")"
  cat >"$staged"
  validate_state_file "$staged" || fail 'refusing to write invalid semantic state'
  chmod 600 "$staged"
  mv -f -- "$staged" "$state_file"
  staged=""
}

validate_state_file() {
  local file="$1" current
  current="$(jq -r '.lifecycle.current_candidate // empty' "$file" 2>/dev/null)"
  jq -e --argjson issue "$issue" --arg current "$current" '
    def candidate:
      type == "string" and test("^repo:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+;tree:[0-9a-f]{40}([0-9a-f]{24})?$");
    def events:
      ([.lifecycle.corrections[] |
        {sequence, source:.source_candidate,
         result:(if .status == "completed" then .result_candidate else .source_candidate end)}] +
       [.lifecycle.continuity[] |
        {sequence, source:.source_candidate, result:.result_candidate}]) | sort_by(.sequence);
    def chain:
      reduce events[] as $event
        ({ok:true, current:.lifecycle.initial_candidate};
         if .ok and .current == $event.source
         then .current = $event.result else .ok = false end);
    .schema == 1 and .issue == $issue and (.history | type == "array") and
    (.lifecycle | type == "object") and
    (.lifecycle.id | type == "string" and length > 0) and
    (.lifecycle.status == "active" or .lifecycle.status == "irreconcilable" or .lifecycle.status == "ended") and
    (.lifecycle.runs | type == "array" and all(.[]; type == "string" and length > 0)) and
    ((.lifecycle.runs | length) == (.lifecycle.runs | unique | length)) and
    (.lifecycle.initial_candidate | candidate) and (.lifecycle.current_candidate | candidate) and
    (.lifecycle.consumed | type == "number" and . >= 0 and . <= 2) and
    (.lifecycle.corrections | type == "array") and (.lifecycle.continuity | type == "array") and
    all(.lifecycle.corrections[];
      (.id | type == "string" and length > 0) and (.sequence | type == "number" and . >= 1) and
      (.source_candidate | candidate) and
      ((.status == "authorized" and .result_candidate == null) or
       (.status == "completed" and (.result_candidate | candidate) and .result_candidate != .source_candidate))) and
    all(.lifecycle.continuity[];
      (.sequence | type == "number" and . >= 1) and
      (.kind == "synchronization" or .kind == "governing-state-restart") and
      (.source_candidate | candidate) and (.result_candidate | candidate)) and
    ([.lifecycle.corrections[].id] | length) == ([.lifecycle.corrections[].id] | unique | length) and
    (([.lifecycle.corrections[].sequence] + [.lifecycle.continuity[].sequence]) | length) ==
      (([.lifecycle.corrections[].sequence] + [.lifecycle.continuity[].sequence]) | unique | length) and
    .lifecycle.next_sequence == (([.lifecycle.corrections[].sequence] + [.lifecycle.continuity[].sequence] | length) + 1) and
    ([.lifecycle.corrections[] | select(.status == "completed")] | length) == .lifecycle.consumed and
    ([.lifecycle.corrections[] | select(.status == "authorized")] | length) <= 1 and
    (chain | .ok and .current == $current)
  ' "$file" >/dev/null 2>&1
}

load_state() {
  [[ -f "$state_file" && ! -L "$state_file" && -r "$state_file" ]] \
    || fail 'semantic state is missing or unsafe'
  [[ "$(stat -c '%a' "$state_dir")" == 700 \
    && "$(stat -c '%a' "$state_file")" == 600 ]] \
    || fail 'semantic state is not owner-only'
  validate_state_file "$state_file" || fail 'semantic state is corrupt'
}

require_lifecycle() {
  local recorded
  valid_token "$lifecycle" || usage
  recorded="$(jq -r '.lifecycle.id' "$state_file")"
  [[ "$recorded" == "$lifecycle" ]] \
    || fail 'lifecycle identity does not match the active semantic authority'
}

mark_irreconcilable() {
  local observed="$1" reason="$2"
  jq --arg observed "$observed" --arg reason "$reason" '
    .lifecycle.status = "irreconcilable" |
    .lifecycle.observed_candidate = $observed |
    .lifecycle.irreconcilable_reason = $reason
  ' "$state_file" | write_state
  fail "$reason; mutation authority is fail-closed"
}

reconcile_candidate() {
  local observed="$1" status current pending_source
  valid_candidate "$observed" || usage
  status="$(jq -r '.lifecycle.status' "$state_file")"
  [[ "$status" == active ]] || fail "lifecycle is $status"
  current="$(jq -r '.lifecycle.current_candidate' "$state_file")"
  [[ "$current" == "$observed" ]] && return 0
  pending_source="$(jq -r '[.lifecycle.corrections[] | select(.status == "authorized")][0].source_candidate // empty' "$state_file")"
  if [[ -n "$pending_source" ]]; then
    mark_irreconcilable "$observed" 'authorized correction no longer matches its unchanged source and has no correlated result'
  fi
  mark_irreconcilable "$observed" 'Candidate transition is absent from the semantic authority'
}

case "$subcommand" in
  begin)
    valid_token "$run" && valid_candidate "$candidate" || usage
    require_current_candidate "$candidate"
    if [[ -e "$state_file" || -L "$state_file" ]]; then
      load_state
      status="$(jq -r '.lifecycle.status' "$state_file")"
      [[ "$status" == active ]] \
        || fail 'prior lifecycle has ended or failed closed; verified material re-entry is required'
      reconcile_candidate "$candidate"
      jq --arg run "$run" '.lifecycle.runs |= (if index($run) then . else . + [$run] end)' \
        "$state_file" | write_state
    else
      lifecycle="$(new_id)"
      jq -n --argjson issue "$issue" --arg id "$lifecycle" --arg run "$run" \
        --arg candidate "$candidate" '{schema:1, issue:$issue, history:[], lifecycle:{id:$id, predecessor:null, status:"active", runs:[$run], initial_candidate:$candidate, current_candidate:$candidate, consumed:0, corrections:[], continuity:[], next_sequence:1, outcome:null, reentry_condition:null}}' \
        | write_state
    fi
    jq -r '.lifecycle.id' "$state_file"
    ;;
  recover)
    valid_token "$run" && valid_candidate "$candidate" || usage
    require_current_candidate "$candidate"
    load_state
    reconcile_candidate "$candidate"
    jq --arg run "$run" '.lifecycle.runs |= (if index($run) then . else . + [$run] end)' \
      "$state_file" | write_state
    jq -c '.lifecycle | {id, consumed, current_candidate, pending_correction:([.corrections[] | select(.status == "authorized")][0] // null)}' "$state_file"
    ;;
  authorize)
    valid_candidate "$candidate" || usage
    require_current_candidate "$candidate"
    load_state
    require_lifecycle
    reconcile_candidate "$candidate"
    pending="$(jq -r '[.lifecycle.corrections[] | select(.status == "authorized")][0].id // empty' "$state_file")"
    if [[ -n "$pending" ]]; then
      printf '%s\n' "$pending"
      exit 0
    fi
    consumed="$(jq -r '.lifecycle.consumed' "$state_file")"
    (( consumed < 2 )) || fail 'Corrective-batch budget exhausted before authorization'
    correction="$(new_id)"
    jq --arg id "$correction" --arg source "$candidate" '
      .lifecycle.corrections += [{id:$id, sequence:.lifecycle.next_sequence, source_candidate:$source, status:"authorized", result_candidate:null}] |
      .lifecycle.next_sequence += 1
    ' "$state_file" | write_state
    printf '%s\n' "$correction"
    ;;
  complete)
    valid_token "$correction" && valid_candidate "$source" && valid_candidate "$result" || usage
    [[ "$source" != "$result" ]] || fail 'unchanged Candidate does not consume a Corrective batch'
    require_current_candidate "$result"
    load_state
    require_lifecycle
    completed="$(jq -r --arg id "$correction" '[.lifecycle.corrections[] | select(.id == $id and .status == "completed")][0] | @json' "$state_file")"
    if [[ "$completed" != null ]]; then
      jq -e --arg id "$correction" --arg source "$source" --arg result "$result" '
        any(.lifecycle.corrections[]; .id == $id and .status == "completed" and .source_candidate == $source and .result_candidate == $result)
      ' "$state_file" >/dev/null || fail 'completed correction identity conflicts with the requested transition'
      jq -r '.lifecycle.consumed' "$state_file"
      exit 0
    fi
    [[ "$(jq -r '.lifecycle.status' "$state_file")" == active ]] || fail 'lifecycle is not active'
    jq -e --arg id "$correction" --arg source "$source" '
      .lifecycle.current_candidate == $source and
      any(.lifecycle.corrections[]; .id == $id and .status == "authorized" and .source_candidate == $source)
    ' "$state_file" >/dev/null || fail 'correction is not the authorized source transition'
    (( $(jq -r '.lifecycle.consumed' "$state_file") < 2 )) \
      || fail 'Corrective-batch budget exhausted before completion'
    jq --arg id "$correction" --arg result "$result" '
      .lifecycle.corrections |= map(if .id == $id and .status == "authorized" then .status = "completed" | .result_candidate = $result else . end) |
      .lifecycle.consumed += 1 |
      .lifecycle.current_candidate = $result
    ' "$state_file" | write_state
    jq -r '.lifecycle.consumed' "$state_file"
    ;;
  advance)
    valid_candidate "$source" && valid_candidate "$result" || usage
    [[ "$kind" == synchronization || "$kind" == governing-state-restart ]] || usage
    require_current_candidate "$result"
    load_state
    require_lifecycle
    reconcile_candidate "$source"
    jq -e '[.lifecycle.corrections[] | select(.status == "authorized")] | length == 0' \
      "$state_file" >/dev/null || fail 'cannot advance continuity during an authorized correction'
    jq --arg kind "$kind" --arg source "$source" --arg result "$result" '
      .lifecycle.continuity += [{kind:$kind, sequence:.lifecycle.next_sequence, source_candidate:$source, result_candidate:$result}] |
      .lifecycle.next_sequence += 1 |
      .lifecycle.current_candidate = $result
    ' "$state_file" | write_state
    jq -r '.lifecycle.consumed' "$state_file"
    ;;
  exhaust)
    valid_candidate "$candidate" || usage
    require_current_candidate "$candidate"
    [[ "$outcome" == Progresses || "$outcome" == failed ]] || usage
    [[ -n "$reentry_condition" && -f "$blockers_file" && ! -L "$blockers_file" && -s "$blockers_file" ]] || usage
    load_state
    require_lifecycle
    reconcile_candidate "$candidate"
    [[ "$(jq -r '.lifecycle.consumed' "$state_file")" == 2 ]] \
      || fail 'exhaustion requires both Corrective batches to be consumed'
    jq -e '[.lifecycle.corrections[] | select(.status == "authorized")] | length == 0' \
      "$state_file" >/dev/null || fail 'cannot exhaust with an unresolved authorized transition'
    jq --rawfile blockers "$blockers_file" --arg outcome "$outcome" \
      --arg condition "$reentry_condition" '
      .lifecycle.status = "ended" | .lifecycle.exhausted = true |
      .lifecycle.outcome = $outcome | .lifecycle.unresolved_blockers = $blockers |
      .lifecycle.reentry_condition = $condition
    ' "$state_file" | write_state
    ;;
  end)
    valid_candidate "$candidate" || usage
    require_current_candidate "$candidate"
    [[ "$outcome" == Closes || "$outcome" == Progresses || "$outcome" == failed ]] || usage
    if [[ "$outcome" != Closes && -z "$reentry_condition" ]]; then usage; fi
    load_state
    require_lifecycle
    status="$(jq -r '.lifecycle.status' "$state_file")"
    if [[ "$status" == active ]]; then reconcile_candidate "$candidate"; fi
    [[ "$status" == active || "$status" == irreconcilable ]] || fail 'lifecycle has already ended'
    if [[ "$outcome" == Closes ]]; then
      [[ "$status" == active ]] \
        || fail 'an irreconcilable lifecycle cannot close'
      jq -e '[.lifecycle.corrections[] | select(.status == "authorized")] | length == 0' \
        "$state_file" >/dev/null || fail 'an authorized unresolved correction cannot close'
    fi
    jq --arg outcome "$outcome" --arg condition "$reentry_condition" --arg candidate "$candidate" '
      .lifecycle.status = "ended" | .lifecycle.outcome = $outcome |
      .lifecycle.final_candidate = $candidate |
      .lifecycle.reentry_condition = (if $condition == "" then null else $condition end)
    ' "$state_file" | write_state
    ;;
  reenter)
    valid_token "$run" && valid_candidate "$candidate" || usage
    [[ -n "$reentry_condition" && -n "$evidence" ]] || usage
    require_current_candidate "$candidate"
    load_state
    [[ "$(jq -r '.lifecycle.status' "$state_file")" == ended ]] \
      || fail 'material re-entry requires a durably ended lifecycle'
    [[ "$(jq -r '.lifecycle.reentry_condition // empty' "$state_file")" == "$reentry_condition" ]] \
      || fail 'the satisfied condition does not match the recorded material re-entry condition'
    previous="$(jq -r '.lifecycle.id' "$state_file")"
    lifecycle="$(new_id)"
    jq --arg id "$lifecycle" --arg predecessor "$previous" --arg run "$run" \
      --arg candidate "$candidate" --arg condition "$reentry_condition" --arg evidence "$evidence" '
      .history += [.lifecycle] |
      .lifecycle = {id:$id, predecessor:$predecessor, status:"active", runs:[$run], initial_candidate:$candidate, current_candidate:$candidate, consumed:0, corrections:[], continuity:[], next_sequence:1, outcome:null, reentry_condition:null, reentry:{condition:$condition, evidence:$evidence}}
    ' "$state_file" | write_state
    printf '%s\n' "$lifecycle"
    ;;
  *) usage ;;
esac
