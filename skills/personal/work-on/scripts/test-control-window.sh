#!/usr/bin/env bash
set -euo pipefail

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
adapter="$script_root/control-window.sh"
fixtures="$(dirname "$script_root")/fixtures/control-window"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'control window test: %s\n' "$1" >&2
  exit 1
}

scenario() {
  printf 'scenario: %s\n' "$1"
}

export XDG_STATE_HOME="$test_root/state"
export XDG_CONFIG_HOME="$test_root/config"

scenario policy-manifests-are-versioned-and-reusable
"$adapter" validate --policy "$fixtures/demo-policy.json" >/dev/null
"$adapter" validate --policy "$fixtures/b2-like-policy.json" >/dev/null
unsafe_policy="$test_root/unsafe-policy.json"
jq '.results.pull_request.reviewer_material = "free-form review"' \
  "$fixtures/demo-policy.json" >"$unsafe_policy"
! "$adapter" validate --policy "$unsafe_policy" >/dev/null 2>&1 \
  || fail "policy accepted a free-form publication field"

scenario prepared-demo-policy-never-matches-or-activates
export WORK_ON_CONTROL_POLICY="$fixtures/demo-policy.json"
if "$adapter" applies --repository faviann/skills --issue 73 >"$test_root/applies"; then
  fail "a prepared demo policy matched observation work"
else
  [[ "$?" -eq 3 ]] || fail "a non-matching policy did not use the observer not-applicable status"
fi
[[ ! -s "$test_root/applies" ]] || fail "a non-matching policy emitted applicability material"
! "$adapter" activate --policy "$fixtures/demo-policy.json" >/dev/null 2>&1 \
  || fail "a demo policy could activate"

scenario ordinary-runs-preserve-the-generic-registry-path
unset WORK_ON_CONTROL_POLICY WORK_ON_OBSERVER || true
ordinary="$test_root/ordinary"
mkdir -p "$ordinary"
git -C "$ordinary" init -q
git -C "$ordinary" config user.name tester
git -C "$ordinary" config user.email tester@example.invalid
git -C "$ordinary" remote add origin git@github.com:example/ordinary.git
printf 'ordinary\n' >"$ordinary/README.md"
git -C "$ordinary" add README.md
git -C "$ordinary" commit -qm base
ordinary_handle="$(cd "$ordinary" && "$script_root/run-telemetry.sh" start --issue 1)"
[[ "$(cd "$ordinary" && "$adapter" register --run "$ordinary_handle")" \
  == "registered ${ordinary_handle%@*} observer=none control=none" ]] \
  || fail "the adapter changed ordinary generic registration"
[[ "$(cd "$ordinary" && "$adapter" finalize --run "$ordinary_handle" \
  --outcome preflight-aborted)" == "finalized ${ordinary_handle%@*}" ]] \
  || fail "the adapter changed ordinary generic finalization"

scenario prepared-results-surface-precedes-activation
seed="$test_root/seed"
remote="$test_root/results.git"
mkdir -p "$seed"
git -C "$seed" init -q
git -C "$seed" config user.name tester
git -C "$seed" config user.email tester@example.invalid
printf 'base\n' >"$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit -qm base
git -C "$seed" branch -M main
git clone -q --bare "$seed" "$remote"

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
export CONTROL_WINDOW_REAL_GIT="$(command -v git)"
cat >"$fake_bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
state="${CONTROL_WINDOW_FAKE_GH_STATE:?}"
[[ "${1:-}" == pr ]] || exit 2
case "${2:-}" in
  list)
    if [[ -f "$state" ]]; then jq -cs '.' "$state"; else printf '[]\n'; fi
    ;;
  create)
    shift 2
    base="" head="" title="" body_file=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        -R|--repo) shift 2 ;;
        --base) base="$2"; shift 2 ;;
        --head) head="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --body-file) body_file="$2"; shift 2 ;;
        --draft) shift ;;
        *) exit 2 ;;
      esac
    done
    jq -cn --argjson number 101 --arg url 'https://example.invalid/pull/101' \
      --arg base "$base" --arg head "$head" --arg title "$title" \
      --arg body "$(cat "$body_file")" \
      '{number:$number,url:$url,isDraft:true,baseRefName:$base,headRefName:$head,title:$title,body:$body,state:"OPEN"}' >"$state"
    printf 'https://example.invalid/pull/101\n'
    ;;
  view)
    cat "$state"
    ;;
  *) exit 2 ;;
esac
GH
chmod +x "$fake_bin/gh"
cat >"$fake_bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
repository=""
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  if [[ "${arguments[$index]}" == -C ]]; then
    repository="${arguments[$((index + 1))]}"
    break
  fi
done
if [[ -n "${CONTROL_WINDOW_KILL_AFTER_ACTIVATION_MARKER:-}" ]]; then
  for argument in "$@"; do
    if [[ "$argument" == push && -n "$repository" \
      && "$("$CONTROL_WINDOW_REAL_GIT" -C "$repository" log -1 --format=%s)" \
        == "Append control-activated: fixture-b2-comparison" ]]; then
      "$CONTROL_WINDOW_REAL_GIT" "$@"
      : >"$CONTROL_WINDOW_KILL_AFTER_ACTIVATION_MARKER"
      kill -KILL "$PPID"
      exit 1
    fi
  done
fi
if [[ -n "${CONTROL_WINDOW_KILL_AFTER_CLOSING_MARKER:-}" ]]; then
  for argument in "$@"; do
    if [[ "$argument" == push && -n "$repository" \
      && "$("$CONTROL_WINDOW_REAL_GIT" -C "$repository" log -1 --format=%s)" \
        == Append\ control-closing:* ]]; then
      "$CONTROL_WINDOW_REAL_GIT" "$@"
      : >"$CONTROL_WINDOW_KILL_AFTER_CLOSING_MARKER"
      kill -KILL "$PPID"
      exit 1
    fi
  done
fi
if [[ -n "${CONTROL_WINDOW_CLOSING_BARRIER:-}" ]]; then
  for argument in "$@"; do
    if [[ "$argument" == push && -n "$repository" \
      && "$("$CONTROL_WINDOW_REAL_GIT" -C "$repository" log -1 --format=%s)" \
        == Append\ control-closing:* ]]; then
      mkdir -p "$CONTROL_WINDOW_CLOSING_BARRIER"
      : >"$CONTROL_WINDOW_CLOSING_BARRIER/entered"
      while [[ ! -e "$CONTROL_WINDOW_CLOSING_BARRIER/release" ]]; do
        sleep 0.02
      done
      break
    fi
  done
