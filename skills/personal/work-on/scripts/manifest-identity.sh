#!/usr/bin/env bash
set -euo pipefail

# Bind an already-materialized manifest to its exact trusted-snapshot bytes and
# pre-implementation commit, then verify that binding before reuse.

staged=""
cleanup() {
  [[ -z "$staged" ]] || rm -f -- "$staged"
}
trap cleanup EXIT

fail() {
  printf 'manifest identity: %s\n' "$1" >&2
  exit 1
}

usage() {
  fail 'usage: manifest-identity.sh freeze --manifest FILE --snapshot FILE --base REF | verify --manifest FILE --snapshot FILE'
}

subcommand="${1:-}"
shift || true
case "$subcommand" in
  freeze)
    (( $# == 6 )) \
      && [[ "$1" == --manifest && "$3" == --snapshot && "$5" == --base ]] \
      || usage
    manifest="$2"
    snapshot="$4"
    base_ref="$6"
    ;;
  verify)
    (( $# == 4 )) && [[ "$1" == --manifest && "$3" == --snapshot ]] \
      || usage
    manifest="$2"
    snapshot="$4"
    ;;
  *) usage ;;
esac

common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || fail 'run from the target Git repository'
manifest_dir="$(dirname -- "$manifest")"
[[ -d "$manifest_dir" && ! -L "$manifest_dir" ]] \
  || fail 'manifest directory is missing or unsafe'
manifest_dir="$(cd -P -- "$manifest_dir" && pwd -P)"
[[ "$manifest_dir" == "$common_dir/work-on-manifest" ]] \
  || fail 'manifest must be in the target repository Git common directory'
[[ -f "$manifest" && ! -L "$manifest" && -r "$manifest" ]] \
  || fail 'manifest is missing or unsafe'
[[ -f "$snapshot" && ! -L "$snapshot" && -r "$snapshot" ]] \
  || fail 'trusted snapshot is missing or unsafe'

snapshot_digest="$(sha256sum <"$snapshot" | cut -d' ' -f1)"
[[ "$snapshot_digest" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'could not identify trusted snapshot'

binding_digest() {
  local snapshot_sha="$1" base_sha="$2" body="$3" first_line="$4"
  {
    printf '%s\n%s\n' "$snapshot_sha" "$base_sha"
    tail -n "+$first_line" -- "$body"
  } | sha256sum | cut -d' ' -f1
}

if [[ "$subcommand" == freeze ]]; then
  [[ -s "$manifest" ]] || fail 'manifest body is empty'
  [[ ! "$(sed -n '1p' "$manifest")" =~ ^(trusted-snapshot-sha256|pre-implementation-base|manifest-binding-sha256)[[:space:]] ]] \
    || fail 'manifest body already carries identity'
  base_sha="$(git rev-parse --verify "${base_ref}^{commit}" 2>/dev/null)" \
    || fail 'pre-implementation base is not a commit'
  [[ "$base_sha" =~ ^[0-9a-f]{40,64}$ ]] \
    || fail 'pre-implementation base is malformed'
  binding="$(binding_digest "$snapshot_digest" "$base_sha" "$manifest" 1)"

  chmod 700 "$manifest_dir"
  staged="$(umask 077 && mktemp "$manifest_dir/.manifest.XXXXXX")"
  {
    printf 'trusted-snapshot-sha256 %s\n' "$snapshot_digest"
    printf 'pre-implementation-base %s\n' "$base_sha"
    printf 'manifest-binding-sha256 %s\n---\n' "$binding"
    cat -- "$manifest"
  } >"$staged"
  chmod 600 "$staged"
  mv -f -- "$staged" "$manifest"
  staged=""
  exit 0
fi

mapfile -t header < <(sed -n '1,4p' "$manifest")
(( ${#header[@]} == 4 )) && [[ "${header[3]}" == '---' ]] \
  || fail 'manifest identity is malformed'
recorded_snapshot="${header[0]#trusted-snapshot-sha256 }"
recorded_base="${header[1]#pre-implementation-base }"
recorded_binding="${header[2]#manifest-binding-sha256 }"
[[ "${header[0]}" == "trusted-snapshot-sha256 $recorded_snapshot" \
  && "$recorded_snapshot" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'manifest snapshot identity is malformed'
[[ "${header[1]}" == "pre-implementation-base $recorded_base" \
  && "$recorded_base" =~ ^[0-9a-f]{40,64}$ ]] \
  || fail 'manifest base identity is malformed'
[[ "${header[2]}" == "manifest-binding-sha256 $recorded_binding" \
  && "$recorded_binding" =~ ^[0-9a-f]{64}$ ]] \
  || fail 'manifest binding is malformed'

[[ "$snapshot_digest" == "$recorded_snapshot" ]] \
  || fail 'trusted snapshot does not match frozen manifest'
resolved_base="$(git rev-parse --verify "${recorded_base}^{commit}" 2>/dev/null)" \
  || fail 'frozen pre-implementation base is unavailable'
[[ "$resolved_base" == "$recorded_base" ]] \
  || fail 'frozen pre-implementation base is not canonical'
[[ "$(binding_digest "$recorded_snapshot" "$recorded_base" "$manifest" 5)" \
  == "$recorded_binding" ]] || fail 'frozen manifest is corrupt'

printf '%s\n' "$recorded_base"
