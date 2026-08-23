#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECONCILER="$ROOT/scripts/reconcile-skills.sh"
LINKER="$ROOT/scripts/link-skills.sh"

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
  cp "$LINKER" "$fixture/scripts/link-skills.sh"
  chmod +x "$fixture/scripts/reconcile-skills.sh"
  chmod +x "$fixture/scripts/link-skills.sh"
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

make_linked_worktree() {
  local repo="$1"
  local worktree_parent
  git -C "$repo" init -q
  git -C "$repo" config user.name "Reconciler tests"
  git -C "$repo" config user.email "reconciler-tests@example.com"
  git -C "$repo" add scripts/reconcile-skills.sh skills
  git -C "$repo" commit -qm "Create fixture"

  new_tmp_dir
  worktree_parent="$TMP_DIR"
  git -C "$repo" worktree add -qb linked-worktree "$worktree_parent/linked"
  LINKED_WORKTREE="$worktree_parent/linked"
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

capture_reconciler_result() {
  if OUTPUT="$("$@" 2>&1)"; then
    STATUS=0
  else
    STATUS=$?
  fi
}

run_reconciler() {
  local home="$1"
  local script="$2"
  shift 2

  capture_reconciler_result env HOME="$home" "$script" "$@"
}

run_reconciler_with_git_environment() {
  local home="$1"
  local primary="$2"
  local script="$3"
  shift 3

  capture_reconciler_result \
    env HOME="$home" \
    GIT_DIR="$primary/.git" \
    GIT_COMMON_DIR="$primary/.git" \
    GIT_WORK_TREE="$primary" \
    "$script" "$@"
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

test_non_repository_directory_does_not_trip_guard() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"

  if [ "$STATUS" -ne 0 ]; then
    echo "non-repository directory tripped the worktree guard: $OUTPUT" >&2
    return 1
  fi
  assert_link_target "$home/.agents/skills/alpha" "$repo/skills/engineering/alpha"
  assert_link_target "$home/.claude/skills/alpha" "$repo/skills/engineering/alpha"
}

test_primary_checkout_preserves_success_output() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  make_linked_worktree "$repo"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh"
  if [ "$STATUS" -ne 0 ] || [ "$OUTPUT" != "created 2 skill links" ]; then
    echo "primary checkout default mode changed: $OUTPUT" >&2
    return 1
  fi

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh" --check
  if [ "$STATUS" -ne 0 ] || [ "$OUTPUT" != "skills are reconciled" ]; then
    echo "primary checkout check mode changed: $OUTPUT" >&2
    return 1
  fi
}

assert_linked_worktree_refusal() {
  local mode="${1:-}"
  local git_environment="${2:-clean}"
  local repo home worktree
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  make_linked_worktree "$repo"
  worktree="$LINKED_WORKTREE"
  mkdir -p "$home/.agents/skills"
  ln -s "$repo/skills/engineering/alpha" "$home/.agents/skills/alpha"

  if [ "$git_environment" = "overridden" ]; then
    run_reconciler_with_git_environment \
      "$home" "$repo" "$worktree/scripts/reconcile-skills.sh" "$mode"
  elif [ -n "$mode" ]; then
    run_reconciler "$home" "$worktree/scripts/reconcile-skills.sh" "$mode"
  else
    run_reconciler "$home" "$worktree/scripts/reconcile-skills.sh"
  fi

  if [ "$STATUS" -eq 0 ]; then
    echo "expected linked worktree invocation to fail in mode: ${mode:-default}" >&2
    return 1
  fi
  if [ "$OUTPUT" != "error: skill links always belong to the primary checkout at $repo; re-run scripts/reconcile-skills.sh from there." ]; then
    echo "linked worktree refusal was not the single expected message: $OUTPUT" >&2
    return 1
  fi
  if [ "$(readlink "$home/.agents/skills/alpha")" != "$repo/skills/engineering/alpha" ] ||
    [ -e "$home/.claude" ]; then
    echo "linked worktree invocation changed skill links in mode: ${mode:-default}" >&2
    return 1
  fi
}

test_linked_worktree_default_mode_refuses_before_changes() {
  assert_linked_worktree_refusal
}

test_linked_worktree_check_mode_refuses_before_changes() {
  assert_linked_worktree_refusal --check
}

