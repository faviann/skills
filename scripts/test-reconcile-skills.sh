#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECONCILER="$ROOT/scripts/reconcile-skills.sh"

tmp_dirs=()

cleanup() {
  local dir
  for dir in "${tmp_dirs[@]}"; do
    rm -rf -- "$dir"
  done
}
trap cleanup EXIT

new_tmp_dir() {
  local dir
  dir="$(mktemp -d)"
  tmp_dirs+=("$dir")
  TMP_DIR="$dir"
}

make_test_context() {
  local fixture
  new_tmp_dir
  fixture="$TMP_DIR"
  mkdir -p "$fixture/scripts"
  cp "$RECONCILER" "$fixture/scripts/reconcile-skills.sh"
  chmod +x "$fixture/scripts/reconcile-skills.sh"
  TEST_REPO="$fixture"

  new_tmp_dir
  TEST_HOME="$TMP_DIR"
}

add_skill() {
  local repo="$1"
  local bucket="$2"
  local name="$3"
  mkdir -p "$repo/skills/$bucket/$name"
  printf '%s\n' "# $name" >"$repo/skills/$bucket/$name/SKILL.md"
}

assert_link_target() {
  local link="$1"
  local expected="$2"

  if [ ! -L "$link" ]; then
    echo "expected symlink: $link" >&2
    return 1
  fi

  if [ "$(readlink -f "$link")" != "$(readlink -f "$expected")" ]; then
    echo "unexpected target for $link: $(readlink "$link")" >&2
    return 1
  fi
}

run_reconciler() {
  local home="$1"
  local script="$2"
  shift 2

  if OUTPUT="$(HOME="$home" "$script" "$@" 2>&1)"; then
    STATUS=0
  else
    STATUS=$?
  fi
}

test_empty_home_creates_links() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  add_skill "$repo" productivity beta

  HOME="$home" "$repo/scripts/reconcile-skills.sh"

  assert_link_target "$home/.agents/skills/alpha" "$repo/skills/engineering/alpha"
  assert_link_target "$home/.agents/skills/beta" "$repo/skills/productivity/beta"
  assert_link_target "$home/.claude/skills/alpha" "$repo/skills/engineering/alpha"
  assert_link_target "$home/.claude/skills/beta" "$repo/skills/productivity/beta"
}

test_second_run_is_idempotent() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha

  HOME="$home" "$repo/scripts/reconcile-skills.sh"
  HOME="$home" "$repo/scripts/reconcile-skills.sh"

  assert_link_target "$home/.agents/skills/alpha" "$repo/skills/engineering/alpha"
  assert_link_target "$home/.claude/skills/alpha" "$repo/skills/engineering/alpha"
}

test_check_passes_after_reconciliation() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha

  HOME="$home" "$repo/scripts/reconcile-skills.sh"
  HOME="$home" "$repo/scripts/reconcile-skills.sh" --check
}

test_check_reports_missing_link_without_creating_it() {
  local repo home missing
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  missing="$home/.agents/skills/alpha"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh" --check

  if [ "$STATUS" -eq 0 ]; then
    echo "expected --check to fail for a missing link" >&2
    return 1
  fi
  if [ -e "$missing" ] || [ -L "$missing" ]; then
    echo "--check created missing link: $missing" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"missing"*"$missing"* ]]; then
    echo "--check did not explain the missing link: $OUTPUT" >&2
    return 1
  fi
}

test_duplicate_skill_names_abort_before_changes() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering shared
  add_skill "$repo" productivity shared

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -eq 0 ]; then
    echo "expected duplicate skill names to fail" >&2
    return 1
  fi
  if [ -e "$home/.agents" ] || [ -e "$home/.claude" ]; then
    echo "duplicate detection changed the home" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"duplicate skill name: shared"* ]]; then
    echo "duplicate error was not actionable: $OUTPUT" >&2
    return 1
  fi
}

