#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"
identity="$script_dir/manifest-identity.sh"
provenance="$script_dir/workflow-provenance.sh"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
repo="$fixture/repo"; git init -q -b main "$repo"
git -C "$repo" config user.name Test; git -C "$repo" config user.email test@example.invalid
printf 'base\n' >"$repo/base"; git -C "$repo" add .; git -C "$repo" commit -qm base
printf '%s\n' '- criterion: public seam' >"$fixture/manifest.md"
printf '%s\n' '{"body":"trusted contract"}' >"$fixture/snapshot.json"
workflow_identity="$(cd "$repo" && "$provenance" identify-workflow)"

freeze() {
  (cd "$repo" && "$identity" freeze --manifest "$fixture/manifest.md" --snapshot "$fixture/snapshot.json" --base HEAD --workflow-identity "$workflow_identity")
}
run1="$(freeze)"; run2="$(freeze)"
[[ "$run1" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}$ && "$run2" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}$ && "$run1" != "$run2" ]]
custody="$repo/.git/work-on-manifest"
[[ "$(stat -c %a "$custody")" == 700 ]]
for run in "$run1" "$run2"; do
  for suffix in .md .trusted-snapshot.json .provenance.json; do
    [[ -f "$custody/$run$suffix" && "$(stat -c %a "$custody/$run$suffix")" == 600 ]]
  done
  [[ "$(cd "$repo" && "$identity" verify --run "$run")" == "$(git -C "$repo" rev-parse HEAD)" ]]
done
[[ "$run1" != *@* ]]
[[ ! -e "$repo/.git/work-on-provenance.json" && ! -e "$repo/.git/work-on-provenance.workflow-sha256" ]]

# Complete custody is the acceptance marker; a provenance-only interrupted
# publication is rejected by both custody verification and rendering readers.
partial=opaque-partial
cp "$custody/$run1.provenance.json" "$custody/$partial.provenance.json"
chmod 600 "$custody/$partial.provenance.json"
if (cd "$repo" && "$identity" read --run "$partial") >"$fixture/out" 2>"$fixture/err"; then
  echo 'partial custody was accepted' >&2; exit 1
fi
grep -Fq 'complete custody is missing' "$fixture/err"

cp "$custody/$run1.md" "$fixture/saved-manifest"
printf '\ncorrupt\n' >>"$custody/$run1.md"
if (cd "$repo" && "$identity" read --run "$run1") >/dev/null 2>&1; then
  echo 'corrupt custody was accepted' >&2; exit 1
fi
cp "$fixture/saved-manifest" "$custody/$run1.md"; chmod 600 "$custody/$run1.md"

bad_identity="$(printf '0%.0s' {1..64})"
before="$(find "$custody" -maxdepth 1 -type f | wc -l)"
if (cd "$repo" && "$identity" freeze --manifest "$fixture/manifest.md" --snapshot "$fixture/snapshot.json" --base HEAD --workflow-identity "$bad_identity") >/dev/null 2>&1; then
  echo 'freeze accepted a workflow identity the gate did not read' >&2; exit 1
fi
[[ "$(find "$custody" -maxdepth 1 -type f | wc -l)" == "$before" ]]
if (cd "$repo" && "$identity" verify) >/dev/null 2>&1; then
  echo 'unnamed resume was accepted' >&2; exit 1
fi

flatten() { awk '/^[[:space:]]*$/{print b;b="";next}{b=(b?b" ":"")$0}END{print b}' "$1"; }
for file in "$skill_dir/SKILL.md" "$skill_dir/references/closability-gate.md" "$skill_dir/references/default-workflow.md"; do
  flat="$(flatten "$file")"
  [[ "$flat" != *'run-telemetry.sh start'* && "$flat" != *'run-registry.sh register'* && "$flat" != *'--continues-run'* ]]
done
flat_skill="$(flatten "$skill_dir/SKILL.md")"
[[ "$flat_skill" == *'single authority point that mints the Run identity'* ]]
flat_gate="$(flatten "$skill_dir/references/closability-gate.md")"
[[ "$flat_gate" == *'<run-identity>.provenance.json'* && "$flat_gate" == *'incomplete staging or interrupted publication never verifies or renders'* ]]
[[ "$flat_gate" != *'before workflow-provenance capture'* && "$flat_gate" != *"resolves the run's existing outcome"* ]]
flat_workflow="$(flatten "$skill_dir/references/default-workflow.md")"
[[ "$flat_workflow" == *'positively name the Run identity'* && "$flat_workflow" == *'mismatch refuses continuation outright'* ]]

assert_has() {
  flatten "$1" | grep -Eqi -- "$2" || {
    echo "missing governing rule in ${1#"$skill_dir/"}: $2" >&2
    exit 1
  }
}
gate="$skill_dir/references/closability-gate.md"
workflow_doc="$skill_dir/references/default-workflow.md"
closeout="$skill_dir/references/github-closeout.md"

