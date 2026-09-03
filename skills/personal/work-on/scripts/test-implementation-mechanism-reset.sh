#!/usr/bin/env bash
set -euo pipefail

# The reset splits across the workflow spine, which keeps qualification, and a
# module, which owns what happens once an entry qualifies. Exercise only that
# extraction seam: the module exists, qualification survives in the spine so a
# run decides it with nothing preloaded, remediation reaches the module, and a
# delegate-first dispatch carries its content rather than a skills-checkout
# path. Code review owns the semantic fidelity of the moved prose.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

WORKFLOW="$skill_dir/references/default-workflow.md"
MODULE="$skill_dir/references/default-workflow/implementation-mechanism-reset.md"

failures=0
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

flatten() {
  local source="$1"
  local flat="$fixture_dir/$(printf '%s' "${source#"$skill_dir/"}" | tr '/' '_')"
  [[ -f "$flat" ]] || awk '
    /^[[:space:]]*$/ { print paragraph; paragraph = ""; next }
    { paragraph = (paragraph == "" ? $0 : paragraph " " $0) }
    END { print paragraph }
  ' "$source" | tr -s ' ' >"$flat"
  printf '%s' "$flat"
}

has() {
  if ! grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3"
  fi
}

remediation="$fixture_dir/remediation-step.md"
awk '/^## / { inside = ($0 ~ /^## 5\./) } inside { print }' \
  "$WORKFLOW" >"$remediation"
if [[ ! -s "$MODULE" || ! -s "$remediation" ]]; then
  fail 'the reset has a module reached from the adjudicate-and-remediate step'
  printf '\n%s implementation-mechanism-reset assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

## Qualification is decidable from the spine with nothing preloaded.
has "$remediation" '\*\*Support loop\*\*' \
  'the support-loop entry is defined in the spine'
has "$remediation" '\*\*Accepted incompatibility\*\*' \
  'the accepted-incompatibility entry is defined in the spine'
echo 'ok - qualification is decidable from the spine alone'

## Remediation reaches the module, and a delegate-first dispatch carries it as
## content because that delegate acts with no primary round trip.
has "$remediation" \
  '(when|once) either entry qualifies.{0,120}`references/default-workflow/implementation-mechanism-reset\.md`' \
  'the call site names the module its trigger reaches'
has "$remediation" \
  'read `references/default-workflow/implementation-mechanism-reset\.md` at this dispatch' \
  'every remediation dispatch reads the reset contract at that point'
has "$remediation" \
  'supply it.{0,120}as content rather than as a path' \
  'the delegate receives the reset contract as content rather than a path'
echo 'ok - remediation reaches the module and dispatches it as content'

if (( failures > 0 )); then
  printf '\n%s implementation-mechanism-reset assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll implementation-mechanism-reset contract assertions held.\n'
