#!/usr/bin/env bash
set -euo pipefail

readonly source_skill_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

# The run-start command is loaded from the installed skill while work-on is
# operating in an arbitrary target repository.
grep -Fqx \
  '   `~/.agents/skills/work-on/scripts/workflow-provenance.sh > "$(git rev-parse --git-dir)/work-on-provenance.json"`' \
  "$source_skill_root/SKILL.md"

skills_checkout="$fixture/skills-checkout"
mkdir -p \
  "$skills_checkout/skills/personal" \
  "$skills_checkout/skills/engineering"
cp -R "$source_skill_root" "$skills_checkout/skills/personal/work-on"
cp -R "$source_skill_root/../../engineering/tdd" \
  "$skills_checkout/skills/engineering/tdd"
cp -R "$source_skill_root/../../engineering/code-review" \
  "$skills_checkout/skills/engineering/code-review"
ln -s 'initial-target' \
  "$skills_checkout/skills/engineering/tdd/provenance-link"
printf 'skills/engineering/tdd/ignored-provenance-fixture\n' \
  >"$skills_checkout/.gitignore"

git -C "$skills_checkout" init -q -b main
git -C "$skills_checkout" config user.name 'Provenance Test'
git -C "$skills_checkout" config user.email provenance@example.invalid
git -C "$skills_checkout" add .
git -C "$skills_checkout" commit -qm 'fixture'
git init -q --bare "$fixture/skills-origin.git"
git -C "$skills_checkout" remote add origin \
  'https://github.com/example/skills.git'
git -C "$skills_checkout" config remote.origin.url \
  "$fixture/skills-origin.git"
git -C "$skills_checkout" push -q -u origin main
# Keep the fetch/push transport local while giving the script a canonical
# GitHub origin to report.
git -C "$skills_checkout" config remote.origin.url \
  'https://github.com/example/skills.git'

command_under_test="$skills_checkout/skills/personal/work-on/scripts/workflow-provenance.sh"

canonical_from() {
  jq -er '
    if (keys == ["canonical"] and (.canonical | type == "string"))
    then .canonical
    else error("provenance ledger must contain only canonical")
    end
  ' "$1"
}

component_value() {
  local canonical="$1" component="$2"
  sed -n "s/.*${component}:\\([^ ]*\\).*/\\1/p" <<<"$canonical"
}

(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/clean.json"
)
jq -e '
  keys == ["canonical"]
  and (.canonical
    | test("^work-on:[0-9a-f]{12} workflow:[0-9a-f]{12} tdd:[0-9a-f]{12} review:[0-9a-f]{12} \\(example/skills@[0-9a-f]{12}\\)$"))
' "$fixture/clean.json" >/dev/null

clean_canonical="$(canonical_from "$fixture/clean.json")"
clean_work_on="$(component_value "$clean_canonical" work-on)"
clean_workflow="$(component_value "$clean_canonical" workflow)"
clean_tdd="$(component_value "$clean_canonical" tdd)"
clean_review="$(component_value "$clean_canonical" review)"
[[ "$clean_tdd" =~ ^[0-9a-f]{12}$ ]]
ln -sfn 'changed-target' \
  "$skills_checkout/skills/engineering/tdd/provenance-link"
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/symlink-target.json"
)
symlink_target_canonical="$(canonical_from "$fixture/symlink-target.json")"
[[ "$(component_value "$symlink_target_canonical" work-on)" == "$clean_work_on" ]]
[[ "$(component_value "$symlink_target_canonical" workflow)" == "$clean_workflow" ]]
[[ "$(component_value "$symlink_target_canonical" tdd)" =~ ^[0-9a-f]{12}\*$ ]]
[[ "$(component_value "$symlink_target_canonical" tdd)" != "$clean_tdd" ]]
[[ "$(component_value "$symlink_target_canonical" review)" == "$clean_review" ]]
git -C "$skills_checkout" restore skills/engineering/tdd/provenance-link

