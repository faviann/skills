#!/usr/bin/env bash
set -euo pipefail

readonly source_skill_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

skills_checkout="$fixture/skills-checkout"
mkdir -p \
  "$skills_checkout/skills/personal" \
  "$skills_checkout/skills/engineering"
cp -R "$source_skill_root" "$skills_checkout/skills/personal/work-on"
cp -R "$source_skill_root/../../engineering/tdd" \
  "$skills_checkout/skills/engineering/tdd"
cp -R "$source_skill_root/../../engineering/code-review" \
  "$skills_checkout/skills/engineering/code-review"

git -C "$skills_checkout" init -q -b main
git -C "$skills_checkout" config user.name 'Provenance Test'
git -C "$skills_checkout" config user.email provenance@example.invalid
git -C "$skills_checkout" add .
git -C "$skills_checkout" commit -qm 'fixture'
git -C "$skills_checkout" remote add origin \
  'https://github.com/example/skills.git'

command_under_test="$skills_checkout/skills/personal/work-on/scripts/workflow-provenance.sh"
skills_ledger="$skills_checkout/.git/work-on-provenance.json"

capture_in() {
  (cd "$1" && "${2:-$command_under_test}" capture)
}
verify_in() {
  (cd "$1" && "${2:-$command_under_test}" verify)
}
component_value() {
  sed -n "s/.*$2:\\([^ ]*\\).*/\\1/p" <<<"$1"
}

# Capture writes the ledger and keeps provenance off stdout.
capture_in "$skills_checkout" >"$fixture/capture.out"
[[ ! -s "$fixture/capture.out" ]]
[[ -f "$skills_ledger" ]]

