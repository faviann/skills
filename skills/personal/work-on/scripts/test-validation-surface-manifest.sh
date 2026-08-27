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

verify_rejected() {
  local label="$1" expected="$2" description="$3"
  if (
    cd "$identity_repo"
    "$IDENTITY" verify --manifest "$manifest" --snapshot "$snapshot"
  ) >"$flat_dir/$label.out" 2>"$flat_dir/$label.err"; then
    fail "$description"
    return
  fi
  [[ ! -s "$flat_dir/$label.out" ]] \
    || fail "$description (verification wrote successful output)"
  grep -Fqx "$expected" "$flat_dir/$label.err" \
    || fail "$description (unexpected diagnostic)"
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
has "$SKILL" 'On a supported continuation or resume, do not refetch current comments or rebuild the snapshot' \
  'the top-level procedure routes resume away from live-source reconstruction'
has "$SKILL" 'proceed only when it recovers and verifies the exact retained pair without refetching or reconstruction' \
  'every selected workflow must recover the retained contract before resume'
echo "ok - preflight materializes a finite surface from an enumeration or a deterministic rule"

## An authorized-to-be-created member needs a contract-determinable identity
has "$GATE" 'artifact this issue authorizes creating' \
  'the gate admits an artifact the issue authorizes creating'
has "$GATE" 'identity, location, and criterion role are already determinable' \
  'such a member needs a contract-determinable identity, location, and role'
has "$GATE" 'merely turns out to touch never' \
  'implementation-only artifacts never join a surface'
echo "ok - an authorized-to-be-created member is admitted only when the contract determines it"

## A recorded command is the vehicle for the surface's owed observations
has "$GATE" 'command.*records as the discharging action.*surface.*required observations' \
  'a recorded discharging command owes the surface observations'
has "$GATE" 'default vehicle.*carries the obligation.s owning phase' \
  'the recorded vehicle carries the obligation owning phase'
has "$GATE" 'Re-executing that exact command is not itself the discharge condition' \
  'the recorded command is not itself the discharge condition'
has "$GATE" 'discharged when every owed member.*qualifying evidence.*owning phase' \
  'every owed surface member needs qualifying evidence at the owning phase'
echo "ok - a recorded command carries phase as the default vehicle, not the discharge condition"

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
has "$GATE" 'capture in `SKILL.md` step 7 compares the current selected workflow with that retained identity' \
  'post-freeze provenance capture must match the workflow used for derivation'
lacks "$GATE" 'scripts/workflow-provenance.sh capture' \
  'the gate hands back after freeze instead of performing provenance capture'
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
has "$GATE" 'not telemetry, not Workflow provenance, not Run registry state, and never tracked' \
  'the frozen files are neither telemetry, provenance, registry state, nor tracked artifacts'
has "$GATE" 'for their owner only — `0700` and `0600`' \
  'the manifest directory and file are owner-only'
has_fixed "$GATE" 'run_id="${RUN_HANDLE%%@*}"' \
  'the frozen files resolve the bare run id from the bound run handle'
has_fixed "$GATE" 'trusted_snapshot_file="$manifest_dir/$run_id.trusted-snapshot.json"' \
  'the retained snapshot has a run-owned sibling path'
has_fixed "$GATE" 'manifest_file="$manifest_dir/$run_id.md"' \
  'the manifest has a run-owned sibling path'
has_fixed "$GATE" '[[ -e "$trusted_snapshot_file" ]] || (umask 077 && : >"$trusted_snapshot_file")' \
  'creating the snapshot is guarded so a resume cannot truncate it'
has_fixed "$GATE" '[[ -e "$manifest_file" ]] || (umask 077 && : >"$manifest_file")' \
  'creating the manifest file is guarded so a re-run cannot truncate it'
has_fixed "$GATE" '[[ -d "$manifest_dir" ]] || (umask 077 && mkdir -p "$manifest_dir")' \
  'creating the manifest directory is guarded the same way'
has_fixed "$GATE" 'chmod 700 "$manifest_dir"' \
  'the manifest directory is tightened with an explicit operand'
has_fixed "$GATE" 'chmod 600 "$manifest_file"' \
  'the manifest file is tightened with an explicit operand'
has_fixed "$GATE" 'chmod 600 "$trusted_snapshot_file"' \
  'the snapshot file is tightened with an explicit operand'
has "$GATE" 'manifest-identity.sh freeze' \
  'the frozen manifest is bound to its snapshot and base identities'
has "$GATE" 'umask closes the creation-to-chmod window only for shell-created files' \
  'the umask is scoped to shell-created files, not tool-written ones'
has "$GATE" 'Write the exact source-labelled snapshot before applying the gate' \
  'the retained snapshot is established before Closability'
has "$GATE" 'atomically replaces the manifest at `0600`' \
  'the identity writer replaces and re-tightens the manifest'
lacks "$skill_dir/references/run-telemetry.md" 'validation-surface manifest' \
  'the telemetry sink does not carry the manifest'
lacks "$skill_dir/references/run-registry.md" 'validation-surface manifest' \
  'the run registry does not carry the manifest'
has "$WORKFLOW" 'At the start of every continuation or resume' \
  'the workflow recovers the manifest on continuation or resume'
has "$WORKFLOW" 'recover the retained trusted-snapshot and manifest files for this run' \
  'resume recovers both frozen run-local objects'
has "$WORKFLOW" 'Do not refetch current trusted GitHub comments or recreate either file from conversational memory' \
  'resume does not reconstruct the snapshot from live sources or memory'
has "$WORKFLOW" 'newly arrived trusted comment does not join this frozen snapshot or invalidate it merely by existing' \
  'a new non-amending trusted comment leaves the frozen run contract unchanged'
has "$WORKFLOW" 'Only an explicit trusted-maintainer contract change takes the invalidation path' \
  'requirements change only through the established explicit maintainer path'
has "$WORKFLOW" 'manifest-identity.sh verify' \
  'resume verifies the manifest identity before reuse'
has "$WORKFLOW" 'workflow-provenance.sh verify' \
  'resume verifies the selected workflow before manifest reuse'
has "$WORKFLOW" 'before any manifest reuse, whether before or after delegation' \
  'provenance verification governs both sides of the delegation boundary'
has "$WORKFLOW" 'provenance was not captured after this manifest froze' \
  'an interruption before provenance capture invalidates the old manifest'
has "$WORKFLOW" 'Before delegation, a missing or failing Workflow provenance ledger or a missing, malformed, corrupt, replaced, or mismatched frozen snapshot or manifest' \
  'either pre-delegation verification failure takes complete recomputation'
has "$WORKFLOW" 'After delegation, either Workflow provenance or frozen-state verification failure takes the fail-closed hand-back' \
  'either post-delegation verification failure takes fail-closed hand-back'
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
has "$GATE" 'a rebuild before delegation still overwrites both paths. contents' \
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
has "$WORKFLOW" 'never inherits these objects' \
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

manifest_dir="$identity_repo/.git/work-on-manifest"
manifest="$manifest_dir/test-run.md"
snapshot="$manifest_dir/test-run.trusted-snapshot.json"
current_sources="$flat_dir/current-trusted-sources.json"
(umask 077 && mkdir -p "$manifest_dir")
printf '%s\n' \
  '[{"body":"trusted contract","source":"issue:example/repo#103:body"},' \
  ' {"source":"comment:2","body":"line one\nline two"}]' >"$snapshot"
printf '%s\n' \
  '[{"body":"trusted contract","source":"issue:example/repo#103:body"},' \
  ' {"source":"comment:2","body":"line one\nline two"},' \
  ' {"source":"comment:99","body":"trusted observation, not a contract amendment"}]' \
  >"$current_sources"
printf '%s\n' '- criterion 1: cmd/build' >"$manifest"
chmod 600 "$snapshot" "$manifest"

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
# The implementation delegate has launched. Provenance drift on this resume is
# now immutable-run failure, not permission to rebuild the manifest.
delegation_crossed=true
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
[[ "$delegation_crossed" == true ]]
git -C "$identity_repo" restore docs/workflow.md
echo "ok - post-delegation selected-workflow drift cannot reuse the frozen manifest"

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
echo "ok - an unchanged resume verifies and reuses the retained frozen state"

# A fresh context recovers only the run-owned paths. It neither reconstructs
# source locators nor consults the current trusted-source population, which now
# contains a later trusted observation that is not a contract amendment.
fresh_run_id=test-run
fresh_manifest="$identity_repo/.git/work-on-manifest/$fresh_run_id.md"
fresh_snapshot="$identity_repo/.git/work-on-manifest/$fresh_run_id.trusted-snapshot.json"
grep -Fq 'comment:99' "$current_sources"
if grep -Fq 'comment:99' "$fresh_snapshot"; then
  fail 'a later trusted comment silently joined the frozen snapshot'
fi
fresh_base="$(
  cd "$identity_repo"
  "$IDENTITY" verify --manifest "$fresh_manifest" --snapshot "$fresh_snapshot"
)"
[[ "$fresh_base" == "$base_sha" ]]
echo "ok - fresh continuation reuses the retained snapshot despite a later trusted comment"

