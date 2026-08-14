#!/usr/bin/env bash
set -euo pipefail

# Record and aggregate one work-on run's mechanical telemetry. Events are
# appended as JSON lines to a run-scoped sink inside the target repository's
# git-dir, beside the provenance ledger and adjudication log, so the sink is
# untracked by construction and never reaches a published artifact.
#
# The recorder stores a closed set of enumerated fields, resolved SHAs,
# byte/duration counts, and a redacted command identity. It has no field for a
# prompt, an issue body, a diff, a file's contents, or a command's output, so
# that material cannot be recorded even by mistake.

readonly schema_version=1
readonly roles=(
  implementation
  readiness
  review-standards
  review-spec
  closure-sweep
  other
)
readonly review_kinds=(readiness full delta)
readonly phases=(orient implementation checkpoint gate remediation closeout)
readonly run_outcomes=(Closes Progresses aborted)

fail() {
  printf 'run telemetry: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: run-telemetry.sh <subcommand>
  start                                     begin a run; prints the run id
  run-id                                    print the active run id
  launch --role R --phase P --round N [--tokens-in N] [--tokens-out N]
  review --kind K --phase P --round N --base REF (--head REF | --worktree)
  exec --phase P --round N -- <command...>  run and time a validation command
  finish --outcome (Closes|Progresses|aborted)
  summary [--run ID]                        deterministic aggregate as JSON
USAGE
  exit 1
}

contains() {
  local needle="$1" candidate
  shift
  for candidate in "$@"; do
    [[ "$candidate" == "$needle" ]] && return 0
  done
  return 1
}

require_enum() {
  local label="$1" value="$2"
  shift 2
  contains "$value" "$@" || fail "$label must be one of: $*"
}

require_round() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)$ ]] || fail "round must be a nonnegative integer"
}

require_count() {
  [[ "$2" =~ ^(0|[1-9][0-9]*)$ ]] || fail "$1 must be a nonnegative integer"
}