clean_canonical="$(verify_in "$skills_checkout")"
[[ "$clean_canonical" =~ ^work-on:[0-9a-f]{12}[[:space:]]workflow:[0-9a-f]{12}[[:space:]]tdd:[0-9a-f]{12}[[:space:]]review:[0-9a-f]{12}[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
clean_work_on="$(component_value "$clean_canonical" work-on)"
clean_workflow="$(component_value "$clean_canonical" workflow)"
clean_tdd="$(component_value "$clean_canonical" tdd)"
clean_review="$(component_value "$clean_canonical" review)"

# File modes are not instruction identity.
chmod +x "$skills_checkout/skills/engineering/tdd/tests.md"
capture_in "$skills_checkout"
[[ "$(verify_in "$skills_checkout")" == "$clean_canonical" ]]
chmod -x "$skills_checkout/skills/engineering/tdd/tests.md"

# A changed declared input stars and changes only its own component.
printf 'dirty instruction change\n' \
  >>"$skills_checkout/skills/engineering/tdd/tests.md"
capture_in "$skills_checkout"
dirty_canonical="$(verify_in "$skills_checkout")"
[[ "$(component_value "$dirty_canonical" work-on)" == "$clean_work_on" ]]
[[ "$(component_value "$dirty_canonical" workflow)" == "$clean_workflow" ]]
[[ "$(component_value "$dirty_canonical" review)" == "$clean_review" ]]
dirty_tdd="$(component_value "$dirty_canonical" tdd)"
[[ "$dirty_tdd" =~ ^[0-9a-f]{12}\*$ ]]
[[ "$dirty_tdd" != "$clean_tdd" ]]

# An undeclared file in a component directory is not workflow identity.
printf 'not an instruction input\n' \
  >"$skills_checkout/skills/engineering/tdd/undeclared.md"
capture_in "$skills_checkout"
[[ "$(verify_in "$skills_checkout")" == "$dirty_canonical" ]]
rm "$skills_checkout/skills/engineering/tdd/undeclared.md"

# Committing the captured bytes keeps verification passing on the frozen value,
# then clears the star on recapture without changing the digest.
git -C "$skills_checkout" add .
git -C "$skills_checkout" commit -qm 'unpushed instruction change'
[[ "$(verify_in "$skills_checkout")" == "$dirty_canonical" ]]
capture_in "$skills_checkout"
unpushed_canonical="$(verify_in "$skills_checkout")"
[[ "$unpushed_canonical" =~ ^work-on:[0-9a-f]{12}[[:space:]]workflow:[0-9a-f]{12}[[:space:]]tdd:[0-9a-f]{12}[[:space:]]review:[0-9a-f]{12}[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
[[ "$(component_value "$unpushed_canonical" tdd)" == "${dirty_tdd%\*}" ]]

# The installed harness links the whole skill directory, not each script.
mkdir -p "$fixture/installed-skills"
ln -s "$skills_checkout/skills/personal/work-on" \
  "$fixture/installed-skills/work-on"
installed_command="$fixture/installed-skills/work-on/scripts/workflow-provenance.sh"
capture_in "$skills_checkout" "$installed_command"
[[ "$(verify_in "$skills_checkout" "$installed_command")" == \
  "$unpushed_canonical" ]]

# Verify survives an unrelated commit and a byte-identical input being
# committed, and prints exactly the captured value.
printf 'unrelated content\n' >"$skills_checkout/unrelated.txt"
git -C "$skills_checkout" add .
git -C "$skills_checkout" commit -qm 'unrelated commit'
[[ "$(verify_in "$skills_checkout")" == "$unpushed_canonical" ]]

# A changed declared input after capture fails verification by name.
printf 'post-capture change\n' \
  >>"$skills_checkout/skills/personal/work-on/references/github-closeout.md"
if verify_in "$skills_checkout" \
    >"$fixture/frozen.out" 2>"$fixture/frozen.err"; then
  printf 'FAIL[frozen]: verify accepted changed instructions\n' >&2
  exit 1
fi
[[ ! -s "$fixture/frozen.out" ]]
grep -Fqx 'workflow provenance: work-on instructions changed since capture' \
  "$fixture/frozen.err"
# A failed verification reports; it never discards the frozen run record.
[[ -f "$skills_ledger" ]]
git -C "$skills_checkout" restore \
  skills/personal/work-on/references/github-closeout.md

# A missing ledger fails verification without a canonical value.
mv "$skills_ledger" "$fixture/saved-ledger.json"
if verify_in "$skills_checkout" \
    >"$fixture/no-ledger.out" 2>"$fixture/no-ledger.err"; then
  printf 'FAIL[no-ledger]: verify accepted a missing ledger\n' >&2
  exit 1
fi
[[ ! -s "$fixture/no-ledger.out" ]]
grep -Fq 'run ledger is missing' "$fixture/no-ledger.err"
mv "$fixture/saved-ledger.json" "$skills_ledger"

# A target repository's docs/workflow.md supplies the workflow identity with no
# repository suffix, and is starred only while it differs from target HEAD.
target_checkout="$fixture/target-checkout"
git init -q -b main "$target_checkout"
git -C "$target_checkout" config user.name 'Provenance Test'
git -C "$target_checkout" config user.email provenance@example.invalid
mkdir -p "$target_checkout/docs"
printf '# Target workflow\n' >"$target_checkout/docs/workflow.md"
git -C "$target_checkout" remote add origin 'git@github.com:example/target.git'
capture_in "$target_checkout"
target_dirty_canonical="$(verify_in "$target_checkout")"
[[ "$(component_value "$target_dirty_canonical" workflow)" =~ ^[0-9a-f]{12}\*$ ]]
[[ "$(component_value "$target_dirty_canonical" workflow)" != "$clean_workflow" ]]
[[ "$target_dirty_canonical" == *'(example/skills@'* ]]

git -C "$target_checkout" add .
git -C "$target_checkout" commit -qm 'target fixture'
capture_in "$target_checkout"
target_canonical="$(verify_in "$target_checkout")"
[[ "$(component_value "$target_canonical" workflow)" =~ ^[0-9a-f]{12}$ ]]

# A declared instruction input must itself be an ordinary file, even when its
# target is readable.
symlink_checkout="$fixture/symlink-checkout"
git init -q -b main "$symlink_checkout"
git -C "$symlink_checkout" config user.name 'Provenance Test'
git -C "$symlink_checkout" config user.email provenance@example.invalid
mkdir -p "$symlink_checkout/docs" "$symlink_checkout/workflows"
printf '# Target workflow\n' >"$symlink_checkout/workflows/main.md"
ln -s ../workflows/main.md "$symlink_checkout/docs/workflow.md"
git -C "$symlink_checkout" add .
git -C "$symlink_checkout" commit -qm 'symlinked workflow fixture'
if capture_in "$symlink_checkout" \
    >"$fixture/symlink.out" 2>"$fixture/symlink.err"; then
  printf 'FAIL[symlink]: capture accepted a declared input symlink\n' >&2
  exit 1
fi
[[ ! -s "$fixture/symlink.out" ]]
[[ ! -e "$symlink_checkout/.git/work-on-provenance.json" ]]
grep -Fq 'declared instruction input is unreadable' "$fixture/symlink.err"

# An unrecognizable skills origin still captures, with an unknown pointer.
git -C "$skills_checkout" remote set-url origin "$fixture/skills-origin.git"
capture_in "$target_checkout"
unknown_canonical="$(verify_in "$target_checkout")"
[[ "$unknown_canonical" =~ [[:space:]]\(unknown@[0-9a-f]{12}\)$ ]]

git -C "$skills_checkout" remote set-url origin \
  'https://example.invalid/github.com/not-github/repo.git'
capture_in "$target_checkout"
non_github_canonical="$(verify_in "$target_checkout")"
[[ "$non_github_canonical" =~ [[:space:]]\(unknown@[0-9a-f]{12}\)$ ]]
git -C "$skills_checkout" remote set-url origin \
  'https://github.com/example/skills.git'

# A GitHub-shaped origin whose slug is not a valid repository identifier is not
# a recognizable pointer. Accepting it would put unescaped bytes in the ledger
# JSON, so capture would succeed and verify would then fail to read it back.
for hostile_origin in \
    'https://github.com/example/re"po.git' \
    'https://github.com/exa mple/repo.git' \
    'https://github.com/example/re\po.git'; do
  git -C "$skills_checkout" remote set-url origin "$hostile_origin"
  capture_in "$target_checkout"
  hostile_canonical="$(verify_in "$target_checkout")"
  [[ "$hostile_canonical" =~ [[:space:]]\(unknown@[0-9a-f]{12}\)$ ]]
done
git -C "$skills_checkout" remote set-url origin \
  'https://github.com/example/skills.git'

# Capture requires git.
no_git_bin="$fixture/no-git-bin"
mkdir "$no_git_bin"
for dependency in awk bash cat cut dirname grep jq mktemp mv printf pwd rm sed sha256sum; do
  dependency_path="$(command -v "$dependency")" || continue
  ln -s "$dependency_path" "$no_git_bin/$dependency"
done
[[ ! -e "$no_git_bin/git" ]]
if (
  cd "$target_checkout"
  PATH="$no_git_bin" /bin/bash "$command_under_test" capture
) >"$fixture/no-git.out" 2>"$fixture/no-git.err"; then
  printf 'FAIL[no-git]: capture succeeded without git\n' >&2
  exit 1
fi
[[ ! -s "$fixture/no-git.out" ]]

# Capture requires a Git-backed skills checkout.
non_git_skills_checkout="$fixture/non-git-skills-checkout"
mkdir -p "$non_git_skills_checkout"
cp -R "$skills_checkout/skills" "$non_git_skills_checkout/skills"
non_git_command="$non_git_skills_checkout/skills/personal/work-on/scripts/workflow-provenance.sh"
if capture_in "$target_checkout" "$non_git_command" \
    >"$fixture/non-git-skills.out" 2>"$fixture/non-git-skills.err"; then
  printf 'FAIL[non-git-skills]: capture succeeded from a non-git skills checkout\n' >&2
  exit 1
fi
[[ ! -s "$fixture/non-git-skills.out" ]]
# The target repository is resolvable here, so a stale ledger is reachable and
# must not survive the failure.
[[ ! -e "$target_checkout/.git/work-on-provenance.json" ]]

# Capture requires every declared input to be a readable regular file.
unreadable_checkout="$fixture/unreadable-checkout"
cp -R "$skills_checkout" "$unreadable_checkout"
rm "$unreadable_checkout/skills/engineering/tdd/mocking.md"
rm -f "$unreadable_checkout/.git/work-on-provenance.json"
unreadable_command="$unreadable_checkout/skills/personal/work-on/scripts/workflow-provenance.sh"
if capture_in "$unreadable_checkout" "$unreadable_command" \
    >"$fixture/unreadable.out" 2>"$fixture/unreadable.err"; then
  printf 'FAIL[unreadable]: capture succeeded with a missing declared input\n' >&2
  exit 1
fi
[[ ! -s "$fixture/unreadable.out" ]]
[[ ! -e "$unreadable_checkout/.git/work-on-provenance.json" ]]
grep -Fq 'declared instruction input is unreadable' "$fixture/unreadable.err"

# A target docs/workflow.md that exists but is not a readable regular file is a
# selected input that cannot be read, never a silent fall back to the default.
invalid_workflow_target="$fixture/invalid-workflow-target"
git init -q -b main "$invalid_workflow_target"
git -C "$invalid_workflow_target" config user.name 'Provenance Test'
git -C "$invalid_workflow_target" config user.email provenance@example.invalid
invalid_workflow_ledger="$invalid_workflow_target/.git/work-on-provenance.json"
mkdir -p "$invalid_workflow_target/docs"

refuse_invalid_workflow() {
  local label="$1"
  if capture_in "$invalid_workflow_target" \
      >"$fixture/$label.out" 2>"$fixture/$label.err"; then
    printf 'FAIL[%s]: capture accepted an invalid target workflow\n' "$label" >&2
    exit 1
  fi
  [[ ! -s "$fixture/$label.out" ]]
  [[ ! -e "$invalid_workflow_ledger" ]]
  grep -Fq 'declared instruction input is unreadable' "$fixture/$label.err"
}

mkdir "$invalid_workflow_target/docs/workflow.md"
refuse_invalid_workflow workflow-directory
rmdir "$invalid_workflow_target/docs/workflow.md"

ln -s missing-workflow.md "$invalid_workflow_target/docs/workflow.md"
refuse_invalid_workflow workflow-broken-symlink
rm "$invalid_workflow_target/docs/workflow.md"

# Root bypasses permission bits, so the unreadable case is only meaningful for
# an ordinary user.
if [[ "$(id -u)" -ne 0 ]]; then
  printf '# Target workflow\n' >"$invalid_workflow_target/docs/workflow.md"
  chmod 000 "$invalid_workflow_target/docs/workflow.md"
  refuse_invalid_workflow workflow-unreadable
  chmod 644 "$invalid_workflow_target/docs/workflow.md"
fi

# A failing capture invalidates the previous run's ledger rather than leaving a
# stale record that a later verify would treat as this run's frozen value.
stale_checkout="$fixture/stale-ledger-checkout"
cp -R "$skills_checkout" "$stale_checkout"
stale_command="$stale_checkout/skills/personal/work-on/scripts/workflow-provenance.sh"
stale_ledger="$stale_checkout/.git/work-on-provenance.json"
capture_in "$stale_checkout" "$stale_command"
[[ -f "$stale_ledger" ]]
rm "$stale_checkout/skills/engineering/tdd/mocking.md"
if capture_in "$stale_checkout" "$stale_command" \
    >"$fixture/stale-ledger.out" 2>"$fixture/stale-ledger.err"; then
  printf 'FAIL[stale-ledger]: capture succeeded with a missing declared input\n' >&2
  exit 1
fi
[[ ! -s "$fixture/stale-ledger.out" ]]
[[ ! -e "$stale_ledger" ]]
grep -Fq 'declared instruction input is unreadable' "$fixture/stale-ledger.err"

printf 'work-on workflow provenance black-box scenarios passed\n'
