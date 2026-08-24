#!/usr/bin/env bash
set -euo pipefail

# The Validation-surface manifest is semantic contract state carried by
# instructions, not by a script: the primary materializes it, freezes it, and
# hands it on. These checks pin the parts of that contract a later edit could
# silently drop — which file owns each rule, the freeze ordering, the storage
# semantics, the evidence strength, and the fail-closed handling.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

SKILL="$skill_dir/SKILL.md"
GATE="$skill_dir/references/closability-gate.md"
WORKFLOW="$skill_dir/references/default-workflow.md"
CLOSEOUT="$skill_dir/references/github-closeout.md"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

# These documents wrap at 80 columns, so a rule routinely straddles a newline.
# Content assertions run against a whitespace-flattened copy of each file;
# ordering assertions run against the original, which still has line numbers.
flat_dir="$(mktemp -d)"
trap 'rm -rf "$flat_dir"' EXIT

flatten() {
  local flat="$flat_dir/$(printf '%s' "${1#"$skill_dir/"}" | tr '/' '_')"
  [[ -f "$flat" ]] || tr '\n' ' ' < "$1" | tr -s ' ' > "$flat"
  printf '%s' "$flat"
}

has() {
  # has <file> <extended regex> <description>
  if grep -Eqi -- "$2" "$(flatten "$1")"; then
    return 0
  fi
  fail "$3 (missing in ${1#"$skill_dir/"}: $2)"
}

lacks() {
  if grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3 (unexpected in ${1#"$skill_dir/"}: $2)"
  fi
}

line_of() {
  grep -Eni -m1 -- "$2" "$1" | cut -d: -f1
}

precedes() {
  # precedes <file> <earlier regex> <later regex> <description>
  local first second
  first="$(line_of "$1" "$2" || true)"
  second="$(line_of "$1" "$3" || true)"
  if [[ -z "$first" || -z "$second" ]]; then
    fail "$4 (one of the anchors is absent from ${1#"$skill_dir/"})"
    return
  fi
  if (( first >= second )); then
    fail "$4 (${1#"$skill_dir/"}: line $first is not before line $second)"
  fi
}

## Materialization — only an enumeration or a deterministic rule, evaluated here
has "$GATE" 'explicit finite enumeration' \
  'the gate accepts an explicit finite enumeration'
has "$GATE" 'deterministic, non-interpretive finite selection rule' \
  'the gate accepts a deterministic, non-interpretive finite selection rule'
has "$GATE" 'must actually be evaluated during this preflight' \
  'the gate evaluates the chosen form during preflight'
has "$GATE" 'complete concrete list for the trusted snapshot' \
  'materialization produces the complete concrete list for the trusted snapshot'
has "$GATE" 'whatever implementation touches' \
  'the gate names an interpretive rule that fails the test'
has "$GATE" 'passes only when all six hold' \
  'the gate has a sixth condition'
has "$GATE" 'Validation surface is finite and materialized here' \
  'condition 6 requires a finite materialized surface'
has "$SKILL" 'materialized as a finite frozen' \
  'the top-level procedure requires materialization before delegation'
echo "ok - preflight materializes a finite surface from an enumeration or a deterministic rule"

## An authorized-to-be-created member needs a contract-determinable identity
has "$GATE" 'artifact this issue authorizes creating' \
  'the gate admits an artifact the issue authorizes creating'
has "$GATE" 'identity, location, and criterion role are already determinable' \
  'such a member needs a contract-determinable identity, location, and role'
has "$GATE" 'merely turns out to touch never' \
  'implementation-only artifacts never join a surface'
echo "ok - an authorized-to-be-created member is admitted only when the contract determines it"

## Freeze timing and identity
has "$GATE" 'freezes when the complete gate passes' \
  'the manifest freezes on a complete gate pass'
has "$GATE" 'before workflow-provenance capture' \
  'the freeze precedes workflow-provenance capture'
has "$GATE" 'and implementation delegation' \
  'the freeze precedes implementation delegation'
has "$GATE" 'trusted snapshot, the selected.*workflow, and the pre-implementation base' \
  'the manifest is identified with snapshot, workflow, and base'
precedes "$SKILL" 'closability-gate\.md' 'workflow-provenance\.sh capture' \
  'the procedure applies the gate before capturing provenance'
echo "ok - the manifest freezes after the complete gate and before provenance capture or delegation"

## Recoverable run-local state, and where it is not
has "$GATE" 'git-common-dir' \
  'the manifest lives in the repository Git common directory'
has "$GATE" 'work-on-manifest' \
  'the manifest has its own run-local location'
has "$GATE" 'every supported continuation or resume' \
  'the manifest survives the run continuation and resume lifetime'
has "$GATE" 'not telemetry, not Workflow provenance, and never a tracked' \
  'the manifest is neither telemetry, provenance, nor a tracked artifact'
lacks "$skill_dir/references/run-telemetry.md" 'validation-surface manifest' \
  'the telemetry sink does not carry the manifest'
lacks "$skill_dir/references/run-registry.md" 'validation-surface manifest' \
  'the run registry does not carry the manifest'
has "$WORKFLOW" 'Read it back from its run-local file at the start of' \
  'the workflow recovers the manifest on continuation or resume'
has "$WORKFLOW" 'readiness, Standards, Spec, and closure contexts' \
  'the workflow supplies the manifest to every review context'
has "$WORKFLOW" 'available for adjudication' \
  'the manifest stays available to the primary for adjudication'
has "$WORKFLOW" '- Validation-surface manifest: <the frozen instances' \
  'the scoped implementation contract carries the manifest'
has "$GATE" 'contract input, not a prior review conclusion' \
  'the manifest never substitutes for independent review judgement'
echo "ok - the manifest is recoverable run-local state supplied to every downstream context"

## Evidence strength is unchanged by finiteness
has "$GATE" 'Finiteness does not weaken evidence' \
  'finiteness does not weaken the required evidence'
has "$CLOSEOUT" 'every instance.*in its frozen Validation surface' \
  'the closure gate requires evidence at every listed member'
has "$WORKFLOW" 'every instance in that' \
  'the checkpoint statuses a criterion only on its whole frozen surface'
echo "ok - every listed member keeps its criterion's direct-evidence strength"

## The manifest bounds evidence, not scope
has "$WORKFLOW" 'bounds evidence, not scope' \
  'the manifest bounds evidence rather than scope'
has "$WORKFLOW" 'may inspect anything their own contracts already permit' \
  'ordinary review scope is unrestricted by the manifest'
has "$WORKFLOW" 'reviewers may report' \
  'defects outside the manifest remain reportable'
has "$WORKFLOW" 'same-mechanism neighborhood brief below stays fully' \
  'same-mechanism investigation remains fully available'
has "$WORKFLOW" 'sibling reproduced outside the manifest does not enlarge it' \
  'a reproduced sibling does not silently enlarge the manifest'
has "$WORKFLOW" 'never limits what the sweep may inspect or report' \
  'the review brief ships the manifest without narrowing the sweep'
has "$GATE" 'never where implementation or review may look' \
  'the gate disclaims the manifest as an inspection whitelist'
echo "ok - the manifest restricts neither implementation, review, nor same-mechanism discovery"

## Before delegation: complete recomputation, never an entry-level patch
has "$GATE" 'Any change to an input the manifest was derived from invalidates it' \
  'any derivation-input change invalidates the manifest'
has "$GATE" 'discard the manifest, rebuild the affected trusted preflight state' \
  'invalidation rebuilds the trusted preflight state'
has "$GATE" 'rerun the complete gate over it' \
  'invalidation reruns the complete gate'
has "$GATE" 'Never patch one entry in place' \
  'an entry-level patch is forbidden'
has "$GATE" 'no valid.*replacement can be established, abort' \
  'an unestablished replacement aborts'
has "$SKILL" 'preflight-aborted' \
  'a failed preflight finalizes as preflight-aborted'
echo "ok - pre-delegation invalidation recomputes completely or ends as preflight-aborted"

## After delegation: immutable, and fail closed on an omitted member
has "$GATE" 'After implementation is delegated the manifest is immutable' \
  'the gate hands post-delegation immutability to the workflow'
has "$WORKFLOW" 'After delegation the manifest is immutable' \
  'the workflow holds the manifest immutable after delegation'
has "$WORKFLOW" '`Closes` is unavailable for this run' \
  'an omitted required member makes Closes unavailable'
has "$WORKFLOW" 'do not append the member, remediate it, and restart review here' \
  'in-run amendment and remediation of the omission are forbidden'
has "$WORKFLOW" 'record the criterion, the omitted instance' \
  'the omission is recorded'
has "$WORKFLOW" 'classify it' \
  'the omission is classified'
has "$WORKFLOW" 'blocking tracker issue for unresolved work that must' \
  'unresolved work survives the run durably'
has "$WORKFLOW" 'hand back as `Progresses`.*' \
  'the hand-back is Progresses or failed'
has "$WORKFLOW" 'and as `failed` when it does not' \
  'a determinate invalidation with no partial candidate is failed'
has "$CLOSEOUT" 'Validation-surface manifest omits' \
  'the closure gate routes an omitted member to the fail-closed hand-back'
echo "ok - a post-delegation omission fails closed instead of growing the manifest"

## A later attempt starts fresh
has "$WORKFLOW" 'fresh trusted snapshot and a fresh manifest' \
  'a later attempt builds a fresh snapshot and manifest'
has "$WORKFLOW" 'never inherits this one' \
  'a later attempt never inherits the invalidated manifest'
echo "ok - a later attempt after invalidation starts from a fresh snapshot and manifest"

if (( failures > 0 )); then
  printf '\n%s manifest-contract assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll Validation-surface manifest contract assertions held.\n'