# Milliseconds since the epoch. EPOCHREALTIME avoids a subprocess per event;
# a shell without it degrades to whole seconds rather than failing.
now_ms() {
  local raw="${EPOCHREALTIME:-}"
  if [[ "$raw" =~ ^([0-9]+)[.,]([0-9]+)$ ]]; then
    printf '%s%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]:0:3}"
  else
    printf '%s000\n' "$(date -u +%s)"
  fi
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

command -v git >/dev/null 2>&1 || fail "run telemetry requires git"
command -v jq >/dev/null 2>&1 || fail "run telemetry requires jq"

git rev-parse --show-toplevel >/dev/null 2>&1 \
  || fail "run telemetry requires a Git-backed target repository"
telemetry_root="$(git rev-parse --absolute-git-dir)/work-on-telemetry"
pointer="$telemetry_root/current-run"
runs_root="$telemetry_root/runs"

readonly run_id_pattern='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$'

active_run() {
  local id
  [[ -f "$pointer" ]] || fail "no active telemetry run; run start first"
  id="$(head -n 1 "$pointer" | tr -d '\r\n')"
  [[ "$id" =~ $run_id_pattern ]] || fail "active telemetry run id is malformed"
  [[ -f "$runs_root/$id.jsonl" ]] || fail "telemetry sink is missing for run $id"
  printf '%s\n' "$id"
}

# Appends exactly one line. `extra` is a compact JSON object supplying the
# event's own fields; the envelope is identical for every event type.
append_event() {
  local run_id="$1" type="$2" extra="${3:-}" run_file sequence
  [[ -n "$extra" ]] || extra='{}'
  run_file="$runs_root/$run_id.jsonl"
  sequence=$(( $(wc -l <"$run_file" | tr -d ' ') + 1 ))
  jq -cn \
    --argjson schema "$schema_version" \
    --arg run "$run_id" \
    --argjson seq "$sequence" \
    --arg at "$(now_iso)" \
    --argjson epoch_ms "$(now_ms)" \
    --arg type "$type" \
    --argjson extra "$extra" \
    '{schema: $schema, run: $run, seq: $seq, at: $at, epoch_ms: $epoch_ms, type: $type}
      + $extra' >>"$run_file"
}

# A command token is kept only when it is neither a secret-shaped value nor the
# value of a secret-shaped name. Redaction is by name, by flag, by position
# after a secret-shaped flag, and by value shape.
readonly secret_name_pattern='(TOKEN|SECRET|PASSWORD|PASSWD|APIKEY|API_KEY|_KEY|^KEY$|CREDENTIAL|AUTHORIZATION|AUTH_|_AUTH|^AUTH$|SESSION|COOKIE|SIGNATURE|PRIVATE)'
readonly secret_flag_pattern='^--?[A-Za-z0-9-]*(token|secret|password|passwd|apikey|api-key|key|credential|auth|bearer)[A-Za-z0-9-]*$'
readonly secret_value_pattern='^(gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk-[A-Za-z0-9_-]{16,}|xox[abposr]-[A-Za-z0-9-]{10,}|AKIA[A-Z0-9]{12,}|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|[A-Za-z0-9+/]{40,}={0,2})$'

redact_command() {
  local token name value previous_was_secret_flag=false
  redacted_command=()
  for token in "$@"; do
    if [[ "$previous_was_secret_flag" == true ]]; then
      redacted_command+=('[redacted]')
      previous_was_secret_flag=false
      continue
    fi
    if [[ "$token" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      if [[ "${name^^}" =~ $secret_name_pattern || "$value" =~ $secret_value_pattern ]]; then
        redacted_command+=("$name=[redacted]")
        continue
      fi
    elif [[ "$token" =~ ^(--?[A-Za-z0-9][A-Za-z0-9_-]*)=(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      if [[ "$name" =~ $secret_flag_pattern || "$value" =~ $secret_value_pattern ]]; then
        redacted_command+=("$name=[redacted]")
        continue
      fi
    fi
    if [[ "$token" =~ $secret_flag_pattern ]]; then
      previous_was_secret_flag=true
      redacted_command+=("$token")
      continue
    fi
    if [[ "$token" =~ $secret_value_pattern ]]; then
      redacted_command+=('[redacted]')
      continue
    fi
    redacted_command+=("$token")
  done
}

subcommand="${1:-}"
[[ -n "$subcommand" ]] || usage
shift || true

case "$subcommand" in
  start)
    [[ "$#" -eq 0 ]] || usage
    mkdir -p "$runs_root"
    suffix="$(od -An -tx1 -N4 /dev/urandom 2>/dev/null | tr -d ' \n')"
    [[ "$suffix" =~ ^[0-9a-f]{8}$ ]] \
      || suffix="$(printf '%08x' $(( (RANDOM << 16 | RANDOM) & 0xffffffff )))"
    run_id="$(date -u +%Y%m%dT%H%M%SZ)-$suffix"
    [[ "$run_id" =~ $run_id_pattern ]] || fail "could not mint a run id"
    [[ ! -e "$runs_root/$run_id.jsonl" ]] || fail "run id collision: $run_id"
    : >"$runs_root/$run_id.jsonl"
    head_sha="$(git rev-parse --verify HEAD 2>/dev/null || printf '')"
    append_event "$run_id" run_start "$(
      jq -cn --arg head "$head_sha" \
        '{workflow: "work-on"} + (if $head == "" then {} else {head: $head} end)'
    )"
    staged="$pointer.$$"
    printf '%s\n' "$run_id" >"$staged"
    mv -f "$staged" "$pointer"
    printf '%s\n' "$run_id"
    ;;

  run-id)
    [[ "$#" -eq 0 ]] || usage
    active_run
    ;;

  launch)
    role=""
    phase=""
    round=""
    tokens_in=""
    tokens_out=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --role) role="${2:?--role requires a value}"; shift 2 ;;
        --phase) phase="${2:?--phase requires a value}"; shift 2 ;;
        --round) round="${2:?--round requires a value}"; shift 2 ;;
        --tokens-in) tokens_in="${2:?--tokens-in requires a value}"; shift 2 ;;
        --tokens-out) tokens_out="${2:?--tokens-out requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_enum role "$role" "${roles[@]}"
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    # Token counts are optional: a runtime that does not expose them records a
    # launch without them rather than failing or inventing a number.
    [[ -z "$tokens_in" ]] || require_count tokens-in "$tokens_in"
    [[ -z "$tokens_out" ]] || require_count tokens-out "$tokens_out"
    run_id="$(active_run)"
    append_event "$run_id" subagent_launch "$(
      jq -cn \
        --arg role "$role" --arg phase "$phase" --argjson round "$round" \
        --arg tokens_in "$tokens_in" --arg tokens_out "$tokens_out" \
        '{role: $role, phase: $phase, round: $round}
          + (if $tokens_in == "" then {} else {tokens_in: ($tokens_in | tonumber)} end)
          + (if $tokens_out == "" then {} else {tokens_out: ($tokens_out | tonumber)} end)'
    )"
    ;;

  review)
    kind=""
    phase=""
    round=""
    base=""
    head_ref=""
    worktree=false
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --kind) kind="${2:?--kind requires a value}"; shift 2 ;;
        --phase) phase="${2:?--phase requires a value}"; shift 2 ;;
        --round) round="${2:?--round requires a value}"; shift 2 ;;
        --base) base="${2:?--base requires a value}"; shift 2 ;;
        --head) head_ref="${2:?--head requires a value}"; shift 2 ;;
        --worktree) worktree=true; shift ;;
        *) usage ;;
      esac
    done
    require_enum kind "$kind" "${review_kinds[@]}"
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    [[ -n "$base" ]] || fail "review requires --base"
    if [[ "$worktree" == true ]]; then
      [[ -z "$head_ref" ]] || fail "review takes --head or --worktree, not both"
      head_ref=HEAD
    else
      [[ -n "$head_ref" ]] || fail "review requires --head or --worktree"
    fi
    base_sha="$(git rev-parse --verify "$base^{commit}" 2>/dev/null)" \
      || fail "review --base does not resolve to a commit: $base"
    head_sha="$(git rev-parse --verify "$head_ref^{commit}" 2>/dev/null)" \
      || fail "review --head does not resolve to a commit: $head_ref"
    # Only the size of the compared material is recorded; the diff itself is
    # measured and discarded.
    if [[ "$worktree" == true ]]; then
      input_bytes="$(git diff "$base_sha" | wc -c | tr -d ' ')"
    else
      input_bytes="$(git diff "$base_sha...$head_sha" | wc -c | tr -d ' ')"
    fi
    run_id="$(active_run)"
    append_event "$run_id" review "$(
      jq -cn \
        --arg kind "$kind" --arg phase "$phase" --argjson round "$round" \
        --arg base "$base_sha" --arg head "$head_sha" \
        --argjson worktree "$worktree" --argjson input_bytes "$input_bytes" \
        '{kind: $kind, phase: $phase, round: $round, base: $base, head: $head,
          head_is_worktree: $worktree, input_bytes: $input_bytes}'
    )"
    ;;

  exec)
    phase=""
    round=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --phase) phase="${2:?--phase requires a value}"; shift 2 ;;
        --round) round="${2:?--round requires a value}"; shift 2 ;;
        --) shift; break ;;
        *) usage ;;
      esac
    done
    require_enum phase "$phase" "${phases[@]}"
    require_round "$round"
    [[ "$#" -gt 0 ]] || fail "exec requires a command after --"
    run_id="$(active_run)"
    run_file="$runs_root/$run_id.jsonl"

    redact_command "$@"
    # Command tokens travel as base64 lines so a token that looks like one of
    # jq's own options cannot be swallowed by jq's argument parser, and so a
    # token containing any byte still round-trips exactly.
    encoded_command=""
    for token in "${redacted_command[@]}"; do
      encoded_command+="$(printf '%s' "$token" | base64 | tr -d '\n')"$'\n'
    done
    command_id="$(printf '%s' "$encoded_command" | sha256sum | cut -c1-12)"
    execution_index="$(
      jq -n -R '[inputs | fromjson? // empty
        | select(type == "object" and .type == "validation_start")] | length' \
        <"$run_file"
    )"
    exec_id="$(printf '%s-e%03d' "$run_id" "$((execution_index + 1))")"
    started_ms="$(now_ms)"

    append_event "$run_id" validation_start "$(
      jq -cn \
        --arg exec_id "$exec_id" --arg command_id "$command_id" \
        --arg phase "$phase" --argjson round "$round" \
        --arg encoded_command "$encoded_command" \
        '{exec_id: $exec_id, command_id: $command_id, phase: $phase,
          round: $round,
          command: ($encoded_command | split("\n")
            | map(select(length > 0) | @base64d))}'
    )"

    validation_ended=false
    record_end() {
      local outcome="$1" status="$2"
      validation_ended=true
      append_event "$run_id" validation_end "$(
        jq -cn \
          --arg exec_id "$exec_id" --arg command_id "$command_id" \
          --arg phase "$phase" --argjson round "$round" \
          --arg outcome "$outcome" --argjson exit_status "$status" \
          --argjson duration_ms "$(( $(now_ms) - started_ms ))" \
          '{exec_id: $exec_id, command_id: $command_id, phase: $phase,
            round: $round, outcome: $outcome, exit_status: $exit_status,
            duration_ms: $duration_ms}'
      )"
    }
    # An interrupted wrapper still closes its own execution, so the sink holds
    # a controlled `interrupted` record instead of a dangling start.
    on_exit() {
      [[ "$validation_ended" == true ]] || record_end interrupted null
    }
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    set +e
    "$@"
    exit_status=$?
    set -e
    if [[ "$exit_status" -eq 0 ]]; then
      record_end passed "$exit_status"
    else
      record_end failed "$exit_status"
    fi
    exit "$exit_status"
    ;;

  finish)
    outcome=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --outcome) outcome="${2:?--outcome requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    require_enum outcome "$outcome" "${run_outcomes[@]}"
    run_id="$(active_run)"
    append_event "$run_id" run_finish "$(
      jq -cn --arg outcome "$outcome" '{outcome: $outcome}'
    )"
    ;;

  summary)
    run_id=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --run) run_id="${2:?--run requires a value}"; shift 2 ;;
        *) usage ;;
      esac
    done
    if [[ -n "$run_id" ]]; then
      [[ "$run_id" =~ $run_id_pattern ]] || fail "run id is malformed: $run_id"
      [[ -f "$runs_root/$run_id.jsonl" ]] \
        || fail "telemetry sink is missing for run $run_id"
    else
      run_id="$(active_run)"
    fi
    # Aggregation is a pure function of one run's sink: enumerated keys in a
    # fixed order, and lines that are not this run's schema-1 JSON ignored.
    jq -n -R -c \
      --argjson schema "$schema_version" \
      --arg run "$run_id" \
      --argjson roles "$(printf '%s\n' "${roles[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
      --argjson kinds "$(printf '%s\n' "${review_kinds[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
      --argjson phases "$(printf '%s\n' "${phases[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" '
      [inputs | select(length > 0)] as $lines
      | [$lines[] | fromjson? // empty] as $parsed
      | [$parsed[] | select(type == "object" and .run == $run and .schema == $schema)] as $events
      | [$events[] | select(.type == "subagent_launch")] as $launches
      | [$events[] | select(.type == "review")] as $reviews
      | [$events[] | select(.type == "validation_start")] as $starts
      | [$events[] | select(.type == "validation_end")] as $ends
      | ([$ends[] | .exec_id] | unique) as $ended_ids
      | [$launches[] | select(has("tokens_in") or has("tokens_out"))] as $token_launches
      | {
          schema: $schema,
          run: $run,
          started_at: ([$events[] | select(.type == "run_start") | .at] | first),
          finished_at: ([$events[] | select(.type == "run_finish") | .at] | last),
          final_workflow_outcome:
            ([$events[] | select(.type == "run_finish") | .outcome] | last),
          events: ($events | length),
          malformed_lines: (($lines | length) - ($parsed | length)),
          subagent_launches: {
            total: ($launches | length),
            by_role: (reduce $roles[] as $role ({};
              .[$role] = ([$launches[] | select(.role == $role)] | length)))
          },
          reviews: {
            total: ($reviews | length),
            by_kind: (reduce $kinds[] as $kind ({};
              .[$kind] = ([$reviews[] | select(.kind == $kind)] | length))),
            input_bytes: ([$reviews[] | .input_bytes] | add // 0)
          },
          validations: {
            total: ($starts | length),
            passed: ([$ends[] | select(.outcome == "passed")] | length),
            failed: ([$ends[] | select(.outcome == "failed")] | length),
            interrupted: ([$ends[] | select(.outcome == "interrupted")] | length),
            incomplete: ([$starts[]
              | select(.exec_id as $id | ($ended_ids | index($id)) == null)]
              | length),
            duration_ms: ([$ends[] | .duration_ms] | add // 0)
          },
          phase_elapsed_ms: (reduce $phases[] as $phase ({};
            ([$events[] | select(.phase == $phase) | .epoch_ms]) as $stamps
            | if ($stamps | length) > 0
              then .[$phase] = (($stamps | max) - ($stamps | min))
              else . end)),
          tokens: {
            input: ([$token_launches[] | .tokens_in // 0] | add // 0),
            output: ([$token_launches[] | .tokens_out // 0] | add // 0),
            coverage:
              (if ($token_launches | length) == 0 then "none"
               elif ($token_launches | length) == ($launches | length) then "complete"
               else "partial" end)
          }
        }
    ' <"$runs_root/$run_id.jsonl"
    ;;

  *)
    usage
    ;;
esac
