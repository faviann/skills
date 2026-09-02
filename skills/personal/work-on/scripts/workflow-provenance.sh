#!/usr/bin/env bash
set -euo pipefail

# Own the exact governing-instruction identity and its canonical presentation.
# Contract freeze supplies the capture destination; later readers address the
# captured record by opaque Run identity.

script_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
work_on_root="$(cd -P -- "$script_root/.." && pwd -P)"
skills_checkout="$(cd -P -- "$work_on_root/../../.." && pwd -P)"

work_on_inputs=(skills/personal/work-on/SKILL.md skills/personal/work-on/references/closability-gate.md skills/personal/work-on/references/github-closeout.md skills/personal/work-on/references/normative-remediation.md skills/personal/work-on/references/review-state-machine.md skills/personal/work-on/references/validation-evidence.md skills/personal/work-on/scripts/manifest-identity.sh)
default_workflow_inputs=(skills/personal/work-on/references/default-workflow.md skills/personal/work-on/references/default-workflow/accepted-blocker-correction-self-check.md skills/personal/work-on/references/default-workflow/bounded-re-adjudication.md skills/personal/work-on/references/default-workflow/implementation-mechanism-reset.md)
target_workflow_inputs=(docs/workflow.md)
tdd_inputs=(skills/engineering/tdd/SKILL.md skills/engineering/tdd/mocking.md skills/engineering/tdd/tests.md)
review_inputs=(skills/engineering/code-review/SKILL.md skills/engineering/code-review/WORK-ON-REVIEW.md)

fail() { printf 'workflow provenance: %s\n' "$1" >&2; exit 1; }
usage() { fail 'usage: workflow-provenance.sh identify-workflow | capture --output FILE | read --run ID | verify --run ID'; }

