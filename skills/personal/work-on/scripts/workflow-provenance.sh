#!/usr/bin/env bash
set -euo pipefail

# Fingerprint the complete work-on, TDD, and review skill directories plus the
# selected workflow file that governed this work-on run. The JSON is suitable
# for the target repository's git-dir ledger; `canonical` is the human-readable
# value rendered into pull-request telemetry.

script_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
work_on_root="$(cd -P -- "$script_root/.." && pwd -P)"
skills_checkout="$(cd -P -- "$work_on_root/../../.." && pwd -P)"

hash_directory() {
  local root="$1"
  (
    cd "$root"
    while IFS= read -r -d '' relative_path; do
      relative_path="${relative_path#./}"
      if [[ -L "$relative_path" ]]; then
        mode=120000
      elif [[ -x "$relative_path" ]]; then
        mode=100755
      else
        mode=100644
      fi
      printf '%s\0%s\0' "$relative_path" "$mode"
      if [[ -L "$relative_path" ]]; then
        readlink -n -- "$relative_path"
      else
        cat "$relative_path"
      fi
      printf '\0'
    done < <(
      LC_ALL=C find . \( -type f -o -type l \) -print0 | LC_ALL=C sort -z
    )
  ) | sha256sum | awk '{ print $1 }'
}

hash_file() {
  sha256sum "$1" | awk '{ print $1 }'
}

hash_head_directory() {
  local repo="$1" root="$2" relative
  relative="${root#"$repo"/}"
  (
    git -C "$repo" ls-tree -r -z HEAD -- "$relative" |
      while IFS= read -r -d '' record; do
        metadata="${record%%$'\t'*}"
        repo_path="${record#*$'\t'}"
        mode="${metadata%% *}"
        [[ "$mode" == 100644 || "$mode" == 100755 \
          || "$mode" == 120000 ]] || continue
        component_path="${repo_path#"$relative"/}"
        printf '%s\0%s\0' "$component_path" "$mode"
        git -C "$repo" cat-file blob "HEAD:$repo_path"
        printf '\0'
      done
  ) | sha256sum | awk '{ print $1 }'
}

path_matches_head() {
  local repo="$1" path="$2" relative current_hash head_hash
  relative="${path#"$repo"/}"
  if [[ -d "$path" ]]; then
    current_hash="$(hash_directory "$path")"
    head_hash="$(hash_head_directory "$repo" "$path")" || return 1
  elif [[ -f "$path" ]]; then
    current_hash="$(hash_file "$path")"
    head_hash="$(git -C "$repo" cat-file blob "HEAD:$relative" \
      | sha256sum | awk '{ print $1 }')" || return 1
  else
    return 1
  fi
  [[ "$current_hash" == "$head_hash" ]]
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
    skills_origin_slug="$(origin_slug "$skills_checkout" || true)"
    if [[ -n "$target_slug" && -n "$skills_origin_slug" \
        && "$target_slug" != "$skills_origin_slug" ]]; then
      workflow_suffix="@$target_slug"
    fi
  fi
fi

work_on_digest="$(hash_directory "$work_on_root")"
work_on_digest="${work_on_digest:0:12}"
workflow_digest="$(hash_file "$workflow_path")"
workflow_digest="${workflow_digest:0:12}"
tdd_digest="$(hash_directory "$skills_checkout/skills/engineering/tdd")"
tdd_digest="${tdd_digest:0:12}"
review_digest="$(hash_directory "$skills_checkout/skills/engineering/code-review")"
review_digest="${review_digest:0:12}"

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
      path_matches_head "$skills_repo" "$work_on_root" && work_on_star=false
      path_matches_head "$skills_repo" "$skills_checkout/skills/engineering/tdd" \
        && tdd_star=false
      path_matches_head "$skills_repo" "$skills_checkout/skills/engineering/code-review" \
        && review_star=false
    fi
  fi

  workflow_git_root="$(repo_root_for "$workflow_repo" || true)"
  workflow_slug="$(origin_slug "$workflow_repo" || true)"
  if [[ -n "$workflow_git_root" && -n "$workflow_slug" ]] \
      && repo_commit_is_fetchable "$workflow_git_root" \
      && path_matches_head "$workflow_git_root" "$workflow_path"; then
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

printf '{"canonical":"%s"}\n' "$canonical"
