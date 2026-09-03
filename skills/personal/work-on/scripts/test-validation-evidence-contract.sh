#!/usr/bin/env bash
set -euo pipefail

# No shipped work-on script may decide validation from cost, duration, or
# telemetry. The instruction-prose assertions this suite carried were removed:
# grepping semantic prose does not make that prose mechanically authoritative,
# and those properties belong to review. See docs/agents/testing.md.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

# What may not exist is an executable decision keyed to observed duration.
script_cost_predicates=(
  'expensive'
  'materially costly'
  'materially_costly'
  '(skip|reuse|rerun|classify).{0,80}(duration|elapsed|timing|telemetry)'
  '(duration|elapsed|timing|telemetry).{0,80}(skip|reuse|rerun|classify)'
)
for candidate_script in "$skill_dir"/scripts/*.sh; do
  case "$(basename "$candidate_script")" in test-*) continue ;; esac
  for pattern in "${script_cost_predicates[@]}"; do
    if grep -Eqi -- "$pattern" "$candidate_script"; then
      fail "no work-on script decides validation from cost or duration (${candidate_script##*/}: $pattern)"
    fi
  done
done

if (( failures > 0 )); then
  printf '\n%s validation-evidence contract assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll validation-evidence contract assertions held.\n'
