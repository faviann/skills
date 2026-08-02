# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Which repository

This checkout has two remotes: `origin` → `faviann/skills` and `upstream` → `mattpocock/skills`.
**`origin` is the mutation target** unless the user explicitly names another repository.

Do not rely on unqualified `gh` repository resolution for a mutation. Before any GitHub mutation, run `gh repo set-default origin`, verify the target with `gh repo set-default --view`, and pass that verified `owner/repo` via `-R`.

## Conventions

- **Create an issue**: `gh issue create -R faviann/skills --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> -R faviann/skills --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list -R faviann/skills --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> -R faviann/skills --body "..."`
- **Apply / remove labels**: `gh issue edit <number> -R faviann/skills --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> -R faviann/skills --comment "..."`

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> -R faviann/skills --comments` and `gh pr diff <number> -R faviann/skills` for the diff.
- **List external PRs for triage**: `gh pr list -R faviann/skills --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close` — each with `-R faviann/skills`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42 -R faviann/skills` and fall back to `gh issue view 42 -R faviann/skills`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue on `faviann/skills`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> -R faviann/skills --comments`.

## Calibration-record operations

Used by staged `/to-tickets`. A Calibration record is a coordination Issue labelled `calibration:record`; it never receives an implementation-ready triage label and is excluded from Frontier queries. Before any mutation, follow **Which repository** above and pass `-R faviann/skills`.

- **Create and mark**: ensure the dedicated marker exists with `gh label create calibration:record -R faviann/skills --description "Staged-calibration coordination record" --force`, then create the record first with `gh issue create -R faviann/skills --label calibration:record`; its body contains the current snapshot and `Parent: #<n>`.
- **Read/update snapshot**: use `gh issue view <record> -R faviann/skills --comments` and `gh issue edit <record> -R faviann/skills --body-file <file>`.
- **Append history**: post dated entries with `gh issue comment <record> -R faviann/skills --body "..."`; never replace earlier comments.
- **Find from Parent**: search `gh issue list -R faviann/skills --label calibration:record --search '"Parent: #<n>"'`; the Parent is not modified.
- **Bidirectional Ticket discovery**: every implementation Issue body references `Parent: #<n>` and `Calibration: #<record>`. Follow the Ticket reference to the record; find Tickets from the record's ordered Published Frontiers and verify with an Issue search for `"Calibration: #<record>"`.
- **Reconcile**: on every resumption, read each discovered Issue and linked PR with `gh issue view` / `gh pr view`, always with `-R faviann/skills`; compare real open/closed and PR state with the snapshot, repair the snapshot and missing links, and append a dated reconciliation comment. Never infer an unreachable artifact.
- **Abandon**: append the dated reason and remaining-work dispositions, set status `abandoned`, then `gh issue close <record> -R faviann/skills`. Do not close the Parent or implementation Issues.
- **Complete successfully**: append final approval/history, set status `complete`, then `gh issue close <record> -R faviann/skills`. Do not close the Parent.

There is no background monitoring, expiry, or automatic abandonment.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create -R faviann/skills --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies** — the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/faviann/skills/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/faviann/skills/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only — the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list -R faviann/skills --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> -R faviann/skills --add-assignee @me` — the session's first write.
- **Resolve**: `gh issue comment <n> -R faviann/skills --body "<answer>"`, then `gh issue close <n> -R faviann/skills`, then append a context pointer (gist + link) to the map's Decisions-so-far.
