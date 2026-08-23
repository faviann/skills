#!/usr/bin/env bash
set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mapfile -d '' suites < <(
  git -C "$ROOT" ls-files -z -- ':(glob)**/test-*.sh'
)

if [[ "${#suites[@]}" -eq 0 ]]; then
  echo "No shell test suites found." >&2
  exit 1
fi

failures=()
for suite in "${suites[@]}"; do
  printf '\n==> %s\n' "$suite"
  if (cd "$ROOT" && bash "$suite"); then
    printf 'PASS %s\n' "$suite"
  else
    status=$?
    failures+=("$suite (exit $status)")
    printf 'FAIL %s (exit %s)\n' "$suite" "$status" >&2
  fi
done

printf '\nRan %s shell test suites: %s passed, %s failed.\n' \
  "${#suites[@]}" \
  "$(( ${#suites[@]} - ${#failures[@]} ))" \
  "${#failures[@]}"

if [[ "${#failures[@]}" -gt 0 ]]; then
  printf 'Failed suites:\n' >&2
  printf '  - %s\n' "${failures[@]}" >&2
  exit 1
fi