fi
if [[ -n "${CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER:-}" ]]; then
  for argument in "$@"; do
    if [[ "$argument" == push && ! -e "$CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER" ]]; then
      "$CONTROL_WINDOW_REAL_GIT" "$@"
      : >"$CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER"
      exit 1
    fi
  done
fi
if [[ -n "${CONTROL_WINDOW_CAPTURE_COMMITS:-}" ]]; then
  for argument in "$@"; do
    if [[ "$argument" == commit && -n "$repository" ]]; then
      "$CONTROL_WINDOW_REAL_GIT" "$@"
      "$CONTROL_WINDOW_REAL_GIT" -C "$repository" show -s \
        --format='%an|%ae|%cn|%ce|%s' HEAD \
        >>"$CONTROL_WINDOW_CAPTURE_COMMITS"
      exit 0
    fi
  done
fi
exec "$CONTROL_WINDOW_REAL_GIT" "$@"
GIT
chmod +x "$fake_bin/git"
export PATH="$fake_bin:$PATH"
export CONTROL_WINDOW_FAKE_GH_STATE="$test_root/pr.json"
export CONTROL_WINDOW_REMOTE_URL="$remote"
demo_policy="$test_root/demo-policy.json"
jq --arg branch 'demo/control-window-prepared-test' \
  '.results.branch = $branch' "$fixtures/demo-policy.json" >"$demo_policy"
export WORK_ON_CONTROL_POLICY="$demo_policy"

