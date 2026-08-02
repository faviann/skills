# Matt Pocock Skills

A collection of agent skills (slash commands and behaviors) loaded by Claude Code. Skills are organized into buckets and consumed by per-repo configuration emitted by `/setup-matt-pocock-skills`.

## Language

**Issue tracker**:
The tool that hosts a repo's issues — GitHub Issues, Linear, a local `.scratch/` markdown convention, or similar. Skills like `to-tickets`, `to-spec`, `triage`, and `qa` read from and write to it.
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
The work takeable right now. `wayfinder` additionally requires it to be *unclaimed* because it claims before working; `to-tickets` does not, because it publishes rather than dispatches — see **Flagged ambiguities**.
_Avoid_: pilot Frontier

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

## Relationships

- An **Issue tracker** holds many **Issues**
- An **Issue** carries one **Triage role** at a time
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
