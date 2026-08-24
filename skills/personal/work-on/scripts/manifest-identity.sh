#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# Canonicalize trusted sources, bind a materialized manifest to those exact
# snapshot bytes and its pre-implementation commit, then verify before reuse.

staged=""
workflow_staged=""
cleanup() {
  [[ -z "$staged" ]] || rm -f -- "$staged"
  [[ -z "$workflow_staged" ]] || rm -f -- "$workflow_staged"
}
trap cleanup EXIT

fail() {
  printf 'manifest identity: %s\n' "$1" >&2
  exit 1
}

usage() {
  fail 'usage: manifest-identity.sh snapshot --input FILE --output FILE | freeze --manifest FILE --snapshot FILE --base REF --workflow-identity SHA256 | verify --manifest FILE --snapshot FILE'
}

subcommand="${1:-}"
shift || true
case "$subcommand" in
  snapshot)
    (( $# == 4 )) && [[ "$1" == --input && "$3" == --output ]] \
      || usage
    sources="$2"
    output="$4"
    ;;
  freeze)
    (( $# == 8 )) \
      && [[ "$1" == --manifest && "$3" == --snapshot && "$5" == --base \
        && "$7" == --workflow-identity ]] \
      || usage
    manifest="$2"
    snapshot="$4"
    base_ref="$6"
    workflow_identity="$8"
    ;;
  verify)
    (( $# == 4 )) && [[ "$1" == --manifest && "$3" == --snapshot ]] \
      || usage
    manifest="$2"
    snapshot="$4"
    ;;
  *) usage ;;
esac

if [[ "$subcommand" == snapshot ]]; then
  command -v jq >/dev/null 2>&1 || fail 'snapshot creation requires jq'
  [[ -f "$sources" && ! -L "$sources" && -r "$sources" ]] \
    || fail 'trusted sources are missing or unsafe'
  [[ ! -L "$output" ]] || fail 'trusted snapshot output is unsafe'
  output_dir="$(dirname -- "$output")"
  [[ -d "$output_dir" && ! -L "$output_dir" ]] \
    || fail 'trusted snapshot directory is missing or unsafe'
  output_dir="$(cd -P -- "$output_dir" && pwd -P)"
  staged="$(umask 077 && mktemp "$output_dir/.trusted-snapshot.XXXXXX")"
  if ! jq -ce '
    . as $records
    | if (
        type == "array" and length > 0
        and all(.[];
          type == "object"
          and keys == ["body", "source"]
          and (.source | type == "string" and length > 0)
          and (.body | type == "string"))
        and ([.[].source] | unique | length) == ($records | length)
      )
      then sort_by(.source)[] | {source: .source, body: .body}
      else error("trusted sources must be unique source/body string records")
      end
  ' "$sources" >"$staged" 2>/dev/null; then
    fail 'trusted sources are invalid'
  fi
  chmod 600 "$staged"
  mv -f -- "$staged" "$output"
  staged=""
  exit 0
fi

common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || fail 'run from the target Git repository'
git_dir="$(git rev-parse --path-format=absolute --absolute-git-dir 2>/dev/null)" \
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
  [[ "$workflow_identity" =~ ^[0-9a-f]{64}$ ]] \
    || fail 'selected workflow identity is malformed'
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
  workflow_boundary="$git_dir/work-on-provenance.workflow-sha256"
  if [[ -e "$workflow_boundary" || -L "$workflow_boundary" ]]; then
    [[ -f "$workflow_boundary" && ! -L "$workflow_boundary" ]] \
      || fail 'workflow provenance boundary is unsafe'
  fi
  workflow_staged="$(umask 077 && mktemp "$git_dir/.workflow-boundary.XXXXXX")"
  printf '%s\n' "$workflow_identity" >"$workflow_staged"
  chmod 600 "$workflow_staged"
  rm -f -- "$git_dir/work-on-provenance.json"
  mv -f -- "$staged" "$manifest"
  staged=""
  mv -f -- "$workflow_staged" "$workflow_boundary"
  workflow_staged=""
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