snapshot_backup="$flat_dir/frozen-snapshot.backup"
manifest_backup="$flat_dir/frozen-manifest.backup"
cp -p -- "$snapshot" "$snapshot_backup"
cp -p -- "$manifest" "$manifest_backup"

mv -- "$snapshot" "$snapshot.missing"
verify_rejected missing-snapshot \
  'manifest identity: trusted snapshot is missing or unsafe' \
  'identity verification silently accepted a missing frozen snapshot'
mv -- "$snapshot.missing" "$snapshot"

printf '%s\n' 'truncated frozen snapshot' >>"$snapshot"
verify_rejected corrupt-snapshot \
  'manifest identity: trusted snapshot does not match frozen manifest' \
  'identity verification silently accepted a corrupt frozen snapshot'
cp -p -- "$snapshot_backup" "$snapshot"

printf '%s\n' \
  '[{"source":"comment:replacement","body":"different frozen contract"}]' \
  >"$snapshot"
chmod 600 "$snapshot"
verify_rejected replaced-snapshot \
  'manifest identity: trusted snapshot does not match frozen manifest' \
  'identity verification silently accepted a replaced frozen snapshot'
cp -p -- "$snapshot_backup" "$snapshot"

chmod 644 "$snapshot"
verify_rejected unsafe-mode \
  'manifest identity: frozen state is not owner-only' \
  'identity verification silently accepted non-owner-only frozen state'
