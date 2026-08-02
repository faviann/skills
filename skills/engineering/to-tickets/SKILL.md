---
name: to-tickets
description: Break a plan, spec, or the current conversation into a set of tracer-bullet tickets, each declaring its blocking edges, published to the configured tracker — edges as text in one file per ticket locally, or native blocking links on a real tracker.
disable-model-invocation: true
---

# To Tickets

Break a plan, spec, or conversation into a set of **tickets** — tracer-bullet vertical slices, each declaring the tickets that **block** it.

The issue tracker and triage label vocabulary should have been provided to you — run `/setup-matt-pocock-skills` if not.

## Process

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes a reference (a spec path, an issue number or URL) as an argument, fetch it and read its full body and comments.

If the argument is a **Calibration record**, this is a resumption. Follow **Resume staged calibration** below instead of starting a new decomposition. A record reference may be a labelled coordination Issue, a GitLab Issue, or a local `.scratch/<feature>/calibration.md` path as defined by the configured tracker.

If the argument is a durable **Parent/source reference**, run the configured tracker's Parent-to-record discovery operation before beginning a new decomposition. If it returns one record, surface and load that record, then follow **Resume staged calibration** for a non-terminal status or report the terminal status without creating another record. If it returns more than one record, stop and show the ambiguity; never choose silently. If discovery or a returned record cannot be read, stop and surface the failure rather than inferring that no record exists. Begin a new decomposition only when the authoritative query succeeds and returns no record.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code. Ticket titles and descriptions should use the project's domain glossary vocabulary, and respect ADRs in the area you're touching.

Look for opportunities to prefactor the code to make the implementation easier. "Make the change easy, then make the easy change."

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests) — vertical, NOT a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice is sized by two constraints that both must hold: it fits in a single fresh context window, AND it closes as one reviewable pull request
- **Risk decides whether to split**: split a slice that introduces more than one independent state, lifecycle, or authorization model — even one that fits both budgets
- **Safe and useful seams decide where to split**: once risk calls for a split, place the seam so every resulting slice is independently safe and useful — where the settled design needs a code seam, create one in its own prefactor ticket, sequenced ahead of the split slices by a real blocking edge; where an unresolved design question prevents a safe seam, stop without publishing and hand the question back to the appropriate fog-clearing flow
- **One owner per mechanism**: each semantic case and production mechanism belongs to exactly one ticket. Where two tickets genuinely must touch the same one, give them an explicit sequence — a real blocking edge, not a remark — and state in the later ticket how it integrates with what the earlier one landed
- Any prefactoring should be done first

</vertical-slice-rules>

Risk decides **whether** a split is required; the seam rule decides **where** that split can land. Apply them together — neither overrides the other. The unit the risk rule counts is the **independent model**: a state, lifecycle, or authorization model that can be got wrong on its own. Alternatives within one shared determination — whose state space has to stay complete and coherent — are one model however many outcomes, authorities, or code paths they span; two genuinely independent instances of the same shape are two. Where the rule never fired, the slice is one ticket on those grounds. Where it did fire, its verdict stands — the seam rule places the split, it does not cancel it.

Where the required split has no seam, first consider whether a prefactor ticket can create one for the settled design. If the missing seam instead exposes an unresolved design question, the input is not ready for `to-tickets`: show the user the independent models that fired the rule, the seams and prefactors considered, and the question blocking a safe decomposition; then end the run without publishing. Tell the user to return to `/grilling` and `/domain-modeling` for a sharp decision, `/prototype` when the answer must be runnable or visible, or `/wayfinder` when the remaining fog is too large for one session. Do not resolve that design work inside the publication quiz. Once the decision is recorded in the source conversation or spec, rerun `to-tickets`. A complete set advances to step 5 only when it satisfies these rules and the user has approved it.

Read [CALIBRATION.md](CALIBRATION.md) before you settle a slice that crosses several production models, protocols, trust boundaries, compatibility paths, or resource-governance boundaries, or when the codebase offers no close implementation analogue for what the slice introduces. Otherwise skip it.

After the ordinary risk and seam analysis, consider **staged calibration** only when all four conditions hold:

1. the destination, product behaviour, architecture, and cross-slice contracts are settled;
2. an immediate Frontier satisfies the ordinary risk, ownership, safe/useful-seam, context, and review-budget rules;
3. later work is understood in scope but cannot yet be divided into safely reviewable Tickets; and
4. named evidence from implementing that Frontier will materially inform the later Ticket boundaries.

All four are required. A large plan, uncertain diff estimate, or missing implementation analogue is not enough. If the missing fact is a product choice, legal state transition, authority boundary, architecture, or other behavioural contract, staged calibration is forbidden: publish nothing and hand the work back to `/grilling`, `/domain-modeling`, `/prototype`, `/wayfinder`, or specification repair as appropriate. A prototype may settle design, but is not Calibration evidence.