test_real_directory_collision_aborts_without_partial_changes() {
  local repo home collision
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  add_skill "$repo" engineering beta
  collision="$home/.agents/skills/alpha"
  mkdir -p "$collision"
  printf '%s\n' "keep me" >"$collision/marker"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -eq 0 ]; then
    echo "expected a real-directory collision to fail" >&2
    return 1
  fi
  if [ "$(cat "$collision/marker")" != "keep me" ]; then
    echo "real-directory collision lost data" >&2
    return 1
  fi
  if [ -e "$home/.agents/skills/beta" ] ||
    [ -e "$home/.claude/skills/alpha" ] ||
    [ -e "$home/.claude/skills/beta" ]; then
    echo "collision caused partial reconciliation" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"collision"*"$collision"* ]] ||
    [[ "$OUTPUT" != *"No changes were made."* ]]; then
    echo "collision error was not actionable: $OUTPUT" >&2
    return 1
  fi
}

test_unrelated_symlink_collision_is_preserved() {
  local repo home collision unrelated
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  new_tmp_dir
  unrelated="$TMP_DIR"
  add_skill "$repo" engineering alpha
  collision="$home/.agents/skills/alpha"
  mkdir -p "$(dirname "$collision")"
  ln -s "$unrelated" "$collision"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -eq 0 ]; then
    echo "expected an unrelated symlink collision to fail" >&2
    return 1
  fi
  if [ "$(readlink "$collision")" != "$unrelated" ]; then
    echo "unrelated symlink collision was replaced" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"wrong symlink"*"$collision"* ]] ||
    [[ "$OUTPUT" != *"expected $repo/skills/engineering/alpha"* ]]; then
    echo "symlink collision error was not actionable: $OUTPUT" >&2
    return 1
  fi
}

test_wrong_repository_link_aborts_and_is_preserved() {
  local repo home wrong target
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  add_skill "$repo" engineering beta
  wrong="$home/.agents/skills/alpha"
  target="$repo/skills/engineering/beta"
  mkdir -p "$(dirname "$wrong")"
  ln -s "$target" "$wrong"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -eq 0 ]; then
    echo "expected a wrong repository link to fail" >&2
    return 1
  fi
  if [ "$(readlink "$wrong")" != "$target" ]; then
    echo "wrong repository link was modified" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"wrong symlink"*"$wrong"* ]] ||
    [[ "$OUTPUT" != *"expected $repo/skills/engineering/alpha"* ]]; then
    echo "wrong-link error was not actionable: $OUTPUT" >&2
    return 1
  fi
}

test_stale_repository_link_aborts_and_is_preserved() {
  local repo home stale stale_target
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  stale="$home/.agents/skills/removed"
  stale_target="$repo/skills/engineering/removed"
  mkdir -p "$(dirname "$stale")"
  ln -s "$stale_target" "$stale"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -eq 0 ]; then
    echo "expected a stale repository link to fail" >&2
    return 1
  fi
  if [ "$(readlink "$stale")" != "$stale_target" ]; then
    echo "stale repository link was modified" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"stale repository link"*"$stale"* ]]; then
    echo "stale-link error was not actionable: $OUTPUT" >&2
    return 1
  fi
  if [ -e "$home/.agents/skills/alpha" ] ||
    [ -e "$home/.claude/skills/alpha" ]; then
    echo "stale link caused partial reconciliation" >&2
    return 1
  fi
}

test_unrelated_destination_entries_are_preserved() {
  local repo home unrelated
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  new_tmp_dir
  unrelated="$TMP_DIR"
  add_skill "$repo" engineering alpha
  mkdir -p "$home/.agents/skills/local-directory"
  printf '%s\n' "keep me" >"$home/.agents/skills/local-file"
  ln -s "$unrelated" "$home/.agents/skills/local-link"

  HOME="$home" "$repo/scripts/reconcile-skills.sh"

  if [ ! -d "$home/.agents/skills/local-directory" ] ||
    [ "$(cat "$home/.agents/skills/local-file")" != "keep me" ] ||
    [ "$(readlink "$home/.agents/skills/local-link")" != "$unrelated" ]; then
    echo "unrelated destination entries were modified" >&2
    return 1
  fi
  assert_link_target "$home/.agents/skills/alpha" "$repo/skills/engineering/alpha"
}

