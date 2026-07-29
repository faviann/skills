#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
digest="$script_dir/gh-digest.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin"
events="$fixture/events"

cat >"$fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >>"$DIGEST_TEST_EVENTS"

candidate_json() {
  case "$DIGEST_TEST_SCENARIO" in
    mixed|all-blocked|unreadable|all-unreadable) printf '%s\n' '[{"number":42,"title":"Blocked work","labels":[{"name":"ready-for-agent"},{"name":"Sandcastle"}]},{"number":43,"title":"Eligible work","labels":[{"name":"ready-for-agent"},{"name":"Sandcastle"}]}]' ;;
    closed-blocker|manual) printf '%s\n' '[{"number":42,"title":"Ready work","labels":[{"name":"ready-for-agent"},{"name":"Sandcastle"}]}]' ;;
  esac
}

case "$*" in
  "repo view --json nameWithOwner --jq .nameWithOwner") printf 'acme/widget\n' ;;
  "repo view --json defaultBranchRef --jq .defaultBranchRef.name") printf 'main\n' ;;
  issue\ list\ --state\ open\ --limit\ 1000\ --label\ ready-for-agent*)
    if [[ "$*" == *"--json number,title,labels --jq"* ]]; then
      candidate_json | jq -r '.[] | "#\(.number) [\(.labels | map(.name) | join(","))] \(.title)"'
    else
      candidate_json
    fi ;;
  "issue list --state open --limit 1000 --json number,title,labels --jq .[] | select("*)
    ;;
  "pr list --state merged --limit 15 --json number,title --jq .[] | \"PR#\\(.number) \\(.title)\"") ;;
  "api repos/acme/widget/commits?sha=main&per_page=15 --jq .[] | \"\\(.sha[0:7]) \\(.commit.message | split(\"\\n\")[0])\"") ;;
  api\ --paginate\ repos/acme/widget/issues/*/dependencies/blocked_by?per_page=100\ --jq\ *)
    issue_path="${3}"; issue="${issue_path#repos/acme/widget/issues/}"; issue="${issue%%/*}"
    case "$DIGEST_TEST_SCENARIO:$issue" in
      mixed:42|all-blocked:42) printf '7\n' ;;
      all-blocked:43) printf '8\n' ;;
      unreadable:42|all-unreadable:42|all-unreadable:43) exit 1 ;;
      closed-blocker:42)
        [[ "$*" == *'select(.state == "open")'* ]] || printf '7\n' ;;
    esac ;;
  *) printf 'unexpected gh call: %s\n' "$*" >&2; exit 90 ;;
esac
EOF
chmod +x "$fixture/bin/gh"

run_digest() {
  local scenario="$1" mode="${2:-afk}"
  : >"$events"
  PATH="$fixture/bin:$PATH" \
    DIGEST_TEST_EVENTS="$events" \
    DIGEST_TEST_SCENARIO="$scenario" \
    "$digest" digest "$mode"
}

mixed="$(run_digest mixed)"
grep -Fq '#43 [ready-for-agent,Sandcastle] Eligible work' <<<"$mixed"
! grep -Fq '#42 [ready-for-agent,Sandcastle] Blocked work' \
  <<<"$(sed -n '/^## ready-for-agent + Sandcastle candidates$/,/^## AFK dependency exclusions$/p' <<<"$mixed")"
grep -Fq '#42 blocked by #7' <<<"$mixed"
grep -Fq 'gh api --paginate repos/acme/widget/issues/42/dependencies/blocked_by?per_page=100 --jq' "$events"
grep -Fq 'gh api --paginate repos/acme/widget/issues/43/dependencies/blocked_by?per_page=100 --jq' "$events"

all_blocked="$(run_digest all-blocked)"
all_blocked_candidates="$(
  sed -n '/^## ready-for-agent + Sandcastle candidates$/,/^## AFK dependency exclusions$/p' \
    <<<"$all_blocked"
)"
! grep -Eq '^#[0-9]+ ' <<<"$all_blocked_candidates"
grep -Fq '#42 blocked by #7' <<<"$all_blocked"
grep -Fq '#43 blocked by #8' <<<"$all_blocked"

unreadable="$(run_digest unreadable)"
grep -Fq '#43 [ready-for-agent,Sandcastle] Eligible work' <<<"$unreadable"
! grep -Fq '#42 [ready-for-agent,Sandcastle] Blocked work' \
  <<<"$(sed -n '/^## ready-for-agent + Sandcastle candidates$/,/^## AFK dependency exclusions$/p' <<<"$unreadable")"
grep -Fq '#42 dependency data unreadable' <<<"$unreadable"

all_unreadable="$(run_digest all-unreadable)"
all_unreadable_candidates="$(
  sed -n '/^## ready-for-agent + Sandcastle candidates$/,/^## AFK dependency exclusions$/p' \
    <<<"$all_unreadable"
)"
! grep -Eq '^#[0-9]+ ' <<<"$all_unreadable_candidates"
grep -Fq '#42 dependency data unreadable' <<<"$all_unreadable"
grep -Fq '#43 dependency data unreadable' <<<"$all_unreadable"

closed_blocker="$(run_digest closed-blocker)"
grep -Fq '#42 [ready-for-agent,Sandcastle] Ready work' <<<"$closed_blocker"
grep -A1 '^## AFK dependency exclusions$' <<<"$closed_blocker" |
  grep -Fq '(none)'

manual="$(run_digest manual manual)"
grep -Fq '## ready-for-agent candidates' <<<"$manual"
grep -Fq '#42 [ready-for-agent,Sandcastle] Ready work' <<<"$manual"
! grep -Fq '## AFK dependency exclusions' <<<"$manual"
! grep -Fq '/dependencies/blocked_by' "$events"

printf 'select-issue GitHub digest scenarios passed\n'
