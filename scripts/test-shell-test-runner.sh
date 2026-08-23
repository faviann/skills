#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RUNNER="$ROOT/scripts/run-shell-tests.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

mkdir -p "$fixture/scripts" "$fixture/suites"
cp "$RUNNER" "$fixture/scripts/run-shell-tests.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo intentional failure' \
  'exit 23' \
  >"$fixture/suites/test-01-failure.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo later suite ran' \
  >"$fixture/suites/test-02-success.sh"

git -C "$fixture" init -q
git -C "$fixture" add scripts/run-shell-tests.sh suites

if output="$(bash "$fixture/scripts/run-shell-tests.sh" 2>&1)"; then
  echo "runner unexpectedly succeeded with a failing suite" >&2
  exit 1
fi

grep -Fq 'FAIL suites/test-01-failure.sh (exit 23)' <<<"$output"
grep -Fq 'later suite ran' <<<"$output"
grep -Fq 'PASS suites/test-02-success.sh' <<<"$output"
grep -Fq 'Ran 2 shell test suites: 1 passed, 1 failed.' <<<"$output"

echo "shell test runner failure scenarios passed"