test_destination_symlink_aborts_without_writing_through_it() {
  local repo home redirected
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  new_tmp_dir
  redirected="$TMP_DIR"
  add_skill "$repo" engineering alpha
  mkdir -p "$home/.agents"
  ln -s "$redirected" "$home/.agents/skills"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -eq 0 ]; then
    echo "expected a destination symlink to fail" >&2
    return 1
  fi
  if [ -e "$redirected/alpha" ] || [ -L "$redirected/alpha" ]; then
    echo "reconciler wrote through a destination symlink" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"destination is a symlink"*"$home/.agents/skills"* ]]; then
    echo "destination-symlink error was not actionable: $OUTPUT" >&2
    return 1
  fi
}

test_blocking_parent_aborts_without_partial_changes() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  printf '%s\n' "keep me" >"$home/.claude"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -eq 0 ]; then
    echo "expected a blocking destination parent to fail" >&2
    return 1
  fi
  if [ -e "$home/.agents" ]; then
    echo "blocking destination parent caused partial reconciliation" >&2
    return 1
  fi
  if [ "$(cat "$home/.claude")" != "keep me" ]; then
    echo "blocking destination parent was modified" >&2
    return 1
  fi
  if [[ "$OUTPUT" != *"harness directory is not a directory"*"$home/.claude"* ]] ||
    [[ "$OUTPUT" != *"No changes were made."* ]]; then
    echo "blocking-parent error was not actionable: $OUTPUT" >&2
    return 1
  fi
}

test_in_progress_and_deprecated_skills_are_not_installed() {
  local repo home in_progress deprecated
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  add_skill "$repo" in-progress draft
  add_skill "$repo" deprecated retired
  in_progress="$home/.agents/skills/draft"
  deprecated="$home/.agents/skills/retired"

  HOME="$home" "$repo/scripts/reconcile-skills.sh"

  assert_link_target "$home/.agents/skills/alpha" "$repo/skills/engineering/alpha"
  if [ -e "$in_progress" ] || [ -L "$in_progress" ]; then
    echo "in-progress skill was installed: $in_progress" >&2
    return 1
  fi
  if [ -e "$deprecated" ] || [ -L "$deprecated" ]; then
    echo "deprecated skill was installed: $deprecated" >&2
    return 1
  fi
}

test_empty_home_creates_links
echo "ok - empty home creates links"
test_second_run_is_idempotent
echo "ok - second run is idempotent"
test_check_passes_after_reconciliation
echo "ok - check passes after reconciliation"
test_check_reports_missing_link_without_creating_it
echo "ok - check reports missing link without creating it"
test_duplicate_skill_names_abort_before_changes
echo "ok - duplicate skill names abort before changes"
test_real_directory_collision_aborts_without_partial_changes
echo "ok - real directory collision aborts without partial changes"
test_unrelated_symlink_collision_is_preserved
echo "ok - unrelated symlink collision is preserved"
test_wrong_repository_link_aborts_and_is_preserved
echo "ok - wrong repository link aborts and is preserved"
test_stale_repository_link_aborts_and_is_preserved
echo "ok - stale repository link aborts and is preserved"
test_unrelated_destination_entries_are_preserved
echo "ok - unrelated destination entries are preserved"
test_destination_symlink_aborts_without_writing_through_it
echo "ok - destination symlink aborts without write-through"
test_blocking_parent_aborts_without_partial_changes
echo "ok - blocking parent aborts without partial changes"
test_in_progress_and_deprecated_skills_are_not_installed
echo "ok - in-progress and deprecated skills are not installed"
