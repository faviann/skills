#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
review_index="$script_dir/review-index.sh"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT

repo="$fixture/repo"; git init -q -b main "$repo"
git -C "$repo" config user.name Test; git -C "$repo" config user.email test@example.invalid
printf 'comparison\n' >"$repo/base"; git -C "$repo" add .; git -C "$repo" commit -qm comparison
comparison_commit="$(git -C "$repo" rev-parse HEAD)"
comparison_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
printf 'candidate\n' >"$repo/candidate"; git -C "$repo" add .; git -C "$repo" commit -qm candidate
candidate_commit="$(git -C "$repo" rev-parse HEAD)"
candidate_tree="$(git -C "$repo" rev-parse 'HEAD^{tree}')"

inputs="$fixture/inputs"; mkdir -p "$inputs"
printf '%s\n' 'frozen trusted contract' >"$inputs/trusted-contract"
printf '%s\n' 'neutral review assignment' >"$inputs/review-assignment"
printf '%s\n' 'frozen validation-evidence policy' >"$inputs/validation-evidence-policy"
printf '%s\n' 'binding Standards input' >"$inputs/standards"
printf '%s\n' 'frozen Validation-surface manifest' >"$inputs/validation-surface-manifest"

singleton_roles=(trusted-contract review-assignment validation-evidence-policy standards validation-surface-manifest)

digest() { sha256sum <"$1" | cut -d' ' -f1; }

# The expected member set, built from the explicit inputs rather than from the
# index under test, so the oracle stays independent of the serialization.
expected_enumeration() {
  local role sha
  for role in "${singleton_roles[@]}"; do
    printf '%s components/%s %s\n' "$role" "$role" "$(digest "$inputs/$role")"
  done
  for sha in "$@"; do
    printf 'evidence components/evidence/%s %s\n' "$sha" "$sha"
  done
}

create_endpoints() {
  local package_root="$1" gate_kind="$2" c_commit="$3" c_tree="$4" k_commit="$5" k_tree="$6"; shift 6
  (cd "$repo" && TMPDIR="$package_root" "$review_index" create \
    --gate-kind "$gate_kind" \
    --comparison-commit "$c_commit" --comparison-tree "$c_tree" \
    --candidate-commit "$k_commit" --candidate-tree "$k_tree" \
    --trusted-contract "$inputs/trusted-contract" \
    --review-assignment "$inputs/review-assignment" \
    --validation-evidence-policy "$inputs/validation-evidence-policy" \
    --standards "$inputs/standards" \
    --validation-surface-manifest "$inputs/validation-surface-manifest" \
    "$@")
}

create() {
  local package_root="$1"; shift
  create_endpoints "$package_root" cumulative \
    "$comparison_commit" "$comparison_tree" "$candidate_commit" "$candidate_tree" "$@"
}

