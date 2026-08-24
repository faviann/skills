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
IDENTITY="$skill_dir/scripts/manifest-identity.sh"
PROVENANCE="$skill_dir/scripts/workflow-provenance.sh"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

# These documents wrap at 80 columns, so a rule routinely straddles a newline.
# Content assertions run against a copy flattened one paragraph per line: that
# rejoins a wrapped rule while still keeping every match inside the block that
# states it, so no pattern can be satisfied by fragments of two unrelated
# paragraphs. Ordering assertions run against the original, which still has
# line numbers.
flat_dir="$(mktemp -d)"
trap 'rm -rf "$flat_dir"' EXIT

flatten() {
  local flat="$flat_dir/$(printf '%s' "${1#"$skill_dir/"}" | tr '/' '_')"
  [[ -f "$flat" ]] || awk '
    /^[[:space:]]*$/ { print buf; buf = ""; next }
    { buf = (buf == "" ? $0 : buf " " $0) }
    END { print buf }
  ' "$1" | tr -s ' ' > "$flat"
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

has_fixed() {
  # has_fixed <file> <literal string> <description> — for shell idioms whose
  # brackets, pipes, and dollars would otherwise need escaping into noise.
  if grep -Fq -- "$2" "$(flatten "$1")"; then
    return 0
  fi
  fail "$3 (missing in ${1#"$skill_dir/"}: $2)"
}

last_line_of() {
  grep -Eni -- "$2" "$1" | tail -n1 | cut -d: -f1
}

first_line_of() {
  grep -Eni -m1 -- "$2" "$1" | cut -d: -f1
}

precedes() {
  # precedes <file> <earlier regex> <later regex> <description>
  # The earlier anchor takes its last match and the later anchor its first, so
  # a repeated anchor narrows the window rather than widening it.
  local first second
  first="$(last_line_of "$1" "$2" || true)"
  second="$(first_line_of "$1" "$3" || true)"
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
has "$GATE" 'the one list any later execution against that same snapshot would also produce' \
  'a rule must be reproducible, not merely terminating'
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
has "$GATE" 'Identify it with the trusted snapshot and the pre-implementation base' \
  'the manifest is identified with the snapshot and base'
lacks "$GATE" 'Identify it with the trusted snapshot, the selected workflow' \
  'selected-workflow identity is not duplicated in the manifest'
has "$GATE" 'selected workflow remains an invalidation input' \
  'workflow identity stays in provenance while workflow changes still invalidate'
has "$GATE" 'workflow-provenance.sh identify-workflow' \
  'the selected workflow is fingerprinted before manifest derivation'
has "$GATE" 'capture compares the current selected workflow with that retained identity' \
  'post-freeze provenance capture must match the workflow used for derivation'
precedes "$SKILL" "apply this skill's .references/closability-gate\.md" \
  '`scripts/workflow-provenance\.sh capture`' \
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
has "$GATE" 'for their owner only — `0700` and `0600`' \
  'the manifest directory and file are owner-only'
has_fixed "$GATE" 'manifest_file="$manifest_dir/${RUN_HANDLE%%@*}.md"' \
  'the manifest file resolves the bare run id from the bound run handle'
has_fixed "$GATE" '[[ -e "$manifest_file" ]] || (umask 077 && : >"$manifest_file")' \
  'creating the manifest file is guarded so a re-run cannot truncate it'
has_fixed "$GATE" '[[ -d "$manifest_dir" ]] || (umask 077 && mkdir -p "$manifest_dir")' \
  'creating the manifest directory is guarded the same way'
has_fixed "$GATE" 'chmod 700 "$manifest_dir"' \
  'the manifest directory is tightened with an explicit operand'
has_fixed "$GATE" 'chmod 600 "$manifest_file"' \
  'the manifest file is tightened with an explicit operand'
has "$GATE" 'manifest-identity.sh freeze' \
  'the frozen manifest is bound to its snapshot and base identities'
has "$GATE" 'only closes the creation-to-chmod window for a file the shell itself creates' \
  'the umask is scoped to shell-created files, not tool-written ones'
has "$GATE" 'before writing the materialized surfaces into it' \
  'a tool-written manifest is created in the shell first'
has "$GATE" 'atomically replaces the file at `0600`' \
  'the identity writer replaces and re-tightens the manifest'
lacks "$skill_dir/references/run-telemetry.md" 'validation-surface manifest' \
  'the telemetry sink does not carry the manifest'
lacks "$skill_dir/references/run-registry.md" 'validation-surface manifest' \
  'the run registry does not carry the manifest'
has "$WORKFLOW" 'At the start of every continuation or resume' \
  'the workflow recovers the manifest on continuation or resume'
has "$WORKFLOW" 'manifest-identity.sh verify' \
  'resume verifies the manifest identity before reuse'
has "$WORKFLOW" 'workflow-provenance.sh verify' \
  'pre-delegation resume verifies the selected workflow before manifest reuse'
has "$WORKFLOW" 'provenance was not captured after this manifest froze' \
  'an interruption before provenance capture invalidates the old manifest'
has "$WORKFLOW" 'Before delegation, a missing, malformed, corrupt, or mismatched manifest' \
  'a pre-delegation mismatch takes complete recomputation'
has "$WORKFLOW" 'After delegation, the frozen manifest is immutable' \
  'a post-delegation mismatch takes fail-closed hand-back'
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
has "$CLOSEOUT" 'every instance in its frozen Validation surface' \
  'the closure gate requires evidence at every listed member'
has "$WORKFLOW" 'every instance in that' \
  'the checkpoint statuses a criterion only on its whole frozen surface'
echo "ok - every listed member keeps its criterion's direct-evidence strength"

## The manifest bounds evidence, not scope
has "$WORKFLOW" 'bounds evidence, not scope' \
  'the manifest bounds evidence rather than scope'
has "$WORKFLOW" 'may inspect anything their own contracts already permit' \
  'ordinary review scope is unrestricted by the manifest'
has "$WORKFLOW" 'reviewers may report defects outside it' \
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
has "$GATE" 'not a second gate: the run passes one complete gate' \
  'a rerun after invalidation is still the run.s one gate'
has "$GATE" 'Never patch one entry in place' \
  'an entry-level patch is forbidden'
has "$GATE" 're-materialize every criterion.s surface, including those whose own inputs did not move' \
  'recomputation re-materializes unmoved criteria too'
has "$GATE" 'a rebuild before delegation still overwrites this same path.s contents' \
  'the anti-truncation guard does not block a rebuild'
has "$GATE" 'no valid replacement can be established, abort' \
  'an unestablished replacement aborts'
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
has "$WORKFLOW" 'classify it — the trusted contract already clearly required the instance' \
  'the omission is classified as a preflight defect or a contract question'
has "$WORKFLOW" 'blocking tracker issue for unresolved work that must' \
  'unresolved work survives the run durably'
has "$WORKFLOW" 'hand back as `Progresses` when ordinary closeout permits a safe, independently useful partial candidate' \
  'a safe partial candidate hands back as Progresses'
has "$WORKFLOW" 'and as `failed` when it does not' \
  'a determinate invalidation with no partial candidate is failed'
has "$CLOSEOUT" 'Validation-surface manifest omits' \
  'the closure gate routes an omitted member to the fail-closed hand-back'
has "$CLOSEOUT" 'an omitted member is not a row a human can confirm' \
  'human confirmation cannot restore Closes for an omitted member'
echo "ok - a post-delegation omission fails closed instead of growing the manifest"

## A later attempt starts fresh
has "$WORKFLOW" 'fresh trusted snapshot and a fresh manifest' \
  'a later attempt builds a fresh snapshot and manifest'
has "$WORKFLOW" 'never inherits this one' \
  'a later attempt never inherits the invalidated manifest'
echo "ok - a later attempt after invalidation starts from a fresh snapshot and manifest"

## Runtime identity — the file carries and verifies snapshot + base
identity_repo="$flat_dir/identity-repo"
git init -q -b main "$identity_repo"
git -C "$identity_repo" config user.name 'Manifest Identity Test'
git -C "$identity_repo" config user.email manifest@example.invalid
printf 'base\n' >"$identity_repo/base.txt"
git -C "$identity_repo" add base.txt
git -C "$identity_repo" commit -qm 'base'

sources_a="$flat_dir/trusted-sources-a.json"
sources_b="$flat_dir/trusted-sources-b.json"
sources_changed="$flat_dir/trusted-sources-changed.json"
snapshot="$flat_dir/trusted-snapshot.jsonl"
snapshot_rebuilt="$flat_dir/trusted-snapshot-rebuilt.jsonl"
snapshot_changed="$flat_dir/trusted-snapshot-changed.jsonl"
manifest_dir="$identity_repo/.git/work-on-manifest"
manifest="$manifest_dir/test-run.md"
mkdir -p "$manifest_dir"
printf '%s\n' \
  '[{"body":"trusted contract","source":"issue:example/repo#103:body"},' \
  ' {"source":"comment:2","body":"line one\nline two"}]' >"$sources_a"
printf '%s\n' \
  '[ { "body" : "line one\u000aline two", "source" : "comment:2" },' \
  ' { "source" : "issue:example/repo#103:body", "body" : "trusted contract" } ]' \
  >"$sources_b"
printf '%s\n' \
  '[{"source":"issue:example/repo#103:body","body":"changed contract"},' \
  ' {"source":"comment:2","body":"line one\nline two"}]' \
  >"$sources_changed"

"$IDENTITY" snapshot --input "$sources_a" --output "$snapshot"
"$IDENTITY" snapshot --input "$sources_b" --output "$snapshot_rebuilt"
"$IDENTITY" snapshot --input "$sources_changed" --output "$snapshot_changed"
cmp -s "$snapshot" "$snapshot_rebuilt"
[[ "$(sha256sum <"$snapshot" | cut -d' ' -f1)" == \
  "$(sha256sum <"$snapshot_rebuilt" | cut -d' ' -f1)" ]]
if cmp -s "$snapshot" "$snapshot_changed"; then
  fail 'canonical snapshot identity ignored an actual trusted-source change'
fi
[[ "$(stat -c '%a' "$snapshot")" == 600 ]]
echo "ok - equivalent trusted sources reconstruct one canonical snapshot identity"

printf '%s\n' '- criterion 1: cmd/build' >"$manifest"

# A newly frozen manifest cannot inherit a provenance ledger from an older
# freeze. Until capture succeeds after this freeze, continuation must recompute.
mkdir -p "$identity_repo/docs"
printf '# Selected workflow\n' >"$identity_repo/docs/workflow.md"
git -C "$identity_repo" add docs/workflow.md
git -C "$identity_repo" commit -qm 'selected workflow'
selected_workflow_identity="$(
  cd "$identity_repo"
  "$PROVENANCE" identify-workflow
)"
(umask 077 && printf '%s\n' "$selected_workflow_identity" \
  >"$identity_repo/.git/work-on-provenance.workflow-sha256")
(
  cd "$identity_repo"
  "$PROVENANCE" capture --expected-workflow "$selected_workflow_identity"
)
[[ -f "$identity_repo/.git/work-on-provenance.json" ]]

selected_workflow_identity="$(
  cd "$identity_repo"
  "$PROVENANCE" identify-workflow
)"

(
  cd "$identity_repo"
  "$IDENTITY" freeze --manifest "$manifest" --snapshot "$snapshot" --base HEAD \
    --workflow-identity "$selected_workflow_identity"
)
[[ "$(stat -c '%a' "$identity_repo/.git/work-on-provenance.workflow-sha256")" == 600 ]]
grep -Fqx "$selected_workflow_identity" \
  "$identity_repo/.git/work-on-provenance.workflow-sha256"

[[ ! -e "$identity_repo/.git/work-on-provenance.json" ]]
(
  cd "$identity_repo"
  "$IDENTITY" verify --manifest "$manifest" --snapshot "$snapshot" >/dev/null
)
if (
  cd "$identity_repo"
  "$PROVENANCE" verify
) >"$flat_dir/pre-capture.out" 2>"$flat_dir/pre-capture.err"; then
  fail 'continuation accepted a manifest frozen before provenance capture'
fi
[[ ! -s "$flat_dir/pre-capture.out" ]]
grep -Fq 'run ledger is missing' "$flat_dir/pre-capture.err"
echo "ok - interruption before provenance capture cannot reuse the frozen manifest"

printf '\nworkflow changed before capture\n' >>"$identity_repo/docs/workflow.md"
if (
  cd "$identity_repo"
  "$PROVENANCE" capture --expected-workflow "$selected_workflow_identity"
) >"$flat_dir/pre-capture-drift.out" 2>"$flat_dir/pre-capture-drift.err"; then
  fail 'a later provenance capture authorized a manifest derived under another workflow'
fi
[[ ! -s "$flat_dir/pre-capture-drift.out" ]]
[[ ! -e "$identity_repo/.git/work-on-provenance.json" ]]
grep -Fqx \
  'workflow provenance: workflow instructions changed since manifest derivation' \
  "$flat_dir/pre-capture-drift.err"

changed_workflow_identity="$(
  cd "$identity_repo"
  "$PROVENANCE" identify-workflow
)"
if (
  cd "$identity_repo"
  "$PROVENANCE" capture --expected-workflow "$changed_workflow_identity"
) >"$flat_dir/reidentified-workflow.out" 2>"$flat_dir/reidentified-workflow.err"; then
  fail 'a newly identified workflow authorized a manifest derived under the old workflow'