printf 'non-SKILL fixture change\n' \
  >>"$skills_checkout/skills/engineering/tdd/tests.md"
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/dirty.json"
)
dirty_canonical="$(canonical_from "$fixture/dirty.json")"
[[ "$dirty_canonical" =~ ^work-on:[0-9a-f]{12}[[:space:]]workflow:[0-9a-f]{12}[[:space:]]tdd:[0-9a-f]{12}\*[[:space:]]review:[0-9a-f]{12}[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
[[ "$(component_value "$dirty_canonical" tdd)" != "$clean_tdd" ]]

git -C "$skills_checkout" restore skills/engineering/tdd/tests.md
printf 'ignored but instruction-affecting\n' \
  >"$skills_checkout/skills/engineering/tdd/ignored-provenance-fixture"
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/ignored.json"
)
ignored_canonical="$(canonical_from "$fixture/ignored.json")"
[[ "$ignored_canonical" =~ ^work-on:[0-9a-f]{12}[[:space:]]workflow:[0-9a-f]{12}[[:space:]]tdd:[0-9a-f]{12}\*[[:space:]]review:[0-9a-f]{12}[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
[[ "$(component_value "$ignored_canonical" tdd)" != "$clean_tdd" ]]
rm "$skills_checkout/skills/engineering/tdd/ignored-provenance-fixture"

git -C "$skills_checkout" update-index --assume-unchanged \
  skills/engineering/tdd/tests.md
printf 'hidden tracked change\n' \
  >>"$skills_checkout/skills/engineering/tdd/tests.md"
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/assume-unchanged.json"
)
assume_unchanged_canonical="$(canonical_from "$fixture/assume-unchanged.json")"
[[ "$assume_unchanged_canonical" =~ ^work-on:[0-9a-f]{12}[[:space:]]workflow:[0-9a-f]{12}[[:space:]]tdd:[0-9a-f]{12}\*[[:space:]]review:[0-9a-f]{12}[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
[[ "$(component_value "$assume_unchanged_canonical" tdd)" != "$clean_tdd" ]]
git -C "$skills_checkout" update-index --no-assume-unchanged \
  skills/engineering/tdd/tests.md
git -C "$skills_checkout" restore skills/engineering/tdd/tests.md

printf 'unpushed instruction change\n' \
  >>"$skills_checkout/skills/engineering/tdd/tests.md"
git -C "$skills_checkout" add .
git -C "$skills_checkout" commit -qm 'unpushed fixture change'
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/unpushed.json"
)
unpushed_canonical="$(canonical_from "$fixture/unpushed.json")"
[[ "$unpushed_canonical" =~ ^work-on:[0-9a-f]{12}\*[[:space:]]workflow:[0-9a-f]{12}\*[[:space:]]tdd:[0-9a-f]{12}\*[[:space:]]review:[0-9a-f]{12}\*[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]

# The installed harness links the whole skill directory, not each script.
mkdir -p "$fixture/installed-skills"
ln -s "$skills_checkout/skills/personal/work-on" \
  "$fixture/installed-skills/work-on"
(
  cd "$skills_checkout"
  timeout 5 "$fixture/installed-skills/work-on/scripts/workflow-provenance.sh" \
    >"$fixture/symlinked-parent.json"
)
[[ "$(canonical_from "$fixture/symlinked-parent.json")" == \
  "$unpushed_canonical" ]]

mkdir -p "$skills_checkout/docs"
printf '# Same-repository workflow\n' >"$skills_checkout/docs/workflow.md"
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/same-repository.json"
)
jq -e '
  .canonical
  | test(" workflow:[0-9a-f]{12}\\*? tdd:")
' "$fixture/same-repository.json" >/dev/null

same_identity_checkout="$fixture/same-identity-checkout"
git init -q -b main "$same_identity_checkout"
git -C "$same_identity_checkout" config user.name 'Provenance Test'
git -C "$same_identity_checkout" config user.email provenance@example.invalid
mkdir -p "$same_identity_checkout/docs"
printf '# Same-origin workflow\n' >"$same_identity_checkout/docs/workflow.md"
git -C "$same_identity_checkout" add .
git -C "$same_identity_checkout" commit -qm 'same-origin target fixture'
git init -q --bare "$fixture/same-identity-origin.git"
git -C "$same_identity_checkout" remote add origin \
  "$fixture/same-identity-origin.git"
git -C "$same_identity_checkout" push -q -u origin main
git -C "$same_identity_checkout" config remote.origin.url \
  'https://github.com/example/skills.git'
(
  cd "$same_identity_checkout"
  "$command_under_test" >"$fixture/same-identity.json"
)
jq -e '
  .canonical
  | test(" workflow:[0-9a-f]{12} tdd:")
' "$fixture/same-identity.json" >/dev/null

target_checkout="$fixture/target-checkout"
git init -q -b main "$target_checkout"
git -C "$target_checkout" config user.name 'Provenance Test'
git -C "$target_checkout" config user.email provenance@example.invalid
mkdir -p "$target_checkout/docs"
printf '# Target workflow\n' >"$target_checkout/docs/workflow.md"
git -C "$target_checkout" add .
git -C "$target_checkout" commit -qm 'target fixture'
git init -q --bare "$fixture/target-origin.git"
git -C "$target_checkout" remote add origin "$fixture/target-origin.git"
git -C "$target_checkout" push -q -u origin main
git -C "$target_checkout" config remote.origin.url \
  'git@github.com:example/target.git'
(
  cd "$target_checkout"
  "$command_under_test" >"$fixture/target.json"
)
jq -e '
  .canonical
  | test(" workflow:[0-9a-f]{12}@example/target ")
' "$fixture/target.json" >/dev/null

no_git_bin="$fixture/no-git-bin"
mkdir "$no_git_bin"
for dependency in awk bash cat dirname find grep mktemp pwd readlink rm sha256sum sort; do
  dependency_path="$(command -v "$dependency")"
  [[ "$dependency_path" != "$(command -v git)" ]]
  ln -s "$dependency_path" "$no_git_bin/$dependency"
done
(
  cd "$target_checkout"
  PATH="$no_git_bin" /bin/bash "$command_under_test" \
    >"$fixture/no-git.json"
)
jq -e '
  keys == ["canonical"]
  and (.canonical
    | test("^work-on:[0-9a-f]{12}\\* workflow:[0-9a-f]{12}\\* tdd:[0-9a-f]{12}\\* review:[0-9a-f]{12}\\* \\(unknown\\)$"))
' "$fixture/no-git.json" >/dev/null

mkdir "$fixture/not-a-repo"
(
  cd "$fixture/not-a-repo"
  "$command_under_test" >"$fixture/not-a-repo.json"
)
jq -e '
  keys == ["canonical"]
  and (.canonical
    | test("^work-on:[0-9a-f]{12}\\* workflow:[0-9a-f]{12}\\* tdd:[0-9a-f]{12}\\* review:[0-9a-f]{12}\\* \\(unknown\\)$"))
' "$fixture/not-a-repo.json" >/dev/null

printf 'work-on workflow provenance black-box scenarios passed\n'
