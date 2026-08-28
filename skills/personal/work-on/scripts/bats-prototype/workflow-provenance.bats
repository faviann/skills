#!/usr/bin/env bats

load provenance-fixture
bats_require_minimum_version 1.13.0

setup() { setup_provenance_fixture; }
teardown() { teardown_provenance_fixture; }

@test "capture fingerprints only declared bytes and preserves a frozen canonical value" {
  run capture_in "$skills_checkout"
  assert_success
  [[ -z "$output" && -f "$skills_ledger" ]]
  clean_canonical="$(verify_in "$skills_checkout")"
  [[ "$clean_canonical" =~ ^work-on:[0-9a-f]{12}[[:space:]]workflow:[0-9a-f]{12}[[:space:]]tdd:[0-9a-f]{12}[[:space:]]review:[0-9a-f]{12}[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
  clean_work_on="$(component_value "$clean_canonical" work-on)"
  clean_workflow="$(component_value "$clean_canonical" workflow)"
  clean_tdd="$(component_value "$clean_canonical" tdd)"
  clean_review="$(component_value "$clean_canonical" review)"

  chmod +x "$skills_checkout/skills/engineering/tdd/tests.md"
  capture_in "$skills_checkout"
  [[ "$(verify_in "$skills_checkout")" == "$clean_canonical" ]]
  chmod -x "$skills_checkout/skills/engineering/tdd/tests.md"

  printf 'dirty instruction change\n' >>"$skills_checkout/skills/engineering/tdd/tests.md"
  capture_in "$skills_checkout"
  dirty_canonical="$(verify_in "$skills_checkout")"
  [[ "$(component_value "$dirty_canonical" work-on)" == "$clean_work_on" ]]
  [[ "$(component_value "$dirty_canonical" workflow)" == "$clean_workflow" ]]
  [[ "$(component_value "$dirty_canonical" review)" == "$clean_review" ]]
  dirty_tdd="$(component_value "$dirty_canonical" tdd)"
  [[ "$dirty_tdd" =~ ^[0-9a-f]{12}\*$ && "$dirty_tdd" != "$clean_tdd" ]]

  printf 'not an instruction input\n' >"$skills_checkout/skills/engineering/tdd/undeclared.md"
  capture_in "$skills_checkout"
  [[ "$(verify_in "$skills_checkout")" == "$dirty_canonical" ]]
  rm "$skills_checkout/skills/engineering/tdd/undeclared.md"

  git -C "$skills_checkout" add .
  git -C "$skills_checkout" commit -qm 'unpushed instruction change'
  [[ "$(verify_in "$skills_checkout")" == "$dirty_canonical" ]]
  capture_in "$skills_checkout"
  unpushed_canonical="$(verify_in "$skills_checkout")"
  [[ "$unpushed_canonical" =~ ^work-on:[0-9a-f]{12}[[:space:]]workflow:[0-9a-f]{12}[[:space:]]tdd:[0-9a-f]{12}[[:space:]]review:[0-9a-f]{12}[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
  [[ "$(component_value "$unpushed_canonical" tdd)" == "${dirty_tdd%\*}" ]]

  mkdir -p "$fixture/installed-skills"
  ln -s "$skills_checkout/skills/personal/work-on" "$fixture/installed-skills/work-on"
  installed_command="$fixture/installed-skills/work-on/scripts/workflow-provenance.sh"
  capture_in "$skills_checkout" "$installed_command"
  [[ "$(verify_in "$skills_checkout" "$installed_command")" == "$unpushed_canonical" ]]
  printf 'unrelated content\n' >"$skills_checkout/unrelated.txt"
  git -C "$skills_checkout" add .
  git -C "$skills_checkout" commit -qm 'unrelated commit'
  [[ "$(verify_in "$skills_checkout")" == "$unpushed_canonical" ]]
}

@test "verify rejects changed declared instructions without deleting the frozen ledger" {
  capture_in "$skills_checkout"
  printf 'post-capture change\n' >>"$skills_checkout/skills/personal/work-on/references/github-closeout.md"
  run --separate-stderr verify_in "$skills_checkout"
  assert_failure
  [[ -z "$output" ]]
  [[ "$stderr" == 'workflow provenance: work-on instructions changed since capture' ]]
  [[ -f "$skills_ledger" ]]
}

@test "verify rejects a missing ledger without printing a canonical value" {
  capture_in "$skills_checkout"
  rm "$skills_ledger"
  run --separate-stderr verify_in "$skills_checkout"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'run ledger is missing'
}

@test "target workflow identity is dirty before commit and clean after commit" {
  capture_in "$skills_checkout"
  clean_workflow="$(component_value "$(verify_in "$skills_checkout")" workflow)"
  make_target_checkout
  capture_in "$target_checkout"
  target_dirty="$(verify_in "$target_checkout")"
  [[ "$(component_value "$target_dirty" workflow)" =~ ^[0-9a-f]{12}\*$ ]]
  [[ "$(component_value "$target_dirty" workflow)" != "$clean_workflow" ]]
  [[ "$target_dirty" == *'(example/skills@'* ]]
  git -C "$target_checkout" add .
  git -C "$target_checkout" commit -qm 'target fixture'
  capture_in "$target_checkout"
  [[ "$(component_value "$(verify_in "$target_checkout")" workflow)" =~ ^[0-9a-f]{12}$ ]]
}

@test "capture rejects a symlinked declared workflow even when its target is readable" {
  symlink_checkout="$fixture/symlink-checkout"
  git init -q -b main "$symlink_checkout"
  git -C "$symlink_checkout" config user.name 'Provenance Test'
  git -C "$symlink_checkout" config user.email provenance@example.invalid
  mkdir -p "$symlink_checkout/docs" "$symlink_checkout/workflows"
  printf '# Target workflow\n' >"$symlink_checkout/workflows/main.md"
  ln -s ../workflows/main.md "$symlink_checkout/docs/workflow.md"
  git -C "$symlink_checkout" add .
  git -C "$symlink_checkout" commit -qm fixture
  run --separate-stderr capture_in "$symlink_checkout"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'declared instruction input is unreadable'
  [[ ! -e "$symlink_checkout/.git/work-on-provenance.json" ]]
}

@test "unrecognized and hostile skills origins capture with an unknown pointer" {
  make_target_checkout
  for origin in \
    "$fixture/skills-origin.git" \
    'https://example.invalid/github.com/not-github/repo.git' \
    'https://github.com/example/re"po.git' \
    'https://github.com/exa mple/repo.git' \
    'https://github.com/example/re\po.git'; do
    git -C "$skills_checkout" remote set-url origin "$origin"
    capture_in "$target_checkout"
    [[ "$(verify_in "$target_checkout")" =~ [[:space:]]\(unknown@[0-9a-f]{12}\)$ ]]
  done
}

@test "capture fails when git is unavailable" {
  make_target_checkout
  no_git_bin="$fixture/no-git-bin"
  mkdir "$no_git_bin"
  for dependency in awk bash cat cut dirname grep jq mktemp mv printf pwd rm sed sha256sum; do
    dependency_path="$(command -v "$dependency")" || continue
    ln -s "$dependency_path" "$no_git_bin/$dependency"
  done
  run --separate-stderr env PATH="$no_git_bin" /bin/bash -c 'cd "$1" && "$2" capture' _ "$target_checkout" "$command_under_test"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'capture requires git'
}

@test "capture rejects a non-Git skills checkout and removes a reachable stale ledger" {
  make_target_checkout
  capture_in "$target_checkout"
  non_git="$fixture/non-git-skills-checkout"
  mkdir -p "$non_git"
  cp -R "$skills_checkout/skills" "$non_git/skills"
  run --separate-stderr capture_in "$target_checkout" "$non_git/skills/personal/work-on/scripts/workflow-provenance.sh"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'capture requires a Git-backed skills checkout'
  [[ ! -e "$target_checkout/.git/work-on-provenance.json" ]]
}

@test "capture rejects a missing declared instruction and leaves no ledger" {
  unreadable="$fixture/unreadable-checkout"
  cp -R "$skills_checkout" "$unreadable"
  rm "$unreadable/skills/engineering/tdd/mocking.md" "$unreadable/.git/work-on-provenance.json" 2>/dev/null || true
  run --separate-stderr capture_in "$unreadable" "$unreadable/skills/personal/work-on/scripts/workflow-provenance.sh"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'declared instruction input is unreadable'
  [[ ! -e "$unreadable/.git/work-on-provenance.json" ]]
}

@test "capture rejects directory, broken-symlink, and unreadable target workflows" {
  invalid="$fixture/invalid-workflow-target"
  git init -q -b main "$invalid"
  git -C "$invalid" config user.name 'Provenance Test'
  git -C "$invalid" config user.email provenance@example.invalid
  mkdir -p "$invalid/docs"
  mkdir "$invalid/docs/workflow.md"
  run --separate-stderr capture_in "$invalid"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'declared instruction input is unreadable'
  rmdir "$invalid/docs/workflow.md"
  ln -s missing.md "$invalid/docs/workflow.md"
  run --separate-stderr capture_in "$invalid"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'declared instruction input is unreadable'
  rm "$invalid/docs/workflow.md"
  if [[ "$(id -u)" -ne 0 ]]; then
    printf '# Target workflow\n' >"$invalid/docs/workflow.md"
    chmod 000 "$invalid/docs/workflow.md"
    run --separate-stderr capture_in "$invalid"
    chmod 644 "$invalid/docs/workflow.md"
    assert_failure
    [[ -z "$output" ]]
    assert_stderr_contains 'declared instruction input is unreadable'
  fi
  [[ ! -e "$invalid/.git/work-on-provenance.json" ]]
}

@test "a failed recapture removes the previous run ledger" {
  stale="$fixture/stale-ledger-checkout"
  cp -R "$skills_checkout" "$stale"
  stale_command="$stale/skills/personal/work-on/scripts/workflow-provenance.sh"
  capture_in "$stale" "$stale_command"
  [[ -f "$stale/.git/work-on-provenance.json" ]]
  rm "$stale/skills/engineering/tdd/mocking.md"
  run --separate-stderr capture_in "$stale" "$stale_command"
  assert_failure
  [[ -z "$output" ]]
  assert_stderr_contains 'declared instruction input is unreadable'
  [[ ! -e "$stale/.git/work-on-provenance.json" ]]
}
