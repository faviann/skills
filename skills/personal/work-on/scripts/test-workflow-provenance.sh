#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
skills="$fixture/skills"
mkdir -p "$skills/skills/personal" "$skills/skills/engineering"
cp -R "$source_root/skills/personal/work-on" "$skills/skills/personal/work-on"
cp -R "$source_root/skills/engineering/tdd" "$skills/skills/engineering/tdd"
cp -R "$source_root/skills/engineering/code-review" "$skills/skills/engineering/code-review"
git -C "$skills" init -q -b main
git -C "$skills" config user.name Test; git -C "$skills" config user.email test@example.invalid
git -C "$skills" add .; git -C "$skills" commit -qm fixture
git -C "$skills" remote add origin https://github.com/example/skills.git

target="$fixture/target"; git init -q -b main "$target"
git -C "$target" config user.name Test; git -C "$target" config user.email test@example.invalid
printf 'base\n' >"$target/base"; git -C "$target" add .; git -C "$target" commit -qm base
command="$skills/skills/personal/work-on/scripts/workflow-provenance.sh"
freeze_command="$skills/skills/personal/work-on/scripts/manifest-identity.sh"
identity="$(cd "$target" && "$command" identify-workflow)"
[[ "$identity" =~ ^[0-9a-f]{64}$ ]]

custody="$target/.git/work-on-manifest"; mkdir "$custody"; chmod 700 "$custody"
fabricated=opaque_run-123
(cd "$target" && "$command" capture --output "$custody/$fabricated.provenance.json")
printf 'frozen manifest\n' >"$custody/$fabricated.md"
printf '{"trusted":true}\n' >"$custody/$fabricated.trusted-snapshot.json"
chmod 600 "$custody/$fabricated.md" "$custody/$fabricated.trusted-snapshot.json"
[[ "$(stat -c %a "$custody/$fabricated.provenance.json")" == 600 ]]
for operation in read verify; do
  if (cd "$target" && "$command" "$operation" --run "$fabricated") \
      >"$fixture/fabricated-$operation.out" \
      2>"$fixture/fabricated-$operation.err"; then
    echo "$operation accepted a fabricated owner-mode custody trio" >&2
    exit 1
  fi
done

printf '%s\n' '- criterion: public seam' >"$fixture/manifest"
printf '%s\n' '{"body":"trusted"}' >"$fixture/snapshot"
run="$(cd "$target" && "$freeze_command" freeze \
  --manifest "$fixture/manifest" --snapshot "$fixture/snapshot" --base HEAD \
  --workflow-identity "$identity")"
canonical="$(cd "$target" && "$command" read --run "$run")"
[[ "$canonical" =~ ^work-on:[0-9a-f]{12}\*?[[:space:]]workflow:[0-9a-f]{12}\*?[[:space:]]tdd:[0-9a-f]{12}\*?[[:space:]]review:[0-9a-f]{12}\*?[[:space:]]\(example/skills@[0-9a-f]{12}\)$ ]]
[[ "$(cd "$target" && "$command" verify --run "$run")" == "$canonical" ]]
[[ ! -e "$target/.git/work-on-provenance.json" && ! -e "$target/.git/work-on-provenance.workflow-sha256" ]]

# The captured pointer is canonical presentation. An unrelated skills commit
# does not change any declared governing input and therefore does not invalidate
# resume under the existing instruction-identity contract.
printf 'unrelated\n' >"$skills/unrelated"
git -C "$skills" add unrelated; git -C "$skills" commit -qm unrelated
[[ "$(cd "$target" && "$command" verify --run "$run")" == "$canonical" ]]

# Read is custody-backed and survives live self-change; resume verification does not.
printf '\nchanged after freeze\n' >>"$skills/skills/personal/work-on/SKILL.md"
[[ "$(cd "$target" && "$command" read --run "$run")" == "$canonical" ]]
if (cd "$target" && "$command" verify --run "$run") >"$fixture/out" 2>"$fixture/err"; then
  echo 'verify accepted changed governing instructions' >&2; exit 1
fi
grep -Fq 'governing instructions changed since contract freeze' "$fixture/err"
git -C "$skills" restore skills/personal/work-on/SKILL.md