Give each ticket its **blocking edges** — the other tickets that must complete before it can start. A ticket with no blockers can start immediately.

**Prefer final-form behavioural contracts** — a slice lands the behaviour it is meant to keep. **Wide refactors are the one exception**, and their transitional form is an intentional contract, not an improvised seam. A **wide refactor** is one mechanical change — rename a column, retype a shared symbol — whose **blast radius** fans across the whole codebase, so a single edit breaks thousands of call sites at once and no vertical slice can land green. Sequence it as **expand–contract**: the expand ticket introduces a **compatibility form** beside the old one; **name the migration batches that consume it**, sized by blast radius (per package, per directory), each batch its own ticket blocked by the expand; **retain the compatibility form until every named batch has landed**, and keep the old form standing beside it — call sites no batch has reached yet still compile against the old form, which is what keeps CI green batch to batch; then the contract ticket, blocked by every batch, removes the old form. When even the batches can't stay green alone, keep the sequence but let them share an integration branch that all block a final integrate-and-verify ticket — green is promised only there. This is the exception to final-form slicing, not a licence to invent temporary behavioural seams elsewhere.

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each ticket, show:

- **Title**: short descriptive name
- **Blocked by**: which other tickets (if any) must complete first
- **What it delivers**: the end-to-end behaviour this ticket makes work

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct — does each ticket only depend on tickets that genuinely gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.

For staged calibration, use one approval checkpoint for the complete staged proposal. In the same quiz, present:

1. why all four eligibility conditions hold;
2. the proposed immediate Frontier and its blocking edges;
3. the coarse undecomposed remainder;
4. the sizing assumptions that production evidence must test; and
5. the named evidence checkpoint and its sources.

Ask the ordinary granularity, edge, merge, and split questions as well. Approval covers only this Frontier and record snapshot; it never authorises a later Frontier.

### 5. Publish the tickets to the configured tracker

Publish the approved tickets. **How** depends on the tracker `/setup-matt-pocock-skills` configured — the tickets are the same either way, only the shape of the blocking edges changes:

- **Local files** → write one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). Each file's "Blocked by" lists the numbers/titles it depends on. Use the per-ticket file template below — one ticket per file, never a single combined file.
- **A real issue tracker (GitHub, Linear, …)** → publish one issue per ticket in dependency order (blockers first) so each ticket's blocking edges can reference real identifiers. Use the platform's native blocking / sub-issue relationship where it has one; otherwise set each ticket's "Blocked by" to the blocking issues. Apply the `ready-for-agent` triage label — the tickets are agent-grabbable by construction.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

Do NOT close or modify any parent issue.

<local-ticket-template>

# <NN> — <Ticket title>

**Parent/source contract:** the durable source path/reference. Required when published through staged calibration; otherwise include it when one exists.

**Calibration record:** `../calibration.md` when published through staged calibration; otherwise omit.

**Implementation artifacts:** for staged calibration, append durable production diff, PR/MR, review, remediation, validation, or operational-evidence references as they become available. Use `None yet` until then; tracker-native links remain authoritative where available. Otherwise omit.

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective — not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None — can start immediately".

**Status:** ready-for-agent

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

**Out of scope:** scope fences for the reviewer, not acceptance criteria — a prohibition this ticket carries down from the parent. They assert that code does not exist, which has no honest test seam; do not build machinery to prove them. Omit if the ticket carries none.

</local-ticket-template>

<issue-template>

## Parent/source contract

A durable reference to the source contract. Required when published through staged calibration; otherwise include it when the source was an existing tracker issue and omit it when none exists.

## Calibration record

A reference to the Calibration record when published through staged calibration; otherwise omit this section.

## Implementation artifacts

For staged calibration, append durable production diff, PR/MR, review, remediation, validation, or operational-evidence references as they become available. If the tracker exposes native Issue-to-PR/MR links, those links are authoritative and this section may say so; otherwise use explicit references. Omit for ordinary publication.

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective — not layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Out of scope

These are scope fences for the reviewer, not acceptance criteria. They assert that code does not exist, which has no honest test seam; do not build machinery to prove them.

- A prohibition this ticket carries down from the parent, or omit this section.

## Blocked by

- A reference to each blocking ticket, or "None — can start immediately".

</issue-template>

In either form, a prohibition the ticket carries down from the parent belongs in **Out of scope**, never in acceptance criteria. A fence asserts some code does not exist, so no input could make it fail; as a criterion it can only ever be ticked on faith.

In either form, avoid specific file paths or code snippets — they go stale fast. Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

## Staged calibration

Before staging, read the configured `docs/agents/issue-tracker.md`. It must document how to create and mark a Calibration record, read/update its snapshot, append dated history, discover the record from its Parent/source reference, discover Tickets from the record and the record from a Ticket, reconcile linked Tickets and pull requests, abandon it, and complete it successfully. If any operation is absent, stop before publishing and ask the user to complete `/setup-matt-pocock-skills` for that tracker.

