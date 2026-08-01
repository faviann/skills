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
- **Safe and useful seams decide where to split**: once risk calls for a split, place the seam so every resulting slice is independently safe and useful — where no seam does that yet, create one in its own prefactor ticket, sequenced ahead of the split slices by a real blocking edge; where none can be created even then, the breakdown is not ready to publish — raise it in the quiz
- **One owner per mechanism**: each semantic case and production mechanism belongs to exactly one ticket. Where two tickets genuinely must touch the same one, give them an explicit sequence — a real blocking edge, not a remark — and state in the later ticket how it integrates with what the earlier one landed
- Any prefactoring should be done first

</vertical-slice-rules>

Risk decides **whether** a split is required; the seam rule decides **where** that split can land. Apply them together — neither overrides the other. The unit the risk rule counts is the **independent model**: a state, lifecycle, or authorization model that can be got wrong on its own. Alternatives within one shared determination — whose state space has to stay complete and coherent — are one model however many outcomes, authorities, or code paths they span; two genuinely independent instances of the same shape are two. Where the rule never fired, the slice is one ticket on those grounds. Where it did fire, its verdict stands — the seam rule places the split, it does not cancel it.

Where the required split has no seam and none can be created, the decomposition is unresolved and the set is not ready to publish. Show the user the independent models that fired the rule, the candidate seams considered and why none is both safe and useful, and the prefactor tickets considered and why none would create such a seam. Stay in step 4 and keep proposing revisions; end the `to-tickets` run without publishing only once the user confirms that none of them resolves the decomposition. The complete set advances to step 5 only once the breakdown satisfies these rules and the user has approved it.

Read [CALIBRATION.md](CALIBRATION.md) before you settle a slice that crosses several production models, protocols, trust boundaries, compatibility paths, or resource-governance boundaries, or when the codebase offers no close implementation analogue for what the slice introduces. Otherwise skip it.

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

### 5. Publish the tickets to the configured tracker

Publish the approved tickets. **How** depends on the tracker `/setup-matt-pocock-skills` configured — the tickets are the same either way, only the shape of the blocking edges changes:

- **Local files** → write one file per ticket under `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` in dependency order (blockers first). Each file's "Blocked by" lists the numbers/titles it depends on. Use the per-ticket file template below — one ticket per file, never a single combined file.
- **A real issue tracker (GitHub, Linear, …)** → publish one issue per ticket in dependency order (blockers first) so each ticket's blocking edges can reference real identifiers. Use the platform's native blocking / sub-issue relationship where it has one; otherwise set each ticket's "Blocked by" to the blocking issues. Apply the `ready-for-agent` triage label unless instructed otherwise — the tickets are agent-grabbable by construction.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain that means top to bottom.

Do NOT close or modify any parent issue.

<local-ticket-template>

# <NN> — <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective — not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or "None — can start immediately".

**Status:** ready-for-agent

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2

**Out of scope:** scope fences for the reviewer, not acceptance criteria — a prohibition this ticket carries down from the parent. They assert that code does not exist, which has no honest test seam; do not build machinery to prove them. Omit if the ticket carries none.

</local-ticket-template>

<issue-template>

## Parent

A reference to the parent issue on the tracker (if the source was an existing issue, otherwise omit this section).

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
