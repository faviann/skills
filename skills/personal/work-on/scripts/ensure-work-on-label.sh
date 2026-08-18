#!/usr/bin/env bash
set -euo pipefail

# Apply the repository-local `work-on` label to a pull request whose closeout
# body has already been rendered, read back, and validated.
#
# The label is a discovery aid, not evidence authority. Every failure here
# warns and returns success: a valid observation that no label search returns
# is still a valid observation, and a closeout that already published its
# evidence must not be undone because a label could not be attached.

readonly label_name='work-on'
readonly label_color='1D76DB'
readonly label_description='Pull request created or updated through /work-on'

usage() {
  printf 'usage: ensure-work-on-label.sh --repository owner/repository --pr N\n' >&2
  exit 1
}

repository=""
pr_number=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --repository) repository="${2:-}"; shift 2 || usage ;;
    --pr) pr_number="${2:-}"; shift 2 || usage ;;
    *) usage ;;
  esac
done

# The repository and pull request are always named explicitly. Inferring either
# from the working directory would let a closeout label whichever repository the
# shell happened to be in.
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || usage

readonly target="$repository#$pr_number"

# Raw command output can carry a token, a URL, or an unbounded API body, so it
# is captured and dropped. The warning names the stage and the target and
# nothing else.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

warn_and_exit() {
  printf 'warning: work-on label %s failed for %s; closeout remains complete\n' \
    "$1" "$target" >&2
  exit 0
}

# Exact-name lookup. `--search` matches loosely and a single-label endpoint
# cannot distinguish "absent" from "could not ask", so the labels are listed and
# matched exactly here: a non-zero status is a lookup failure, and a zero status
# is a definite present-or-absent answer.
list_labels() {
  gh api --paginate "repos/$repository/labels" --jq '.[].name' \
    >"$scratch/labels.out" 2>"$scratch/labels.err"
}

label_exists() {
  list_labels || return 2
  grep -Fxq -- "$label_name" "$scratch/labels.out"
}

lookup_status=0
label_exists || lookup_status=$?
[[ "$lookup_status" -ne 2 ]] || warn_and_exit lookup

if [[ "$lookup_status" -ne 0 ]]; then
  # Never `--force`: that edits an existing label's color and description. An
  # existing `work-on` label is usable whatever its metadata says, and its
  # metadata belongs to whoever set it.
  if ! gh label create "$label_name" --repo "$repository" \
      --color "$label_color" --description "$label_description" \
      >"$scratch/create.out" 2>"$scratch/create.err"; then
    # A concurrent creator wins the race and fails this create. Re-read the
    # exact label before declaring failure: if it is there now, the
    # postcondition holds regardless of which process established it.
    label_exists || warn_and_exit create
  fi
fi

gh pr edit "$pr_number" --repo "$repository" --add-label "$label_name" \
  >"$scratch/apply.out" 2>"$scratch/apply.err" \
  || warn_and_exit apply
