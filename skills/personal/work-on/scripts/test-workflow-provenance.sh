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

(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/clean.json"
)
jq -e '
  .canonical
  | test("^work-on:[0-9a-f]{12} workflow:[0-9a-f]{12} tdd:[0-9a-f]{12} review:[0-9a-f]{12} \\(example/skills@[0-9a-f]{12}\\)$")
' "$fixture/clean.json" >/dev/null

clean_tdd="$(jq -r '.components.tdd.digest' "$fixture/clean.json")"
printf 'non-SKILL fixture change\n' \
  >>"$skills_checkout/skills/engineering/tdd/tests.md"
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/dirty.json"
)
jq -e '
  (.components["work-on"].starred == false)
  and (.components.workflow.starred == false)
  and (.components.tdd.starred == true)
  and (.components.review.starred == false)
' "$fixture/dirty.json" >/dev/null
[[ "$(jq -r '.components.tdd.digest' "$fixture/dirty.json")" != "$clean_tdd" ]]

git -C "$skills_checkout" add .
git -C "$skills_checkout" commit -qm 'unpushed fixture change'
(
  cd "$skills_checkout"
  "$command_under_test" >"$fixture/unpushed.json"
)
jq -e '
  [.components[].starred] == [true, true, true, true]
  and (.commit | test("^example/skills@[0-9a-f]{12}$"))
' "$fixture/unpushed.json" >/dev/null

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
  (.canonical
    | test("^work-on:[0-9a-f]{12}\\* workflow:[0-9a-f]{12}\\* tdd:[0-9a-f]{12}\\* review:[0-9a-f]{12}\\* \\(unknown\\)$"))
  and ([.components[].starred] == [true, true, true, true])
  and (.commit == "unknown")
' "$fixture/no-git.json" >/dev/null

mkdir "$fixture/not-a-repo"
(
  cd "$fixture/not-a-repo"
  "$command_under_test" >"$fixture/not-a-repo.json"
)
jq -e '
  ([.components[].starred] == [true, true, true, true])
  and (.commit == "unknown")
' "$fixture/not-a-repo.json" >/dev/null

printf 'work-on workflow provenance black-box scenarios passed\n'
