# Issue tracker: Local Markdown

Issues and specs (you may know a spec as a PRD) for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` — never a single combined tickets file
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Calibration-record operations

Used by staged `/to-tickets`.

- **Create and mark**: create `.scratch/<feature>/calibration.md` first. Its Calibration-record template and non-ticket path mark it as coordination state; never give it an implementation-ready status or include it in Frontier scans.
- **Read/update snapshot**: read and edit the latest snapshot in that file.
- **Append history**: append dated entries under `## Decision history`; never replace earlier entries.
- **Find record from Parent/source**: the record's `Source contract` stores the Parent/spec path or reference. Starting from that reference, search `.scratch/*/calibration.md` for the exact value to recover the record without modifying the Parent/source.
- **Bidirectional Ticket discovery**: every `.scratch/<feature>/issues/<NN>-<slug>.md` includes `Calibration record: ../calibration.md` and its Parent reference; the record's ordered Published Frontiers links every Ticket. Scan those files to verify both directions.
- **Implementation-artifact discovery**: local Markdown has no native PR/MR linkage. Read each staged Ticket's `Implementation artifacts` field and the record's Evidence checkpoint for explicit durable diff, PR/MR, review, remediation, validation, or operational-evidence references. Open every local path; for a PR/MR URL, use the corresponding platform CLI with the repository and identifier parsed from that URL to read its metadata and diff. `None yet` means evidence is missing. If a reference is ambiguous or unreachable, stop rather than infer it.
- **Reconcile**: on resumption, inspect the Parent, record, every linked Ticket file, and every explicitly referenced implementation artifact; compare their real status with the snapshot, repair the snapshot and missing links, and append a dated reconciliation entry.
- **Abandon**: append the dated reason and remaining-work dispositions, then set `Status: abandoned`. Do not alter the Parent or implementation Tickets.
- **Complete successfully**: append final approval/history, then set `Status: complete`. Do not alter the Parent.

The terminal status and history distinguish successful completion from abandonment. There is no background monitoring, expiry, or automatic abandonment.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` — the Notes / Decisions-so-far / Fog body.
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.