fi
[[ ! -s "$flat_dir/reidentified-workflow.out" ]]
[[ ! -e "$identity_repo/.git/work-on-provenance.json" ]]
grep -Fqx \
  'workflow provenance: expected workflow identity does not belong to frozen manifest' \
  "$flat_dir/reidentified-workflow.err"
git -C "$identity_repo" restore docs/workflow.md
echo "ok - capture rejects workflow drift between manifest derivation and capture"

(
  cd "$identity_repo"
  "$PROVENANCE" capture --expected-workflow "$selected_workflow_identity"
  "$PROVENANCE" verify >/dev/null
)
printf '\nworkflow drift\n' >>"$identity_repo/docs/workflow.md"
(
  cd "$identity_repo"
  "$IDENTITY" verify --manifest "$manifest" --snapshot "$snapshot" >/dev/null
)
if (
  cd "$identity_repo"
  "$PROVENANCE" verify
) >"$flat_dir/workflow-drift.out" 2>"$flat_dir/workflow-drift.err"; then
  fail 'continuation accepted selected-workflow drift'
fi
[[ ! -s "$flat_dir/workflow-drift.out" ]]
grep -Fqx 'workflow provenance: workflow instructions changed since capture' \
  "$flat_dir/workflow-drift.err"
git -C "$identity_repo" restore docs/workflow.md
echo "ok - selected-workflow drift cannot reuse the frozen manifest"