test_linked_worktree_git_environment_cannot_bypass_guard() {
  assert_linked_worktree_refusal --check overridden
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

test_excluded_skills_are_removed() {
  local repo home unrelated
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  add_skill "$repo" misc upstream-only
  mkdir -p "$repo/.agents" "$home/.agents/skills" "$home/.claude/skills"
  printf '%s\n' "upstream-only" >"$repo/.agents/skill-link-excludes"
  ln -s "$repo/skills/misc/upstream-only" "$home/.agents/skills/upstream-only"
  ln -s "$repo/skills/misc/upstream-only" "$home/.claude/skills/upstream-only"

  new_tmp_dir
  unrelated="$TMP_DIR"
  ln -s "$unrelated" "$home/.agents/skills/local-link"

  HOME="$home" "$repo/scripts/reconcile-skills.sh"

  assert_link_target "$home/.agents/skills/alpha" "$repo/skills/engineering/alpha"
  assert_link_target "$home/.claude/skills/alpha" "$repo/skills/engineering/alpha"
  if [ -e "$home/.agents/skills/upstream-only" ] ||
    [ -L "$home/.agents/skills/upstream-only" ] ||
    [ -e "$home/.claude/skills/upstream-only" ] ||
    [ -L "$home/.claude/skills/upstream-only" ]; then
    echo "excluded skill remains installed" >&2
    return 1
  fi
  if [ "$(readlink "$home/.agents/skills/local-link")" != "$unrelated" ]; then
    echo "excluding a skill changed an unrelated link" >&2
    return 1
  fi
}

test_check_reports_excluded_skill_without_removing_it() {
  local repo home installed
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" misc upstream-only
  mkdir -p "$repo/.agents" "$home/.agents/skills"
  printf '%s\n' "upstream-only" >"$repo/.agents/skill-link-excludes"
  installed="$home/.agents/skills/upstream-only"
  ln -s "$repo/skills/misc/upstream-only" "$installed"

  run_reconciler "$home" "$repo/scripts/reconcile-skills.sh" --check

  if [ "$STATUS" -eq 0 ]; then
    echo "expected --check to fail for an excluded installed skill" >&2
    return 1
  fi
  assert_link_target "$installed" "$repo/skills/misc/upstream-only"
  if [[ "$OUTPUT" != *"excluded skill is still linked: $installed"* ]]; then
    echo "--check did not explain the excluded link: $OUTPUT" >&2
    return 1
  fi
}

test_linker_does_not_install_excluded_skills() {
  local repo home
  make_test_context
  repo="$TEST_REPO"
  home="$TEST_HOME"
  add_skill "$repo" engineering alpha
  add_skill "$repo" misc upstream-only
  mkdir -p "$repo/.agents"
  printf '%s\n' "upstream-only" >"$repo/.agents/skill-link-excludes"

  HOME="$home" "$repo/scripts/link-skills.sh"

  assert_link_target "$home/.agents/skills/alpha" "$repo/skills/engineering/alpha"
  assert_link_target "$home/.claude/skills/alpha" "$repo/skills/engineering/alpha"
  if [ -e "$home/.agents/skills/upstream-only" ] ||
    [ -L "$home/.agents/skills/upstream-only" ] ||
    [ -e "$home/.claude/skills/upstream-only" ] ||
    [ -L "$home/.claude/skills/upstream-only" ]; then
    echo "linker installed an excluded skill" >&2
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
test_non_repository_directory_does_not_trip_guard
echo "ok - non-repository directory does not trip guard"
test_primary_checkout_preserves_success_output
echo "ok - primary checkout preserves success output"
test_linked_worktree_default_mode_refuses_before_changes
echo "ok - linked worktree default mode refuses before changes"
test_linked_worktree_check_mode_refuses_before_changes
echo "ok - linked worktree check mode refuses before changes"
test_linked_worktree_git_environment_cannot_bypass_guard
echo "ok - linked worktree Git environment cannot bypass guard"
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
test_excluded_skills_are_removed
echo "ok - excluded skills are removed"
test_check_reports_excluded_skill_without_removing_it
echo "ok - check reports excluded skills without removing them"
test_linker_does_not_install_excluded_skills
echo "ok - linker does not install excluded skills"
