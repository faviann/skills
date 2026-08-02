Quickstart:

```bash
npx skills add faviann/skills --skill=to-tickets
```

```bash
npx skills update to-tickets
```

[Source](https://github.com/faviann/skills/tree/main/skills/engineering/to-tickets)

## What it does

`to-tickets` breaks a plan, spec, or the current conversation into a set of **tickets** — each a tracer-bullet vertical slice — and publishes them to your configured tracker, with every ticket declaring the tickets that block it.

Every ticket is a **tracer bullet** — a thin *vertical* slice that cuts through all integration layers end-to-end (schema, API, UI, tests), never a horizontal slice of one layer. A completed slice is demoable or verifiable on its own, which is what makes each ticket safe to hand to an agent.

## When to reach for it

You invoke this by typing `/to-tickets` — the agent won't reach for it on its own.

Reach for it once you have an agreed plan or a written spec and you want it split into tickets. Point it at the conversation, or pass a spec or issue reference and it fetches the body and comments first. If the change hasn't been written up as a spec yet, produce one first — for that, use [to-spec](https://aihero.dev/skills-to-spec).

You can also invoke `/to-tickets <calibration-record>` in a fresh session after a staged Frontier has produced its named evidence. That is a resumption of one durable decomposition, not a new breakdown.

## Prerequisites

`to-tickets` publishes into your issue tracker, so [setup-matt-pocock-skills](https://aihero.dev/skills-setup-matt-pocock-skills) must have configured the tracker and its triage label vocabulary for this repo first. On a real tracker it applies the ready-for-agent label as it publishes.

## One artifact, two readings

The blocking edges are the whole point. They make one set of tickets read two ways, depending on the tracker:

- **Local files** → one file per ticket under `.scratch/<feature>/issues/`, numbered blockers-first, the edges written as text. You work them top-to-bottom, by hand, staying in the loop.
- **A real tracker (GitHub, Linear)** → one issue per ticket, the edges as native blocking links (or sub-issues). Any ticket whose blockers are all done is on the **frontier** and can be grabbed — so several agents can run at once.

The edges live in the ticket regardless of medium; the medium only decides whether anything acts on them in parallel. `to-tickets` produces the artifact — how you run it (sequential by hand, or a parallel fleet) is up to you.

## Vertical slices, not horizontal ones

The whole skill turns on one distinction. A **horizontal** slice ships one layer of the change — all the schema, or all the API — and nothing works until every layer lands. A **vertical** slice, the tracer bullet, ships one narrow path through *every* layer at once, so it can be demoed the moment it's done.

Two constraints bound how big a slice gets, and both have to hold: it has to fit in a single fresh context window, and it has to close as one reviewable pull request. The first is a capacity limit on the agent building it; the second is a limit on the human reviewing it. A ticket can pass the first and fail the second — it fits in context comfortably, then lands as a pull request nobody can review in one sitting — which is why the review budget is named separately.

Both budgets are about capacity, and a slice can clear both and still be a bad thing to land at once. So **risk** decides whether a slice splits: one that introduces more than one independent state, lifecycle, or authorization model gets split, however comfortably it fits. Independent means it can be got wrong on its own — alternatives within a single determination are one model however many outcomes it has, so their plurality alone doesn't trigger the rule, while two genuinely separate models do.

Risk decides *whether* a slice splits; a **safe and useful seam** decides *where* it can be cut. Neither overrides the other, which matters most when they disagree: a settled design may need a prefactor ticket to create the seam, while an unresolved design question sends the work back to [grill-with-docs](https://aihero.dev/skills-grill-with-docs), [prototype](https://aihero.dev/skills-prototype), or [wayfinder](https://aihero.dev/skills-wayfinder). `to-tickets` publishes nothing until the design can be safely decomposed.

And each semantic case or production mechanism gets exactly one owning ticket, because two tickets quietly claiming the same mechanism only discover each other as integration work after both have landed. Where two genuinely must touch the same one, the overlap gets scheduled rather than discovered.

There are no size numbers in any of this, deliberately. Counts and diff estimates are a prompt to look again at a slice, not a pass mark — a decomposition-time estimate is a guess about code that doesn't exist yet. For the slices where that judgement is hardest, the skill reaches for its own calibration reference — the risk taxonomy and a set of worked examples — and ordinary decompositions never pay for it.

Before slicing, `to-tickets` looks for prefactoring — "make the change easy, then make the easy change" — and orders that work first. It then quizzes you on the breakdown (granularity, blocking edges, what to merge or split) before publishing anything, and publishes blockers first so each ticket's "Blocked by" can reference a real ticket.

## Staged calibration

Most runs publish the whole approved decomposition. **Staged calibration** is the narrow exception for work whose behaviour and architecture are already settled but whose later reviewable Ticket boundaries depend on evidence from implementing an initial Frontier. It is not a way to defer design decisions: unresolved product behaviour, legal transitions, authority, or architecture sends the work back upstream and publishes nothing.

Before that first Frontier is published, `to-tickets` requires a durable Parent/source-contract reference, then creates a durable **Calibration record** in the configured tracker. The record and every staged Ticket link that source, while the record also links every published Frontier, the still-coarse settled remainder, sizing assumptions, and a concrete production evidence checkpoint. Without a durable source reference, staged publication stops. Deferred work stays in the record—not in placeholder Issues, hidden drafts, or human-ready Tickets—so implementation can start in fresh contexts without losing it.

Each Frontier gets one complete approval covering its edges, remainder, assumptions, and checkpoint. On `/to-tickets <calibration-record>`, the tracker is reconciled with the record before the evidence is assessed or more work is proposed. Production diffs, review/remediation findings, production-path validation, or relevant operational measurements may qualify; a throwaway prototype does not expose the integration and review burden being calibrated.

The record makes revisions visible instead of rewriting history: the original contract or assumption, contradiction/evidence, and affected Tickets are recorded before suspension or Ticket/dependency changes; the replacement conclusion and Ticket dispositions are completed before resumption. It can pause as `suspended-for-design`, finish as `complete`, or be deliberately `abandoned`; abandonment closes only the coordination record, not its Parent or implementation Tickets. Nothing expires or reconciles in the background.

## Fences go in Out of scope, not acceptance criteria

A spec usually carries prohibitions as well as requirements — "capture adds no message broker", "no mutable `latest` tag". When a ticket inherits one, it goes in the ticket's **Out of scope** section, never in its acceptance criteria.

The reason is that a fence asserts some code *doesn't* exist, so there is no input that could make it fail. As a criterion it can only ever be ticked on faith, and it invites someone to build machinery proving a negative. Both templates carry an Out of scope section for exactly this, with the standing note that these are fences for the reviewer — nothing should be built to prove them.

## The wide-refactor exception

A slice normally lands the behaviour it is meant to keep — its final form. One shape breaks that rule: a **wide refactor** — a single mechanical change (rename a column, retype a shared symbol) whose **blast radius** fans across the whole codebase, so one edit breaks thousands of call sites at once and no vertical slice can land green. `to-tickets` slices it as **expand–contract** instead: expand (introduce a compatibility form beside the old one), migrate (named batches sized by blast radius, one ticket per batch, consuming that form while both exist so CI stays green), then contract (remove the old form once every named batch has landed). When even the batches can't stay green alone, they share an integration branch that all block a final integrate-and-verify ticket, and green is promised only there.

What makes this legitimate is that the transitional arrangement is a contract, not an improvisation: the compatibility form is introduced deliberately, consumed by batches named up front, and the old form it stands beside is retired by a contract ticket that already exists in the breakdown. That is the exception — it isn't a general licence to leave a half-finished behavioural seam behind and call it transitional.

## Where it fits

`to-tickets` is a step in the main build chain:

```txt
grill-with-docs → to-spec → to-tickets → implement → code-review
```

It sits between [to-spec](https://aihero.dev/skills-to-spec), which hands it a settled spec with user stories to slice against, and [implement](https://aihero.dev/skills-implement), which builds each ticket, driving [tdd](https://aihero.dev/skills-tdd) internally to write the tests test-first, before its [code-review](https://aihero.dev/skills-code-review) pass. Work the frontier one ticket per fresh context, clearing between them. When you're unsure which skill or flow fits, [ask-matt](https://aihero.dev/skills-ask-matt) routes you.