component() { sed -n "s/.*$1:\([^ ]*\).*/\1/p" <<<"$2"; }

# Modes and undeclared neighbours are outside instruction identity.
chmod +x "$skills/skills/engineering/tdd/tests.md"
[[ "$(cd "$target" && "$command" verify --run "$run")" == "$canonical" ]]
chmod -x "$skills/skills/engineering/tdd/tests.md"

# A changed declared input changes and stars only its component. Successful
# freeze is used for every custody-backed observation.
printf 'dirty tdd input\n' >>"$skills/skills/engineering/tdd/tests.md"
dirty_run="$(cd "$target" && "$freeze_command" freeze \
  --manifest "$fixture/manifest" --snapshot "$fixture/snapshot" --base HEAD \
  --workflow-identity "$identity")"
dirty="$(cd "$target" && "$command" read --run "$dirty_run")"
[[ "$(component work-on "$dirty")" == "$(component work-on "$canonical")" ]]
[[ "$(component workflow "$dirty")" == "$(component workflow "$canonical")" ]]
[[ "$(component review "$dirty")" == "$(component review "$canonical")" ]]
dirty_tdd="$(component tdd "$dirty")"
[[ "$dirty_tdd" =~ ^[0-9a-f]{12}\*$ ]]
printf 'undeclared\n' >"$skills/skills/engineering/tdd/undeclared.md"
undeclared_run="$(cd "$target" && "$freeze_command" freeze \
  --manifest "$fixture/manifest" --snapshot "$fixture/snapshot" --base HEAD \
  --workflow-identity "$identity")"
[[ "$(cd "$target" && "$command" read --run "$undeclared_run")" == "$dirty" ]]
rm "$skills/skills/engineering/tdd/undeclared.md"

# Committing byte-identical captured inputs keeps resume valid and clears only
# presentation's dirty star on a fresh capture.
git -C "$skills" add .; git -C "$skills" commit -qm 'commit dirty input'
[[ "$(cd "$target" && "$command" verify --run "$dirty_run")" == "$dirty" ]]
committed_run="$(cd "$target" && "$freeze_command" freeze \
  --manifest "$fixture/manifest" --snapshot "$fixture/snapshot" --base HEAD \
  --workflow-identity "$identity")"
committed="$(cd "$target" && "$command" read --run "$committed_run")"
[[ "$(component tdd "$committed")" == "${dirty_tdd%\*}" ]]
[[ "$(component tdd "$committed")" != *'*' ]]

# Every declared authority family retains its component boundary, and failed
# verification never discards valid frozen custody.
for case_spec in \
  'skills/personal/work-on/references/validation-evidence.md:work-on' \
  'skills/personal/work-on/references/review-state-machine.md:work-on' \
  'skills/personal/work-on/references/normative-remediation.md:work-on' \
  'skills/engineering/code-review/WORK-ON-REVIEW.md:review'; do
  path="${case_spec%:*}"
  printf 'changed authority input\n' >>"$skills/$path"
  if (cd "$target" && "$command" verify --run "$committed_run") \
      >"$fixture/authority.out" 2>"$fixture/authority.err"; then
    echo "verify accepted changed $path" >&2; exit 1
  fi
  [[ -f "$target/.git/work-on-manifest/$committed_run.provenance.json" ]]
  grep -Fq 'governing instructions changed since contract freeze' \
    "$fixture/authority.err"
  if (cd "$target" && "$freeze_command" verify --run "$committed_run") \
      >"$fixture/manifest-authority.out" 2>"$fixture/manifest-authority.err"; then
    echo "manifest verify accepted changed $path" >&2; exit 1
  fi
  grep -Fq 'current governing instruction identity does not match frozen custody' \
    "$fixture/manifest-authority.err"
  if [[ "$path" == skills/personal/work-on/references/normative-remediation.md ]]; then
    (cd "$target" && "$command" capture \
      --output "$fixture/normative-authority.json")
    normative_canonical="$(jq -r '.canonical' \
      "$fixture/normative-authority.json")"
    [[ "$(component work-on "$normative_canonical")" != \
      "$(component work-on "$committed")" ]]
    [[ "$(component work-on "$normative_canonical")" == *'*' ]]
  fi
  git -C "$skills" restore "$path"