chmod 600 "$snapshot"

printf '%s\n' '- corrupt manifest body' >>"$manifest"
verify_rejected corrupt-manifest \
  'manifest identity: frozen manifest is corrupt' \
  'identity verification silently accepted a corrupt frozen manifest'
cp -p -- "$manifest_backup" "$manifest"

other_base="$(git -C "$identity_repo" rev-parse HEAD^)"
sed -i "2cpre-implementation-base $other_base" "$manifest"
chmod 600 "$manifest"
verify_rejected base-mismatch \
  'manifest identity: frozen manifest is corrupt' \
  'identity verification silently accepted a replaced pre-implementation base'
cp -p -- "$manifest_backup" "$manifest"
echo "ok - missing, replaced, or corrupt frozen state fails closed"

printf '%s\n' \
  '{"source":"issue:example/repo#103:body","body":"changed contract"}' \
  >"$snapshot"
verify_rejected mismatch \
  'manifest identity: trusted snapshot does not match frozen manifest' \
  'identity verification silently reused a mismatched trusted snapshot'
cp -p -- "$snapshot_backup" "$snapshot"
echo "ok - manifest, retained snapshot, and base binding mismatches are not silently reused"

if (( failures > 0 )); then
  printf '\n%s manifest-contract assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll Validation-surface manifest contract assertions held.\n'
