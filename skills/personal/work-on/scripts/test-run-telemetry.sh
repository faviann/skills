#!/usr/bin/env bash
set -euo pipefail

# Black-box scenarios for the run-scoped telemetry sink. Every assertion goes
# through the shipped command's public subcommands; nothing reaches into the
# sink's storage layout except to prove what is and is not stored there.

readonly source_script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly command_under_test="$source_script_root/run-telemetry.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

run_id_from_handle() {
  printf '%s\n' "${1%%@*}"
}

# A run begun in a disposable linked worktree is stored in the repository's
# common Git directory, so the surviving worktree can still read it after the
# linked worktree has been removed.
durable_repo="$fixture/durable-repo"
durable_worktree="$fixture/durable-worktree"
git init -q -b main "$durable_repo"
git -C "$durable_repo" config user.name 'Telemetry Test'
git -C "$durable_repo" config user.email telemetry@example.invalid
git -C "$durable_repo" remote add origin \
  'https://github.com/example/durable.git'
printf 'durable\n' >"$durable_repo/file.txt"
git -C "$durable_repo" add .
git -C "$durable_repo" commit -qm 'first'
git -C "$durable_repo" worktree add -q -b telemetry-test "$durable_worktree"
durable_run="$(cd "$durable_worktree" && "$command_under_test" start --issue 71)"
(cd "$durable_worktree" && "$command_under_test" launch --run "$durable_run" \
  --role implementation --phase implementation --round 1)
git -C "$durable_repo" worktree remove "$durable_worktree"
durable_summary="$(cd "$durable_repo" && "$command_under_test" summary \
  --run "$durable_run")"
[[ "$(jq -r '.subagent_launches.total' <<<"$durable_summary")" -eq 1 ]]

target="$fixture/target"
git init -q -b main "$target"
git -C "$target" config user.name 'Telemetry Test'
git -C "$target" config user.email telemetry@example.invalid
git -C "$target" remote add origin 'https://github.com/example/target.git'
printf 'SYNTHETIC-FILE-CONTENT-MARKER\n' >"$target/first.txt"
git -C "$target" add .
git -C "$target" commit -qm 'first'

telemetry() {
  (cd "$target" && "$command_under_test" "$@")
}
sink_root="$target/.git/work-on-telemetry"

# Visibly synthetic stand-ins for material that must never reach the sink. The
# output markers are assembled at run time so that proving they are absent from
# the sink proves the recorder discarded the command's output, not merely that
# the literal never appeared in an argument.
readonly fake_token='ghp_EXAMPLENOTAREALTOKEN0000000000'
readonly fake_password='SYNTHETIC-NOT-A-REAL-PASSWORD'
readonly stdout_marker='SYNTHETIC-OUTPUT-MARKER'
readonly stderr_marker='SYNTHETIC-DIAGNOSTIC-MARKER'
readonly emit_stdout_marker='printf "SYNTHETIC-%s-MARKER\n" OUTPUT'
readonly emit_stderr_marker='printf "SYNTHETIC-%s-MARKER\n" DIAGNOSTIC >&2'

# 1. A run is created, identified, and kept separate from any other run.
first_run="$(telemetry start --issue 71)"
[[ "$first_run" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}@[0-9a-f]{32}$ ]]
telemetry launch --run "$first_run" \
  --role implementation --phase implementation --round 1
telemetry launch --run "$first_run" \
  --role other --phase checkpoint --round 1

second_run="$(telemetry start --issue 71)"
[[ "$second_run" != "$first_run" ]]
telemetry launch --run "$second_run" --role other --phase gate --round 2
# Explicit handles, rather than the most recently started run, route interleaved
# events back to their own sinks.
telemetry launch --run "$first_run" --role other --phase closeout --round 3

# A stale or corrupt convenience pointer is outside routing correctness.
printf 'not-a-run\n' >"$sink_root/current-run"
telemetry launch --run "$first_run" --role other --phase checkpoint --round 4
rm "$sink_root/current-run"

