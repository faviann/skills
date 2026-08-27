#!/usr/bin/env bash
set -euo pipefail

# Contract freeze is the authority point for Run identity and complete custody.
# A pending manifest is published after its siblings. Its atomic replacement
# with the accepted manifest is the irreversible success point for readers.

script_root="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
staging_dir=""
cleanup() { [[ -z "$staging_dir" ]] || rm -rf -- "$staging_dir"; }
trap cleanup EXIT

fail() { printf 'manifest identity: %s\n' "$1" >&2; exit 1; }
usage() { fail 'usage: manifest-identity.sh freeze --manifest FILE --snapshot FILE --base REF --workflow-identity SHA256 | read --run ID | verify --run ID'; }

subcommand="${1:-}"; shift || true
case "$subcommand" in
  freeze)
    (( $# == 8 )) && [[ "$1" == --manifest && "$3" == --snapshot && "$5" == --base && "$7" == --workflow-identity ]] || usage
    manifest_source="$2"; snapshot_source="$4"; base_ref="$6"; retained_workflow_identity="$8"
    ;;
  read|verify)
    (( $# == 2 )) && [[ "$1" == --run ]] || usage
    run_identity="$2"
    [[ "$run_identity" =~ ^[A-Za-z0-9._-]{8,64}$ ]] || fail 'Run identity is malformed'
    ;;
  *) usage ;;
esac

common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || fail 'run from the target Git repository'
custody_dir="$common_dir/work-on-manifest"

binding_digest() {
  local identity="$1" snapshot_sha="$2" base_sha="$3" provenance_sha="$4" body="$5" first_line="$6"
  { printf '%s\n%s\n%s\n%s\n' "$identity" "$snapshot_sha" "$base_sha" "$provenance_sha"; tail -n "+$first_line" -- "$body"; } | sha256sum | cut -d' ' -f1
}

validate_complete_custody() {
  local manifest="$1" snapshot="$2" provenance="$3"
  [[ -d "$custody_dir" && ! -L "$custody_dir" && -f "$manifest" && ! -L "$manifest" && -r "$manifest" && -f "$snapshot" && ! -L "$snapshot" && -r "$snapshot" && -f "$provenance" && ! -L "$provenance" && -r "$provenance" ]] || fail "complete custody is missing or unsafe for Run identity $run_identity"
  [[ "$(stat -c '%a' "$custody_dir")" == 700 && "$(stat -c '%a' "$manifest")" == 600 && "$(stat -c '%a' "$snapshot")" == 600 && "$(stat -c '%a' "$provenance")" == 600 ]] || fail 'frozen custody is not owner-only'
}

if [[ "$subcommand" == freeze ]]; then
  [[ -f "$manifest_source" && ! -L "$manifest_source" && -r "$manifest_source" && -s "$manifest_source" ]] || fail 'manifest body is missing or unsafe'
  [[ -f "$snapshot_source" && ! -L "$snapshot_source" && -r "$snapshot_source" && -s "$snapshot_source" ]] || fail 'trusted snapshot is missing or unsafe'
  [[ "$retained_workflow_identity" =~ ^[0-9a-f]{64}$ ]] || fail 'selected workflow identity is malformed'
  [[ ! "$(sed -n '1p' "$manifest_source")" =~ ^(run-identity|freeze-state|trusted-snapshot-sha256|pre-implementation-base|workflow-provenance-sha256|manifest-binding-sha256)[[:space:]] ]] || fail 'manifest body already carries identity'
  base_sha="$(git rev-parse --verify "${base_ref}^{commit}" 2>/dev/null)" || fail 'pre-implementation base is not a commit'
  [[ "$base_sha" =~ ^[0-9a-f]{40,64}$ ]] || fail 'pre-implementation base is malformed'
  current_workflow_identity="$($script_root/workflow-provenance.sh identify-workflow)" || fail 'could not identify selected workflow'
  [[ "$current_workflow_identity" == "$retained_workflow_identity" ]] || fail 'selected workflow changed since the closability gate read it'

  if [[ -e "$custody_dir" || -L "$custody_dir" ]]; then
    [[ -d "$custody_dir" && ! -L "$custody_dir" ]] || fail 'custody directory is unsafe'
  else
    (umask 077 && mkdir -p -- "$custody_dir")
  fi
  chmod 700 "$custody_dir"
  while :; do
    run_identity="$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
    manifest="$custody_dir/$run_identity.md"
    snapshot="$custody_dir/$run_identity.trusted-snapshot.json"
    provenance="$custody_dir/$run_identity.provenance.json"
    [[ ! -e "$manifest" && ! -L "$manifest" && ! -e "$snapshot" && ! -L "$snapshot" && ! -e "$provenance" && ! -L "$provenance" ]] && break
  done

  staging_dir="$(umask 077 && mktemp -d "$custody_dir/.freeze.XXXXXX")"
  staged_accepted_manifest="$staging_dir/accepted-manifest"
  staged_pending_manifest="$staging_dir/pending-manifest"
  staged_snapshot="$staging_dir/snapshot"
  staged_provenance="$staging_dir/provenance"
  cp -- "$snapshot_source" "$staged_snapshot"
  chmod 600 "$staged_snapshot"
  "$script_root/workflow-provenance.sh" capture --output "$staged_provenance"
  captured_workflow_identity="$(jq -er '.workflow_identity' "$staged_provenance" 2>/dev/null)" || fail 'captured provenance is invalid'
  [[ "$captured_workflow_identity" == "$retained_workflow_identity" ]] || fail 'selected workflow changed during contract freeze'
  snapshot_digest="$(sha256sum <"$staged_snapshot" | cut -d' ' -f1)"
  provenance_digest="$(sha256sum <"$staged_provenance" | cut -d' ' -f1)"
  binding="$(binding_digest "$run_identity" "$snapshot_digest" "$base_sha" "$provenance_digest" "$manifest_source" 1)"
  {
    printf 'run-identity %s\n' "$run_identity"
    printf 'freeze-state accepted\n'
    printf 'trusted-snapshot-sha256 %s\n' "$snapshot_digest"
    printf 'pre-implementation-base %s\n' "$base_sha"
    printf 'workflow-provenance-sha256 %s\n' "$provenance_digest"
    printf 'manifest-binding-sha256 %s\n---\n' "$binding"
    cat -- "$manifest_source"
  } >"$staged_accepted_manifest"
  chmod 600 "$staged_accepted_manifest"
  printf 'run-identity %s\nfreeze-state pending\n' "$run_identity" >"$staged_pending_manifest"
  chmod 600 "$staged_pending_manifest"
  mv -- "$staged_provenance" "$provenance"
  mv -- "$staged_snapshot" "$snapshot"
  mv -- "$staged_pending_manifest" "$manifest"
  mv -- "$staged_accepted_manifest" "$manifest"
  rmdir -- "$staging_dir"
  staging_dir=""
  printf '%s\n' "$run_identity"
  exit 0
fi

manifest="$custody_dir/$run_identity.md"
snapshot="$custody_dir/$run_identity.trusted-snapshot.json"
provenance="$custody_dir/$run_identity.provenance.json"
validate_complete_custody "$manifest" "$snapshot" "$provenance"
mapfile -t header < <(sed -n '1,7p' "$manifest")
(( ${#header[@]} == 7 )) && [[ "${header[6]}" == --- ]] || fail 'manifest identity is malformed'
recorded_identity="${header[0]#run-identity }"
recorded_snapshot="${header[2]#trusted-snapshot-sha256 }"
recorded_base="${header[3]#pre-implementation-base }"
recorded_provenance="${header[4]#workflow-provenance-sha256 }"
recorded_binding="${header[5]#manifest-binding-sha256 }"
[[ "${header[0]}" == "run-identity $recorded_identity" && "$recorded_identity" == "$run_identity" ]] || fail 'manifest Run identity does not match custody'
[[ "${header[1]}" == 'freeze-state accepted' ]] || fail 'contract freeze was not accepted'
[[ "${header[2]}" == "trusted-snapshot-sha256 $recorded_snapshot" && "$recorded_snapshot" =~ ^[0-9a-f]{64}$ ]] || fail 'manifest snapshot identity is malformed'
[[ "${header[3]}" == "pre-implementation-base $recorded_base" && "$recorded_base" =~ ^[0-9a-f]{40,64}$ ]] || fail 'manifest base identity is malformed'
[[ "${header[4]}" == "workflow-provenance-sha256 $recorded_provenance" && "$recorded_provenance" =~ ^[0-9a-f]{64}$ ]] || fail 'manifest provenance identity is malformed'
[[ "${header[5]}" == "manifest-binding-sha256 $recorded_binding" && "$recorded_binding" =~ ^[0-9a-f]{64}$ ]] || fail 'manifest binding is malformed'
[[ "$(sha256sum <"$snapshot" | cut -d' ' -f1)" == "$recorded_snapshot" ]] || fail 'trusted snapshot does not match frozen manifest'
[[ "$(sha256sum <"$provenance" | cut -d' ' -f1)" == "$recorded_provenance" ]] || fail 'captured provenance does not match frozen manifest'
resolved_base="$(git rev-parse --verify "${recorded_base}^{commit}" 2>/dev/null)" || fail 'frozen pre-implementation base is unavailable'
[[ "$resolved_base" == "$recorded_base" ]] || fail 'frozen pre-implementation base is not canonical'
[[ "$(binding_digest "$recorded_identity" "$recorded_snapshot" "$recorded_base" "$recorded_provenance" "$manifest" 8)" == "$recorded_binding" ]] || fail 'frozen manifest is corrupt'
if [[ "$subcommand" == verify ]]; then
  "$script_root/workflow-provenance.sh" verify --run "$run_identity" >/dev/null || fail 'current governing instruction identity does not match frozen custody'
fi
printf '%s\n' "$recorded_base"
