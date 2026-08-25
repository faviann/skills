#!/usr/bin/env bash
set -euo pipefail

# Fingerprint the declared instruction files that govern a work-on run: the
# work-on instructions, the selected workflow, and the TDD and review skills.
# `identify-workflow` returns the selected workflow's exact digest for the
# preflight context. `capture` compares it before freezing all instructions in
# the target repository's git-dir ledger; `verify` proves they have not changed
# and prints the frozen canonical value.

script_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
work_on_root="$(cd -P -- "$script_root/.." && pwd -P)"
skills_checkout="$(cd -P -- "$work_on_root/../../.." && pwd -P)"

work_on_inputs=(
  skills/personal/work-on/SKILL.md
  skills/personal/work-on/references/closability-gate.md
  skills/personal/work-on/references/convergence-state.md
  skills/personal/work-on/references/github-closeout.md
  skills/personal/work-on/references/review-state-machine.md
  skills/personal/work-on/references/run-telemetry.md
  skills/personal/work-on/references/validation-evidence.md
  skills/personal/work-on/scripts/manifest-identity.sh
  skills/personal/work-on/scripts/convergence-state.sh
)
default_workflow_inputs=(
  skills/personal/work-on/references/default-workflow.md
)
target_workflow_inputs=(docs/workflow.md)
tdd_inputs=(
  skills/engineering/tdd/SKILL.md
  skills/engineering/tdd/mocking.md
  skills/engineering/tdd/tests.md
)
review_inputs=(
  skills/engineering/code-review/SKILL.md
  skills/engineering/code-review/WORK-ON-REVIEW.md
)

# A failed capture must not leave the previous run's ledger behind: a later
# verify would read it as this run's frozen value. Verification failures only
# report, so they never discard the record.
ledger=""
invalidate_ledger_on_fail=false

fail() {
  if [[ "$invalidate_ledger_on_fail" == true && -n "$ledger" ]]; then
    rm -f "$ledger"
  fi
  printf 'workflow provenance: %s\n' "$1" >&2
  exit 1
}

# Identity is the declared relative path plus the exact bytes of each input,
# in declaration order. Executable modes are not part of it; every input must
# itself be a readable regular file.
inputs_digest_full() {
  local root="$1" rel payload=""
  shift
  for rel in "$@"; do
    [[ -f "$root/$rel" && ! -L "$root/$rel" && -r "$root/$rel" ]] \
      || fail "declared instruction input is unreadable: $root/$rel"
    payload+="$rel"$'\n'"$(sha256sum <"$root/$rel")"$'\n'
  done
  printf '%s' "$payload" | sha256sum | cut -d' ' -f1
}

inputs_digest() {
  inputs_digest_full "$@" | cut -c1-12
}

# `*` means a declared input's filename or bytes differ from that repository's
# HEAD. Modes are not identity; compare the declared paths directly without
# walking trees, resolving symlinks, or normalizing paths.
star_for() {
  local root="$1" rel head_hash
  shift
  for rel in "$@"; do
    head_hash="$(git -C "$root" show "HEAD:$rel" 2>/dev/null | sha256sum)" || {
      printf '*'
      return
    }
    [[ "$head_hash" == "$(sha256sum <"$root/$rel")" ]] || {
      printf '*'
      return
    }
  done
}

