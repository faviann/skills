#!/usr/bin/env bash
set -euo pipefail

# Fingerprint the declared instruction files that govern a work-on run: the
# work-on instructions, the selected workflow, and the TDD and review skills.
# `capture` freezes them in the target repository's git-dir ledger; `verify`
# proves they have not changed and prints the frozen canonical value.

script_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
work_on_root="$(cd -P -- "$script_root/.." && pwd -P)"
skills_checkout="$(cd -P -- "$work_on_root/../../.." && pwd -P)"

work_on_inputs=(
  skills/personal/work-on/SKILL.md
  skills/personal/work-on/references/github-closeout.md
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
review_inputs=(skills/engineering/code-review/SKILL.md)

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
# in declaration order. Executable modes and symlink-node identity are not
# part of it; every input must resolve to a readable regular file.
inputs_digest() {
  local root="$1" rel payload=""
  shift
  for rel in "$@"; do
    [[ -f "$root/$rel" && -r "$root/$rel" ]] \
      || fail "declared instruction input is unreadable: $root/$rel"
    payload+="$rel"$'\n'"$(sha256sum <"$root/$rel")"$'\n'
  done
  printf '%s' "$payload" | sha256sum | cut -c1-12
}

normalize_repo_path() {
  local part out=()
  local IFS=/
  for part in $1; do
    case "$part" in
      '' | .) ;;
      ..)
        [[ "${#out[@]}" -gt 0 ]] || return 1
        unset 'out[-1]'
        ;;
      *) out+=("$part") ;;
    esac
  done
  [[ "${#out[@]}" -gt 0 ]] || return 1
  printf '%s' "${out[*]}"
}

# Git stores a symlink's target text as the blob, but the run reads the file the
# link resolves to. Follow symlink entries inside HEAD so a committed,
# unmodified symlink compares equal to the bytes Bash hashed.
head_blob() {
  local root="$1" rel="$2" depth=0 entry mode target dir
  while ((depth++ < 10)); do
    entry="$(git -C "$root" ls-tree HEAD -- "$rel" 2>/dev/null)" || return 1
    [[ -n "$entry" ]] || return 1
    mode="${entry%% *}"
    if [[ "$mode" != 120000 ]]; then
      git -C "$root" rev-parse --quiet --verify "HEAD:$rel" 2>/dev/null
      return
    fi
    target="$(git -C "$root" cat-file blob "HEAD:$rel" 2>/dev/null)" || return 1
    # An absolute or repository-escaping target is outside the identity Git can
    # account for; treat it as unresolvable rather than guessing.
    [[ "$target" != /* ]] || return 1
    dir="${rel%/*}"
    [[ "$dir" != "$rel" ]] || dir=""
    rel="$(normalize_repo_path "${dir:+$dir/}$target")" || return 1
  done
  return 1
}

head_digest() {
  local root="$1" rel payload="" blob
  shift
  for rel in "$@"; do
    blob="$(head_blob "$root" "$rel")" || return 1
    [[ -n "$blob" ]] || return 1
    payload+="$rel"$'\n'"$(git -C "$root" cat-file blob "$blob" | sha256sum)"$'\n'
  done
  printf '%s' "$payload" | sha256sum | cut -c1-12
}

origin_slug() {
  local origin slug
  origin="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  origin="${origin%.git}"
  case "$origin" in
    *github.com:*) slug="${origin##*github.com:}" ;;
    *github.com/*) slug="${origin##*github.com/}" ;;
    *) return 1 ;;
  esac
  # Only a real owner/repo identifier is a recognizable pointer. Anything else
  # is `unknown`: the slug is interpolated into the ledger JSON and the pull
  # request row, and characters outside this set would corrupt both.
  [[ "$slug" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$slug"
}

subcommand="${1:-}"
[[ "$subcommand" == capture || "$subcommand" == verify ]] \
  || fail "usage: workflow-provenance.sh (capture|verify)"

command -v git >/dev/null 2>&1 || fail "capture requires git"

# Resolve the ledger before validating anything else, so every later capture
# failure can invalidate a previous run's record.
target_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || fail "capture requires a Git-backed target repository"
ledger="$(git rev-parse --absolute-git-dir)/work-on-provenance.json"
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

work_on_digest="$(inputs_digest "$skills_checkout" "${work_on_inputs[@]}")"
workflow_digest="$(inputs_digest "$workflow_root" "${workflow_inputs[@]}")"
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

# `*` means the component's declared inputs differ from that repository's
# HEAD. It makes no claim about whether the commit is fetchable.
star_for() {
  local root="$1" digest="$2"
  shift 2
  [[ "$(head_digest "$root" "$@" || true)" == "$digest" ]] || printf '*'
}

skills_sha="$(git -C "$skills_checkout" rev-parse --short=12 HEAD)" \
  || fail "capture requires a committed skills checkout"
pointer="$(origin_slug "$skills_checkout" || printf 'unknown')@$skills_sha"

canonical="work-on:$work_on_digest$(star_for "$skills_checkout" \
  "$work_on_digest" "${work_on_inputs[@]}")"
canonical+=" workflow:$workflow_digest$(star_for "$workflow_root" \
  "$workflow_digest" "${workflow_inputs[@]}")"
canonical+=" tdd:$tdd_digest$(star_for "$skills_checkout" \
  "$tdd_digest" "${tdd_inputs[@]}")"
canonical+=" review:$review_digest$(star_for "$skills_checkout" \
  "$review_digest" "${review_inputs[@]}")"
canonical+=" ($pointer)"

staged="$ledger.$$"
printf '{"work-on":"%s","workflow":"%s","tdd":"%s","review":"%s","canonical":"%s"}\n' \
  "$work_on_digest" "$workflow_digest" "$tdd_digest" "$review_digest" \
  "$canonical" >"$staged"
mv -f "$staged" "$ledger"
