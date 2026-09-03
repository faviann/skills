#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
identity="$script_dir/manifest-identity.sh"
provenance="$script_dir/workflow-provenance.sh"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
repo="$fixture/repo"; git init -q -b main "$repo"
git -C "$repo" config user.name Test; git -C "$repo" config user.email test@example.invalid
printf 'base\n' >"$repo/base"; git -C "$repo" add .; git -C "$repo" commit -qm base
printf '%s\n' '- criterion: public seam' >"$fixture/manifest.md"
printf '%s\n' '{"body":"trusted contract"}' >"$fixture/snapshot.json"
workflow_identity="$(cd "$repo" && "$provenance" identify-workflow)"

freeze() {
  (cd "$repo" && "$identity" freeze --manifest "$fixture/manifest.md" --snapshot "$fixture/snapshot.json" --base HEAD --workflow-identity "$workflow_identity")
}
run1="$(freeze)"; run2="$(freeze)"
[[ "$run1" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}$ && "$run2" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{16}$ && "$run1" != "$run2" ]]
custody="$repo/.git/work-on-manifest"
[[ "$(stat -c %a "$custody")" == 700 ]]
for run in "$run1" "$run2"; do
  for suffix in .md .trusted-snapshot.json .provenance.json; do
    [[ -f "$custody/$run$suffix" && "$(stat -c %a "$custody/$run$suffix")" == 600 ]]
  done
  [[ "$(cd "$repo" && "$identity" verify --run "$run")" == "$(git -C "$repo" rev-parse HEAD)" ]]
done
[[ "$run1" != *@* ]]
[[ ! -e "$repo/.git/work-on-provenance.json" && ! -e "$repo/.git/work-on-provenance.workflow-sha256" ]]

# Renaming complete owner-only custody cannot mint a second Run identity.
renamed_run=opaque-renamed-150
for suffix in .md .trusted-snapshot.json .provenance.json; do
  cp -p "$custody/$run1$suffix" "$custody/$renamed_run$suffix"
done
for command in read verify; do
  if (cd "$repo" && "$identity" "$command" --run "$renamed_run") >/dev/null 2>&1; then
    echo "renamed custody was accepted by manifest $command" >&2; exit 1
  fi
done