inputs_digest_full() {
  local root="$1" rel payload=""
  shift
  for rel in "$@"; do
    [[ -f "$root/$rel" && ! -L "$root/$rel" && -r "$root/$rel" ]] || fail "declared instruction input is unreadable: $root/$rel"
    payload+="$rel"$'\n'"$(sha256sum <"$root/$rel")"$'\n'
  done
  printf '%s' "$payload" | sha256sum | cut -d' ' -f1
}
inputs_digest() { inputs_digest_full "$@" | cut -c1-12; }
star_for() {
  local root="$1" rel head_hash
  shift
  for rel in "$@"; do
    head_hash="$(git -C "$root" show "HEAD:$rel" 2>/dev/null | sha256sum)" || { printf '*'; return; }
    [[ "$head_hash" == "$(sha256sum <"$root/$rel")" ]] || { printf '*'; return; }
  done
}
origin_slug() {
  local origin slug
  origin="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  origin="${origin%.git}"
  [[ "$origin" =~ ^([A-Za-z][A-Za-z0-9+.-]*://([^/@]+@)?github\.com(:[0-9]+)?/|([^/:@]+@)?github\.com:)(.*)$ ]] || return 1
  slug="${BASH_REMATCH[5]}"
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$slug"
}

subcommand="${1:-}"; shift || true
case "$subcommand" in
  identify-workflow) (( $# == 0 )) || usage ;;
  capture) (( $# == 2 )) && [[ "$1" == --output ]] || usage; output="$2" ;;
  read|verify)
    (( $# == 2 )) && [[ "$1" == --run ]] || usage
    run_identity="$2"
    [[ "$run_identity" =~ ^[A-Za-z0-9._-]{8,64}$ ]] || fail 'Run identity is malformed'
    ;;
  *) usage ;;
esac

command -v git >/dev/null 2>&1 || fail 'capture requires git'
target_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail 'capture requires a Git-backed target repository'
common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || fail 'capture requires a Git-backed target repository'

if [[ "$subcommand" == read || "$subcommand" == verify ]]; then
  record="$common_dir/work-on-manifest/$run_identity.provenance.json"
  "$script_root/manifest-identity.sh" read --run "$run_identity" >/dev/null \
    || fail 'captured provenance does not belong to valid frozen custody'
  canonical="$(jq -er '.canonical | select(type == "string" and length > 0)' "$record" 2>/dev/null)" || fail 'captured provenance is invalid'
  if [[ "$subcommand" == read ]]; then printf '%s\n' "$canonical"; exit 0; fi
fi

[[ "$(git -C "$skills_checkout" rev-parse --show-toplevel 2>/dev/null)" == "$skills_checkout" ]] || fail 'capture requires a Git-backed skills checkout'

workflow_root="$skills_checkout"; workflow_inputs=("${default_workflow_inputs[@]}")
if [[ -e "$target_root/docs/workflow.md" || -L "$target_root/docs/workflow.md" ]]; then
  workflow_root="$target_root"; workflow_inputs=("${target_workflow_inputs[@]}")
fi
workflow_identity="$(inputs_digest_full "$workflow_root" "${workflow_inputs[@]}")"
[[ "$workflow_identity" =~ ^[0-9a-f]{64}$ ]] || fail 'could not identify selected workflow'
if [[ "$subcommand" == identify-workflow ]]; then printf '%s\n' "$workflow_identity"; exit 0; fi

work_on_digest="$(inputs_digest "$skills_checkout" "${work_on_inputs[@]}")"
workflow_digest="${workflow_identity:0:12}"
tdd_digest="$(inputs_digest "$skills_checkout" "${tdd_inputs[@]}")"
review_digest="$(inputs_digest "$skills_checkout" "${review_inputs[@]}")"

if [[ "$subcommand" == verify ]]; then
  recorded_work_on="$(jq -er '.["work-on"] | select(type == "string")' "$record" 2>/dev/null)" || fail 'captured provenance is invalid'
  recorded_workflow="$(jq -er '.workflow | select(type == "string")' "$record" 2>/dev/null)" || fail 'captured provenance is invalid'
  recorded_identity="$(jq -er '.workflow_identity | select(type == "string")' "$record" 2>/dev/null)" || fail 'captured provenance is invalid'
  recorded_tdd="$(jq -er '.tdd | select(type == "string")' "$record" 2>/dev/null)" || fail 'captured provenance is invalid'
  recorded_review="$(jq -er '.review | select(type == "string")' "$record" 2>/dev/null)" || fail 'captured provenance is invalid'
  [[ "$recorded_work_on" == "$work_on_digest" && "$recorded_workflow" == "$workflow_digest" && "$recorded_identity" == "$workflow_identity" && "$recorded_tdd" == "$tdd_digest" && "$recorded_review" == "$review_digest" ]] || fail 'governing instructions changed since contract freeze'
  printf '%s\n' "$canonical"
  exit 0
fi

skills_sha="$(git -C "$skills_checkout" rev-parse --short=12 HEAD)" || fail 'capture requires a committed skills checkout'
pointer="$(origin_slug "$skills_checkout" || printf unknown)@$skills_sha"
current_canonical="work-on:$work_on_digest$(star_for "$skills_checkout" "${work_on_inputs[@]}")"
current_canonical+=" workflow:$workflow_digest$(star_for "$workflow_root" "${workflow_inputs[@]}")"
current_canonical+=" tdd:$tdd_digest$(star_for "$skills_checkout" "${tdd_inputs[@]}")"
current_canonical+=" review:$review_digest$(star_for "$skills_checkout" "${review_inputs[@]}") ($pointer)"

output_dir="$(dirname -- "$output")"
[[ -d "$output_dir" && ! -L "$output_dir" ]] || fail 'capture output directory is missing or unsafe'
staged="$(umask 077 && mktemp "$output_dir/.provenance.XXXXXX")"
trap 'rm -f -- "$staged"' EXIT
jq -cn --arg work_on "$work_on_digest" --arg workflow "$workflow_digest" --arg workflow_identity "$workflow_identity" --arg tdd "$tdd_digest" --arg review "$review_digest" --arg canonical "$current_canonical" '{"work-on":$work_on,workflow:$workflow,workflow_identity:$workflow_identity,tdd:$tdd,review:$review,canonical:$canonical}' >"$staged"
chmod 600 "$staged"
mv -f -- "$staged" "$output"
staged=""