done

# The installed harness symlink resolves the same skills checkout.
mkdir "$fixture/installed"; ln -s "$skills/skills/personal/work-on" "$fixture/installed/work-on"
installed="$fixture/installed/work-on/scripts/workflow-provenance.sh"
installed_output="$fixture/installed-capture.json"
(cd "$target" && "$installed" capture --output "$installed_output")
jq -e '.canonical | type == "string"' "$installed_output" >/dev/null

# Target workflow selection is exact and dirty state is represented only in
# the workflow component; default workflow is used when the target path is absent.
target_workflow_repo="$fixture/target-workflow"; git init -q -b main "$target_workflow_repo"
git -C "$target_workflow_repo" config user.name Test; git -C "$target_workflow_repo" config user.email test@example.invalid
mkdir "$target_workflow_repo/docs"; printf '# target workflow\n' >"$target_workflow_repo/docs/workflow.md"
target_identity="$(cd "$target_workflow_repo" && "$command" identify-workflow)"
[[ "$target_identity" != "$identity" ]]
(cd "$target_workflow_repo" && "$command" capture --output "$fixture/target-dirty.json")
[[ "$(jq -r '.canonical' "$fixture/target-dirty.json")" == *' workflow:'*'* '* ]]
git -C "$target_workflow_repo" add .; git -C "$target_workflow_repo" commit -qm workflow
(cd "$target_workflow_repo" && "$command" capture --output "$fixture/target-clean.json")
[[ "$(jq -r '.workflow' "$fixture/target-clean.json")" =~ ^[0-9a-f]{12}$ ]]

# Extracted default-workflow modules are part of the default workflow's frozen
# instruction identity. This list is hardcoded independently of the production
# array on purpose: asking provenance for its own inputs would hide the exact
# bug worth catching, a module created but never declared.
expected_default_workflow_modules=(
  skills/personal/work-on/references/default-workflow/accepted-blocker-correction-self-check.md
  skills/personal/work-on/references/default-workflow/bounded-re-adjudication.md
  skills/personal/work-on/references/default-workflow/implementation-mechanism-reset.md
)
default_identity_before="$(cd "$target" && "$command" identify-workflow)"
target_clean_workflow="$(jq -r '.workflow' "$fixture/target-clean.json")"
target_clean_work_on="$(jq -r '.["work-on"]' "$fixture/target-clean.json")"
for module in "${expected_default_workflow_modules[@]}"; do
  [[ -f "$skills/$module" ]] || {
    echo "expected default-workflow module is missing: $module" >&2; exit 1; }
  printf 'mutated module\n' >>"$skills/$module"
  mutated_identity="$(cd "$target" && "$command" identify-workflow)"
  [[ "$mutated_identity" != "$default_identity_before" ]] || {
    echo "mutating $module left the default workflow identity unchanged" >&2
    exit 1
  }
  if (cd "$target" && "$command" verify --run "$committed_run") \
      >"$fixture/module.out" 2>"$fixture/module.err"; then
    echo "verify accepted a mid-run change to $module" >&2; exit 1
  fi
  grep -Fq 'governing instructions changed since contract freeze' \
    "$fixture/module.err"
  if (cd "$target" && "$freeze_command" verify --run "$committed_run") \
      >"$fixture/module-custody.out" 2>"$fixture/module-custody.err"; then
    echo "frozen custody accepted a mid-run change to $module" >&2; exit 1
  fi
  grep -Fq 'current governing instruction identity does not match frozen custody' \
    "$fixture/module-custody.err"
  [[ "$(cd "$target_workflow_repo" && "$command" identify-workflow)" \
    == "$target_identity" ]] || {
    echo "mutating $module changed a docs/workflow.md selection" >&2; exit 1; }
  # identify-workflow exposes only the workflow component, so also capture the
  # custom-workflow run's full provenance: a default-only module wrongly added
  # to work_on_inputs would move its work-on digest while leaving workflow alone.
  (cd "$target_workflow_repo" && "$command" capture \
    --output "$fixture/target-module.json")
  [[ "$(jq -r '.workflow' "$fixture/target-module.json")" \
    == "$target_clean_workflow" ]] || {
    echo "mutating $module changed the docs/workflow.md workflow digest" >&2
    exit 1
  }
  [[ "$(jq -r '.["work-on"]' "$fixture/target-module.json")" \
    == "$target_clean_work_on" ]] || {
    echo "mutating $module changed the docs/workflow.md work-on digest" >&2
    exit 1
  }
  git -C "$skills" restore "$module"
