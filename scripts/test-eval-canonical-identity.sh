#!/usr/bin/env bash
set -euo pipefail

# Black-box coverage of scripts/eval-canonical-identity.sh through its only
# supported interface: LABEL CANONICAL_NAME PATH triples in, one digest out.
#
# Expected digests are independent constants computed outside this suite; the
# canonical framing is never reimplemented here. That keeps one executable
# definition of the predicate, per docs/agents/testing.md.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
identity="$root/scripts/eval-canonical-identity.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
check() {
  local what="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok - %s\n' "$what"
  else
    printf 'not ok - %s\n  expected: %s\n  actual:   %s\n' \
      "$what" "$expected" "$actual" >&2
    failures=$(( failures + 1 ))
  fi
}

printf 'alpha\n' >"$work/a"
printf 'beta\n' >"$work/b"
printf 'alphA\n' >"$work/a-mutated"

# One component, fixed vector.
check 'a fixed one-component input produces the known canonical identity' \
  7b979471d73ade01605b4ed76bc215859aeb40442e4ef01300e78aac2ff5554c \
  "$("$identity" instruction skills/a.md "$work/a")"

# Two components, fixed vector: the eval frames several components per identity.
check 'a fixed two-component input produces the known canonical identity' \
  2b930919542e5f8480ed9f8ec97003f24bb2c6681d017e394414a20ac99ab980 \
  "$("$identity" instruction skills/a.md "$work/a" package P1 "$work/b")"

# Declared component order is part of the identity the eval records.
check 'reversing the declared component order produces the known other identity' \
  f859e580445ee723dd4b957337301ff47aaf5bc407e80445f6dcc7f99ac66d66 \
  "$("$identity" package P1 "$work/b" instruction skills/a.md "$work/a")"

# Identical inputs are stable across invocations.
check 'identical inputs produce identical identity' \
  "$("$identity" instruction skills/a.md "$work/a")" \
  "$("$identity" instruction skills/a.md "$work/a")"

# Each identity-bearing field moves the identity.
baseline="$("$identity" instruction skills/a.md "$work/a")"
for variant in \
  'changed component bytes:instruction:skills/a.md:a-mutated' \
  'changed label:measured:skills/a.md:a' \
  'changed canonical name:instruction:skills/renamed.md:a'; do
  IFS=: read -r what label name file <<<"$variant"
  if [[ "$("$identity" "$label" "$name" "$work/$file")" == "$baseline" ]]; then
    printf 'not ok - %s changes the identity\n' "$what" >&2
    failures=$(( failures + 1 ))
  else
    printf 'ok - %s changes the identity\n' "$what"
  fi
done

# The interface refuses inputs it cannot frame.
for bad in 'instruction skills/a.md' "instruction skills/a.md $work/missing"; do
  # shellcheck disable=SC2086
  if "$identity" $bad >/dev/null 2>&1; then
    printf 'not ok - refuses unusable arguments (%s)\n' "$bad" >&2
    failures=$(( failures + 1 ))
  fi
done
printf 'ok - incomplete triples and unreadable sources are refused\n'

if (( failures > 0 )); then
  printf '\n%s canonical-identity assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\ncanonical identity black-box scenarios passed\n'