# Preserve the base suite's governing contract inventory outside the retired
# handle, ledger, telemetry, and registry mechanics.
for rule in \
  'explicit finite enumeration' \
  'deterministic, non-interpretive finite selection rule' \
  'must actually be evaluated during this preflight' \
  'complete concrete list for the trusted snapshot' \
  'whatever implementation touches' \
  'passes only when all six hold' \
  'Validation surface is finite and materialized here' \
  'artifact this issue authorizes creating' \
  'identity, location, and criterion role are already determinable' \
  'default vehicle.*carries the obligation.s owning phase' \
  'Re-executing that exact command is not itself the discharge condition' \
  'discharged when every owed member.*qualifying evidence.*owning phase' \
  'Finiteness does not weaken evidence' \
  'never where implementation or review may look' \
  'Any change to an input the manifest was derived from invalidates it' \
  'rerun the complete gate over it' \
  'Never patch one entry in place' \
  're-materialize every criterion.s surface' \
  'After implementation is delegated the manifest is immutable' \
  'contract input, not a prior review conclusion'; do
  assert_has "$gate" "$rule"
done
for rule in \
  'Do not refetch current trusted GitHub comments' \
  'newly arrived trusted comment does not join this frozen snapshot' \
  'Only an explicit trusted-maintainer contract change' \
  'readiness, Standards, Spec, and closure contexts' \
  'bounds evidence, not scope' \
  'may inspect anything their own contracts already permit' \
  'reviewers may report defects outside it' \
  'sibling reproduced outside the manifest does not enlarge it' \
  'never limits what the sweep may inspect or report' \
  'Closes.*unavailable for this run' \
  'do not append the member, remediate it, and restart review here' \
  'blocking tracker issue for unresolved work' \
  'fresh trusted snapshot and a fresh manifest' \
  'never inherits these objects'; do
  assert_has "$workflow_doc" "$rule"
done
assert_has "$closeout" 'every instance in its frozen Validation surface'
assert_has "$closeout" 'an omitted member is not a row a human can confirm'

# Missing, replaced, corrupt, unsafe, or non-canonical custody remains refused.
backup="$fixture/custody-backup"; mkdir "$backup"
for suffix in .md .trusted-snapshot.json .provenance.json; do
  cp -p "$custody/$run1$suffix" "$backup/run$suffix"
done
reject_read() {
  if (cd "$repo" && "$identity" read --run "$run1") >/dev/null 2>&1; then
    echo "invalid custody was accepted: $1" >&2; exit 1
  fi
}
mv "$custody/$run1.trusted-snapshot.json" "$fixture/missing-snapshot"
reject_read missing-snapshot
mv "$fixture/missing-snapshot" "$custody/$run1.trusted-snapshot.json"
printf 'corrupt\n' >>"$custody/$run1.trusted-snapshot.json"; reject_read corrupt-snapshot
cp -p "$backup/run.trusted-snapshot.json" "$custody/$run1.trusted-snapshot.json"
printf 'corrupt\n' >>"$custody/$run1.provenance.json"; reject_read corrupt-provenance
cp -p "$backup/run.provenance.json" "$custody/$run1.provenance.json"
chmod 644 "$custody/$run1.md"; reject_read unsafe-manifest-mode; chmod 600 "$custody/$run1.md"
for suffix in .trusted-snapshot.json .provenance.json; do
  chmod 644 "$custody/$run1$suffix"; reject_read "unsafe-$suffix-mode"
  chmod 600 "$custody/$run1$suffix"
done
chmod 755 "$custody"; reject_read unsafe-directory-mode; chmod 700 "$custody"
mv "$custody/$run1.trusted-snapshot.json" "$fixture/real-snapshot"
ln -s "$fixture/real-snapshot" "$custody/$run1.trusted-snapshot.json"
reject_read symlink-snapshot
rm "$custody/$run1.trusted-snapshot.json"; mv "$fixture/real-snapshot" "$custody/$run1.trusted-snapshot.json"
mv "$custody" "$fixture/real-custody"
ln -s "$fixture/real-custody" "$custody"
reject_read symlink-custody-directory
rm "$custody"; mv "$fixture/real-custody" "$custody"
sed -i '2cpre-implementation-base 0000000000000000000000000000000000000000' "$custody/$run1.md"
reject_read unavailable-base
cp -p "$backup/run.md" "$custody/$run1.md"
short_base="$(git -C "$repo" rev-parse --short HEAD)"
sed -i "2cpre-implementation-base $short_base" "$custody/$run1.md"
reject_read noncanonical-base
cp -p "$backup/run.md" "$custody/$run1.md"

ln -s "$fixture/manifest.md" "$fixture/symlink-manifest"
if (cd "$repo" && "$identity" freeze --manifest "$fixture/symlink-manifest" \
    --snapshot "$fixture/snapshot.json" --base HEAD \
    --workflow-identity "$workflow_identity") >/dev/null 2>&1; then
  echo 'freeze accepted a symlinked materialized manifest' >&2; exit 1
fi

echo 'Validation-surface manifest contract assertions held'