snapshot_digest="$(sha256sum <"$snapshot" | cut -d' ' -f1)"
base_sha="$(git -C "$identity_repo" rev-parse HEAD)"
grep -Fqx "trusted-snapshot-sha256 $snapshot_digest" "$manifest"
grep -Fqx "pre-implementation-base $base_sha" "$manifest"
grep -Eq '^manifest-binding-sha256 [0-9a-f]{64}$' "$manifest"
[[ "$(sed -n '5p' "$manifest")" == '- criterion 1: cmd/build' ]]
[[ "$(stat -c '%a' "$manifest")" == 600 ]]
echo "ok - a frozen manifest carries recoverable trusted-snapshot and base identity"

verified_base="$(
  cd "$identity_repo"
  "$IDENTITY" verify --manifest "$manifest" --snapshot "$snapshot"
)"
[[ "$verified_base" == "$base_sha" ]]
echo "ok - an unchanged resume verifies and reuses the frozen identity"

printf '%s\n' \
  '{"source":"issue:example/repo#103:body","body":"changed contract"}' \
  >"$snapshot"
if (
  cd "$identity_repo"
  "$IDENTITY" verify --manifest "$manifest" --snapshot "$snapshot"
) >"$flat_dir/mismatch.out" 2>"$flat_dir/mismatch.err"; then
  fail 'identity verification silently reused a mismatched trusted snapshot'
fi
[[ ! -s "$flat_dir/mismatch.out" ]]
grep -Fqx 'manifest identity: trusted snapshot does not match frozen manifest' \
  "$flat_dir/mismatch.err"
echo "ok - a mismatched identity is not silently reused"

if (( failures > 0 )); then
  printf '\n%s manifest-contract assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll Validation-surface manifest contract assertions held.\n'