first_summary="$(telemetry summary --run "$first_run")"
second_summary="$(telemetry summary --run "$second_run")"
[[ "$(jq -r '.subagent_launches.total' <<<"$first_summary")" -eq 4 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$second_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role.other' <<<"$second_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role.implementation' <<<"$second_summary")" -eq 0 ]]
[[ "$(jq -r '.run' <<<"$first_summary")" == \
  "$(run_id_from_handle "$first_run")" ]]

# Two live linked worktrees share one common Git directory but retain distinct
# run sinks while their public writers execute concurrently. Every writer first
# announces readiness, then waits for one shared release, so both worktrees are
# active before any telemetry command begins.
linked_one="$fixture/linked-one"
linked_two="$fixture/linked-two"
git -C "$target" worktree add -q -b linked-one "$linked_one"
git -C "$target" worktree add -q -b linked-two "$linked_two"
linked_one_run="$(cd "$linked_one" && "$command_under_test" start --issue 71)"
linked_two_run="$(cd "$linked_two" && "$command_under_test" start --issue 71)"
[[ "${linked_one_run#*@}" == "${linked_two_run#*@}" ]]
linked_sync="$fixture/linked-sync"
mkdir "$linked_sync"
readonly linked_writers_per_run=8
linked_writer_pids=()
for ((writer = 1; writer <= linked_writers_per_run; writer++)); do
  (
    touch "$linked_sync/one-$writer.ready"
    while [[ ! -e "$linked_sync/release" ]]; do sleep 0.01; done
    cd "$linked_one"
    "$command_under_test" launch --run "$linked_one_run" \
      --role implementation --phase implementation --round "$writer"
  ) &
  linked_writer_pids+=("$!")
  (
    touch "$linked_sync/two-$writer.ready"
    while [[ ! -e "$linked_sync/release" ]]; do sleep 0.01; done
    cd "$linked_two"
    "$command_under_test" launch --run "$linked_two_run" \
      --role other --phase gate --round "$writer"
  ) &
  linked_writer_pids+=("$!")
done
for ((attempt = 0; attempt < 500; attempt++)); do
  ready_count="$(find "$linked_sync" -name '*.ready' -type f | wc -l)"
  [[ "$ready_count" -eq $(( linked_writers_per_run * 2 )) ]] && break
  sleep 0.01
done
[[ "$ready_count" -eq $(( linked_writers_per_run * 2 )) ]]
touch "$linked_sync/release"
for writer_pid in "${linked_writer_pids[@]}"; do
  wait "$writer_pid"
done

# Long-lived public exec writers prove the two worktrees' telemetry operations
# overlap, rather than merely being scheduled from background shells together.
linked_overlap_release="$linked_sync/overlap-release"
linked_overlap_pids=()
for linked_side in one two; do
  if [[ "$linked_side" == one ]]; then
    linked_worktree="$linked_one"
    linked_run="$linked_one_run"
  else
    linked_worktree="$linked_two"
    linked_run="$linked_two_run"
  fi
  (
    cd "$linked_worktree"
    "$command_under_test" exec --run "$linked_run" \
      --command-id linked-overlap --phase gate --round 1 -- \
      bash -c 'touch "$1"; while [[ ! -e "$2" ]]; do sleep 0.01; done' \
      _ "$linked_sync/$linked_side.entered" "$linked_overlap_release"
  ) &
  linked_overlap_pids+=("$!")
done
for ((attempt = 0; attempt < 500; attempt++)); do
  [[ -e "$linked_sync/one.entered" && -e "$linked_sync/two.entered" ]] && break
  sleep 0.01
done
[[ -e "$linked_sync/one.entered" && -e "$linked_sync/two.entered" ]]
touch "$linked_overlap_release"
for writer_pid in "${linked_overlap_pids[@]}"; do
  wait "$writer_pid"
done

linked_one_id="$(run_id_from_handle "$linked_one_run")"
linked_two_id="$(run_id_from_handle "$linked_two_run")"
linked_one_sink="$sink_root/runs/$linked_one_id.jsonl"
linked_two_sink="$sink_root/runs/$linked_two_id.jsonl"
linked_one_summary="$(cd "$linked_two" && "$command_under_test" summary \
  --run "$linked_one_run")"
linked_two_summary="$(cd "$linked_one" && "$command_under_test" summary \
  --run "$linked_two_run")"
[[ "$(jq -r '.subagent_launches.total' <<<"$linked_one_summary")" \
  -eq "$linked_writers_per_run" ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$linked_two_summary")" \
  -eq "$linked_writers_per_run" ]]
[[ "$(jq -r '.subagent_launches.by_role.implementation' \
  <<<"$linked_one_summary")" -eq "$linked_writers_per_run" ]]
[[ "$(jq -r '.subagent_launches.by_role.other' \
  <<<"$linked_one_summary")" -eq 0 ]]
[[ "$(jq -r '.subagent_launches.by_role.other' \
  <<<"$linked_two_summary")" -eq "$linked_writers_per_run" ]]
[[ "$(jq -r '.subagent_launches.by_role.implementation' \
  <<<"$linked_two_summary")" -eq 0 ]]
[[ "$(jq -r '.validations.total' <<<"$linked_one_summary")" -eq 1 ]]
[[ "$(jq -r '.validations.passed' <<<"$linked_one_summary")" -eq 1 ]]
[[ "$(jq -r '.validations.total' <<<"$linked_two_summary")" -eq 1 ]]
[[ "$(jq -r '.validations.passed' <<<"$linked_two_summary")" -eq 1 ]]
for linked_sink_and_id in \
    "$linked_one_sink:$linked_one_id" "$linked_two_sink:$linked_two_id"; do
  linked_sink="${linked_sink_and_id%%:*}"
  linked_id="${linked_sink_and_id#*:}"
  [[ "$(wc -l <"$linked_sink")" -eq $(( linked_writers_per_run + 3 )) ]]
  jq -e . "$linked_sink" >/dev/null
  jq -s -e --arg run "$linked_id" \
    'all(.[]; .run == $run)' "$linked_sink" >/dev/null
  [[ "$(jq -r '.seq' "$linked_sink" | sort -u | wc -l)" \
    -eq $(( linked_writers_per_run + 3 )) ]]
done

# Before durable common-directory storage, a linked worktree's recorder put its
# schema-1 sink under that worktree's own absolute Git directory. A canonical
# common-directory sink can have the same textual run ID. The plain ID must keep
# the current worktree's legacy sink individually readable, while the bound
# handle selects the canonical sink; neither read may rewrite either source.
legacy_linked_run=20000101T000000Z-00000002
legacy_linked_git_dir="$(git -C "$linked_one" rev-parse --absolute-git-dir)"
legacy_linked_sink="$legacy_linked_git_dir/work-on-telemetry/runs/$legacy_linked_run.jsonl"
canonical_colliding_sink="$sink_root/runs/$legacy_linked_run.jsonl"
canonical_colliding_handle="$legacy_linked_run@${linked_one_run#*@}"
mkdir -p "$(dirname "$legacy_linked_sink")"
printf '%s\n' \
  '{"schema":1,"run":"20000101T000000Z-00000002","seq":1,"at":"2000-01-01T00:00:00Z","epoch_ms":946684800000,"type":"run_start","workflow":"work-on"}' \
  '{"schema":1,"run":"20000101T000000Z-00000002","seq":2,"at":"2000-01-01T00:00:01Z","epoch_ms":946684801000,"type":"subagent_launch","role":"implementation","phase":"implementation","round":1}' \
  >"$legacy_linked_sink"
printf '%s\n' \
  '{"schema":1,"run":"20000101T000000Z-00000002","seq":1,"at":"2000-01-01T00:00:00Z","epoch_ms":946684800000,"type":"run_start","workflow":"work-on"}' \
  '{"schema":1,"run":"20000101T000000Z-00000002","seq":2,"at":"2000-01-01T00:00:01Z","epoch_ms":946684801000,"type":"subagent_launch","role":"review-spec","phase":"gate","round":1}' \
  '{"schema":1,"run":"20000101T000000Z-00000002","seq":3,"at":"2000-01-01T00:00:02Z","epoch_ms":946684802000,"type":"subagent_launch","role":"review-spec","phase":"gate","round":2}' \
  >"$canonical_colliding_sink"
chmod 600 "$legacy_linked_sink" "$canonical_colliding_sink"
cp "$legacy_linked_sink" "$fixture/legacy-linked-before.jsonl"
cp "$canonical_colliding_sink" "$fixture/canonical-colliding-before.jsonl"
legacy_linked_checksum="$(sha256sum "$legacy_linked_sink")"
canonical_colliding_checksum="$(sha256sum "$canonical_colliding_sink")"
legacy_linked_summary="$(cd "$linked_one" && "$command_under_test" summary \
  --run "$legacy_linked_run")"
[[ "$(jq -r '.subagent_launches.total' <<<"$legacy_linked_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role.implementation' \
  <<<"$legacy_linked_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role."review-spec"' \
  <<<"$legacy_linked_summary")" -eq 0 ]]
canonical_colliding_summary="$(cd "$linked_one" && "$command_under_test" summary \
  --run "$canonical_colliding_handle")"
[[ "$(jq -r '.subagent_launches.total' \
  <<<"$canonical_colliding_summary")" -eq 2 ]]
[[ "$(jq -r '.subagent_launches.by_role."review-spec"' \
  <<<"$canonical_colliding_summary")" -eq 2 ]]
[[ "$(jq -r '.subagent_launches.by_role.implementation' \
  <<<"$canonical_colliding_summary")" -eq 0 ]]
[[ "$(sha256sum "$legacy_linked_sink")" == "$legacy_linked_checksum" ]]
[[ "$(sha256sum "$canonical_colliding_sink")" == \
  "$canonical_colliding_checksum" ]]
cmp "$fixture/legacy-linked-before.jsonl" "$legacy_linked_sink"
cmp "$fixture/canonical-colliding-before.jsonl" "$canonical_colliding_sink"
refuse_legacy_write() {
  local label="$1"
  shift
  if (cd "$linked_one" && "$command_under_test" "$@") \
      >"$fixture/legacy-linked-$label.out" \
      2>"$fixture/legacy-linked-$label.err"; then
    printf 'FAIL[legacy-linked-%s]: recorder wrote through a plain ID\n' \
      "$label" >&2
    exit 1
  fi
  [[ ! -s "$fixture/legacy-linked-$label.out" ]]
  grep -Fq 'run handle is malformed' "$fixture/legacy-linked-$label.err"
}
refuse_legacy_write launch launch --run "$legacy_linked_run" \
  --role implementation --phase implementation --round 2
refuse_legacy_write resolve resolve --run "$legacy_linked_run" --outcome Closes
[[ "$(sha256sum "$legacy_linked_sink")" == "$legacy_linked_checksum" ]]
[[ "$(sha256sum "$canonical_colliding_sink")" == \
  "$canonical_colliding_checksum" ]]
cmp "$fixture/legacy-linked-before.jsonl" "$legacy_linked_sink"
cmp "$fixture/canonical-colliding-before.jsonl" "$canonical_colliding_sink"

# Without a canonical collision, a plain ID still selects the current linked
# worktree's legacy forensic sink.
legacy_only_run=20000101T000000Z-00000004
legacy_only_git_dir="$(git -C "$linked_two" rev-parse --absolute-git-dir)"
legacy_only_sink="$legacy_only_git_dir/work-on-telemetry/runs/$legacy_only_run.jsonl"
mkdir -p "$(dirname "$legacy_only_sink")"
printf '%s\n' \
  '{"schema":1,"run":"20000101T000000Z-00000004","seq":1,"at":"2000-01-01T00:00:00Z","epoch_ms":946684800000,"type":"run_start","workflow":"work-on"}' \
  '{"schema":1,"run":"20000101T000000Z-00000004","seq":2,"at":"2000-01-01T00:00:01Z","epoch_ms":946684801000,"type":"subagent_launch","role":"other","phase":"closeout","round":1}' \
  >"$legacy_only_sink"
[[ ! -e "$sink_root/runs/$legacy_only_run.jsonl" ]]
legacy_only_checksum="$(sha256sum "$legacy_only_sink")"
legacy_only_summary="$(cd "$linked_two" && "$command_under_test" summary \
  --run "$legacy_only_run")"
[[ "$(jq -r '.subagent_launches.total' <<<"$legacy_only_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role.other' \
  <<<"$legacy_only_summary")" -eq 1 ]]
[[ "$(sha256sum "$legacy_only_sink")" == "$legacy_only_checksum" ]]
git -C "$target" worktree remove "$linked_one"
git -C "$target" worktree remove "$linked_two"

# The sink lives inside the git directory, so it is untracked by construction
# and no telemetry command dirties the worktree.
[[ -z "$(git -C "$target" status --porcelain)" ]]
[[ -d "$sink_root" ]]

# The sink records what this workstation's runs did, so nothing under it is
# readable or writable by anyone else.
assert_private() {
  local path mode
  for path in "$@"; do
    mode="$(stat -c '%a' "$path")"
    if [[ ! "$mode" =~ ^[0-7]00$ ]]; then
      printf 'FAIL[sink-permissions]: %s is mode %s\n' "$path" "$mode" >&2
      exit 1
    fi
  done
}
assert_private "$sink_root" "$sink_root/runs" \
  "$sink_root/repository-binding" "$sink_root/repository-binding.lock" \
  "$sink_root/runs/$(run_id_from_handle "$first_run").jsonl" \
  "$sink_root/runs/$(run_id_from_handle "$second_run").jsonl"

# A directory an earlier version left readable is tightened rather than reused
# as it is.
chmod 755 "$sink_root" "$sink_root/runs"
loose_run="$(telemetry start --issue 71)"
assert_private "$sink_root" "$sink_root/runs" \
  "$sink_root/repository-binding" "$sink_root/repository-binding.lock" \
  "$sink_root/runs/$(run_id_from_handle "$loose_run").jsonl"

# 2. A launch retains its role, phase, and round.
work_run="$(telemetry start --issue 71)"
telemetry launch --run "$work_run" \
  --role implementation --phase implementation --round 1
telemetry launch --run "$work_run" \
  --role other --phase gate --round 2
telemetry launch --run "$work_run" --role other --phase gate --round 2
telemetry launch --run "$work_run" \
  --role other --phase closeout --round 2
sink="$sink_root/runs/$(run_id_from_handle "$work_run").jsonl"
grep -Fqx "${work_run#*@}" "$sink_root/repository-binding"
if grep -Fq "${work_run#*@}" "$sink"; then
  printf 'FAIL[event-schema]: repository binding reached a schema-1 event\n' >&2
  exit 1
fi
launch_rows="$(jq -c 'select(.type == "subagent_launch")
  | [.role, .phase, .round]' "$sink")"
grep -Fqx '["implementation","implementation",1]' <<<"$launch_rows"
grep -Fqx '["other","gate",2]' <<<"$launch_rows"
grep -Fqx '["other","closeout",2]' <<<"$launch_rows"

# An unknown role, phase, kind, or round is refused rather than recorded.
refuse() {
  local label="$1"
  shift
  if telemetry "$@" >"$fixture/$label.out" 2>"$fixture/$label.err"; then
    printf 'FAIL[%s]: telemetry accepted %s\n' "$label" "$*" >&2
    exit 1
  fi
  [[ ! -s "$fixture/$label.out" ]]
}
refuse bad-role launch --run "$work_run" --role reviewer --phase gate --round 1
refuse bad-phase launch --run "$work_run" \
  --role implementation --phase deploy --round 1
refuse bad-round launch --run "$work_run" \
  --role implementation --phase gate --round -1
refuse bad-kind review-delegation --run "$work_run" --role review-spec \
  --kind smoke --phase gate --round 1 --base HEAD --worktree
refuse bad-outcome resolve --run "$work_run" --outcome merged
refuse missing-run launch --role implementation --phase gate --round 1
refuse malformed-run launch --run ../current-run \
  --role implementation --phase gate --round 1
refuse unknown-run launch \
  --run "20260101T000000Z-00000000@${first_run#*@}" \
  --role implementation --phase gate --round 1

foreign_repo="$fixture/foreign"
git init -q -b main "$foreign_repo"
git -C "$foreign_repo" config user.name 'Telemetry Test'
git -C "$foreign_repo" config user.email telemetry@example.invalid
git -C "$foreign_repo" remote add origin 'https://github.com/example/foreign.git'
printf 'foreign\n' >"$foreign_repo/file.txt"
git -C "$foreign_repo" add .
git -C "$foreign_repo" commit -qm 'first'
foreign_run="$(cd "$foreign_repo" && "$command_under_test" start --issue 71)"
refuse foreign-run launch --run "$foreign_run" \
  --role implementation --phase gate --round 1

# A run handle is repository-bound even when independent repositories mint the
# same run-id component. Fixing the public clock and random boundary reproduces
# the collision deterministically; repository B must not gain authority over
# repository A's handle merely because B has a same-named sink.
collision_bin="$fixture/collision-bin"
mkdir "$collision_bin"
cat >"$collision_bin/date" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  +%Y%m%dT%H%M%SZ) printf '20260816T180000Z\n' ;;
  +%Y-%m-%dT%H:%M:%SZ) printf '2026-08-16T18:00:00Z\n' ;;
  +%s) printf '1786903200\n' ;;
  *) exit 1 ;;