origin_slug() {
  local origin slug
  origin="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  origin="${origin%.git}"
  [[ "$origin" =~ ^([A-Za-z][A-Za-z0-9+.-]*://([^/@]+@)?github\.com(:[0-9]+)?/|([^/:@]+@)?github\.com:)(.*)$ ]] \
    || return 1
  slug="${BASH_REMATCH[5]}"
  # Only a real owner/repo identifier is a recognizable pointer. Anything else
  # is `unknown`: the slug is interpolated into the ledger JSON and the pull
  # request row, and characters outside this set would corrupt both.
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$slug"
}

subcommand="${1:-}"
shift || true
case "$subcommand" in
  identify-workflow|verify)
    (( $# == 0 )) || fail "usage: workflow-provenance.sh identify-workflow | capture --expected-workflow SHA256 | verify"
    ;;
  capture)
    (( $# == 2 )) && [[ "$1" == --expected-workflow ]] \
      || fail "usage: workflow-provenance.sh identify-workflow | capture --expected-workflow SHA256 | verify"
    expected_workflow="$2"
    ;;
  *) fail "usage: workflow-provenance.sh identify-workflow | capture --expected-workflow SHA256 | verify" ;;
esac

command -v git >/dev/null 2>&1 || fail "capture requires git"

# Resolve the ledger before validating anything else, so every later capture
# failure can invalidate a previous run's record.
target_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || fail "capture requires a Git-backed target repository"
git_dir="$(git rev-parse --absolute-git-dir)"
ledger="$git_dir/work-on-provenance.json"
workflow_boundary="$git_dir/work-on-provenance.workflow-sha256"
if [[ "$subcommand" == capture ]]; then
  invalidate_ledger_on_fail=true
fi

[[ "$(git -C "$skills_checkout" rev-parse --show-toplevel 2>/dev/null)" \
  == "$skills_checkout" ]] \
  || fail "capture requires a Git-backed skills checkout"

# Selection turns on whether the target repository offers a workflow at all, not
# on whether that path happens to be readable. A docs/workflow.md that exists as
# a directory, a broken symlink, or an unreadable file is the selected input and
# must fail as one; falling back to the default would fingerprint instructions
# the run did not read.
workflow_root="$skills_checkout"
workflow_inputs=("${default_workflow_inputs[@]}")
if [[ -e "$target_root/docs/workflow.md" || -L "$target_root/docs/workflow.md" ]]; then
  workflow_root="$target_root"
  workflow_inputs=("${target_workflow_inputs[@]}")
fi

workflow_identity="$(inputs_digest_full "$workflow_root" "${workflow_inputs[@]}")"
[[ "$workflow_identity" =~ ^[0-9a-f]{64}$ ]] \
  || fail "could not identify selected workflow"
if [[ "$subcommand" == identify-workflow ]]; then
  printf '%s\n' "$workflow_identity"
  exit 0
fi

work_on_digest="$(inputs_digest "$skills_checkout" "${work_on_inputs[@]}")"
workflow_digest="${workflow_identity:0:12}"
tdd_digest="$(inputs_digest "$skills_checkout" "${tdd_inputs[@]}")"
review_digest="$(inputs_digest "$skills_checkout" "${review_inputs[@]}")"

if [[ "$subcommand" == verify ]]; then
  [[ -f "$ledger" ]] || fail "run ledger is missing: $ledger"
  for component in work-on workflow tdd review; do
    recorded="$(jq -er --arg component "$component" \
      '.[$component] | select(type == "string" and length == 12)' \
      "$ledger" 2>/dev/null)" || fail "run ledger is invalid: $ledger"
    case "$component" in
      work-on) current="$work_on_digest" ;;
      workflow) current="$workflow_digest" ;;
      tdd) current="$tdd_digest" ;;
      review) current="$review_digest" ;;
    esac
    [[ "$recorded" == "$current" ]] \
      || fail "$component instructions changed since capture"
  done
  jq -er '.canonical | select(type == "string" and length > 0)' \
    "$ledger" 2>/dev/null || fail "run ledger is invalid: $ledger"
  exit 0
fi

[[ "$expected_workflow" =~ ^[0-9a-f]{64}$ ]] \
  || fail "expected workflow identity is malformed"
[[ -f "$workflow_boundary" && ! -L "$workflow_boundary" \
  && -r "$workflow_boundary" ]] \
  || fail "frozen manifest workflow identity is missing or unsafe"
IFS= read -r frozen_workflow <"$workflow_boundary" \
  || fail "frozen manifest workflow identity is malformed"
[[ "$frozen_workflow" =~ ^[0-9a-f]{64}$ ]] \
  || fail "frozen manifest workflow identity is malformed"
[[ "$expected_workflow" == "$frozen_workflow" ]] \
  || fail "expected workflow identity does not belong to frozen manifest"
[[ "$expected_workflow" == "$workflow_identity" ]] \
  || fail "workflow instructions changed since manifest derivation"

skills_sha="$(git -C "$skills_checkout" rev-parse --short=12 HEAD)" \
  || fail "capture requires a committed skills checkout"
pointer="$(origin_slug "$skills_checkout" || printf 'unknown')@$skills_sha"

canonical="work-on:$work_on_digest$(star_for "$skills_checkout" \
  "${work_on_inputs[@]}")"
canonical+=" workflow:$workflow_digest$(star_for "$workflow_root" \
  "${workflow_inputs[@]}")"
canonical+=" tdd:$tdd_digest$(star_for "$skills_checkout" \
  "${tdd_inputs[@]}")"
canonical+=" review:$review_digest$(star_for "$skills_checkout" \
  "${review_inputs[@]}")"
canonical+=" ($pointer)"

staged="$ledger.$$"
printf '{"work-on":"%s","workflow":"%s","tdd":"%s","review":"%s","canonical":"%s"}\n' \
  "$work_on_digest" "$workflow_digest" "$tdd_digest" "$review_digest" \
  "$canonical" >"$staged"
mv -f "$staged" "$ledger"
