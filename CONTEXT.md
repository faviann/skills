# Matt Pocock Skills

A collection of agent skills (slash commands and behaviors) loaded by Claude Code. Skills are organized into buckets and consumed by per-repo configuration emitted by `/setup-matt-pocock-skills`.

## Language

**Issue tracker**:
The tool that hosts a repo's issues — GitHub Issues, Linear, a local `.scratch/` markdown convention, or similar. Skills like `to-tickets`, `to-spec`, and `triage` read from and write to it.
_Avoid_: backlog manager, backlog backend, issue host

**Issue**:
A single tracked unit of work inside an **Issue tracker** — a bug, task, spec, or slice produced by `to-tickets`.
_Avoid_: ticket (use only when quoting external systems that call them tickets, or for a **Decision ticket** — see below)

**Map**:
A `wayfinder` artifact — a single **Issue** labelled `wayfinder:map` charting one effort toward its **Destination**. It is an *index, not a store*: it gists the decisions made and links to the **Decision tickets** holding their detail, and is loaded once per session at low resolution.

**Destination**:
What reaching the end of a **Map** looks like — the spec, decision, or change the effort is finding its way to. Named first when charting, because it fixes the effort's scope: work beyond it is *out of scope* rather than **Not yet specified**.

**Decision ticket**:
A `wayfinder` unit — a child **Issue** of a `wayfinder:map` holding a *question* whose resolution is a decision, not a slice of a build to execute. The **decision** qualifier is what keeps it distinct from an implementation ticket; `wayfinder` introduces the term, then uses "ticket".

**Frontier**:
The work takeable right now. Two scoped uses, not one contested definition — `wayfinder` adds an *unclaimed* condition because it claims before working; `to-tickets` omits it because it publishes rather than dispatches — see **Flagged ambiguities**.

**Not yet specified** (the *fog of war*):
The section of a **Map** holding what is in scope but not yet sharp enough to ticket — the decisions and investigations you can tell are coming but cannot yet pin down. The test is whether the *question* can be stated precisely now, not whether it can be answered.

**Graduate**:
What happens when resolving a **Decision ticket** clears the fog ahead of it: material in **Not yet specified** becomes sharp enough to state as a question and is promoted into fresh **Decision tickets** — one at a time. Work ruled out of scope never graduates.

**Parent**:
The source **Issue** that a set of `to-tickets` slices was decomposed from — a spec or feature request the tickets link back to. `to-tickets` never changes its source-contract content, scope, or lifecycle, but may append a **Staged calibration** checkpoint to its comment surface after explicit approval.

**Staged calibration**:
Partial publication of settled work when production evidence must inform the boundaries of later implementation **Issues**; its durable checkpoint is appended to the **Parent** comment surface.

**Calibration evidence**:
Evidence from the maintained production path that answers a staged-calibration sizing assumption.

**Triage role**:
A canonical state-machine label applied to an **Issue** during triage (e.g. `needs-triage`, `ready-for-agent`). Each role maps to a real label string in the **Issue tracker** via `docs/agents/triage-labels.md`.

**Risk shape**:
A diagnostic pattern showing where independently failure-prone **Correctness contracts** commonly live. It guides inspection but is neither exhaustive nor the unit counted by `to-tickets`'s risk rule.
_Avoid_: taxonomy gate, counted shape

**Workflow provenance**:
The `work-on` telemetry fingerprint of the exact `work-on`, selected workflow, `tdd`, and `code-review` instruction bytes that governed a run. This is runtime attribution, not the risk-shapes provenance record that maps production examples to their sources.
_Avoid_: instruction version, risk-shapes provenance

**Correctness contract**:
A coherent set of outcomes and invariants that must remain correct as one unit. `to-tickets`'s risk rule counts independent correctness contracts.
_Avoid_: production contract

**Responsibility**:
What a **Correctness contract** decides or governs, such as state, lifecycle, or authorization. One contract can have several responsibilities, and several contracts can have the same responsibility.
_Avoid_: model kind, model family

## Relationships

- An **Issue tracker** holds many **Issues**
- An **Issue** carries one **Triage role** at a time
- A **Correctness contract** has one or more **Responsibilities**, and several **Correctness contracts** may share one **Responsibility**
- A **Risk shape** helps locate **Correctness contracts** but does not determine how many a slice contains
- A **Decision ticket** is an **Issue** (a child of a `wayfinder:map`)
- A **Map** is an **Issue**, and charts one effort toward its **Destination**
- A **Map** holds many **Decision tickets** and one **Not yet specified** section
- A **Decision ticket** joins a **Map** either at charting, or by **Graduating** from **Not yet specified**
- A **Parent** is an **Issue**, and the **Issues** `to-tickets` produced from it link back to it
- A **Map** is written to as its effort progresses; a **Parent** keeps its source-contract content unchanged, though `to-tickets` may append an approved **Staged calibration** checkpoint to its comment surface