# Interrupt the shipped freeze around each publication boundary. Siblings alone
# are incomplete; final-manifest absence or presence is the commit marker.
mkdir "$fixture/wrapped-bin"
real_mv="$(command -v mv)"
cat >"$fixture/wrapped-bin/mv" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
destination="${!#}"
matched=false
[[ "$destination" == "$INTERRUPT_CUSTODY"/*"$INTERRUPT_SUFFIX" ]] && matched=true
if [[ "$matched" == true && "$INTERRUPT_WHEN" == before ]]; then
  printf '%s\n' "$destination" >"$INTERRUPT_SIGNAL"
  while :; do /bin/sleep 1; done
fi
"$REAL_MV" "$@"
if [[ "$matched" == true && "$INTERRUPT_WHEN" == after ]]; then
  printf '%s\n' "$destination" >"$INTERRUPT_SIGNAL"
  while :; do /bin/sleep 1; done
fi
SH
chmod +x "$fixture/wrapped-bin/mv"
printf '%s\n' '{"issue_number":150,"outcome":"Closes","acceptance_criteria":["criterion"],"acceptance":[{"criterion":"criterion","production_path":"script","seam":"CLI","evidence":"interrupted custody refused","status":"tested"}]}' >"$fixture/interrupted-facts.json"
: >"$fixture/interrupted-narrative.md"
reject_interrupted() {
  if (cd "$repo" && "$@") >/dev/null 2>&1; then
    echo "interrupted custody was accepted by: $*" >&2; exit 1
  fi
}

interrupt_freeze() {
  local label="$1" suffix="$2" when="$3" expected="$4"
  local interrupt_signal="$fixture/$1-publication.signal"
  PATH="$fixture/wrapped-bin:$PATH" REAL_MV="$real_mv" \
    INTERRUPT_CUSTODY="$custody" INTERRUPT_SIGNAL="$interrupt_signal" \
    INTERRUPT_SUFFIX="$suffix" INTERRUPT_WHEN="$when" \
    setsid bash -c 'cd "$1" && exec "$2" freeze --manifest "$3" --snapshot "$4" --base HEAD --workflow-identity "$5"' \
      _ "$repo" "$identity" "$fixture/manifest.md" "$fixture/snapshot.json" "$workflow_identity" \
      >"$fixture/$label-interrupted.out" 2>"$fixture/$label-interrupted.err" &
  freeze_pid=$!
  for _ in {1..100}; do
    [[ -s "$interrupt_signal" ]] && break
    /bin/sleep 0.05
  done
  [[ -s "$interrupt_signal" ]] || { kill -KILL -- "-$freeze_pid" 2>/dev/null || true; echo "freeze did not reach $label publication boundary" >&2; exit 1; }
  kill -KILL -- "-$freeze_pid"
  set +e
  wait "$freeze_pid" 2>/dev/null
  interrupted_status=$?
  set -e
  [[ "$interrupted_status" -ne 0 && ! -s "$fixture/$label-interrupted.out" ]]
  partial_path="$(<"$interrupt_signal")"
  partial_run="$(basename "$partial_path" "$suffix")"
  if [[ "$when" == before ]]; then [[ ! -e "$partial_path" ]]; else [[ -f "$partial_path" ]]; fi
  if [[ "$expected" == incomplete ]]; then
    reject_interrupted "$identity" read --run "$partial_run"
    reject_interrupted "$identity" verify --run "$partial_run"
    reject_interrupted "$provenance" read --run "$partial_run"
    reject_interrupted "$provenance" verify --run "$partial_run"
    reject_interrupted "$script_dir/render-closeout.sh" --run "$partial_run" \
      "$fixture/interrupted-facts.json" "$fixture/interrupted-narrative.md" --new-pr
  else
    (cd "$repo" && "$identity" read --run "$partial_run") >/dev/null
    (cd "$repo" && "$identity" verify --run "$partial_run") >/dev/null
    (cd "$repo" && "$provenance" read --run "$partial_run") >/dev/null
    (cd "$repo" && "$provenance" verify --run "$partial_run") >/dev/null
    (cd "$repo" && "$script_dir/render-closeout.sh" --run "$partial_run" \
      "$fixture/interrupted-facts.json" "$fixture/interrupted-narrative.md" \
      --new-pr) >/dev/null
  fi
}
interrupt_freeze provenance .provenance.json after incomplete
interrupt_freeze snapshot .trusted-snapshot.json after incomplete
interrupt_freeze manifest-before .md before incomplete
interrupt_freeze manifest-after .md after committed

# The Review-index command a Run uses is reached only after its governing
# identity verifies. Complete custody yields the governing script's path;
# custody that does not validate yields nothing. Provenance dependence itself is
# proven where governing inputs are mutated, in test-workflow-provenance.sh.
review_index_command="$(cd "$repo" && "$identity" review-index-path --run "$run1")"
[[ "$review_index_command" == "$script_dir/review-index.sh" ]]
reject_interrupted "$identity" review-index-path --run "$renamed_run"

# Final-manifest presence is the authority marker; a provenance-only
# interrupted publication is rejected by custody and rendering readers.
partial=opaque-partial
cp "$custody/$run1.provenance.json" "$custody/$partial.provenance.json"
chmod 600 "$custody/$partial.provenance.json"
if (cd "$repo" && "$identity" read --run "$partial") >"$fixture/out" 2>"$fixture/err"; then
  echo 'partial custody was accepted' >&2; exit 1
fi
grep -Fq 'complete custody is missing' "$fixture/err"

cp "$custody/$run1.md" "$fixture/saved-manifest"
printf '\ncorrupt\n' >>"$custody/$run1.md"
if (cd "$repo" && "$identity" read --run "$run1") >/dev/null 2>&1; then
  echo 'corrupt custody was accepted' >&2; exit 1
fi
cp "$fixture/saved-manifest" "$custody/$run1.md"; chmod 600 "$custody/$run1.md"

bad_identity="$(printf '0%.0s' {1..64})"
before="$(find "$custody" -maxdepth 1 -type f | wc -l)"
if (cd "$repo" && "$identity" freeze --manifest "$fixture/manifest.md" --snapshot "$fixture/snapshot.json" --base HEAD --workflow-identity "$bad_identity") >/dev/null 2>&1; then
  echo 'freeze accepted a workflow identity the gate did not read' >&2; exit 1
fi
[[ "$(find "$custody" -maxdepth 1 -type f | wc -l)" == "$before" ]]
if (cd "$repo" && "$identity" verify) >/dev/null 2>&1; then
  echo 'unnamed resume was accepted' >&2; exit 1
fi

# Missing, replaced, corrupt, unsafe, or non-canonical custody remains refused.
backup="$fixture/custody-backup"; mkdir "$backup"
for suffix in .md .trusted-snapshot.json .provenance.json; do
  cp -p "$custody/$run1$suffix" "$backup/run$suffix"
done
reject_read() {
  if (cd "$repo" && "$identity" read --run "$run1") >/dev/null 2>&1; then
    echo "invalid custody was accepted: $1" >&2; exit 1
  fi
}
mv "$custody/$run1.trusted-snapshot.json" "$fixture/missing-snapshot"
reject_read missing-snapshot
mv "$fixture/missing-snapshot" "$custody/$run1.trusted-snapshot.json"
printf 'corrupt\n' >>"$custody/$run1.trusted-snapshot.json"; reject_read corrupt-snapshot
cp -p "$backup/run.trusted-snapshot.json" "$custody/$run1.trusted-snapshot.json"
printf 'corrupt\n' >>"$custody/$run1.provenance.json"; reject_read corrupt-provenance
cp -p "$backup/run.provenance.json" "$custody/$run1.provenance.json"
chmod 644 "$custody/$run1.md"; reject_read unsafe-manifest-mode; chmod 600 "$custody/$run1.md"
for suffix in .trusted-snapshot.json .provenance.json; do
  chmod 644 "$custody/$run1$suffix"; reject_read "unsafe-$suffix-mode"
  chmod 600 "$custody/$run1$suffix"
done
chmod 755 "$custody"; reject_read unsafe-directory-mode; chmod 700 "$custody"
mv "$custody/$run1.trusted-snapshot.json" "$fixture/real-snapshot"
ln -s "$fixture/real-snapshot" "$custody/$run1.trusted-snapshot.json"
reject_read symlink-snapshot
rm "$custody/$run1.trusted-snapshot.json"; mv "$fixture/real-snapshot" "$custody/$run1.trusted-snapshot.json"
mv "$custody" "$fixture/real-custody"
ln -s "$fixture/real-custody" "$custody"
reject_read symlink-custody-directory
rm "$custody"; mv "$fixture/real-custody" "$custody"
sed -i '3cpre-implementation-base 0000000000000000000000000000000000000000' "$custody/$run1.md"
reject_read unavailable-base
cp -p "$backup/run.md" "$custody/$run1.md"
short_base="$(git -C "$repo" rev-parse --short HEAD)"
sed -i "3cpre-implementation-base $short_base" "$custody/$run1.md"
reject_read noncanonical-base
cp -p "$backup/run.md" "$custody/$run1.md"

ln -s "$fixture/manifest.md" "$fixture/symlink-manifest"
if (cd "$repo" && "$identity" freeze --manifest "$fixture/symlink-manifest" \
    --snapshot "$fixture/snapshot.json" --base HEAD \
    --workflow-identity "$workflow_identity") >/dev/null 2>&1; then
  echo 'freeze accepted a symlinked materialized manifest' >&2; exit 1
fi

echo 'Validation-surface manifest contract assertions held'