esac
EOF
cat >"$collision_bin/od" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *' -N4 '* ]]; then
  printf ' aa bb cc dd\n'
else
  /usr/bin/od "$@"
fi
EOF
chmod +x "$collision_bin/date" "$collision_bin/od"

collision_a="$fixture/collision-a"
collision_b="$fixture/collision-b"
for collision_repo in "$collision_a" "$collision_b"; do
  git init -q -b main "$collision_repo"
  git -C "$collision_repo" config user.name 'Telemetry Test'
  git -C "$collision_repo" config user.email telemetry@example.invalid
  git -C "$collision_repo" remote add origin \
    "https://github.com/example/$(basename "$collision_repo").git"
  printf 'collision\n' >"$collision_repo/file.txt"
  git -C "$collision_repo" add .
  git -C "$collision_repo" commit -qm 'first'
done
collision_a_run="$(cd "$collision_a" && \
  PATH="$collision_bin:$PATH" "$command_under_test" start --issue 71)"
collision_b_run="$(cd "$collision_b" && \
  PATH="$collision_bin:$PATH" "$command_under_test" start --issue 71)"
[[ "$(run_id_from_handle "$collision_a_run")" == \
  20260816T180000Z-aabbccdd ]]
[[ "$(run_id_from_handle "$collision_b_run")" == \
  "$(run_id_from_handle "$collision_a_run")" ]]