prepared_url="$($adapter prepare --policy "$demo_policy")"
[[ "$prepared_url" == https://example.invalid/pull/101 ]] \
  || fail "prepare did not return the verified draft PR URL"
git --git-dir="$remote" show-ref --verify --quiet \
  refs/heads/demo/control-window-prepared-test \
  || fail "prepare did not create the evidence branch"
head="$(git --git-dir="$remote" rev-parse refs/heads/demo/control-window-prepared-test)"
tree="$(git --git-dir="$remote" ls-tree -r --name-only "$head")"
grep -Fxq 'control-window/demo-control-window-73/policy.json' <<<"$tree" \
  || fail "the prepared branch lacks its bounded policy projection"
[[ "$(grep -c '/transitions/' <<<"$tree")" -eq 1 ]] \
  || fail "prepare did not publish exactly one transition artifact"
[[ "$(jq -r .phase "$(dirname "$XDG_STATE_HOME")/state/work-on/control-windows/demo-control-window-73.json")" == prepared ]] \
  || fail "prepare did not retain distinct prepared state"
grep -Fq 'PREPARED / NON-OBSERVING' "$CONTROL_WINDOW_FAKE_GH_STATE" \
  || fail "the draft PR does not visibly identify prepared non-observing state"
before_count="$(git --git-dir="$remote" rev-list --count main..demo/control-window-prepared-test)"
[[ "$($adapter prepare --policy "$demo_policy")" == "$prepared_url" ]] \
  || fail "an idempotent prepare did not adopt the existing PR"
after_count="$(git --git-dir="$remote" rev-list --count main..demo/control-window-prepared-test)"
[[ "$before_count" == "$after_count" ]] \
  || fail "an idempotent prepare appended a second prepared transition"
[[ ! -e "$XDG_CONFIG_HOME/work-on/observer" \
  && ! -e "$XDG_CONFIG_HOME/work-on/control-policy" ]] \
  || fail "demo preparation installed a real observer/control descriptor"

scenario publisher-commit-metadata-is-closed-and-bounded
privacy_policy="$test_root/privacy-production-policy.json"
jq --arg control fixture-control-window-privacy \
  --arg branch experiment/control-window-privacy \
  '.control_id = $control | .results.branch = $branch' \
  "$fixtures/b2-like-policy.json" >"$privacy_policy"
privacy_hooks="$test_root/privacy-hooks"
privacy_hook_marker="$test_root/privacy-hook-ran"
mkdir -p "$privacy_hooks"
cat >"$privacy_hooks/commit-msg" <<HOOK
#!/usr/bin/env bash
printf '\nSECRET REVIEWER MATERIAL\n' >>"\$1"
: >"$privacy_hook_marker"
HOOK
chmod +x "$privacy_hooks/commit-msg"
privacy_git_config="$test_root/privacy-gitconfig"
printf '[user]\n\tname = AMBIENT PROMPT SENTINEL\n\temail = ambient-credential@example.invalid\n[core]\n\thooksPath = %s\n' \
  "$privacy_hooks" >"$privacy_git_config"
export GIT_CONFIG_GLOBAL="$privacy_git_config"
export CONTROL_WINDOW_GIT_NAME='CONTROL REVIEWER PROSE SENTINEL'
export CONTROL_WINDOW_GIT_EMAIL='control-credential@example.invalid'
export GIT_AUTHOR_NAME='AUTHOR PROMPT SENTINEL'
export GIT_AUTHOR_EMAIL='author-credential@example.invalid'
export GIT_COMMITTER_NAME='COMMITTER DIAGNOSTIC SENTINEL'
export GIT_COMMITTER_EMAIL='committer-credential@example.invalid'
export CONTROL_WINDOW_CAPTURE_COMMITS="$test_root/privacy-local-commits"
rm -f "$CONTROL_WINDOW_FAKE_GH_STATE"
env XDG_STATE_HOME="$test_root/privacy-state" \
  XDG_CONFIG_HOME="$test_root/privacy-config" \
  WORK_ON_CONTROL_POLICY="$privacy_policy" \
  "$adapter" prepare --policy "$privacy_policy" >/dev/null
env XDG_STATE_HOME="$test_root/privacy-state" \
  XDG_CONFIG_HOME="$test_root/privacy-config" \
  WORK_ON_CONTROL_POLICY="$privacy_policy" \
  "$adapter" activate --policy "$privacy_policy" >/dev/null
privacy_surface="$test_root/privacy-surface"
{
  git --git-dir="$remote" log --format=fuller --stat -p \
    main..experiment/control-window-privacy
  cat "$CONTROL_WINDOW_FAKE_GH_STATE"
} >"$privacy_surface"
for sentinel in \
  'SECRET REVIEWER MATERIAL' \
  'AMBIENT PROMPT SENTINEL' 'ambient-credential@example.invalid' \
  'CONTROL REVIEWER PROSE SENTINEL' 'control-credential@example.invalid' \
  'AUTHOR PROMPT SENTINEL' 'author-credential@example.invalid' \
  'COMMITTER DIAGNOSTIC SENTINEL' 'committer-credential@example.invalid'; do
  ! grep -Fq "$sentinel" "$privacy_surface" \
    || fail "publisher retained prohibited Git metadata: $sentinel"
  ! grep -Fq "$sentinel" "$CONTROL_WINDOW_CAPTURE_COMMITS" \
    || fail "local evidence commit retained prohibited Git metadata: $sentinel"
done
[[ ! -e "$privacy_hook_marker" ]] \
  || fail "ambient commit-msg hook executed during evidence creation"
privacy_metadata="$(git --git-dir="$remote" log --reverse \
  --format='%an|%ae|%cn|%ce|%s' main..experiment/control-window-privacy)"
expected_privacy_metadata=$'Control Window Publisher|control-window@invalid.local|Control Window Publisher|control-window@invalid.local|Prepare control results: fixture-control-window-privacy\nControl Window Publisher|control-window@invalid.local|Control Window Publisher|control-window@invalid.local|Append control-activated: fixture-control-window-privacy'
[[ "$privacy_metadata" == "$expected_privacy_metadata" \
  && "$(cat "$CONTROL_WINDOW_CAPTURE_COMMITS")" == "$expected_privacy_metadata" ]] \
  || fail "publisher did not force its bounded commit identity and message"
unset GIT_CONFIG_GLOBAL CONTROL_WINDOW_GIT_NAME CONTROL_WINDOW_GIT_EMAIL \
  GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
  CONTROL_WINDOW_CAPTURE_COMMITS

scenario activation-readback-precedes-matching
rm -f "$CONTROL_WINDOW_FAKE_GH_STATE"
production_policy="$test_root/production-policy.json"
jq --arg branch 'experiment/fixture-b2-activation-test' \
  '.results.branch = $branch' "$fixtures/b2-like-policy.json" >"$production_policy"
export WORK_ON_CONTROL_POLICY="$production_policy"
"$adapter" prepare --policy "$production_policy" >/dev/null
published_policy="$(git --git-dir="$remote" show \
  experiment/fixture-b2-activation-test:control-window/fixture-b2-comparison/policy.json)"
[[ "$(jq -r '.arm | has("configuration")' <<<"$published_policy")" == false \
  && "$(jq -r '.results | has("pull_request")' <<<"$published_policy")" == false ]] \
  || fail "the public policy serializer copied local free-form configuration"
# An ordinary advance of the configured base is not a results-branch rewrite;
# later verification remains pinned to the preparation merge-base.
printf 'base advanced\n' >>"$seed/README.md"
git -C "$seed" add README.md
git -C "$seed" commit -qm 'advance main after preparation'
git -C "$seed" push -q "$remote" main
if "$adapter" applies --repository example/comparison-repository --issue 101 \
  >"$test_root/pre-activation-applies"; then
  fail "prepared production state matched before activation"
else
  [[ "$?" -eq 3 ]] || fail "prepared production state returned a policy error"
fi
rm -f "$CONTROL_WINDOW_FAKE_GH_STATE"
! "$adapter" activate --policy "$production_policy" >/dev/null 2>&1 \
  || fail "activation proceeded without the prepared results PR"
"$adapter" prepare --policy "$production_policy" >/dev/null
scenario remote-activation-is-authoritative-after-local-state-loss
activation_crash_target="$test_root/activation-crash-target"
mkdir -p "$activation_crash_target"
git -C "$activation_crash_target" init -q
git -C "$activation_crash_target" config user.name tester
git -C "$activation_crash_target" config user.email tester@example.invalid
git -C "$activation_crash_target" remote add origin \
  git@github.com:example/comparison-repository.git
printf 'activation crash target\n' >"$activation_crash_target/README.md"
git -C "$activation_crash_target" add README.md
git -C "$activation_crash_target" commit -qm base
activation_crash_handle="$(cd "$activation_crash_target" \
  && "$script_root/run-telemetry.sh" start --issue 101)"
export GIT_CONFIG_GLOBAL="$privacy_git_config"
export CONTROL_WINDOW_GIT_NAME='CONTROL REVIEWER PROSE SENTINEL'
export CONTROL_WINDOW_GIT_EMAIL='control-credential@example.invalid'
export GIT_AUTHOR_NAME='AUTHOR PROMPT SENTINEL'
export GIT_AUTHOR_EMAIL='author-credential@example.invalid'
export GIT_COMMITTER_NAME='COMMITTER DIAGNOSTIC SENTINEL'
export GIT_COMMITTER_EMAIL='committer-credential@example.invalid'
export CONTROL_WINDOW_KILL_AFTER_ACTIVATION_MARKER="$test_root/activation-killed"
! "$adapter" activate --policy "$production_policy" >/dev/null 2>&1 \
  || fail "activation caller survived the injected post-push loss"
unset CONTROL_WINDOW_KILL_AFTER_ACTIVATION_MARKER
[[ -e "$test_root/activation-killed" ]] \
  || fail "activation crash did not occur after the remote write"
state_file="$XDG_STATE_HOME/work-on/control-windows/fixture-b2-comparison.json"
[[ "$(jq -r .phase "$state_file")" == prepared ]] \
  || fail "the crash fixture did not preserve stale prepared local state"
activation_count_before_registration="$(git --git-dir="$remote" grep -l \
  '"kind": "control-activated"' experiment/fixture-b2-activation-test \
  | wc -l)"
crash_registration="$(cd "$activation_crash_target" \
  && "$adapter" register --run "$activation_crash_handle")"
[[ "$crash_registration" == "registered ${activation_crash_handle%@*}" ]] \
  || fail "post-activation matching registration escaped control governance"
[[ "$(cd "$activation_crash_target" && "$script_root/run-registry.sh" status \
  --run "$activation_crash_handle" | jq -r .control_id)" == fixture-b2-comparison ]] \
  || fail "post-activation matching registration became ungoverned"
activation_id="$($adapter activate --policy "$production_policy")"
activation_count_after_retry="$(git --git-dir="$remote" grep -l \
  '"kind": "control-activated"' experiment/fixture-b2-activation-test \
  | wc -l)"
[[ "$activation_count_before_registration" -eq 1 \
  && "$activation_count_after_retry" -eq 1 ]] \
  || fail "activation recovery produced another logical transition"
rm -f "$state_file"
"$adapter" prepare --policy "$production_policy" >/dev/null
[[ "$(jq -r .phase "$state_file")" == active ]] \
  || fail "prepare hid an already-active remote control behind prepared state"
rm -f "$state_file"
[[ "$($adapter applies --repository example/comparison-repository --issue 101)" \
  == $'observer=control-window-publisher\ncontrol=fixture-b2-comparison' ]] \
  || fail "missing local state hid an already-active remote control"
[[ "$(jq -r .phase "$state_file")" == active ]] \
  || fail "remote activation did not reconstruct missing local state"
"$adapter" finalize --run "$activation_crash_handle" --outcome abandoned >/dev/null
git --git-dir="$remote" log --format=fuller --stat -p \
  main..experiment/fixture-b2-activation-test >"$test_root/append-privacy-surface"
cat "$CONTROL_WINDOW_FAKE_GH_STATE" >>"$test_root/append-privacy-surface"
for sentinel in \
  'AMBIENT PROMPT SENTINEL' 'ambient-credential@example.invalid' \
  'CONTROL REVIEWER PROSE SENTINEL' 'control-credential@example.invalid' \
  'AUTHOR PROMPT SENTINEL' 'author-credential@example.invalid' \
  'COMMITTER DIAGNOSTIC SENTINEL' 'committer-credential@example.invalid'; do
  ! grep -Fq "$sentinel" "$test_root/append-privacy-surface" \
    || fail "append publication retained prohibited Git metadata: $sentinel"
done
while IFS='|' read -r author_name author_email committer_name committer_email; do
  [[ "$author_name" == 'Control Window Publisher' \
    && "$author_email" == 'control-window@invalid.local' \
    && "$committer_name" == 'Control Window Publisher' \
    && "$committer_email" == 'control-window@invalid.local' ]] \
    || fail "an append commit escaped the fixed publisher identity"
done < <(git --git-dir="$remote" log --format='%an|%ae|%cn|%ce' \
  main..experiment/fixture-b2-activation-test)
unset GIT_CONFIG_GLOBAL CONTROL_WINDOW_GIT_NAME CONTROL_WINDOW_GIT_EMAIL \
  GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
activation_output="$test_root/activation-output"
if ! "$adapter" activate --policy "$production_policy" >"$activation_output" 2>&1; then
  fail "verified activation failed: $(cat "$activation_output")"
fi
activation_id="$(cat "$activation_output")"
[[ "$activation_id" =~ ^[0-9a-f]{64}$ ]] \
  || fail "activation did not return its opening identity"
[[ "$(jq -r .phase "$state_file")" == active \
  && "$(jq -r .activation_transition "$state_file")" == "$activation_id" ]] \
  || fail "active state was not installed after verified publication"
activation_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
[[ "$(git --git-dir="$remote" grep -l '"kind": "control-activated"' \
  "$activation_head" | wc -l)" -eq 1 ]] \
  || fail "activation did not append exactly one immutable transition"
unset WORK_ON_CONTROL_POLICY
[[ "$($adapter applies --repository example/comparison-repository --issue 101)" \
  == $'observer=control-window-publisher\ncontrol=fixture-b2-comparison' ]] \
  || fail "verified active policy did not match its declared population"
if "$adapter" applies --repository example/other --issue 101 >/dev/null; then
  fail "active policy matched a repository outside its population"
else
  [[ "$?" -eq 3 ]] || fail "a population miss returned a policy error"
fi

scenario registration-is-published-before-work-may-begin
target="$test_root/target"
mkdir -p "$target"
git -C "$target" init -q
git -C "$target" config user.name tester
git -C "$target" config user.email tester@example.invalid
git -C "$target" remote add origin git@github.com:example/comparison-repository.git
printf 'target\n' >"$target/README.md"
git -C "$target" add README.md
git -C "$target" commit -qm base
handle="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
registration="$(cd "$target" && "$adapter" register --run "$handle")"
[[ "$registration" == "registered ${handle%@*}" ]] \
  || fail "the adapter did not acknowledge the published registration"
registration_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
registered_file="$(git --git-dir="$remote" ls-tree -r --name-only "$registration_head" \
  | while read -r candidate; do
      [[ "$candidate" == */transitions/*.json ]] || continue
      candidate_transition="$(git --git-dir="$remote" show "$registration_head:$candidate")"
      [[ "$(jq -r .kind <<<"$candidate_transition")" == run-registered \
        && "$(jq -r .run_id <<<"$candidate_transition")" == "${handle%@*}" ]] \
        && printf '%s\n' "$candidate"
    done || true)"
[[ -n "$registered_file" ]] || fail "registration returned before its transition existed"
published_registration="$(git --git-dir="$remote" show "$registration_head:$registered_file")"
[[ "$(jq -r .run_id <<<"$published_registration")" == "${handle%@*}" ]] \
  || fail "the registration transition names the wrong run"
for prohibited in sink worktree prompt diff command output diagnostic credential reviewer; do
  ! jq -e --arg field "$prohibited" 'has($field)' <<<"$published_registration" >/dev/null \
    || fail "the publication serializer exposed prohibited field $prohibited"
done
(cd "$target" && "$script_root/run-telemetry.sh" launch --run "$handle" \
  --role implementation --phase implementation --round 1)

scenario finalization-publishes-bounded-canonical-evidence
finalized="$(cd "$target" && "$adapter" finalize --run "$handle" --outcome Closes)"
[[ "$finalized" == "finalized ${handle%@*}" ]] \
  || fail "the adapter did not finish the generic #72 finalization"
final_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
final_file="$(git --git-dir="$remote" ls-tree -r --name-only "$final_head" \
  | while read -r candidate; do
      [[ "$candidate" == */transitions/*.json ]] || continue
      candidate_transition="$(git --git-dir="$remote" show "$final_head:$candidate")"
      kind="$(jq -r .kind <<<"$candidate_transition")"
      [[ "$kind" == run-finalized \
        && "$(jq -r .run_id <<<"$candidate_transition")" == "${handle%@*}" ]] \
        && printf '%s\n' "$candidate"
    done || true)"
[[ -n "$final_file" ]] || fail "finalization did not publish a terminal transition"
published_final="$(git --git-dir="$remote" show "$final_head:$final_file")"
[[ "$(jq -r .outcome <<<"$published_final")" == Closes \
  && "$(jq -r .integrity <<<"$published_final")" == valid \
  && "$(jq -r .summary_sha256 <<<"$published_final")" =~ ^[0-9a-f]{64}$ ]] \
  || fail "finalization did not use the bounded canonical summary"
for prohibited in sink worktree prompt diff command output diagnostic credential reviewer; do
  ! jq -e --arg field "$prohibited" 'has($field)' <<<"$published_final" >/dev/null \
    || fail "finalization publication exposed prohibited field $prohibited"
done
before_retry="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
(cd "$target" && "$adapter" finalize --run "$handle" --outcome Closes) >/dev/null
after_retry="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
[[ "$before_retry" == "$after_retry" ]] \
  || fail "idempotent finalization appended a duplicate transition"

scenario finalized-evidence-loss-appends-one-bounded-successor
finalized_row="$(cd "$target" && "$script_root/run-registry.sh" status --run "$handle")"
rm -f "$(jq -r .sink <<<"$finalized_row")"
before_evidence_loss="$(git --git-dir="$remote" rev-list --count \
  main..experiment/fixture-b2-activation-test)"
(cd "$target" && "$adapter" recover --run "$handle") >/dev/null
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$handle" \
  | jq -r .finalization)" == unreproducible ]] \
  || fail "#72 did not reconcile finalized evidence loss to unreproducible"
evidence_loss_head="$(git --git-dir="$remote" rev-parse \
  refs/heads/experiment/fixture-b2-activation-test)"
evidence_loss_files="$(git --git-dir="$remote" ls-tree -r --name-only \
  "$evidence_loss_head" | while read -r candidate; do
    [[ "$candidate" == */transitions/*.json ]] || continue
    [[ "$(git --git-dir="$remote" show "$evidence_loss_head:$candidate" \
      | jq -r .kind)" == run-evidence-lost ]] && printf '%s\n' "$candidate"
  done || true)"
[[ "$(awk 'NF { count++ } END { print count + 0 }' <<<"$evidence_loss_files")" -eq 1 ]] \
  || fail "finalized evidence loss did not publish exactly one successor"
evidence_loss="$(git --git-dir="$remote" show \
  "$evidence_loss_head:$evidence_loss_files")"
[[ "$(jq -r .predecessor_transition <<<"$evidence_loss")" \
    == "$(jq -r .transition_id <<<"$published_final")" \
  && "$(jq -r .failure_code <<<"$evidence_loss")" == SINK_MISSING \
  && "$(jq -r .finalization <<<"$evidence_loss")" == unreproducible ]] \
  || fail "evidence-loss successor does not name the canonical predecessor/state"
after_evidence_loss="$(git --git-dir="$remote" rev-list --count \
  main..experiment/fixture-b2-activation-test)"
[[ "$after_evidence_loss" -eq $(( before_evidence_loss + 1 )) ]] \
  || fail "evidence loss appended more than one correction"
(cd "$target" && "$adapter" recover --run "$handle") >/dev/null
[[ "$(git --git-dir="$remote" rev-list --count \
  main..experiment/fixture-b2-activation-test)" -eq "$after_evidence_loss" ]] \
  || fail "repeated evidence-loss recovery duplicated its successor"

scenario registration-publication-failure-fails-closed-and-recovers
reject_hook="$remote/hooks/pre-receive"
cat >"$reject_hook" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$reject_hook"
failed_registration="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$failed_registration") \
  >"$test_root/register-failure" 2>&1 \
  || fail "registration succeeded despite rejected GitHub publication"
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$failed_registration" \
  | jq -r .finalization)" == pending ]] \
  || fail "failed registration publication lost the generic pending lease"
blocked_after_registration="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$blocked_after_registration") \
  >"$test_root/register-guard" 2>&1 \
  || fail "the next matching run bypassed the pending registration obligation"
grep -Fq 'unfinished obligation' "$test_root/register-guard" \
  || fail "the #72 next-run guard did not explain the blocked predecessor"
rm -f "$reject_hook"
[[ "$(cd "$target" && "$adapter" register --run "$failed_registration")" \
  == "registered ${failed_registration%@*}" ]] \
  || fail "registration recovery did not publish the original run"

scenario finalization-publication-failure-preserves-evidence-and-guard
(cd "$target" && "$script_root/run-telemetry.sh" launch --run "$failed_registration" \
  --role implementation --phase implementation --round 1)
cat >"$reject_hook" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$reject_hook"
! (cd "$target" && "$adapter" finalize --run "$failed_registration" --outcome failed) \
  >"$test_root/finalize-failure" 2>&1 \
  || fail "finalization succeeded despite rejected GitHub publication"
failed_row="$(cd "$target" && "$script_root/run-registry.sh" status --run "$failed_registration")"
[[ "$(jq -r .finalization <<<"$failed_row")" == failed \
  && "$(jq -r .failure_code <<<"$failed_row")" == OBSERVER_FAILED \
  && "$(jq -r .outcome <<<"$failed_row")" == failed \
  && -f "$(jq -r .sink <<<"$failed_row")" ]] \
  || fail "publication failure did not preserve the failed row and raw sink"
! (cd "$target" && "$adapter" register --run "$blocked_after_registration") \
  >/dev/null 2>&1 || fail "the failed finalization did not keep the next run blocked"
rm -f "$reject_hook"
recovery_output="$test_root/recovery-output"
if ! (cd "$target" && "$adapter" recover --run "$failed_registration") \
  >"$recovery_output" 2>&1; then
  fail "publication recovery failed: $(cat "$recovery_output")"
fi
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$failed_registration" \
  | jq -r .finalization)" == finalized ]] \
  || fail "recovery did not discharge the failed publication obligation"
failure_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
git --git-dir="$remote" grep -q '"kind": "run-failed"' "$failure_head" \
  || fail "failed workflow outcome disappeared from published history"

scenario generic-failed-state-is-published-before-recovery
lifecycle_failure="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && "$adapter" register --run "$lifecycle_failure") >/dev/null
(cd "$target" && "$script_root/run-telemetry.sh" resolve --run "$lifecycle_failure" \
  --outcome Progresses) >/dev/null
! (cd "$target" && "$adapter" finalize --run "$lifecycle_failure" --outcome Closes) \
  >"$test_root/outcome-conflict" 2>&1 \
  || fail "a contradictory finalization assertion succeeded"
lifecycle_row="$(cd "$target" && "$script_root/run-registry.sh" status --run "$lifecycle_failure")"
[[ "$(jq -r .finalization <<<"$lifecycle_row")" == failed \
  && "$(jq -r .failure_code <<<"$lifecycle_row")" == OUTCOME_CONFLICT ]] \
  || fail "the generic lifecycle failure was not preserved"
lifecycle_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
git --git-dir="$remote" grep -q '"failure_code": "OUTCOME_CONFLICT"' "$lifecycle_head" \
  || fail "generic failed state disappeared from published history"
(cd "$target" && "$adapter" recover --run "$lifecycle_failure") >/dev/null
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$lifecycle_failure" \
  | jq -r .finalization)" == finalized ]] \
  || fail "a published failed state could not later recover"

scenario missing-sink-publishes-unreproducible-without-disappearing
unreproducible="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && "$adapter" register --run "$unreproducible") >/dev/null
unreproducible_row="$(cd "$target" && "$script_root/run-registry.sh" status --run "$unreproducible")"
rm -f "$(jq -r .sink <<<"$unreproducible_row")"
(cd "$target" && "$adapter" recover --run "$unreproducible" --outcome abandoned) >/dev/null
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$unreproducible" \
  | jq -r .finalization)" == unreproducible ]] \
  || fail "missing sink was not retained as unreproducible"
unreproducible_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
git --git-dir="$remote" grep -q '"kind": "run-unreproducible"' "$unreproducible_head" \
  || fail "unreproducible lifecycle state disappeared from published history"

scenario concurrent-matching-agents-share-the-run-registry-lease
candidate_a="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
candidate_b="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && "$adapter" register --run "$candidate_a") \
  >"$test_root/concurrent-a.out" 2>"$test_root/concurrent-a.err" &
pid_a=$!
(cd "$target" && "$adapter" register --run "$candidate_b") \
  >"$test_root/concurrent-b.out" 2>"$test_root/concurrent-b.err" &
pid_b=$!
status_a=0; wait "$pid_a" || status_a=$?
status_b=0; wait "$pid_b" || status_b=$?
[[ "$(( (status_a == 0) + (status_b == 0) ))" -eq 1 ]] \
  || fail "concurrent matching registrations did not produce exactly one lease"
if [[ "$status_a" -eq 0 ]]; then winner="$candidate_a"; else winner="$candidate_b"; fi
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --pending \
  | jq -s --arg control fixture-b2-comparison \
    '[.[] | select(.control_id == $control)] | length')" -eq 1 ]] \
  || fail "concurrent registration produced conflicting pending records"

scenario ambiguous-success-is-adopted-with-one-logical-transition
(cd "$target" && "$script_root/run-telemetry.sh" launch --run "$winner" \
  --role implementation --phase implementation --round 1)
export CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER="$test_root/ambiguous-push"
before_ambiguous="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
(cd "$target" && "$adapter" finalize --run "$winner" --outcome Progresses) >/dev/null
unset CONTROL_WINDOW_AMBIGUOUS_PUSH_MARKER
[[ -e "$test_root/ambiguous-push" ]] || fail "the ambiguous-success boundary was not exercised"
after_ambiguous="$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)"
[[ "$after_ambiguous" -eq $(( before_ambiguous + 1 )) ]] \
  || fail "ambiguous success produced more than one remote transition"
(cd "$target" && "$adapter" recover --run "$winner") >/dev/null
[[ "$(git --git-dir="$remote" rev-list --count main..experiment/fixture-b2-activation-test)" \
  -eq "$after_ambiguous" ]] || fail "ambiguous-success retry duplicated publication"

scenario conflicting-remote-content-is-rejected
good_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
attack="$test_root/attack"
git clone -q "$remote" "$attack"
git -C "$attack" config user.name 'Control Window Publisher'
git -C "$attack" config user.email control-window@invalid.local
git -C "$attack" switch -q experiment/fixture-b2-activation-test
victim="$(git -C "$attack" ls-tree -r --name-only HEAD \
  | while read -r candidate; do
      [[ "$candidate" == */transitions/*.json ]] || continue
      [[ "$(git -C "$attack" show "HEAD:$candidate" | jq -r .kind)" == run-registered ]] \
        && printf '%s\n' "$candidate" && break
    done)"
jq '.issue = 999' "$attack/$victim" >"$attack/$victim.changed"
mv "$attack/$victim.changed" "$attack/$victim"
git -C "$attack" add -- "$victim"
git -C "$attack" commit -qm 'rewrite published evidence'
git -C "$attack" push -q origin HEAD:refs/heads/experiment/fixture-b2-activation-test
conflict_run="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$conflict_run") \
  >"$test_root/conflict.out" 2>&1 \
  || fail "conflicting remote evidence was accepted"
grep -Eq 'rewrites a published artifact|content does not match its identity' \
  "$test_root/conflict.out" || fail "remote content conflict lacked a fail-closed diagnostic"
git --git-dir="$remote" update-ref refs/heads/experiment/fixture-b2-activation-test "$good_head"
(cd "$target" && "$adapter" register --run "$conflict_run") >/dev/null
(cd "$target" && "$adapter" finalize --run "$conflict_run" --outcome abandoned) >/dev/null

scenario branch-rewrite-is-detected-without-force-push-recovery
rewrite_good_head="$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)"
rewound_head="$(git --git-dir="$remote" rev-parse "$rewrite_good_head^")"
git --git-dir="$remote" update-ref refs/heads/experiment/fixture-b2-activation-test "$rewound_head"
rewrite_run="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
! (cd "$target" && "$adapter" register --run "$rewrite_run") \
  >"$test_root/rewrite.out" 2>&1 \
  || fail "a rewritten results branch was accepted"
grep -Fq 'rewritten behind the last verified head' "$test_root/rewrite.out" \
  || fail "branch rewrite lacked its fail-closed diagnostic"
[[ "$(git --git-dir="$remote" rev-parse refs/heads/experiment/fixture-b2-activation-test)" \
  == "$rewound_head" ]] || fail "the adapter force-repaired the rewritten branch"
git --git-dir="$remote" update-ref refs/heads/experiment/fixture-b2-activation-test "$rewrite_good_head"
(cd "$target" && "$adapter" register --run "$rewrite_run") >/dev/null
(cd "$target" && "$adapter" finalize --run "$rewrite_run" --outcome abandoned) >/dev/null

scenario independent-registry-domains-share-the-remote-active-run-bound
domain_a_state="$test_root/domain-a-state"
domain_a_config="$test_root/domain-a-config"
domain_b_state="$test_root/domain-b-state"
domain_b_config="$test_root/domain-b-config"
env XDG_STATE_HOME="$domain_a_state" XDG_CONFIG_HOME="$domain_a_config" \
  WORK_ON_CONTROL_POLICY="$production_policy" "$adapter" prepare \
  --policy "$production_policy" >/dev/null
env XDG_STATE_HOME="$domain_b_state" XDG_CONFIG_HOME="$domain_b_config" \
  WORK_ON_CONTROL_POLICY="$production_policy" "$adapter" prepare \
  --policy "$production_policy" >/dev/null
domain_a_handle="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
domain_b_handle="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && env XDG_STATE_HOME="$domain_a_state" \
  XDG_CONFIG_HOME="$domain_a_config" WORK_ON_CONTROL_POLICY="$production_policy" \
  "$adapter" register --run "$domain_a_handle") \
  >"$test_root/domain-a.out" 2>"$test_root/domain-a.err" &
domain_a_pid=$!
(cd "$target" && env XDG_STATE_HOME="$domain_b_state" \
  XDG_CONFIG_HOME="$domain_b_config" WORK_ON_CONTROL_POLICY="$production_policy" \
  "$adapter" register --run "$domain_b_handle") \
  >"$test_root/domain-b.out" 2>"$test_root/domain-b.err" &
domain_b_pid=$!
domain_a_status=0; wait "$domain_a_pid" || domain_a_status=$?
domain_b_status=0; wait "$domain_b_pid" || domain_b_status=$?
[[ "$(( (domain_a_status == 0) + (domain_b_status == 0) ))" -eq 1 ]] \
  || fail "independent registry domains produced more than one eligible run"
if [[ "$domain_a_status" -eq 0 ]]; then
  domain_winner_handle="$domain_a_handle"
  domain_winner_state="$domain_a_state"
  domain_winner_config="$domain_a_config"
  domain_loser_handle="$domain_b_handle"
  domain_loser_state="$domain_b_state"
  domain_loser_config="$domain_b_config"
else
  domain_winner_handle="$domain_b_handle"
  domain_winner_state="$domain_b_state"
  domain_winner_config="$domain_b_config"
  domain_loser_handle="$domain_a_handle"
  domain_loser_state="$domain_a_state"
  domain_loser_config="$domain_a_config"
fi
(cd "$target" && env XDG_STATE_HOME="$domain_winner_state" \
  XDG_CONFIG_HOME="$domain_winner_config" WORK_ON_CONTROL_POLICY="$production_policy" \
  "$adapter" finalize --run "$domain_winner_handle" --outcome abandoned) >/dev/null
[[ "$(cd "$target" && env XDG_STATE_HOME="$domain_loser_state" \
  XDG_CONFIG_HOME="$domain_loser_config" WORK_ON_CONTROL_POLICY="$production_policy" \
  "$adapter" register --run "$domain_loser_handle")" \
  == "registered ${domain_loser_handle%@*}" ]] \
  || fail "the losing registry domain could not retry after remote capacity reopened"
(cd "$target" && env XDG_STATE_HOME="$domain_loser_state" \
  XDG_CONFIG_HOME="$domain_loser_config" WORK_ON_CONTROL_POLICY="$production_policy" \
  "$adapter" finalize --run "$domain_loser_handle" --outcome abandoned) >/dev/null

post_close_handle="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
(cd "$target" && "$adapter" register --run "$post_close_handle") >/dev/null
(cd "$target" && "$adapter" finalize --run "$post_close_handle" --outcome abandoned) >/dev/null
post_close_row="$(cd "$target" && "$script_root/run-registry.sh" status \
  --run "$post_close_handle")"

scenario configured-active-control-cannot-be-silently-replaced
second_policy="$test_root/second-production-policy.json"
jq --arg control fixture-second-control \
  --arg branch experiment/fixture-second-control \
  --arg arm second-fixture \
  '.control_id = $control | .results.branch = $branch | .arm.id = $arm' \
  "$fixtures/b2-like-policy.json" >"$second_policy"
! "$adapter" prepare --policy "$second_policy" >"$test_root/second-active.out" 2>&1 \
  || fail "preparing a second policy replaced an active control"
grep -Fq 'still active' "$test_root/second-active.out" \
  || fail "second-policy refusal did not identify the active predecessor"
[[ "$($adapter applies --repository example/comparison-repository --issue 101)" \
  == $'observer=control-window-publisher\ncontrol=fixture-b2-comparison' ]] \
  || fail "refused replacement stopped the active control from matching"

scenario ambiguous-remote-closing-is-reconciled-before-admission
closing_crash_handle="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
export CONTROL_WINDOW_KILL_AFTER_CLOSING_MARKER="$test_root/closing-killed"
! "$adapter" close --policy "$production_policy" >/dev/null 2>&1 \
  || fail "closing caller survived the injected post-push loss"
unset CONTROL_WINDOW_KILL_AFTER_CLOSING_MARKER
[[ -e "$test_root/closing-killed" ]] \
  || fail "closing crash did not occur after the remote write"
[[ "$(jq -r .phase "$state_file")" == active ]] \
  || fail "the closing crash fixture did not leave stale active local state"
! (cd "$target" && "$adapter" register --run "$closing_crash_handle") \
  >"$test_root/post-closing-register.out" 2>&1 \
  || fail "stale local active state admitted work after remote closing"
grep -Fq 'not open for registration' "$test_root/post-closing-register.out" \
  || fail "post-closing admission lacked its fail-closed diagnostic"
[[ -z "$(cd "$target" && "$script_root/run-registry.sh" status \
  --run "$closing_crash_handle")" ]] \
  || fail "post-closing refusal created a generic registry obligation"
closing_count_before_retry="$(git --git-dir="$remote" grep -l \
  '"kind": "control-closing"' experiment/fixture-b2-activation-test | wc -l)"
closing_id="$($adapter close --policy "$production_policy")"
closing_count_after_retry="$(git --git-dir="$remote" grep -l \
  '"kind": "control-closing"' experiment/fixture-b2-activation-test | wc -l)"
[[ "$closing_id" =~ ^[0-9a-f]{64}$ \
  && "$closing_count_before_retry" -eq 1 && "$closing_count_after_retry" -eq 1 \
  && "$(jq -r .phase "$state_file")" == closing ]] \
  || fail "ambiguous closing did not reconcile to one durable transition"
! "$adapter" prepare --policy "$second_policy" >"$test_root/second-closing.out" 2>&1 \
  || fail "preparing a second policy replaced a closing control"
grep -Fq 'still closing' "$test_root/second-closing.out" \
  || fail "second-policy refusal did not identify the closing predecessor"
closed_id="$($adapter close --policy "$production_policy" --complete)"
[[ "$closed_id" =~ ^[0-9a-f]{64}$ \
  && "$(jq -r .phase "$state_file")" == closed ]] \
  || fail "control closed was not durably distinct"
rm -f "$(jq -r .sink <<<"$post_close_row")"
if ! (cd "$target" && "$adapter" recover --run "$post_close_handle") \
  >"$test_root/post-close-recover.out" 2>&1; then
  fail "closed-control evidence-loss recovery failed: $(cat "$test_root/post-close-recover.out")"
fi
[[ "$(cd "$target" && "$script_root/run-registry.sh" status --run "$post_close_handle" \
  | jq -r .finalization)" == unreproducible ]] \
  || fail "a closed control hid #72's later canonical evidence loss"
post_close_head="$(git --git-dir="$remote" rev-parse \
  refs/heads/experiment/fixture-b2-activation-test)"
post_close_loss_files="$(git --git-dir="$remote" ls-tree -r --name-only \
  "$post_close_head" | while read -r candidate; do
    [[ "$candidate" == */transitions/*.json ]] || continue
    candidate_transition="$(git --git-dir="$remote" show "$post_close_head:$candidate")"
    [[ "$(jq -r .kind <<<"$candidate_transition")" == run-evidence-lost \
      && "$(jq -r .run_id <<<"$candidate_transition")" == "${post_close_handle%@*}" ]] \
      && printf 'one\n'
  done || true)"
post_close_loss_count="$(awk 'NF { count++ } END { print count + 0 }' \
  <<<"$post_close_loss_files")"
[[ "$post_close_loss_count" -eq 1 ]] \
  || fail "closed-control recovery did not publish one evidence-loss successor"

scenario closed-control-releases-the-single-production-policy-slot
"$adapter" prepare --policy "$second_policy" >/dev/null
second_state_file="$XDG_STATE_HOME/work-on/control-windows/fixture-second-control.json"
[[ "$(cat "$XDG_CONFIG_HOME/work-on/control-policy")" == "$second_policy" \
  && "$(jq -r .phase "$second_state_file")" == prepared ]] \
  || fail "a durably closed control did not release the production policy slot"
"$adapter" activate --policy "$second_policy" >/dev/null

scenario public-registration-and-closing-share-one-admission-boundary
race_handle="$(cd "$target" && "$script_root/run-telemetry.sh" start --issue 101)"
export CONTROL_WINDOW_CLOSING_BARRIER="$test_root/closing-barrier"
"$adapter" close --policy "$second_policy" \
  >"$test_root/race-close.out" 2>"$test_root/race-close.err" &
race_close_pid=$!
for _ in $(seq 1 200); do
  [[ -e "$CONTROL_WINDOW_CLOSING_BARRIER/entered" ]] && break
  sleep 0.02
done
[[ -e "$CONTROL_WINDOW_CLOSING_BARRIER/entered" ]] \
  || fail "close did not reach the synchronized publication boundary"
(cd "$target" && "$adapter" register --run "$race_handle") \
  >"$test_root/race-register.out" 2>"$test_root/race-register.err" &
race_register_pid=$!
sleep 0.25
kill -0 "$race_close_pid" 2>/dev/null && kill -0 "$race_register_pid" 2>/dev/null \
  || fail "register and close were not simultaneously live at the boundary"
[[ -z "$(cd "$target" && "$script_root/run-registry.sh" status --run "$race_handle")" ]] \
  || fail "registration acquired a generic lease while closing held admission"
: >"$CONTROL_WINDOW_CLOSING_BARRIER/release"
race_close_status=0; wait "$race_close_pid" || race_close_status=$?
race_register_status=0; wait "$race_register_pid" || race_register_status=$?
unset CONTROL_WINDOW_CLOSING_BARRIER
[[ "$race_close_status" -eq 0 && "$race_register_status" -ne 0 ]] \
  || fail "the synchronized register/close race did not close without admission"
[[ -z "$(cd "$target" && "$script_root/run-registry.sh" status --run "$race_handle")" ]] \
  || fail "the losing registration left a generic obligation"
"$adapter" close --policy "$second_policy" --complete >/dev/null

scenario unexpected-demo-branch-content-fails-closed
demo_attack="$test_root/demo-attack"
git clone -q "$remote" "$demo_attack"
git -C "$demo_attack" config user.name 'Control Window Publisher'
git -C "$demo_attack" config user.email control-window@invalid.local
git -C "$demo_attack" switch -q demo/control-window-prepared-test
printf 'unexpected\n' >"$demo_attack/unexpected.txt"
git -C "$demo_attack" add unexpected.txt
git -C "$demo_attack" commit -qm 'unexpected evidence content'
git -C "$demo_attack" push -q origin HEAD:refs/heads/demo/control-window-prepared-test
! "$adapter" prepare --policy "$demo_policy" >"$test_root/unexpected.out" 2>&1 \
  || fail "unexpected results-branch content was accepted"
grep -Fq 'unexpected content' "$test_root/unexpected.out" \
  || fail "unexpected branch content lacked its fail-closed diagnostic"

! rg -n 'git .*push.*(--force|-f)|push .*\+' "$adapter" >/dev/null \
  || fail "the publisher contains a force-push recovery path"

scenario work-on-uses-the-policy-aware-public-wrapper
grep -Fq 'scripts/control-window.sh register --run "$RUN_HANDLE"' \
  "$(dirname "$script_root")/SKILL.md" \
  || fail "work-on does not use publication-gated registration"
grep -Fq 'scripts/control-window.sh finalize --run "$RUN_HANDLE"' \
  "$(dirname "$script_root")/references/github-closeout.md" \
  || fail "normal closeout bypasses the publication-aware finalizer"
grep -Fq 'scripts/control-window.sh finalize --run "$RUN_HANDLE" --outcome preflight-aborted' \
  "$(dirname "$script_root")/references/closability-gate.md" \
  || fail "preflight hand-back bypasses the publication-aware finalizer"

printf 'control window scenarios passed\n'