## Flagged ambiguities

- "backlog" was previously used to mean both the *tool* hosting issues and the *body of work* inside it — resolved: the tool is the **Issue tracker**; "backlog" is no longer used as a domain term.
- "backlog backend" / "backlog manager" — resolved: collapsed into **Issue tracker**.
- "epic" is an imported term (Jira/agile) with **two** targets here, so it is never used on its own. A **Map** and a **Parent** are both "a big thing with smaller things under it", but they route to different skills. The test is whether the decisions are settled: open decisions and no visible route → a **Map**, charted by `wayfinder`; decisions settled and the work is being sliced into a build → a **Parent**, produced by `to-spec` and decomposed by `to-tickets`. Say which one is meant.
- **Frontier** is defined twice. `wayfinder`: "the open, unblocked, *unclaimed* children — the edge of the known". `to-tickets`: "any ticket whose blockers are all done", with no unclaimed condition. Resolved: the two are scoped, not contradictory. `wayfinder` claims a ticket by assigning it before any work, so its frontier query drops assigned children; `to-tickets` publishes and never dispatches, so its line orders work rather than allocating it. The unclaimed condition lives where claiming happens. Both definitions are upstream's and both our copies are byte-identical, so there is nothing here to patch. Our AFK path (`select-issue` → `work-on`) does not claim either, which is safe while one agent runs at a time; running several concurrently would need a claim step in those skills — a gap there, not in this term.
- Whether the **Map** / **Not yet specified** / **Graduate** mechanism belongs to `wayfinder` alone or is shared — resolved by [#11](https://github.com/faviann/skills/issues/11): `wayfinder` retains that design-fog mechanism; `to-tickets` handles a settled deferred remainder with a **Staged calibration** checkpoint on the **Parent**.
- **Correctness contract** is the settled name for the unit `to-tickets`'s risk rule counts, but the skill prose still calls it the *independent model* — in `SKILL.md`, `RISK-SHAPES.md`, and the risk-shapes eval. **Not yet resolved**, and deliberately not listed under `_Avoid_` — for two reasons, of which the second is the one that actually stops the edit. Retiring a name the prose still uses would make this glossary contradict every file it describes. And the eval's **Isolated prompt** is evaluator-visible *measured input*: renaming the vocabulary there forfeits comparability with the isolated baseline, the multi-case run, and the `d21bd3f` control, which is the only captured known-good reading of the pre-change text. An `_Avoid_` line is exactly the kind of instruction an agent acts on unilaterally in a file that looks like prose.

  Scope, so whoever executes it knows what they are taking on: roughly 60 sites across `SKILL.md`, `RISK-SHAPES.md`, `docs/engineering/to-tickets.md`, the risk-shapes eval, and `CLAUDE.md`'s risk-shapes trigger sentence — and the docs page uses *model* to mean the LLM in several places, so a mechanical rename will corrupt those. [ADR 0005](./.agents/adr/0005-do-not-add-a-short-boundary-rule.md) closed #37 without discriminator wording, so the rename needs its own occasion and its own full-suite pass under the then-current eval **Protocol**. `SKILL.md`'s paragraph is deliberate fork-authored wording — `git log -S` it and patch the minimum before touching it. Until then both names denote the same thing, and the prose's name is the one in force.

- **Determination** became load-bearing in `to-tickets`'s counting rule with [ADR 0004](./.agents/adr/0004-risk-shapes-do-not-gate-the-count.md): the rule counts the determinations a slice introduces, whether or not they instantiate a **Risk shape**. Its *boundary* is deliberately undefined. [#37](https://github.com/faviann/skills/issues/37) closed with a negative result after six boundary rules failed on case-independent counterexamples and a separate shape-scoping repair failed through split-instability; [ADR 0005](./.agents/adr/0005-do-not-add-a-short-boundary-rule.md) preserves that record. **Not yet resolved**, and deliberately not a headword: an entry here would have to fix a boundary the decision leaves open, which is the drift this file exists to stop. Its relation to **Correctness contract** is unsettled too — a determination is at least what one contract decides, but whether the two name the same unit is undecided.
