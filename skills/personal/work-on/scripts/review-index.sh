#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

# One Review-index package per review gate. Creation materializes every
# component into an owner-only temporary package and then places the index at
# its final path: that placement is the publication boundary. Successful
# creation additionally requires the full package verification to pass before
# it returns the index path and expected SHA-256, so the existence of a package
# proves no verification or lifecycle result on its own. Every reader
# authenticates a private snapshot of the bytes it is about to act on, so no
# operation hashes one object and then acts on another.

readonly singleton_roles=(
  trusted-contract
  review-assignment
  validation-evidence-policy
  standards
  validation-surface-manifest
)

snapshots=()
cleanup() { (( ${#snapshots[@]} == 0 )) || rm -f -- "${snapshots[@]}"; }
trap cleanup EXIT

fail() { printf 'review index: %s\n' "$1" >&2; exit 1; }
usage() { fail 'usage: review-index.sh create --gate-kind KIND --comparison-commit OID --comparison-tree OID --candidate-commit OID --candidate-tree OID --trusted-contract FILE --review-assignment FILE --validation-evidence-policy FILE --standards FILE --validation-surface-manifest FILE [--evidence FILE]... | verify --index PATH --index-sha256 SHA256 | read --index PATH --index-sha256 SHA256 --role ROLE [--evidence-sha256 SHA256]'; }

digest_of() { sha256sum <"$1" | cut -d' ' -f1; }

# Capture one file into a private owner-only snapshot. The caller hashes and
# consumes that snapshot, never the supplied pathname again.
captured_snapshot=""
capture() {
  captured_snapshot="$(umask 077 && mktemp "${TMPDIR:-/tmp}/work-on-review-index-snapshot.XXXXXX")"
  snapshots+=("$captured_snapshot")
  cp -- "$1" "$captured_snapshot" || fail 'could not capture the supplied file'
}

# Custody is proven for every path component from the package root down, so a
# symlinked intermediate directory cannot smuggle a member in from outside the
# package. Content is settled separately, by digest.
check_directory() {
  [[ -d "$1" && ! -L "$1" && "$(stat -c '%a' "$1" 2>/dev/null)" == 700 ]] || fail "package directory $1 is missing or unsafe"
}
check_regular() {
  [[ -f "$1" && ! -L "$1" && -r "$1" && "$(stat -c '%a' "$1" 2>/dev/null)" == 600 ]] || fail "package member $1 is missing or unsafe"
}

# The one definition of the canonical v1 serialization. Creation emits the index
# through it, and parsing reconstructs the index through it, so the format has a
# single source of truth.
emit_canonical_index() {
  local entry role locator member_digest
  printf 'work-on-review-index/v1\n'
  printf 'gate-kind %s\n' "$index_gate_kind"
  printf 'comparison-role %s\n' "$index_comparison_role"
  printf 'comparison-commit %s\n' "$index_comparison_commit"
  printf 'comparison-tree %s\n' "$index_comparison_tree"
  printf 'candidate-commit %s\n' "$index_candidate_commit"
  printf 'candidate-tree %s\n' "$index_candidate_tree"
  for entry in "${index_members[@]}"; do
    read -r role locator member_digest <<<"$entry"
    printf 'component %s %s %s\n' "$role" "$locator" "$member_digest"
  done
}

# Authenticate the index and parse its shape. Both readers call this, so the
# schema has one definition. Every check reads the authenticated snapshot,
# never the index pathname, so the bytes that were hashed are the bytes that
# govern.
index_package_root=""
index_gate_kind=""; index_comparison_role=""
index_comparison_commit=""; index_comparison_tree=""
index_candidate_commit=""; index_candidate_tree=""
index_members=()
parse_index() {
  local index_path="$1" expected_index_sha="$2"
  local index_snapshot canonical role locator_digest member_digest
  local previous_digest="" position
  local -a index_lines=()

  [[ "$index_path" == /* ]] || fail 'index path is not absolute'
  [[ "$(basename -- "$index_path")" == index ]] || fail 'index path does not name a package index'
  index_package_root="$(dirname -- "$index_path")"
  check_directory "$index_package_root"
  check_regular "$index_path"
  capture "$index_path"
  index_snapshot="$captured_snapshot"
  [[ "$(digest_of "$index_snapshot")" == "$expected_index_sha" ]] || fail 'index identity does not match the supplied SHA-256'

  mapfile -t index_lines <"$index_snapshot"
  [[ "${index_lines[0]:-}" == 'work-on-review-index/v1' ]] || fail 'index schema version is missing or unsupported'
  (( ${#index_lines[@]} >= 7 + ${#singleton_roles[@]} )) || fail 'index is missing required members'

  [[ "${index_lines[1]}" =~ ^gate-kind\ (cumulative|delta)$ ]] || fail 'gate kind is missing or unknown'
  index_gate_kind="${BASH_REMATCH[1]}"
  [[ "${index_lines[2]}" =~ ^comparison-role\ (comparison-base|reviewed-anchor)$ ]] || fail 'comparison role is missing or unknown'
  index_comparison_role="${BASH_REMATCH[1]}"
  [[ "${index_lines[3]}" =~ ^comparison-commit\ ([0-9a-f]{40,64})$ ]] || fail 'comparison commit identity is missing or malformed'
  index_comparison_commit="${BASH_REMATCH[1]}"
  [[ "${index_lines[4]}" =~ ^comparison-tree\ ([0-9a-f]{40,64})$ ]] || fail 'comparison tree identity is missing or malformed'
  index_comparison_tree="${BASH_REMATCH[1]}"
  [[ "${index_lines[5]}" =~ ^candidate-commit\ ([0-9a-f]{40,64})$ ]] || fail 'candidate commit identity is missing or malformed'
  index_candidate_commit="${BASH_REMATCH[1]}"
  [[ "${index_lines[6]}" =~ ^candidate-tree\ ([0-9a-f]{40,64})$ ]] || fail 'candidate tree identity is missing or malformed'
  index_candidate_tree="${BASH_REMATCH[1]}"

  case "$index_gate_kind:$index_comparison_role" in
    cumulative:comparison-base|delta:reviewed-anchor) ;;
    *) fail 'gate kind and comparison role disagree' ;;
  esac

  # Required singleton roles are positional, so a missing, duplicated, unknown,
  # reordered, or malformed member is one rejection rather than four rules.
  index_members=()
  position=7
  for role in "${singleton_roles[@]}"; do
    [[ "${index_lines[$position]}" =~ ^component\ ([a-z-]+)\ components/([a-z-]+)\ ([0-9a-f]{64})$ && "${BASH_REMATCH[1]}" == "$role" && "${BASH_REMATCH[2]}" == "$role" ]] || fail "index member $(( position + 1 )) is not the canonical $role component"
    index_members+=("$role components/$role ${BASH_REMATCH[3]}")
    position=$(( position + 1 ))
  done

  for (( ; position < ${#index_lines[@]}; position++ )); do
    [[ "${index_lines[$position]}" =~ ^component\ evidence\ components/evidence/([0-9a-f]{64})\ ([0-9a-f]{64})$ ]] || fail "index member $(( position + 1 )) is unknown or malformed"
    locator_digest="${BASH_REMATCH[1]}"; member_digest="${BASH_REMATCH[2]}"
    [[ "$locator_digest" == "$member_digest" ]] || fail 'an evidence member is not addressed by its own identity'
    [[ "$locator_digest" > "$previous_digest" ]] || fail 'evidence members are duplicated or not canonically ordered'
    previous_digest="$locator_digest"
    index_members+=("evidence components/evidence/$locator_digest $member_digest")
  done

  # Bash cannot hold every byte a file can: mapfile truncates a line at an
  # embedded NUL, so a schema check over the parsed strings alone would accept
  # bytes the file never contained. Reconstructing the canonical index and
  # comparing bytes proves the authenticated snapshot is exactly the canonical
  # representation of the parsed v1 object, newline termination included.
  canonical="$(umask 077 && mktemp "${TMPDIR:-/tmp}/work-on-review-index-canonical.XXXXXX")"
  snapshots+=("$canonical")
  emit_canonical_index >"$canonical"
  cmp -s "$canonical" "$index_snapshot" || fail 'index is not the canonical v1 byte representation of its members'
}

# A pinned endpoint must resolve to exactly itself and to its separately
# supplied tree. Nothing canonicalizes a live ref into an endpoint.
resolve_endpoint() {
  local label="$1" commit="$2" tree="$3"
  [[ "$(git rev-parse --verify --quiet "${commit}^{commit}" 2>/dev/null)" == "$commit" ]] || fail "$label commit identity is not a canonical full object identity in this repository"
  [[ "$(git rev-parse --verify --quiet "${tree}^{tree}" 2>/dev/null)" == "$tree" ]] || fail "$label tree identity is not a canonical full object identity in this repository"
  [[ "$(git rev-parse --verify --quiet "${commit}^{tree}" 2>/dev/null)" == "$tree" ]] || fail "$label commit does not resolve to its declared tree"
}

check_member_custody() {
  local role="$1" locator="$2"
  check_directory "$index_package_root/components"
  [[ "$role" != evidence ]] || check_directory "$index_package_root/components/evidence"
  check_regular "$index_package_root/$locator"
}

verify_component() {
  local role="$1" locator="$2" member_digest="$3"
  check_member_custody "$role" "$locator"
  [[ "$(digest_of "$index_package_root/$locator")" == "$member_digest" ]] || fail "component $role does not match its frozen digest"
}

# The single package predicate. Both the public verify command and creation's
# pre-return check call this, so no weaker second predicate can drift from it.
# It prints the canonical member enumeration only after the whole package
# verifies.
verify_package() {
  local entry role locator member_digest

  parse_index "$1" "$2"
  resolve_endpoint comparison "$index_comparison_commit" "$index_comparison_tree"
  resolve_endpoint candidate "$index_candidate_commit" "$index_candidate_tree"
  for entry in "${index_members[@]}"; do
    read -r role locator member_digest <<<"$entry"
    verify_component "$role" "$locator" "$member_digest"
  done

  printf '%s\n' "${index_members[@]}"
}

do_create() {
  local -A source_of=()
  local gate_kind="" comparison_role
  local comparison_commit="" comparison_tree="" candidate_commit="" candidate_tree=""
  local -a evidence_sources=()
  local role source package_root staged_index index_sha evidence_digest

  while (( $# )); do
    (( $# >= 2 )) || usage
    case "$1" in
      --gate-kind) gate_kind="$2" ;;
      --comparison-commit) comparison_commit="$2" ;;
      --comparison-tree) comparison_tree="$2" ;;
      --candidate-commit) candidate_commit="$2" ;;
      --candidate-tree) candidate_tree="$2" ;;
      --trusted-contract|--review-assignment|--validation-evidence-policy|--standards|--validation-surface-manifest)
        role="${1#--}"
        [[ -z "${source_of[$role]:-}" ]] || fail "$role was supplied more than once"
        source_of[$role]="$2"
        ;;
      --evidence) evidence_sources+=("$2") ;;
      *) usage ;;
    esac
    shift 2
  done

  case "$gate_kind" in
    cumulative) comparison_role=comparison-base ;;
    delta) comparison_role=reviewed-anchor ;;
    *) usage ;;
  esac

  for role in "${singleton_roles[@]}"; do
    [[ -n "${source_of[$role]:-}" ]] || fail "$role was not supplied"
  done
  for source in "${source_of[@]}" ${evidence_sources[@]+"${evidence_sources[@]}"}; do
    [[ -f "$source" && -r "$source" ]] || fail "frozen input $source is missing or unreadable"
  done

  package_root="$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/work-on-review-index.XXXXXX")"
  mkdir -- "$package_root/components"
  chmod 700 "$package_root" "$package_root/components"

  for role in "${singleton_roles[@]}"; do
    cp -- "${source_of[$role]}" "$package_root/components/$role"
    chmod 600 "$package_root/components/$role"
  done

  # An evidence record is addressed by the SHA-256 of the caller's record bytes.
  # Its own Reusable-evidence identity and safe provenance locator stay inside
  # those bytes, unparsed; the package adds a content address over them and
  # nothing else.
  local -A evidence_seen=()
  local -a evidence_digests=()
  if (( ${#evidence_sources[@]} )); then
    mkdir -- "$package_root/components/evidence"
    chmod 700 "$package_root/components/evidence"
    for source in "${evidence_sources[@]}"; do
      evidence_digest="$(digest_of "$source")"
      [[ -z "${evidence_seen[$evidence_digest]:-}" ]] || fail 'an evidence record was supplied more than once'
      evidence_seen[$evidence_digest]=yes
      evidence_digests+=("$evidence_digest")
      cp -- "$source" "$package_root/components/evidence/$evidence_digest"
      chmod 600 "$package_root/components/evidence/$evidence_digest"
    done
    mapfile -t evidence_digests < <(printf '%s\n' "${evidence_digests[@]}" | sort)
  fi

  index_gate_kind="$gate_kind"
  index_comparison_role="$comparison_role"
  index_comparison_commit="$comparison_commit"
  index_comparison_tree="$comparison_tree"
  index_candidate_commit="$candidate_commit"
  index_candidate_tree="$candidate_tree"
  index_members=()
  for role in "${singleton_roles[@]}"; do
    index_members+=("$role components/$role $(digest_of "$package_root/components/$role")")
  done
  for evidence_digest in ${evidence_digests[@]+"${evidence_digests[@]}"}; do
    index_members+=("evidence components/evidence/$evidence_digest $evidence_digest")
  done

  staged_index="$package_root/.index"
  emit_canonical_index >"$staged_index"
  chmod 600 "$staged_index"
  index_sha="$(digest_of "$staged_index")"

  mv -- "$staged_index" "$package_root/index"
  verify_package "$package_root/index" "$index_sha" >/dev/null
  printf '%s\n%s\n' "$package_root/index" "$index_sha"
}

# Resolve exactly one component through the authenticated index, capture its
# bytes once, verify that capture, and emit only that same capture. A failure
# emits no component bytes at all, so an EOF-consuming filter downstream of a
# pipefail pipeline cannot turn a verifier failure into success.
do_read() {
  local index_path="" expected_index_sha="" role="" evidence_sha="" selector
  local entry member_role member_locator member_digest
  local locator="" digest="" matches=0

  while (( $# )); do
    (( $# >= 2 )) || usage
    case "$1" in
      --index) index_path="$2" ;;
      --index-sha256) expected_index_sha="$2" ;;
      --role) role="$2" ;;
      --evidence-sha256) evidence_sha="$2" ;;
      *) usage ;;
    esac
    shift 2
  done
  [[ -n "$index_path" && -n "$expected_index_sha" && -n "$role" ]] || usage

  if [[ "$role" == evidence ]]; then
    [[ "$evidence_sha" =~ ^[0-9a-f]{64}$ ]] || fail 'reading an evidence component requires its --evidence-sha256 identity'
    selector="components/evidence/$evidence_sha"
  else
    [[ -z "$evidence_sha" ]] || fail '--evidence-sha256 selects an evidence component only'
    selector="components/$role"
  fi

  parse_index "$index_path" "$expected_index_sha"
  for entry in "${index_members[@]}"; do
    read -r member_role member_locator member_digest <<<"$entry"
    [[ "$member_role" == "$role" && "$member_locator" == "$selector" ]] || continue
    locator="$member_locator"; digest="$member_digest"; matches=$(( matches + 1 ))
  done
  (( matches == 1 )) || fail 'the authenticated index does not resolve exactly one such component'

  check_member_custody "$role" "$locator"
  capture "$index_package_root/$locator"
  [[ "$(digest_of "$captured_snapshot")" == "$digest" ]] || fail "component $role does not match its frozen digest"
  cat -- "$captured_snapshot"
}

do_verify() {
  (( $# == 4 )) && [[ "$1" == --index && "$3" == --index-sha256 ]] || usage
  verify_package "$2" "$4"
}

subcommand="${1:-}"; shift || true
case "$subcommand" in
  create) do_create "$@" ;;
  verify) do_verify "$@" ;;
  read) do_read "$@" ;;
  *) usage ;;
esac
