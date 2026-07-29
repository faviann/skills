#!/usr/bin/env bash
set -euo pipefail

# Install this fork's skills, except in-progress and deprecated ones, as
# per-skill links. Existing entries are never rewritten or removed: any
# conflict aborts the entire preflight.

REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
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
names=()
sources=()
declare -A source_by_name=()
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
        continue
      fi

      raw_target="$(readlink "$installed_link")"
      if [[ "$raw_target" = /* ]]; then
        resolved_target="$(realpath -m -- "$raw_target")"
      else
        resolved_target="$(realpath -m -- "$(dirname "$installed_link")/$raw_target")"
      fi
      case "$resolved_target" in
        "$REPO"|"$REPO"/*)
          conflicts+=(
            "stale repository link: $installed_link -> $raw_target"
          )
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
  if [ "${#missing_targets[@]}" -eq 0 ]; then
    echo "skills are reconciled"
    exit 0
  fi
  for target in "${missing_targets[@]}"; do
    echo "missing: $target" >&2
  done
  exit 1
fi

for i in "${!missing_targets[@]}"; do
  mkdir -p "$(dirname "${missing_targets[$i]}")"
  ln -s "${missing_sources[$i]}" "${missing_targets[$i]}"
done

if [ "${#missing_targets[@]}" -eq 0 ]; then
  echo "skills are reconciled"
else
  echo "created ${#missing_targets[@]} skill links"
fi
