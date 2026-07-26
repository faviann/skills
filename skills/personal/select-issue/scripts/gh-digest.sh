#!/usr/bin/env bash
# Read-only GitHub digest for the select-issue skill. Compact output by design.
set -euo pipefail

cmd="${1:-digest}"
mode="${2:-manual}"

comment_snapshot() {
  local issue_number="$1"
  local repo
  repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
  gh api --paginate --slurp "repos/$repo/issues/$issue_number/comments?per_page=100"
}

comment_partition() {
  comment_snapshot "$1" | jq '
    def trusted:
      .author_association == "OWNER" or
      .author_association == "MEMBER" or
      .author_association == "COLLABORATOR";
    [.[][]] as $all |
    {
      trusted: ($all | map(select(trusted))),
      omitted: ($all | map(select(trusted | not)) | length)
    }
  '
}

case "$cmd" in
  digest)
    case "$mode" in
      manual)
        candidate_labels=(--label ready-for-agent)
        candidate_filter='(.labels | map(.name) | index("ready-for-agent"))'
        heading="ready-for-agent candidates"
        ;;
      afk)
        candidate_labels=(--label ready-for-agent --label Sandcastle)
        candidate_filter='((.labels | map(.name) | index("ready-for-agent")) and (.labels | map(.name) | index("Sandcastle")))'
        heading="ready-for-agent + Sandcastle candidates"
        ;;
      *)
        echo "usage: gh-digest.sh digest [manual | afk]" >&2
        exit 2
        ;;
    esac

    echo "## $heading"
    gh issue list --state open --limit 1000 "${candidate_labels[@]}" --json number,title,labels \
      --jq '.[] | "#\(.number) [\(.labels | map(.name) | join(","))] \(.title)"'
    echo
    echo "## other open issues (conflict scan)"
    gh issue list --state open --limit 1000 --json number,title,labels \
      --jq ".[] | select(($candidate_filter) | not) | \"#\\(.number) [\\(.labels | map(.name) | join(\",\"))] \\(.title)\""
    echo
    echo "## last 15 merged PRs"
    gh pr list --state merged --limit 15 --json number,title \
      --jq '.[] | "PR#\(.number) \(.title)"'
    echo
    echo "## last 15 commits on default branch"
    repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
    default="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
    gh api "repos/$repo/commits?sha=$default&per_page=15" \
      --jq '.[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
    ;;
  last-comment)
    comment_partition "$2" | jq -r '
      (if (.trusted | length) == 0
       then "(no trusted comments)"
       else (.trusted[-1] |
         "\(.user.login) [\(.author_association)] (\(.created_at)): \(.body[0:500])")
       end),
      "external comments omitted: \(.omitted)"
    '
    ;;
  body)
    gh issue view "$2" --json number,title,labels,body \
      --jq '"#\(.number) \(.title)\nlabels: \(.labels | map(.name) | join(","))\n\n\(.body)"'
    echo
    echo "--- trusted comments ---"
    comment_partition "$2" | jq -r '
      (if (.trusted | length) == 0
       then "(no trusted comments)"
       else (.trusted |
         map("\(.user.login) [\(.author_association)]: \(.body)") |
         join("\n--\n"))
       end),
      "external comments omitted: \(.omitted)"
    '
    ;;
  *)
    echo "usage: gh-digest.sh [digest [manual | afk] | last-comment <n> | body <n>]" >&2
    exit 2
    ;;
esac