# The smallest valid package returns an absolute index path and that index's
# expected SHA-256.
root_a="$fixture/root-a"; mkdir -p "$root_a"
create "$root_a" >"$fixture/create-a.out"
mapfile -t created <"$fixture/create-a.out"
(( ${#created[@]} == 2 ))
index_a="${created[0]}"; index_a_sha="${created[1]}"
[[ "$index_a" == /* && -f "$index_a" ]]
[[ "$index_a_sha" =~ ^[0-9a-f]{64}$ ]]
[[ "$(digest "$index_a")" == "$index_a_sha" ]]


package_a="$(dirname "$index_a")"

# Components are materialized byte-identically at their canonical locators, and
# the index is exactly the canonical serialization of the explicit inputs.
for role in "${singleton_roles[@]}"; do
  cmp -s "$inputs/$role" "$package_a/components/$role"
done
[[ "$(head -n 1 "$index_a")" == 'work-on-review-index/v1' ]]

# The published package is owner-only throughout, and every member is a regular
# non-symlinked file.
[[ -d "$package_a" && ! -L "$package_a" && "$(stat -c %a "$package_a")" == 700 ]]
[[ -d "$package_a/components" && ! -L "$package_a/components" && "$(stat -c %a "$package_a/components")" == 700 ]]
[[ -f "$index_a" && ! -L "$index_a" && "$(stat -c %a "$index_a")" == 600 ]]
for role in "${singleton_roles[@]}"; do
  [[ -f "$package_a/components/$role" && ! -L "$package_a/components/$role" && "$(stat -c %a "$package_a/components/$role")" == 600 ]]
done


# Evidence records are addressed by the SHA-256 of the caller's record bytes, so
# the package reuses their existing identity model instead of imposing one.
evidence="$fixture/evidence"; mkdir -p "$evidence"
printf '%s\n' '{"reusable-evidence-identity":"one","provenance":"harness://one"}' >"$evidence/one"
printf '%s\n' '{"reusable-evidence-identity":"two","provenance":"harness://two"}' >"$evidence/two"
one_sha="$(digest "$evidence/one")"; two_sha="$(digest "$evidence/two")"
[[ "$one_sha" != "$two_sha" ]]
mapfile -t ordered_evidence < <(printf '%s\n%s\n' "$one_sha" "$two_sha" | LC_ALL=C sort)

root_evidence="$fixture/root-evidence"; mkdir -p "$root_evidence"
create "$root_evidence" --evidence "$evidence/one" --evidence "$evidence/two" >"$fixture/create-evidence.out"
mapfile -t created_evidence <"$fixture/create-evidence.out"
index_evidence="${created_evidence[0]}"
package_evidence="$(dirname "$index_evidence")"
for sha in "$one_sha" "$two_sha"; do
  [[ -f "$package_evidence/components/evidence/$sha" && "$(stat -c %a "$package_evidence/components/evidence/$sha")" == 600 ]]
done
cmp -s "$evidence/one" "$package_evidence/components/evidence/$one_sha"
cmp -s "$evidence/two" "$package_evidence/components/evidence/$two_sha"
[[ -d "$package_evidence/components/evidence" && ! -L "$package_evidence/components/evidence" && "$(stat -c %a "$package_evidence/components/evidence")" == 700 ]]

# Argument order never reaches the package: evidence members are canonically
# ordered by their own identity.
root_reordered="$fixture/root-reordered"; mkdir -p "$root_reordered"
create "$root_reordered" --evidence "$evidence/two" --evidence "$evidence/one" >"$fixture/create-reordered.out"
mapfile -t created_reordered <"$fixture/create-reordered.out"
cmp -s "$index_evidence" "${created_reordered[0]}"
[[ "${created_evidence[1]}" == "${created_reordered[1]}" ]]

# Two records with identical bytes are one member supplied twice.
refuse() {
  local label="$1"; shift
  local out="$fixture/refused-$label.out"
  if "$@" >"$out" 2>/dev/null; then
    printf 'review index: %s was accepted\n' "$label" >&2; exit 1
  fi
  [[ ! -s "$out" ]] || { printf 'review index: %s emitted stdout\n' "$label" >&2; exit 1; }
}
cp -- "$evidence/one" "$evidence/one-copy"
root_duplicate="$fixture/root-duplicate"; mkdir -p "$root_duplicate"
refuse duplicate-evidence create "$root_duplicate" --evidence "$evidence/one" --evidence "$evidence/one-copy"


# Identical explicit inputs produce the same package identity regardless of the
# temporary package root.
root_b="$fixture/root-b"; mkdir -p "$root_b"
create "$root_b" >"$fixture/create-b.out"
mapfile -t created_b <"$fixture/create-b.out"
index_b="${created_b[0]}"
package_b="$(dirname "$index_b")"
[[ "$package_b" != "$package_a" && "$package_b" == "$root_b"/* && "$package_a" == "$root_a"/* ]]
cmp -s "$index_a" "$index_b"
[[ "${created_b[1]}" == "$index_a_sha" ]]
for role in "${singleton_roles[@]}"; do
  cmp -s "$package_a/components/$role" "$package_b/components/$role"
done


# The public verifier independently accepts a complete package and enumerates
# its members in canonical index order.
verify() { (cd "$repo" && "$review_index" verify --index "$1" --index-sha256 "$2"); }
expected_enumeration >"$fixture/expected-enumeration-a"
verify "$index_a" "$index_a_sha" >"$fixture/enumeration-a"
cmp -s "$fixture/expected-enumeration-a" "$fixture/enumeration-a"
expected_enumeration "${ordered_evidence[@]}" >"$fixture/expected-enumeration"
verify "$index_evidence" "${created_evidence[1]}" >"$fixture/enumeration"
cmp -s "$fixture/expected-enumeration" "$fixture/enumeration"

scratch_package() {
  local label="$1"; shift
  local root="$fixture/root-$label"; mkdir -p "$root"
  create "$root" "$@" >"$fixture/create-$label.out"
  mapfile -t scratch <"$fixture/create-$label.out"
}

# A different expected identity, altered index bytes, and an altered component
# are each refused, and none of them emits an enumeration.
refuse wrong-index-identity verify "$index_evidence" "$(printf 'x' | sha256sum | cut -d' ' -f1)"

scratch_package tampered-index
printf 'component standards components/standards %s\n' "$one_sha" >>"${scratch[0]}"
refuse tampered-index verify "${scratch[0]}" "${scratch[1]}"

scratch_package tampered-component
printf 'rewritten Standards input\n' >"$(dirname "${scratch[0]}")/components/standards"
refuse tampered-component verify "${scratch[0]}" "${scratch[1]}"


# Index shape is enforced independently of index identity: each malformed index
# below is re-hashed, so only the schema can reject it.
zero_digest="$(printf '' | sha256sum | cut -d' ' -f1)"
mutate_index() {
  local label="$1"; shift
  scratch_package "$label"
  "$@" <"${scratch[0]}" >"$fixture/mutated-$label"
  cat "$fixture/mutated-$label" >"${scratch[0]}"
  refuse "$label" verify "${scratch[0]}" "$(digest "${scratch[0]}")"
}
mutate_index unsupported-version sed '1s|/v1$|/v2|'
mutate_index missing-version sed '1d'
mutate_index unknown-header sed '2i extra-key value'

# Parsing must prove the authenticated snapshot is the canonical byte
# representation. Bash normalizes bytes a file can hold: mapfile truncates a
# line at an embedded NUL, so a schema check over the parsed strings alone
# would accept a token the index never carried. Each malformed index below is
# supplied with its own SHA-256, so only byte-canonical parsing can reject it.
rewrite_index() {
  local label="$1"; shift
  scratch_package "$label"
  "$@" >"$fixture/rewritten-$label"
  cat "$fixture/rewritten-$label" >"${scratch[0]}"
  refuse "$label" verify "${scratch[0]}" "$(digest "${scratch[0]}")"
}
embedded_nul() {
  head -n 1 "${scratch[0]}"
  printf 'gate-kind cumulative\000\n'
  tail -n +3 "${scratch[0]}"
}
unterminated() { printf '%s' "$(cat "${scratch[0]}")"; }
rewrite_index embedded-nul embedded_nul
rewrite_index unterminated-index unterminated
mutate_index missing-header sed '7d'
mutate_index reordered-header awk '{l[NR]=$0} END{print l[1]; print l[3]; print l[2]; for(i=4;i<=NR;i++) print l[i]}'
mutate_index missing-role sed '/^component standards /d'
mutate_index duplicate-role sed '/^component standards /p'
mutate_index unknown-role sed "\$a component diff components/diff $zero_digest"
mutate_index malformed-member sed 's|^component standards .*|component standards components/standards|'
mutate_index reordered-roles awk '{l[NR]=$0} END{for(i=1;i<=7;i++) print l[i]; print l[9]; print l[8]; for(i=10;i<=NR;i++) print l[i]}'


# Endpoints are pinned identities, never live refs: a supplied identity must
# resolve to exactly itself and to its separately supplied tree.
root_endpoint="$fixture/root-endpoint"; mkdir -p "$root_endpoint"
refuse live-ref-endpoint create_endpoints "$root_endpoint" cumulative \
  "$comparison_commit" "$comparison_tree" HEAD "$candidate_tree"
refuse branch-endpoint create_endpoints "$root_endpoint" cumulative \
  "$comparison_commit" "$comparison_tree" main "$candidate_tree"
refuse abbreviated-endpoint create_endpoints "$root_endpoint" cumulative \
  "$comparison_commit" "$comparison_tree" "${candidate_commit:0:8}" "$candidate_tree"
refuse unknown-endpoint create_endpoints "$root_endpoint" cumulative \
  "$comparison_commit" "$comparison_tree" "${candidate_commit//[0-9a-f]/0}" "$candidate_tree"
refuse mismatched-tree create_endpoints "$root_endpoint" cumulative \
  "$comparison_commit" "$comparison_tree" "$candidate_commit" "$comparison_tree"
refuse swapped-tree-identity create_endpoints "$root_endpoint" cumulative \
  "$comparison_commit" "$comparison_commit" "$candidate_commit" "$candidate_tree"

# A delta gate pins its comparison endpoint in the Reviewed-anchor role.
root_delta="$fixture/root-delta"; mkdir -p "$root_delta"
create_endpoints "$root_delta" delta \
  "$comparison_commit" "$comparison_tree" "$candidate_commit" "$candidate_tree" >"$fixture/create-delta.out"
mapfile -t created_delta <"$fixture/create-delta.out"
verify "${created_delta[0]}" "${created_delta[1]}" >/dev/null
refuse unknown-gate-kind create_endpoints "$root_delta" partial \
  "$comparison_commit" "$comparison_tree" "$candidate_commit" "$candidate_tree"

# The independent verifier rejects a tampered gate-kind/role pairing and a
# tampered endpoint even when the index re-hashes cleanly.
mutate_index disagreeing-comparison-role sed 's|^comparison-role .*|comparison-role reviewed-anchor|'
mutate_index tampered-candidate-tree sed "s|^candidate-tree .*|candidate-tree $comparison_tree|"


# An escaping or absolute locator is not a dangerous member to sanitize: the
# canonical grammar cannot express one.
mutate_index escaping-locator sed "s|^component standards .*|component standards components/../standards $zero_digest|"
mutate_index absolute-locator sed "s|^component standards .*|component standards /etc/passwd $zero_digest|"
mutate_index foreign-evidence-locator sed "\$a component evidence components/evidence/$one_sha $two_sha"

# Custody is proven along the whole package-relative path, so a matching digest
# behind a symlinked directory or leaf is still refused.
scratch_pkg() { printf '%s' "$(dirname "${scratch[0]}")"; }

scratch_package symlinked-components
package="$(scratch_pkg)"
mv -- "$package/components" "$package/elsewhere"
ln -s "$package/elsewhere" "$package/components"
refuse symlinked-components verify "${scratch[0]}" "${scratch[1]}"

scratch_package symlinked-evidence-dir --evidence "$evidence/one"
package="$(scratch_pkg)"
mv -- "$package/components/evidence" "$package/evidence-elsewhere"
ln -s "$package/evidence-elsewhere" "$package/components/evidence"
refuse symlinked-evidence-dir verify "${scratch[0]}" "${scratch[1]}"

scratch_package symlinked-component
package="$(scratch_pkg)"
mv -- "$package/components/standards" "$fixture/standards-elsewhere"
ln -s "$fixture/standards-elsewhere" "$package/components/standards"
refuse symlinked-component verify "${scratch[0]}" "${scratch[1]}"

scratch_package non-regular-component
package="$(scratch_pkg)"
rm -- "$package/components/standards"
mkfifo -m 600 "$package/components/standards"
refuse non-regular-component verify "${scratch[0]}" "${scratch[1]}"

scratch_package widened-component
chmod 644 "$(scratch_pkg)/components/standards"
refuse widened-component verify "${scratch[0]}" "${scratch[1]}"

scratch_package widened-package-root
chmod 755 "$(scratch_pkg)"
refuse widened-package-root verify "${scratch[0]}" "${scratch[1]}"

scratch_package widened-index
chmod 644 "${scratch[0]}"
refuse widened-index verify "${scratch[0]}" "${scratch[1]}"

scratch_package symlinked-index
package="$(scratch_pkg)"
mv -- "${scratch[0]}" "$package/index-elsewhere"
ln -s "$package/index-elsewhere" "${scratch[0]}"
refuse symlinked-index verify "${scratch[0]}" "${scratch[1]}"

scratch_package renamed-index
package="$(scratch_pkg)"
cp -p -- "${scratch[0]}" "$package/other"
refuse renamed-index verify "$package/other" "${scratch[1]}"

scratch_package relative-index
package="$(scratch_pkg)"
relative_sha="${scratch[1]}"
if (cd "$package" && "$review_index" verify --index index --index-sha256 "$relative_sha") >"$fixture/refused-relative.out" 2>/dev/null; then
  printf 'review index: relative index path was accepted\n' >&2; exit 1
fi
[[ ! -s "$fixture/refused-relative.out" ]]


# A verified read is a range-free byte-exact cat of exactly one resolved
# component.
printf 'binary\000record with no trailing newline' >"$evidence/binary"
binary_sha="$(digest "$evidence/binary")"
scratch_package readable --evidence "$evidence/one" --evidence "$evidence/binary"
readable_index="${scratch[0]}"; readable_sha="${scratch[1]}"
readable_package="$(scratch_pkg)"
read_component() { "$review_index" read --index "$readable_index" --index-sha256 "$readable_sha" "$@"; }

for role in "${singleton_roles[@]}"; do
  read_component --role "$role" >"$fixture/read-$role"
  cmp -s "$inputs/$role" "$fixture/read-$role"
done
read_component --role evidence --evidence-sha256 "$one_sha" >"$fixture/read-evidence"
cmp -s "$evidence/one" "$fixture/read-evidence"
read_component --role evidence --evidence-sha256 "$binary_sha" >"$fixture/read-binary"
cmp -s "$evidence/binary" "$fixture/read-binary"

# Selection is unambiguous: evidence needs its own identity, and no other role
# accepts one.
refuse unselected-evidence read_component --role evidence
refuse over-selected-singleton read_component --role standards --evidence-sha256 "$one_sha"
refuse unindexed-evidence read_component --role evidence --evidence-sha256 "$two_sha"
refuse unknown-read-role read_component --role diff
refuse ranged-read read_component --role standards --lines 1-5
refuse read-wrong-identity "$review_index" read --index "$readable_index" \
  --index-sha256 "$zero_digest" --role standards

# The reader re-proves custody rather than trusting an earlier verification.
scratch_package read-symlinked-component
package="$(scratch_pkg)"
mv -- "$package/components/standards" "$fixture/read-standards-elsewhere"
ln -s "$fixture/read-standards-elsewhere" "$package/components/standards"
refuse read-symlinked-component "$review_index" read --index "${scratch[0]}" \
  --index-sha256 "${scratch[1]}" --role standards

# A tampered component emits zero bytes, and an EOF-consuming filter under
# pipefail cannot turn that failure into success.
scratch_package read-tampered
printf 'rewritten Standards input\n' >"$(scratch_pkg)/components/standards"
refuse read-tampered "$review_index" read --index "${scratch[0]}" \
  --index-sha256 "${scratch[1]}" --role standards
set +e
( set -o pipefail
  "$review_index" read --index "${scratch[0]}" --index-sha256 "${scratch[1]}" --role standards 2>/dev/null \
    | cat >"$fixture/piped-read.out" )
piped_status=$?
set -e
(( piped_status != 0 ))
[[ ! -s "$fixture/piped-read.out" ]]

# A content-fired sha256sum shim replaces the indexed source the moment its
# digest is taken. Hashing the pathname and then emitting the pathname would
# leak the replacement; hashing and emitting one captured snapshot does not.
mkdir -p "$fixture/shim-bin"
cat >"$fixture/shim-bin/sha256sum" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
captured="$(mktemp)"
cat >"$captured"
hashed="$("$REAL_SHA256SUM" <"$captured" | cut -d' ' -f1)"
rm -f -- "$captured"
[[ "$hashed" != "$SWAP_WHEN_DIGEST" ]] || cat -- "$SWAP_SOURCE" >"$SWAP_TARGET"
printf '%s  -\n' "$hashed"
SH
chmod +x "$fixture/shim-bin/sha256sum"
real_sha256sum="$(command -v sha256sum)"
with_swap() {
  PATH="$fixture/shim-bin:$PATH" REAL_SHA256SUM="$real_sha256sum" \
    SWAP_WHEN_DIGEST="$1" SWAP_SOURCE="$2" SWAP_TARGET="$3" "${@:4}"
}

printf 'attacker Standards input\n' >"$fixture/attacker-standards"
with_swap "$(digest "$inputs/standards")" "$fixture/attacker-standards" \
  "$readable_package/components/standards" \
  "$review_index" read --index "$readable_index" --index-sha256 "$readable_sha" \
  --role standards >"$fixture/read-after-replacement"
cmp -s "$inputs/standards" "$fixture/read-after-replacement"

# The same discrimination for the index itself. Index A and index B are both
# valid for one package; only the bytes actually parsed decide the member set.
scratch_package index-replacement --evidence "$evidence/one" --evidence "$evidence/two"
package="$(scratch_pkg)"
cp -- "${scratch[0]}" "$fixture/index-b"
grep -v "components/evidence/$two_sha" "$fixture/index-b" >"$fixture/index-a"
cat "$fixture/index-a" >"${scratch[0]}"
index_a_only_sha="$(digest "${scratch[0]}")"
(cd "$repo" && with_swap "$index_a_only_sha" "$fixture/index-b" "${scratch[0]}" \
  "$review_index" verify --index "${scratch[0]}" --index-sha256 "$index_a_only_sha") >"$fixture/replaced-enumeration"
(( "$(grep -c '^evidence ' "$fixture/replaced-enumeration")" == 1 ))
cat "$fixture/index-a" >"${scratch[0]}"
if with_swap "$index_a_only_sha" "$fixture/index-b" "${scratch[0]}" \
  "$review_index" read --index "${scratch[0]}" --index-sha256 "$index_a_only_sha" \
  --role evidence --evidence-sha256 "$two_sha" >"$fixture/replaced-read" 2>/dev/null; then
  printf 'review index: a member the authenticated index never carried was read\n' >&2; exit 1
fi
[[ ! -s "$fixture/replaced-read" ]]


# Placing the index at its final path is the publication boundary. Failing or
# interrupting the real creation path there leaves no returned identity and
# nothing that verifies.
mkdir -p "$fixture/publication-bin"
cat >"$fixture/publication-bin/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$(basename -- "${!#}")" == index ]]; then
  [[ "$PUBLICATION_INTERRUPT" != kill ]] || kill -KILL "$PPID"
  exit 1
fi
exec "$REAL_MV" "$@"
SH
chmod +x "$fixture/publication-bin/mv"
real_mv="$(command -v mv)"

publication_arm() {
  local arm="$1" status package leftover
  local root="$fixture/root-publication-$arm"
  mkdir -p "$root"
  set +e
  ( export PATH="$fixture/publication-bin:$PATH" REAL_MV="$real_mv" PUBLICATION_INTERRUPT="$arm"
    create "$root" ) >"$fixture/publication-$arm.out" 2>/dev/null
  status=$?
  set -e
  case "$arm" in
    fail) (( status == 1 )) ;;
    kill) (( status == 137 )) ;;
  esac
  [[ ! -s "$fixture/publication-$arm.out" ]]
  for package in "$root"/*/; do
    [[ ! -e "$package/index" ]]
    for leftover in "$package".index "$package"index; do
      [[ -e "$leftover" ]] || continue
      if (cd "$repo" && "$review_index" verify --index "$leftover" \
          --index-sha256 "$(digest "$leftover")") >/dev/null 2>&1; then
        printf 'review index: an unpublished %s index was accepted\n' "$arm" >&2; exit 1
      fi
    done
  done
}
publication_arm fail
publication_arm kill


# Creation accepts only explicit inputs: an omitted or unusable one is refused
# rather than defaulted.
root_inputs="$fixture/root-inputs"; mkdir -p "$root_inputs"
partial_create() {
  (cd "$repo" && TMPDIR="$root_inputs" "$review_index" create \
    --gate-kind cumulative \
    --comparison-commit "$comparison_commit" --comparison-tree "$comparison_tree" \
    --candidate-commit "$candidate_commit" --candidate-tree "$candidate_tree" "$@")
}
all_inputs=(
  --trusted-contract "$inputs/trusted-contract"
  --review-assignment "$inputs/review-assignment"
  --validation-evidence-policy "$inputs/validation-evidence-policy"
  --standards "$inputs/standards"
  --validation-surface-manifest "$inputs/validation-surface-manifest"
)
refuse missing-standards partial_create "${all_inputs[@]:0:6}" "${all_inputs[@]:8:2}"
refuse repeated-standards partial_create "${all_inputs[@]}" --standards "$inputs/standards"
refuse unknown-input partial_create "${all_inputs[@]}" --diff "$inputs/standards"
refuse dangling-flag partial_create "${all_inputs[@]}" --evidence
refuse missing-input-file partial_create "${all_inputs[@]}" --evidence "$fixture/absent-record"
refuse missing-gate-kind "$review_index" create "${all_inputs[@]}"
refuse missing-endpoint create_endpoints "$root_inputs" cumulative \
  "$comparison_commit" "$comparison_tree" "$candidate_commit" ""
refuse unknown-subcommand "$review_index" enumerate
refuse verify-without-identity "$review_index" verify --index "$readable_index"
refuse read-without-role "$review_index" read --index "$readable_index" --index-sha256 "$readable_sha"

printf 'review index: all assertions passed\n'