done
[[ "$(cd "$target" && "$command" identify-workflow)" == "$default_identity_before" ]]
[[ "$(cd "$target" && "$command" verify --run "$committed_run")" == "$committed" ]]

# Invalid selected workflow objects fail rather than silently falling back.
invalid="$fixture/invalid"; git init -q -b main "$invalid"; mkdir "$invalid/docs"
mkdir "$invalid/docs/workflow.md"
if (cd "$invalid" && "$command" identify-workflow) >/dev/null 2>&1; then echo 'workflow directory fell back to default' >&2; exit 1; fi
rmdir "$invalid/docs/workflow.md"; ln -s missing "$invalid/docs/workflow.md"
if (cd "$invalid" && "$command" identify-workflow) >/dev/null 2>&1; then echo 'broken workflow symlink fell back to default' >&2; exit 1; fi
if [[ "$(id -u)" -ne 0 ]]; then
  rm "$invalid/docs/workflow.md"; printf '# unreadable\n' >"$invalid/docs/workflow.md"
  chmod 000 "$invalid/docs/workflow.md"
  if (cd "$invalid" && "$command" identify-workflow) >/dev/null 2>&1; then echo 'unreadable workflow fell back to default' >&2; exit 1; fi
  chmod 644 "$invalid/docs/workflow.md"
fi

# Unknown and hostile origins remain safe canonical pointers.
for origin in "$fixture/not-github.git" 'https://github.com/example/re"po.git' 'https://github.com/exa mple/repo.git' 'https://github.com/example/re\po.git'; do
  git -C "$skills" remote set-url origin "$origin"
  (cd "$target" && "$command" capture --output "$fixture/origin.json")
  [[ "$(jq -r '.canonical' "$fixture/origin.json")" == *'(unknown@'* ]]
done
git -C "$skills" remote set-url origin https://github.com/example/skills.git

# Capture requires Git-backed target and skills checkouts, readable declared
# inputs, and leaves an existing output untouched on failure.
if (cd "$fixture" && "$command" capture --output "$fixture/no-target.json") >/dev/null 2>&1; then echo 'capture accepted non-Git target' >&2; exit 1; fi
safe_output="$fixture/safe-output.json"; printf '{"sentinel":true}\n' >"$safe_output"
mv "$skills/skills/engineering/tdd/mocking.md" "$fixture/missing-mocking"
if (cd "$target" && "$command" capture --output "$safe_output") >/dev/null 2>&1; then echo 'capture accepted missing declared input' >&2; exit 1; fi
grep -Fqx '{"sentinel":true}' "$safe_output"
mv "$fixture/missing-mocking" "$skills/skills/engineering/tdd/mocking.md"

non_git_skills="$fixture/non-git-skills"; mkdir -p "$non_git_skills/skills"
cp -R "$skills/skills/personal" "$non_git_skills/skills/personal"
cp -R "$skills/skills/engineering" "$non_git_skills/skills/engineering"
non_git_command="$non_git_skills/skills/personal/work-on/scripts/workflow-provenance.sh"
if (cd "$target" && "$non_git_command" capture --output "$fixture/non-git.json") >/dev/null 2>&1; then echo 'capture accepted non-Git skills checkout' >&2; exit 1; fi

if (cd "$target" && "$command" capture --expected-workflow "$identity") >/dev/null 2>&1; then
  echo 'removed --expected-workflow interface was accepted' >&2; exit 1
fi
if (cd "$target" && "$command" read --run short) >/dev/null 2>&1; then
  echo 'malformed opaque Run identity was accepted' >&2; exit 1
fi

echo 'work-on workflow provenance black-box scenarios passed'
