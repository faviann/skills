#!/usr/bin/env bash
set -euo pipefail

# Install this fork's skills, except in-progress and deprecated ones, as
# per-skill links, and remove the links this repository no longer owns a skill
# for. Entries that belong to anything else are never rewritten or removed: any
# conflict aborts the entire preflight.

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
git_from_checkout() {
  env -i PATH="${PATH:-/usr/bin:/bin}" git -C "$REPO" "$@"
}

if git_dir="$(git_from_checkout rev-parse --git-dir 2>/dev/null)" &&
  common_dir="$(git_from_checkout rev-parse --git-common-dir 2>/dev/null)"; then
  if [[ "$git_dir" != /* ]]; then
    git_dir="$REPO/$git_dir"
  fi
  if [[ "$common_dir" != /* ]]; then
    common_dir="$REPO/$common_dir"
  fi
  git_dir="$(realpath -m -- "$git_dir")"
  common_dir="$(realpath -m -- "$common_dir")"
  if [ "$git_dir" != "$common_dir" ]; then
    primary_checkout="$(dirname "$common_dir")"
    echo "error: skill links always belong to the primary checkout at $primary_checkout; re-run scripts/reconcile-skills.sh from there." >&2
    exit 1
  fi
fi
if [ -z "${HOME:-}" ]; then
  echo "error: HOME must be set" >&2
  exit 2
fi
if [ ! -d "$REPO/skills" ]; then
  echo "error: skills directory not found: $REPO/skills" >&2
  exit 1
fi

check=false
if [ "${1:-}" = "--check" ]; then
  check=true
  shift
fi
if [ "$#" -ne 0 ]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

DESTS=("$HOME/.agents/skills" "$HOME/.claude/skills")
HARNESS_DIRS=("$HOME/.agents" "$HOME/.claude")
EXCLUDES_FILE="$REPO/.agents/skill-link-excludes"
names=()
sources=()
declare -A source_by_name=()
declare -A excluded_name=()
declare -A excluded_source_by_name=()
if [ -f "$EXCLUDES_FILE" ]; then
  while IFS= read -r name || [ -n "$name" ]; do
    case "$name" in
      ""|\#*) continue ;;
    esac
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      echo "error: invalid skill name in $EXCLUDES_FILE: $name" >&2
      exit 1
    fi
    excluded_name["$name"]=true
  done <"$EXCLUDES_FILE"
fi
while IFS= read -r -d '' skill_md; do
  source_dir="$(dirname "$skill_md")"
  name="$(basename "$source_dir")"
  if [ -n "${source_by_name[$name]+present}" ]; then
    echo "error: duplicate skill name: $name" >&2
    echo "  ${source_by_name[$name]}" >&2
    echo "  $source_dir" >&2
    echo "No changes were made." >&2
    exit 1
  fi
  source_by_name["$name"]="$source_dir"
  if [ -n "${excluded_name[$name]+present}" ]; then
    excluded_source_by_name["$name"]="$source_dir"
    continue
  fi
  names+=("$name")
  sources+=("$source_dir")
done < <(
  find "$REPO/skills" \
    -type f \
    -name SKILL.md \
    -not -path '*/node_modules/*' \
    -not -path '*/in-progress/*' \
    -not -path '*/deprecated/*' \
    -print0
)

missing_sources=()
missing_targets=()
excluded_targets=()
stale_targets=()
conflicts=()

for harness_dir in "${HARNESS_DIRS[@]}"; do
  if [ -L "$harness_dir" ]; then
    conflicts+=(
      "harness directory is a symlink: $harness_dir -> $(readlink "$harness_dir")"
    )
  elif [ -e "$harness_dir" ] && [ ! -d "$harness_dir" ]; then
    conflicts+=("harness directory is not a directory: $harness_dir")
  fi
done

for destination in "${DESTS[@]}"; do
  harness_dir="$(dirname "$destination")"
  if [ -L "$harness_dir" ] ||
    { [ -e "$harness_dir" ] && [ ! -d "$harness_dir" ]; }; then
    continue
  fi

  if [ -L "$destination" ]; then
    conflicts+=("destination is a symlink: $destination -> $(readlink "$destination")")
    continue
  fi
  if [ -e "$destination" ] && [ ! -d "$destination" ]; then
    conflicts+=("destination is not a directory: $destination")
    continue
  fi

  for i in "${!names[@]}"; do
    target="$destination/${names[$i]}"
    if [ -L "$target" ] &&
      [ "$(readlink -f "$target")" = "$(readlink -f "${sources[$i]}")" ]; then
      continue
    fi
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      missing_sources+=("${sources[$i]}")
      missing_targets+=("$target")
    elif [ -L "$target" ]; then
      conflicts+=(
        "wrong symlink: $target -> $(readlink "$target") (expected ${sources[$i]})"
      )
    else
      conflicts+=("real entry collision: $target")
    fi
  done

  if [ -d "$destination" ] && [ ! -L "$destination" ]; then
    while IFS= read -r -d '' installed_link; do
      installed_name="$(basename "$installed_link")"
      if [ -n "${source_by_name[$installed_name]+present}" ]; then
        if [ -z "${excluded_source_by_name[$installed_name]+present}" ]; then
          continue
        fi
      fi

      raw_target="$(readlink "$installed_link")"
      if [[ "$raw_target" = /* ]]; then
        resolved_target="$(realpath -m -- "$raw_target")"
      else
        resolved_target="$(realpath -m -- "$(dirname "$installed_link")/$raw_target")"
      fi
      if [ -n "${excluded_source_by_name[$installed_name]+present}" ] &&
        [ "$resolved_target" = "$(realpath -m -- "${excluded_source_by_name[$installed_name]}")" ]; then
        excluded_targets+=("$installed_link")
        continue
      fi
      case "$resolved_target" in
        "$REPO"|"$REPO"/*)
          stale_targets+=("$installed_link")
          ;;
      esac
    done < <(find "$destination" -mindepth 1 -maxdepth 1 -type l -print0)
  fi
done

if [ "${#conflicts[@]}" -ne 0 ]; then
  for conflict in "${conflicts[@]}"; do
    echo "error: $conflict" >&2
  done
  echo "No changes were made." >&2
  exit 1
fi

if "$check"; then
  if [ "${#missing_targets[@]}" -eq 0 ] &&
    [ "${#excluded_targets[@]}" -eq 0 ] &&
    [ "${#stale_targets[@]}" -eq 0 ]; then
    echo "skills are reconciled"
    exit 0
  fi
  for target in "${missing_targets[@]}"; do
    echo "missing: $target" >&2
  done
  for target in "${excluded_targets[@]}"; do
    echo "excluded skill is still linked: $target" >&2
  done
  for target in "${stale_targets[@]}"; do
    echo "stale repository link is still linked: $target" >&2
  done
  exit 1
fi

for target in "${excluded_targets[@]}" "${stale_targets[@]}"; do
  rm -- "$target"
done

for i in "${!missing_targets[@]}"; do
  mkdir -p "$(dirname "${missing_targets[$i]}")"
  ln -s "${missing_sources[$i]}" "${missing_targets[$i]}"
done

summary=()
if [ "${#excluded_targets[@]}" -ne 0 ]; then
  summary+=("removed ${#excluded_targets[@]} excluded skill links")
fi
if [ "${#stale_targets[@]}" -ne 0 ]; then
  summary+=("removed ${#stale_targets[@]} stale skill links")
fi
if [ "${#missing_targets[@]}" -ne 0 ]; then
  summary+=("created ${#missing_targets[@]} skill links")
fi
if [ "${#summary[@]}" -eq 0 ]; then
  echo "skills are reconciled"
else
  line="${summary[0]}"
  for part in "${summary[@]:1}"; do
    line="$line and $part"
  done
  echo "$line"
fi
