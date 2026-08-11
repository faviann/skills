#!/usr/bin/env bash
set -euo pipefail

# Fingerprint the instruction bytes that governed this work-on run. The JSON is
# suitable for the target repository's git-dir ledger; `canonical` is the
# human-readable value rendered into pull-request telemetry.

script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  link_target="$(readlink "$script_path")"
  if [[ "$link_target" == /* ]]; then
    script_path="$link_target"
  else
    script_path="$script_dir/$link_target"
  fi
done
script_root="$(cd "$(dirname "$script_path")" && pwd)"
work_on_root="$(cd "$script_root/.." && pwd)"
skills_checkout="$(cd "$work_on_root/../../.." && pwd)"

digest_directory() {
  local root="$1"
  (
    cd "$root"
    while IFS= read -r -d '' relative_path; do
      relative_path="${relative_path#./}"
      printf '%s\0' "$relative_path"
      cat "$relative_path"
      printf '\0'
    done < <(LC_ALL=C find . -type f -print0 | LC_ALL=C sort -z)
  ) | sha256sum | awk '{ print substr($1, 1, 12) }'
}

digest_file() {
  sha256sum "$1" | awk '{ print substr($1, 1, 12) }'
}

origin_slug() {
  local repo="$1" origin slug
  origin="$(git -C "$repo" remote get-url origin 2>/dev/null)" || return 1
  origin="${origin%.git}"
  case "$origin" in
    *github.com:*) slug="${origin##*github.com:}" ;;
    *github.com/*) slug="${origin##*github.com/}" ;;
    *) return 1 ;;
  esac
  [[ "$slug" =~ ^[^/]+/[^/]+$ ]] || return 1
  printf '%s\n' "$slug"
}

repo_root_for() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

repo_commit_is_fetchable() {
  local repo="$1" head
  head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" || return 1
  git -C "$repo" for-each-ref --format='%(refname)' \
    --contains "$head" refs/remotes/origin 2>/dev/null \
    | grep -Ev '/HEAD$' | grep -q .
}

path_is_dirty() {
  local repo="$1" path="$2" relative
  relative="${path#"$repo"/}"
  [[ -n "$(git -C "$repo" status --porcelain --untracked-files=all -- "$relative" 2>/dev/null)" ]]
}

git_available=false
command -v git >/dev/null 2>&1 && git_available=true

target_root="$PWD"
capture_context_valid=false
if [[ "$git_available" == true ]]; then
  resolved_target_root="$(repo_root_for "$PWD" || true)"
  if [[ -n "$resolved_target_root" ]]; then
    target_root="$resolved_target_root"
    capture_context_valid=true
  fi
fi

workflow_path="$work_on_root/references/default-workflow.md"
workflow_repo="$skills_checkout"
workflow_suffix=""
if [[ -f "$target_root/docs/workflow.md" ]]; then
  workflow_path="$target_root/docs/workflow.md"
  workflow_repo="$target_root"
  if [[ "$git_available" == true ]]; then
    target_slug="$(origin_slug "$target_root" || true)"
    skills_root="$(repo_root_for "$skills_checkout" || true)"
    if [[ -n "$target_slug" && "$target_root" != "$skills_root" ]]; then
      workflow_suffix="@$target_slug"
    fi
  fi
fi

work_on_digest="$(digest_directory "$work_on_root")"
workflow_digest="$(digest_file "$workflow_path")"
tdd_digest="$(digest_directory "$skills_checkout/skills/engineering/tdd")"
review_digest="$(digest_directory "$skills_checkout/skills/engineering/code-review")"

work_on_star=true
workflow_star=true
tdd_star=true
review_star=true
commit="unknown"

if [[ "$capture_context_valid" == true ]]; then
  skills_repo="$(repo_root_for "$skills_checkout" || true)"
  skills_slug="$(origin_slug "$skills_checkout" || true)"
  if [[ -n "$skills_repo" && -n "$skills_slug" ]]; then
    commit="$skills_slug@$(git -C "$skills_repo" rev-parse --short=12 HEAD)"
    if repo_commit_is_fetchable "$skills_repo"; then
      path_is_dirty "$skills_repo" "$work_on_root" || work_on_star=false
      path_is_dirty "$skills_repo" "$skills_checkout/skills/engineering/tdd" \
        || tdd_star=false
      path_is_dirty "$skills_repo" "$skills_checkout/skills/engineering/code-review" \
        || review_star=false
    fi
  fi

  workflow_git_root="$(repo_root_for "$workflow_repo" || true)"
  workflow_slug="$(origin_slug "$workflow_repo" || true)"
  if [[ -n "$workflow_git_root" && -n "$workflow_slug" ]] \
      && repo_commit_is_fetchable "$workflow_git_root" \
      && ! path_is_dirty "$workflow_git_root" "$workflow_path"; then
    workflow_star=false
  fi
fi

star_suffix() {
  [[ "$1" == true ]] && printf '*' || true
}

work_on_value="$work_on_digest$(star_suffix "$work_on_star")"
workflow_value="$workflow_digest$(star_suffix "$workflow_star")$workflow_suffix"
tdd_value="$tdd_digest$(star_suffix "$tdd_star")"
review_value="$review_digest$(star_suffix "$review_star")"
canonical="work-on:$work_on_value workflow:$workflow_value tdd:$tdd_value review:$review_value ($commit)"

printf '{\n'
printf '  "version": 1,\n'
printf '  "canonical": "%s",\n' "$canonical"
printf '  "components": {\n'
printf '    "work-on": {"digest": "%s", "starred": %s},\n' "$work_on_digest" "$work_on_star"
printf '    "workflow": {"digest": "%s", "starred": %s},\n' "$workflow_digest" "$workflow_star"
printf '    "tdd": {"digest": "%s", "starred": %s},\n' "$tdd_digest" "$tdd_star"
printf '    "review": {"digest": "%s", "starred": %s}\n' "$review_digest" "$review_star"
printf '  },\n'
printf '  "commit": "%s"\n' "$commit"
printf '}\n'
