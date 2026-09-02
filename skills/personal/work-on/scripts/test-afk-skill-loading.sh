#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_root="$(cd "$script_dir/../../.." && pwd)"

assert_implicit() {
  local skill="$1"
  local skill_dir="$skills_root/$skill"

  [[ -r "$skill_dir/SKILL.md" ]] || {
    echo "$skill has no readable SKILL.md" >&2
    return 1
  }
  [[ -r "$skill_dir/agents/openai.yaml" ]] || {
    echo "$skill has no readable Codex metadata" >&2
    return 1
  }
  if grep -Fq 'disable-model-invocation: true' "$skill_dir/SKILL.md"; then
    echo "$skill is unavailable to model invocation" >&2
    return 1
  fi
  if grep -Fq 'allow_implicit_invocation: false' "$skill_dir/agents/openai.yaml"; then
    echo "$skill is unavailable to implicit Codex invocation" >&2
    return 1
  fi
}

assert_explicit_only() {
  local skill="$1"
  local skill_dir="$skills_root/$skill"

  [[ -r "$skill_dir/SKILL.md" && -r "$skill_dir/agents/openai.yaml" ]]
  grep -Fqx 'disable-model-invocation: true' "$skill_dir/SKILL.md"
  grep -Fqx '  allow_implicit_invocation: false' \
    "$skill_dir/agents/openai.yaml"
}

assert_implicit personal/select-issue
echo "ok - selector skill is available to noninteractive Codex"

assert_explicit_only personal/work-on
echo "ok - worker skill remains explicit-only"

assert_implicit engineering/tdd
if grep -Eq '(^|[^[:alnum:]])[$/]implement([^[:alnum:]]|$)' \
  "$skills_root/personal/work-on/SKILL.md" \
  "$skills_root/personal/work-on/references/default-workflow.md" \
  "$skills_root/personal/work-on/references/default-workflow/accepted-blocker-correction-self-check.md" \
  "$skills_root/personal/work-on/references/default-workflow/bounded-re-adjudication.md" \
  "$skills_root/personal/work-on/references/default-workflow/implementation-mechanism-reset.md"; then
  echo "work-on delegates through the explicit-only implement skill" >&2
  exit 1
fi
grep -Fq 'Scoped implementation contract:' \
  "$skills_root/personal/work-on/references/default-workflow.md"
echo "ok - delegate receives a scoped contract with an available TDD skill"

assert_implicit engineering/code-review
echo "ok - primary review skill is available to noninteractive Codex"

assert_explicit_only engineering/implement
echo "ok - implement remains explicit-only"