Staged calibration requires a durable Parent/source-contract reference before any mutation. If the input has no durable source reference that both the record and every published Ticket can store, stop; do not create the record or publish a Frontier. This does not change ordinary publication, where the Parent section remains conditional.

The Calibration record is a human-readable coordination artifact, never an implementation Ticket. Do not give it `ready-for-agent`, `ready-for-human`, or any implementation-ready role, and exclude it from Frontier selection. The Parent remains read-only.

<calibration-record-template>

# Calibration: <effort>

**Status:** awaiting-evidence | ready-to-resume | suspended-for-design | complete | abandoned (`complete` and `abandoned` are terminal)

## Source contract

The Parent/spec reference and controlling ADRs.

## Settled scope and decisions

Links or concise statements sufficient to prevent accidental reopening.

## Published Frontiers

Ordered rounds, each linking every published implementation Ticket.

## Undecomposed remainder

In-scope, settled behaviour deliberately coarser than Tickets.

## Sizing assumptions

Exactly what remains unknown about capacity or reviewability.

## Evidence checkpoint

The concrete production implementation, review, remediation, validation, fault-injection, or relevant operational evidence required before another pass, including its source and, once known, its actual artifact identifiers.

## Next action

Who or what should resume, from which evidence.

## Decision history

Append-only dated entries for approval, publication or partial failure, evidence assessment, reconciliation repair, assumption/contract/dependency revision, suspension, resumption, completion, or abandonment.

</calibration-record-template>

### Publish the first Frontier safely

After approval:

1. create the record first, before context may clear;
2. publish only the approved immediate Frontier, blockers first;
3. link every Ticket to both its durable Parent/source contract and the record;
4. replace provisional references in the record with the real Ticket references, set `awaiting-evidence`, and append the publication history; and
5. keep every deferred item only in **Undecomposed remainder**—never as a placeholder Issue, hidden draft Ticket, or `ready-for-human` work.

Treat publication as incomplete until the record and all Ticket links agree. If any mutation fails, append a visible dated partial-failure entry, then repair the record and every missing link before reporting success. Never leave a published Ticket detached from the durable remainder.

### Resume staged calibration

On every `/to-tickets <calibration-record>` resumption, reload the Parent, the complete record, and every linked Ticket. For each staged Ticket, run the configured tracker's native linked-PR/MR discovery operation and also follow explicit durable artifact references in the Ticket or record; read every discovered diff, pull/merge request, and named checkpoint artifact. If the tracker has no native linkage, require explicit durable references. Before proposing work, reconcile the record against the real tracker artifacts:

- the tracker is authoritative for current Ticket and pull-request implementation state;
- the record is authoritative for the undecomposed remainder, sizing assumptions, evidence checkpoint, and decision history;
- repair snapshot discrepancies and append a dated reconciliation entry before continuing; and
- never silently infer an absent identifier or a missing or unreachable Ticket, pull/merge request, Parent, link, or checkpoint artifact. Stop and surface what cannot be read or repaired.

Then transition explicitly:

- **Evidence missing:** optionally append a dated assessment, change nothing else, and remain `awaiting-evidence`.
- **Evidence ready:** set `ready-to-resume`, append the assessment, test it against the recorded sizing assumptions, revise the snapshot, propose the next Frontier, and run the full quiz again.
- **Subsequent Frontier approved:** publish and link only that Frontier, revise the remainder and named checkpoint, append history, and return to `awaiting-evidence`.
- **Design no longer settled:** publish nothing; record the revision described below, set `suspended-for-design`, and route upstream. Resume only after the approved replacement decision is linked, affected Ticket dispositions are complete, and the Parent/source contract references the decision.
- **Remainder empty:** record final approval and history, set `complete`, invoke the tracker's successful-completion operation, and leave the Parent open and unchanged.
- **Effort intentionally dropped or replaced:** append the dated reason, disposition every remaining item, optionally link the replacement in history, set `abandoned`, and invoke the tracker's abandonment/completion operation. Do not automatically close or alter the Parent or any implementation Ticket. There is no separate `superseded` status.

There is no background reconciliation, expiry timer, garbage collection, automatic abandonment, or ownership system. Reconciliation occurs only on resumption.

### Preserve revisions before mutation

Maintain a dated revision entry containing:

1. the exact original assumption or contract;
2. the contradicting implementation, review, validation, or operational evidence;
3. the replacement sizing/dependency conclusion, or the approved replacement-contract link;
4. every affected Ticket; and
5. each Ticket's disposition: unchanged, edited, reordered by dependency, replaced, or closed.

Record the original assumption or contract, contradiction/evidence, and affected Tickets **before** suspending for design and before any mutable Ticket or dependency change. Record the replacement conclusion and all Ticket dispositions before resuming after the replacement decision; they are not prerequisites to suspension. Never rewrite history to make an earlier assumption disappear.
