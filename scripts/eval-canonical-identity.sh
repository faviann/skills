#!/usr/bin/env bash
set -euo pipefail

# The one executable definition of the canonical identity used by
# .agents/evals/work-on-normative-remediation.md for both its
# measured-instruction identity and its per-case instrument-input identity.
#
# Identity is SHA-256 over a canonical byte stream. Each component contributes
# its label, its canonical repository-relative name, its byte count, and its
# exact bytes, every field NUL-terminated:
#
#   <label> NUL <canonical-name> NUL <byte-count> NUL <bytes> NUL
#
# Components are framed in the order given, so the declared order is part of
# the identity. Any change to a label, a canonical name, or a component's bytes
# yields a different identity, which is what makes an affected eval case
# re-executable rather than pooled across versions.

usage='usage: eval-canonical-identity.sh LABEL CANONICAL_NAME PATH [LABEL CANONICAL_NAME PATH]...'
fail() { printf 'canonical identity: %s\n' "$1" >&2; exit 1; }

(( $# >= 3 && $# % 3 == 0 )) || fail "$usage"

stream="$(umask 077 && mktemp "${TMPDIR:-/tmp}/eval-canonical-identity.XXXXXX")"
trap 'rm -f -- "$stream"' EXIT

while (( $# )); do
  label="$1" canonical_name="$2" source="$3"
  shift 3
  [[ -n "$label" && -n "$canonical_name" ]] ||
    fail 'every component needs a label and a canonical name'
  [[ -f "$source" && -r "$source" ]] ||
    fail "component source is unreadable: $source"
  bytes="$(LC_ALL=C wc -c <"$source" | tr -d '[:space:]')"
  {
    printf '%s\0%s\0%s\0' "$label" "$canonical_name" "$bytes"
    cat -- "$source"
    printf '\0'
  } >>"$stream"
done

sha256sum <"$stream" | cut -d' ' -f1
