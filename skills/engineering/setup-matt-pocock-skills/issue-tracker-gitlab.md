# Issue tracker: GitLab

Issues and PRDs for this repo live as GitLab issues. Use the [`glab`](https://gitlab.com/gitlab-org/cli) CLI for all operations.

## Conventions

- **Create an issue**: `glab issue create --title "..." --description "..."`. Use a heredoc for multi-line descriptions. Pass `--description -` to open an editor.
- **Read an issue**: `glab issue view <number> --comments`. Use `-F json` for machine-readable output.
- **List issues**: `glab issue list -F json` with appropriate `--label` filters.
- **Comment on an issue**: `glab issue note <number> --message "..."`. GitLab calls comments "notes".
- **Apply / remove labels**: `glab issue update <number> --label "..."` / `--unlabel "..."`. Multiple labels can be comma-separated or by repeating the flag.
- **Close**: `glab issue close <number>`. `glab issue close` does not accept a closing comment, so post the explanation first with `glab issue note <number> --message "..."`, then close.
- **Merge requests**: GitLab calls PRs "merge requests". Use `glab mr create`, `glab mr view`, `glab mr note`, etc. — the same shape as `gh pr ...` with `mr` in place of `pr` and `note`/`--message` in place of `comment`/`--body`.

Infer the repo from `git remote -v` — `glab` does this automatically when run inside a clone.

## Merge requests as a triage surface

**MRs as a request surface: no.** _(Set to `yes` if this repo treats external merge requests as feature requests; `/triage` reads this flag.)_

When set to `yes`, MRs run through the same labels and states as issues, using the `glab mr` equivalents:

- **Read an MR**: `glab mr view <number> --comments` and `glab mr diff <number>` for the diff.
- **List external MRs for triage**: `glab mr list -F json`, then keep only MRs whose author is not a project member/owner (a contributor's MR, not a maintainer's in-flight work).
- **Comment / label / close**: `glab mr note`, `glab mr update --label`/`--unlabel`, `glab mr close`.

Unlike GitHub, GitLab numbers issues and MRs separately, so `#42` is unambiguous once you know which surface the maintainer means.

## When a skill says "publish to the issue tracker"

Create a GitLab issue.

## When a skill says "fetch the relevant ticket"

Run `glab issue view <number> --comments`.

## Calibration-record operations

Used by staged `/to-tickets`. A Calibration record is a coordination Issue labelled `calibration:record`; it never receives an implementation-ready triage label and is excluded from Frontier queries.

- **Create and mark**: ensure the dedicated `calibration:record` label exists, then create the record first with `glab issue create --label calibration:record`; its description contains the current snapshot and `Parent: #<n>`.
- **Read/update snapshot**: use `glab issue view <record> --comments` and `glab issue update <record> --description "..."`.
- **Append history**: add dated notes with `glab issue note <record> --message "..."`; never replace earlier notes.
- **Find from Parent**: list/search Issues carrying `calibration:record` and match `Parent: #<n>`; never modify the Parent for discovery.
- **Bidirectional Ticket discovery**: every implementation Issue description references both `Parent: #<n>` and `Calibration: #<record>`. The Ticket points to the record; the record's ordered Published Frontiers plus a search for `Calibration: #<record>` find every Ticket.
- **Linked MR discovery**: for each staged Ticket, run `glab api "projects/:id/issues/<ticket-iid>/related_merge_requests" --paginate` and retain each result's project identity from `project_id`, `references.full`, or `web_url` together with its IID; also collect explicit MR URLs or full `namespace/project!iid` references from the Ticket and record. Never reduce a result to a bare IID. Read state, notes, and diffs against the exact project, either with `glab mr view/diff <iid> -R <namespace/project>` or with `glab api projects/<project-id-or-encoded-namespace%2Fproject>/merge_requests/<iid>`, its `/notes`, and its `/diffs` endpoints. For an explicit external URL, preserve its host and namespace/project and pass the exact repository (and hostname when needed), or use those exact API coordinates. If project identity is absent or the query or any referenced MR cannot be read, stop rather than infer its location, state, or contents.
- **Reconcile**: on resumption, read the Parent, record, and every discovered Issue with `glab issue view <iid> --comments`, then perform linked-MR discovery above; compare real Issue and MR state with the snapshot, repair the snapshot and missing references, and append a dated reconciliation note.
- **Abandon**: append the dated reason and remaining-work dispositions, set snapshot status `abandoned`, then close the record Issue. Do not close the Parent or implementation Issues.
- **Complete successfully**: append final approval/history, set snapshot status `complete`, then close the record Issue. Do not close the Parent.

There is no background monitoring, expiry, or automatic abandonment.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `glab issue create --label wayfinder:map`. (On GitLab tiers with native epics, an epic may hold the map instead; a labelled issue works everywhere.)
- **Child ticket**: an issue carrying `Part of #<map>` at the top of its description and labels `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitLab's **native blocking link** — the canonical, UI-visible representation. Add it with the `/blocked_by #<n>` quick action, posted as a note (`glab issue note <child> --message "/blocked_by #<blocker>"`). Native blocking links are a Premium/Ultimate feature; on the free tier (or where unavailable) fall back to a `Blocked by: #<n>, #<n>` line at the top of the description. A ticket is unblocked when every blocker is closed.
- **Frontier query**: `glab issue list -F json` scoped to the map's children, drop any with an open blocker — a native `blocked_by` link to an open issue (`glab api projects/:id/issues/:iid/links`), or an open issue in the `Blocked by` line — or an assignee; first in map order wins.
- **Claim**: `glab issue update <n> --assignee @me` — the session's first write.
- **Resolve**: `glab issue note <n> --message "<answer>"`, then `glab issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