[[ "$collision_b_run" != "$collision_a_run" ]]
(cd "$collision_a" && "$command_under_test" launch \
  --run "$collision_a_run" \
  --role implementation --phase implementation --round 1)
(cd "$collision_b" && "$command_under_test" launch \
  --run "$collision_b_run" \
  --role other --phase gate --round 1)

refuse_collision() {
  local label="$1"
  shift
  if (cd "$collision_b" && "$command_under_test" "$@") \
      >"$fixture/collision-$label.out" \
      2>"$fixture/collision-$label.err"; then
    printf 'FAIL[repository-binding-%s]: repository B accepted repository A handle\n' \
      "$label" >&2
    exit 1
  fi
  [[ ! -s "$fixture/collision-$label.out" ]]
  grep -Fq 'run handle belongs to another repository' \
    "$fixture/collision-$label.err"
}
refuse_collision launch launch --run "$collision_a_run" \
  --role implementation --phase implementation --round 2
refuse_collision review review-delegation --run "$collision_a_run" \
  --role review-spec --kind full --phase gate --round 2 --base HEAD --head HEAD
refuse_collision exec exec --run "$collision_a_run" \
  --command-id foreign-check --phase gate --round 2 -- true
refuse_collision resolve resolve --run "$collision_a_run" --outcome Closes
refuse_collision summary summary --run "$collision_a_run"

[[ "$(cd "$collision_a" && "$command_under_test" summary \
  --run "$collision_a_run" | jq -r '.subagent_launches.total')" -eq 1 ]]
[[ "$(cd "$collision_b" && "$command_under_test" summary \
  --run "$collision_b_run" | jq -r '.subagent_launches.total')" -eq 1 ]]

# 3. A reviewer delegation retains its role, kind, compared SHAs, and input
# byte count in one event.
base_sha="$(git -C "$target" rev-parse HEAD)"
printf 'SYNTHETIC-DIFF-CONTENT-MARKER\n' >"$target/second.txt"
git -C "$target" add .
git -C "$target" commit -qm 'second'
head_sha="$(git -C "$target" rev-parse HEAD)"
expected_bytes="$(git -C "$target" diff "$base_sha...$head_sha" | wc -c | tr -d ' ')"
[[ "$expected_bytes" -gt 0 ]]

telemetry review-delegation --run "$work_run" --role review-standards \
  --kind full --phase gate --round 1 \
  --base "$base_sha" --head "$head_sha"
full_review="$(jq -c 'select(.type == "review_delegation" and .kind == "full")' "$sink")"
[[ "$(jq -r '.role' <<<"$full_review")" == review-standards ]]
[[ "$(jq -r '.base' <<<"$full_review")" == "$base_sha" ]]
[[ "$(jq -r '.head' <<<"$full_review")" == "$head_sha" ]]
[[ "$(jq -r '.input_bytes' <<<"$full_review")" -eq "$expected_bytes" ]]
[[ "$(jq -r '.head_is_worktree' <<<"$full_review")" == false ]]
[[ "$(jq -r '.phase' <<<"$full_review")" == gate ]]
[[ "$(jq -r '.round' <<<"$full_review")" -eq 1 ]]

# A readiness sweep reads the worktree before the first commit, so its compared
# material is the uncommitted diff against the recorded base.
printf 'SYNTHETIC-WORKTREE-CONTENT-MARKER\n' >"$target/third.txt"
git -C "$target" add third.txt
worktree_bytes="$(git -C "$target" diff "$head_sha" | wc -c | tr -d ' ')"
[[ "$worktree_bytes" -gt 0 ]]
telemetry review-delegation --run "$work_run" --role readiness \
  --kind readiness --phase checkpoint --round 1 \
  --base "$head_sha" --worktree
readiness_review="$(jq -c 'select(.type == "review_delegation" and .kind == "readiness")' "$sink")"
[[ "$(jq -r '.head_is_worktree' <<<"$readiness_review")" == true ]]
[[ "$(jq -r '.input_bytes' <<<"$readiness_review")" -eq "$worktree_bytes" ]]

# A file git does not track yet is still material the sweep reads, so it counts
# toward the measured bundle; a file the repository ignores does not.
review_bytes() {
  telemetry review-delegation --run "$work_run" --role readiness \
    --kind readiness --phase checkpoint --round 1 \
    --base "$head_sha" --worktree
  jq -r '[.[] | select(.type == "review_delegation" and .kind == "readiness")][-1]
    | .input_bytes' -s "$sink"
}
# What one untracked file contributes to the bundle, computed independently of
# the recorder.
untracked_bundle_bytes() {
  # `--no-index` reports a difference with status 1, which is the expected
  # result here rather than a failure.
  { git -C "$target" -c core.quotePath=false --no-pager diff --no-ext-diff \
    --no-color --no-textconv --no-index -- /dev/null "$1" || true; } \
    | wc -c | tr -d ' '
}
tracked_only_bytes="$(review_bytes)"
printf 'SYNTHETIC-UNTRACKED-CONTENT-MARKER\n' >"$target/untracked.txt"
with_untracked_bytes="$(review_bytes)"
# The file is genuinely untracked at the moment it is measured — the recorder
# does not stage or commit anything to make it countable.
[[ "$(git -C "$target" status --porcelain -- untracked.txt)" == '?? untracked.txt' ]]
[[ $(( with_untracked_bytes - tracked_only_bytes )) \
  -eq "$(untracked_bundle_bytes untracked.txt)" ]]
[[ "$(untracked_bundle_bytes untracked.txt)" \
  -gt "$(wc -c <"$target/untracked.txt")" ]]

# A name needing quoting is passed through exactly, not skipped and not
# mismeasured.
quoted_name='needs "quoting" and spaces.txt'
printf 'SYNTHETIC-QUOTED-NAME-CONTENT-MARKER\n' >"$target/$quoted_name"
with_quoted_bytes="$(review_bytes)"
[[ $(( with_quoted_bytes - with_untracked_bytes )) \
  -eq "$(untracked_bundle_bytes "$quoted_name")" ]]

# A tracked change counts whether it is staged or not, and staging an existing
# change does not change what the sweep is measured to have read.
printf 'SYNTHETIC-WORKTREE-CONTENT-MARKER\n' >>"$target/first.txt"
unstaged_bytes="$(review_bytes)"
[[ "$unstaged_bytes" -gt "$with_quoted_bytes" ]]
git -C "$target" add first.txt
[[ "$(review_bytes)" -eq "$unstaged_bytes" ]]

printf 'ignored.txt\n' >"$target/.gitignore"
printf 'SYNTHETIC-IGNORED-CONTENT-MARKER\n' >"$target/ignored.txt"
git -C "$target" add .gitignore
git -C "$target" commit -qm 'ignore fixture'
head_sha="$(git -C "$target" rev-parse HEAD)"
tracked_only_bytes="$(review_bytes)"
printf 'SYNTHETIC-IGNORED-CONTENT-MARKER\n' >>"$target/ignored.txt"
[[ "$(review_bytes)" -eq "$tracked_only_bytes" ]]

# The whole measurement is the defined bundle and nothing else: tracked changes
# against the base, then every untracked, non-ignored file.
expected_bundle=$(git -C "$target" -c core.quotePath=false --no-pager diff \
  --no-ext-diff --no-color --no-textconv "$head_sha" | wc -c)
while IFS= read -r -d '' candidate; do
  expected_bundle=$(( expected_bundle + $(untracked_bundle_bytes "$candidate") ))
done < <(git -C "$target" ls-files --others --exclude-standard -z)
[[ "$(review_bytes)" -eq "$expected_bundle" ]]

# The bundle is the repository's, not the caller's working directory's: a review
# recorded from a subdirectory measures the same artifact.
mkdir -p "$target/nested"
printf 'SYNTHETIC-NESTED-CONTENT-MARKER\n' >"$target/nested/nested.txt"
nested_bytes="$(review_bytes)"
(cd "$target/nested" && "$command_under_test" review-delegation \
  --run "$work_run" --role readiness \
  --kind readiness --phase checkpoint --round 1 \
  --base "$head_sha" --worktree)
[[ "$(jq -r '[.[] | select(.type == "review_delegation" and .kind == "readiness")][-1]
  | .input_bytes' -s "$sink")" -eq "$nested_bytes" ]]

# `delta` is recordable even though the workflow does not yet run delta review.
telemetry review-delegation --run "$work_run" --role review-spec \
  --kind delta --phase remediation --round 2 \
  --base "$base_sha" --head "$head_sha"
[[ "$(jq -r '.review_delegations.by_kind.delta' \
  <<<"$(telemetry summary --run "$work_run")")" -eq 1 ]]

# 4. A validation execution gets a stable execution id, a duration, and an
# outcome, and the wrapper is transparent to the command's status and output.
telemetry exec --run "$work_run" --command-id emit-stdout --phase gate --round 1 -- \
  bash -c "$emit_stdout_marker" >"$fixture/passed.out"
grep -Fqx "$stdout_marker" "$fixture/passed.out"

if telemetry exec --run "$work_run" \
    --command-id emit-stderr --phase gate --round 1 -- \
    bash -c "$emit_stderr_marker; exit 3" \
    >"$fixture/failed.out" 2>"$fixture/failed.err"; then
  printf 'FAIL[exec-status]: a failing command reported success\n' >&2
  exit 1
fi
grep -Fqx "$stderr_marker" "$fixture/failed.err"

passed_id="$(jq -r 'select(.type == "validation_end" and .outcome == "passed")
  | .exec_id' "$sink")"
failed_id="$(jq -r 'select(.type == "validation_end" and .outcome == "failed")
  | .exec_id' "$sink")"
[[ "$passed_id" != "$failed_id" ]]
# The id is stable across the execution: its start and end carry the same one.
[[ "$(jq -r "select(.exec_id == \"$passed_id\") | .type" "$sink" | sort | tr '\n' ' ')" \
  == 'validation_end validation_start ' ]]
[[ "$(jq -r "select(.type == \"validation_end\" and .exec_id == \"$failed_id\")
  | .exit_status" "$sink")" -eq 3 ]]
jq -e 'select(.type == "validation_end")
  | .duration_ms | type == "number" and . >= 0' "$sink" >/dev/null
# The supplied identifier is what makes two executions the same validation: the
# same id twice is one identity, a different id is a different one.
telemetry exec --run "$work_run" \
  --command-id emit-stdout --phase gate --round 1 -- \
  bash -c "$emit_stdout_marker" >/dev/null
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$sink" \
  | sort -u | wc -l)" -eq 3 ]]
[[ "$(jq -r 'select(.type == "validation_start") | .command_id' "$sink" \
  | sort -u | wc -l)" -eq 2 ]]

# An identifier outside the narrow supplied syntax is refused before the command
# runs, so a path, a URL, an argument, or a credential cannot become one.
refuse missing-command-id exec --run "$work_run" --phase gate --round 1 -- true
rejected_index=0
for rejected_id in 'Work-On-Tests' 'work_on_tests' './scripts/test.sh' \
    'ghp_EXAMPLENOTAREALTOKEN0000000000' 'https://example.invalid/x' \
    'trailing-' '-leading' '1st-check' 'double--hyphen' 'has space' \
    'aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeeeeff'; do
  refuse "command-id-$rejected_index" exec --run "$work_run" \
    --command-id "$rejected_id" \
    --phase gate --round 1 -- true
  rejected_index=$((rejected_index + 1))
done
for accepted_id in a lint work-on-tests npm-check-plugin-version check2 \
    aaaaaaaaaabbbbbbbbbbccccccccccddddddddddeeeeeeee; do
  telemetry exec --run "$work_run" --command-id "$accepted_id" \
    --phase gate --round 1 -- true
done
[[ "$(jq -r 'select(.type == "validation_start") | .command_id' "$sink" \
  | sort -u | wc -l)" -eq 8 ]]

# 5. An interrupted validation leaves a controlled, machine-readable record.
telemetry exec --run "$work_run" \
  --command-id self-terminating --phase gate --round 1 -- \
  bash -c 'kill -TERM $PPID; exit 0' >/dev/null 2>&1 || true
[[ "$(jq -r '.validations.interrupted' \
  <<<"$(telemetry summary --run "$work_run")")" -eq 1 ]]

# A wrapper killed outright cannot write its own end record; aggregation must
# still report a controlled `incomplete` execution instead of failing.
telemetry exec --run "$work_run" \
  --command-id self-killing --phase gate --round 1 -- \
  bash -c 'kill -9 $PPID' >/dev/null 2>&1 || true
interrupted_summary="$(telemetry summary --run "$work_run")"
[[ "$(jq -r '.validations.incomplete' <<<"$interrupted_summary")" -eq 1 ]]
[[ "$(jq -r '.validations.total' <<<"$interrupted_summary")" -eq 11 ]]
[[ "$(jq -r '.malformed_lines' <<<"$interrupted_summary")" -eq 0 ]]

# The sink survives the interruption: every line is still one JSON event and
# later recording continues in the same run.
jq -e . "$sink" >/dev/null
telemetry launch --run "$work_run" \
  --role implementation --phase remediation --round 3
[[ "$(jq -r '.subagent_launches.total' \
  <<<"$(telemetry summary --run "$work_run")")" -eq 18 ]]

# A line the recorder did not write is ignored rather than corrupting the run.
printf 'not json\n' >>"$sink"
truncated_summary="$(telemetry summary --run "$work_run")"
[[ "$(jq -r '.malformed_lines' <<<"$truncated_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$truncated_summary")" -eq 18 ]]

# 6. Token counts are optional at every stage.
[[ "$(jq -r '.tokens.coverage' <<<"$truncated_summary")" == none ]]
[[ "$(jq -r '.tokens.input' <<<"$truncated_summary")" -eq 0 ]]
telemetry launch --run "$work_run" \
  --role other --phase gate --round 3 \
  --tokens-in 1200 --tokens-out 340
partial_summary="$(telemetry summary --run "$work_run")"
[[ "$(jq -r '.tokens.coverage' <<<"$partial_summary")" == partial ]]
[[ "$(jq -r '.tokens.input' <<<"$partial_summary")" -eq 1200 ]]
[[ "$(jq -r '.tokens.output' <<<"$partial_summary")" -eq 340 ]]

token_free_run="$(telemetry start --issue 71)"
telemetry launch --run "$token_free_run" \
  --role implementation --phase implementation --round 1
token_free_summary="$(telemetry summary --run "$token_free_run")"
[[ "$(jq -r '.tokens.coverage' <<<"$token_free_summary")" == none ]]
[[ "$(jq -r '.run' <<<"$token_free_summary")" == \
  "$(run_id_from_handle "$token_free_run")" ]]

# 7/8. Secrets, command output, and repository content stay out of the sink,
# while the command itself is unaffected by being wrapped.
argv_echo="$fixture/argv-echo.sh"
cat >"$argv_echo" <<'EOF'
#!/usr/bin/env bash
printf 'ARGV:%s\n' "$@"
printf 'SYNTHETIC-%s-MARKER\n' DIAGNOSTIC >&2
exit 7
EOF
chmod +x "$argv_echo"

# Every shape the wrapper must never persist: a header value, a bearer token in
# a script's arguments, an environment assignment, a filesystem path, and
# source-shaped text.
sensitive_argv=(
  --header "Authorization: Bearer $fake_token"
  --bearer "$fake_token"
  "AWS_SECRET_ACCESS_KEY=$fake_password"
  /home/example/.config/credential-store.yml
  'const apiKey = "SYNTHETIC-SOURCE-SHAPED-SECRET";'
)
argv_status=0
telemetry exec --run "$token_free_run" \
  --command-id argv-passthrough --phase gate --round 1 -- \
  "$argv_echo" "${sensitive_argv[@]}" \
  >"$fixture/argv.out" 2>"$fixture/argv.err" || argv_status=$?

# The command received its arguments exactly, and its stdout, stderr, and exit
# status reached the caller unchanged.
printf 'ARGV:%s\n' "${sensitive_argv[@]}" >"$fixture/argv.expected"
diff -u "$fixture/argv.expected" "$fixture/argv.out"
grep -Fqx "$stderr_marker" "$fixture/argv.err"
[[ "$argv_status" -eq 7 ]]

# Arbitrary inline shell, an environment-assignment prefix, and a command that
# reads repository files are all recorded the same way: by name only.
telemetry exec --run "$token_free_run" \
  --command-id shell-inline --phase gate --round 1 -- \
  bash -c 'printf "SYNTHETIC-%s-MARKER\n" INLINE-SHELL; cat first.txt' \
  >/dev/null 2>&1 || true
telemetry exec --run "$token_free_run" \
  --command-id prefixed-assignment --phase gate --round 1 -- \
  env "GH_TOKEN=$fake_token" bash -c "$emit_stdout_marker; $emit_stderr_marker" \
  >/dev/null 2>&1
telemetry exec --run "$token_free_run" \
  --command-id repository-reader --phase gate --round 1 -- \
  cat first.txt second.txt third.txt >/dev/null 2>&1 || true

for secret in "$fake_token" "$fake_password" "$stdout_marker" \
    "$stderr_marker" SYNTHETIC-INLINE-SHELL-MARKER \
    SYNTHETIC-SOURCE-SHAPED-SECRET SYNTHETIC-FILE-CONTENT-MARKER \
    SYNTHETIC-DIFF-CONTENT-MARKER SYNTHETIC-WORKTREE-CONTENT-MARKER \
    SYNTHETIC-UNTRACKED-CONTENT-MARKER SYNTHETIC-IGNORED-CONTENT-MARKER \
    SYNTHETIC-QUOTED-NAME-CONTENT-MARKER SYNTHETIC-NESTED-CONTENT-MARKER \
    'needs "quoting" and spaces.txt'; do
  if grep -Fqr -- "$secret" "$sink_root"; then
    printf 'FAIL[sink-secrets]: %s reached the telemetry sink\n' "$secret" >&2
    exit 1
  fi
done

# Nothing of the command line reaches the sink: not an argument, not a flag, not
# a path, and not the program either. Only the supplied identifier is stored.
secret_sink="$sink_root/runs/$(run_id_from_handle "$token_free_run").jsonl"
for fragment in Authorization Bearer --header --bearer \
    AWS_SECRET_ACCESS_KEY GH_TOKEN /home/example apiKey \
    first.txt second.txt third.txt argv-echo.sh \
    bash env cat redacted; do
  if grep -Fq -- "$fragment" "$secret_sink"; then
    printf 'FAIL[sink-argv]: command material %s reached the telemetry sink\n' \
      "$fragment" >&2
    exit 1
  fi
done
for identifier in argv-passthrough shell-inline prefixed-assignment \
    repository-reader; do
  grep -Fq "\"command_id\":\"$identifier\"" "$secret_sink"
done

# The recorder has no field for a prompt, a diff, a file body, a command line,
# or output: every recorded key comes from this closed set.
readonly allowed_keys='["at","base","command_id","continues_run","duration_ms","epoch_ms","exec_id","exit_status","head","head_is_worktree","input_bytes","issue","kind","outcome","phase","repository","role","round","run","run_identity","schema","seq","tokens_in","tokens_out","type","workflow"]'
for run_sink in "$sink_root"/runs/*.jsonl; do
  unexpected="$(jq -r -R --argjson allowed "$allowed_keys" '
    fromjson? // empty | keys[]
    | . as $key | select(($allowed | index($key)) == null)
  ' <"$run_sink" | sort -u)"
  [[ -z "$unexpected" ]] || {
    printf 'FAIL[sink-keys]: unexpected key(s) in %s: %s\n' \
      "$run_sink" "$unexpected" >&2
    exit 1
  }
done

# An existing schema-1 sink remains readable through its explicit handle and is
# not rewritten as a side effect of aggregation.
legacy_run=20000101T000000Z-00000001
legacy_sink="$sink_root/runs/$legacy_run.jsonl"
printf '%s\n' \
  '{"schema":1,"run":"20000101T000000Z-00000001","seq":1,"at":"2000-01-01T00:00:00Z","epoch_ms":946684800000,"type":"run_start","workflow":"work-on"}' \
  '{"schema":1,"run":"20000101T000000Z-00000001","seq":2,"at":"2000-01-01T00:00:01Z","epoch_ms":946684801000,"type":"subagent_launch","role":"implementation","phase":"implementation","round":1}' \
  >"$legacy_sink"
chmod 600 "$legacy_sink"
legacy_before="$(sha256sum "$legacy_sink")"
legacy_summary="$(telemetry summary --run "$legacy_run")"
[[ "$(jq -r '.schema' <<<"$legacy_summary")" -eq 1 ]]
[[ "$(jq -r '.integrity.state' <<<"$legacy_summary")" == \
  legacy-unverifiable ]]
[[ "$(jq -r '.reviewer_accounting' <<<"$legacy_summary")" == \
  legacy-unverifiable ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$legacy_summary")" -eq 1 ]]
[[ "$(sha256sum "$legacy_sink")" == "$legacy_before" ]]

# 9. Aggregation is a deterministic function of the sink.
repeat_one="$(telemetry summary --run "$token_free_run")"
repeat_two="$(telemetry summary --run "$token_free_run")"
repeat_three="$(telemetry summary --run "$token_free_run")"
[[ "$repeat_one" == "$repeat_two" ]]
[[ "$repeat_one" == "$repeat_three" ]]

# The final workflow outcome is recorded and aggregated.
[[ "$(jq -r '.final_workflow_outcome' <<<"$repeat_one")" == null ]]
telemetry resolve --run "$token_free_run" --outcome Progresses
[[ "$(jq -r '.final_workflow_outcome' \
  <<<"$(telemetry summary --run "$token_free_run")")" == Progresses ]]

# Phase elapsed is reported only for phases that actually recorded events, in a
# fixed order. This run touched implementation and gate and nothing else.
phase_keys="$(jq -r '.phase_elapsed_ms | keys_unsorted | join(",")' \
  <<<"$(telemetry summary --run "$token_free_run")")"
[[ "$phase_keys" == implementation,gate ]]

# Closeout evidence may follow outcome resolution until explicit sealing.
telemetry launch --run "$token_free_run" --role other --phase closeout --round 9
telemetry exec --run "$token_free_run" \
  --command-id after-finish --phase closeout --round 9 -- true
telemetry seal --run "$token_free_run"
sealed_summary="$(telemetry summary --run "$token_free_run")"
[[ "$(jq -r '.integrity.state' <<<"$sealed_summary")" == valid ]]
refuse second-resolution resolve --run "$token_free_run" --outcome Closes
grep -Fq 'is sealed' "$fixture/second-resolution.err"
refuse after-seal launch --run "$token_free_run" \
  --role other --phase closeout --round 10

# 10. Concurrent writers do not lose, fuse, or duplicate events. Several
# subagents and validation wrappers recording at once is the ordinary case.
concurrent_run="$(telemetry start --issue 71)"
concurrent_sink="$sink_root/runs/$(run_id_from_handle "$concurrent_run").jsonl"
readonly writers=12
for ((writer = 0; writer < writers; writer++)); do
  telemetry launch --run "$concurrent_run" \
    --role implementation --phase gate --round 1 &
  telemetry exec --run "$concurrent_run" \
    --command-id concurrent-check --phase gate --round 1 -- true \
    >/dev/null &
done
wait

concurrent_summary="$(telemetry summary --run "$concurrent_run")"
[[ "$(jq -r '.malformed_lines' <<<"$concurrent_summary")" -eq 0 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$concurrent_summary")" -eq "$writers" ]]
[[ "$(jq -r '.validations.total' <<<"$concurrent_summary")" -eq "$writers" ]]
[[ "$(jq -r '.validations.passed' <<<"$concurrent_summary")" -eq "$writers" ]]
[[ "$(jq -r '.validations.incomplete' <<<"$concurrent_summary")" -eq 0 ]]
# One run_start, one launch per writer, and a start plus an end per execution.
[[ "$(wc -l <"$concurrent_sink")" -eq $((1 + writers * 3)) ]]
# Every retained line is one whole JSON event, so no append landed inside
# another and nothing was lost.
jq -e . "$concurrent_sink" >/dev/null
[[ "$(jq -r '.events' <<<"$concurrent_summary")" -eq $((1 + writers * 3)) ]]
# Sequence numbers and execution ids are allocated exactly once each.
[[ "$(jq -r '.seq' "$concurrent_sink" | sort -u | wc -l)" \
  -eq $((1 + writers * 3)) ]]
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$concurrent_sink" \
  | sort -u | wc -l)" -eq "$writers" ]]
# Every start is closed by exactly one end carrying the same execution id, and
# no end belongs to a start that was never written.
[[ "$(jq -r 'select(.type == "validation_end") | .exec_id' "$concurrent_sink" \
  | sort -u | wc -l)" -eq "$writers" ]]
[[ "$(jq -r 'select(.type | startswith("validation_")) | .exec_id' \
  "$concurrent_sink" | sort | uniq -c | awk '$1 != 2' | wc -l)" -eq 0 ]]
[[ "$(jq -r 'select(.type == "validation_start") | .exec_id' "$concurrent_sink" \
  | sort)" == "$(jq -r 'select(.type == "validation_end") | .exec_id' \
  "$concurrent_sink" | sort)" ]]
assert_private "$concurrent_sink"

# 11. A writer killed mid-append leaves a line with no terminator. The next
# append closes it off rather than fusing with it, so one torn line costs one
# malformed line and nothing else.
torn_run="$(telemetry start --issue 71)"
torn_run_id="$(run_id_from_handle "$torn_run")"
torn_sink="$sink_root/runs/$torn_run_id.jsonl"
printf '{"schema":1,"run":"%s","seq":2,"type":"subagent_lau' "$torn_run_id" \
  >>"$torn_sink"
telemetry launch --run "$torn_run" --role other --phase closeout --round 1
torn_summary="$(telemetry summary --run "$torn_run")"
[[ "$(jq -r '.malformed_lines' <<<"$torn_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.total' <<<"$torn_summary")" -eq 1 ]]
[[ "$(jq -r '.subagent_launches.by_role.other' <<<"$torn_summary")" -eq 1 ]]
# The recovered event is a whole line of its own, and the torn one still ends
# where it was cut.
[[ "$(wc -l <"$torn_sink")" -eq 3 ]]
grep -Fqx '{"schema":1,"run":"'"$torn_run_id"'","seq":2,"type":"subagent_lau' \
  "$torn_sink"
[[ "$(jq -R -r 'fromjson? // empty
  | select(.type == "subagent_launch") | .seq' "$torn_sink")" -eq 3 ]]

# Recording outside a started run is refused rather than silently dropped.
bare="$fixture/bare"
git init -q -b main "$bare"
if (cd "$bare" && "$command_under_test" launch \
    --run 20260101T000000Z-00000000@00000000000000000000000000000000 \
    --role implementation --phase gate --round 1) \
    >"$fixture/bare.out" 2>"$fixture/bare.err"; then
  printf 'FAIL[bare]: telemetry recorded without a started run\n' >&2
  exit 1
fi
[[ ! -s "$fixture/bare.out" ]]
grep -Fq 'repository binding is missing' "$fixture/bare.err"

# Telemetry requires a Git-backed target repository.
if (cd "$fixture" && "$command_under_test" start --issue 71) \
    >"$fixture/non-git.out" 2>"$fixture/non-git.err"; then
  printf 'FAIL[non-git]: telemetry started outside a repository\n' >&2
  exit 1
fi
[[ ! -s "$fixture/non-git.out" ]]

printf 'work-on run telemetry black-box scenarios passed\n'
