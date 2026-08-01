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
A `wayfinder` artifact — a single **Issue** labelled `wayfinder:map` charting one effort toward its **Destination**. It is an *index, not a store*: it gists the decisions made and links to the **Decision tickets** holding their detail, and is loaded once per session at low resolution. Where its child tickets, blocking edges, and **Frontier** queries physically live is tracker-specific — see `docs/agents/issue-tracker.md`.

**Destination**:
What reaching the end of a **Map** looks like — the spec, decision, or change the effort is finding its way to. Named first when charting, because it fixes the effort's scope: work beyond it is *out of scope* rather than **Not yet specified**.

**Decision ticket**:
A `wayfinder` unit — a child **Issue** of a `wayfinder:map` holding a *question* whose resolution is a decision, not a slice of a build to execute. The **decision** qualifier is what keeps it distinct from an implementation ticket; `wayfinder` introduces the term, then uses "ticket".

**Frontier**:
The work takeable right now. Defined twice in the skills and not yet reconciled — `wayfinder` requires it to be *unclaimed*, `to-tickets` does not. See **Flagged ambiguities** before relying on either reading.

**Not yet specified** (the *fog of war*):
The section of a **Map** holding what is in scope but not yet sharp enough to ticket — the decisions and investigations you can tell are coming but cannot yet pin down. The test is whether the *question* can be stated precisely now, not whether it can be answered. Deliberately coarser than a ticket: one patch may **Graduate** into several **Decision tickets**, or none. Excludes what is already decided, already a live ticket, or out of scope.

**Graduate**:
What happens when resolving a **Decision ticket** clears the fog ahead of it: material in **Not yet specified** becomes sharp enough to state as a question and is promoted into fresh **Decision tickets** — one at a time. Work ruled out of scope never graduates.

**Parent**:
The source **Issue** that a set of `to-tickets` slices was decomposed from — a spec or feature request the tickets link back to. Unlike a **Map**, a parent is *read-only* to the skill that produced its children: `to-tickets` never closes or modifies it.

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
- A **Map** is written to as its effort progresses; a **Parent** is not written to at all

## Flagged ambiguities

- "backlog" was previously used to mean both the *tool* hosting issues and the *body of work* inside it — resolved: the tool is the **Issue tracker**; "backlog" is no longer used as a domain term.
- "backlog backend" / "backlog manager" — resolved: collapsed into **Issue tracker**.
- "epic" is an imported term (Jira/agile) with **two** targets here, so it is never used on its own. A **Map** and a **Parent** are both "a big thing with smaller things under it", but they route to different skills. The test is whether the decisions are settled: open decisions and no visible route → a **Map**, charted by `wayfinder`; decisions settled and the work is being sliced into a build → a **Parent**, produced by `to-spec` and decomposed by `to-tickets`. Say which one is meant.
- **Frontier** is defined twice and the two do not agree. `wayfinder`: "the open, unblocked, *unclaimed* children — the edge of the known". `to-tickets`: "any ticket whose blockers are all done", with no unclaimed condition. The difference is whether a ticket someone has already taken still counts, which decides whether several agents working one tracker collide. **Unresolved** — do not silently adopt either reading.
- Whether the **Map** / **Not yet specified** / **Graduate** mechanism belongs to `wayfinder` alone or is a shared concept other skills may use is **open**, and owned by [#11](https://github.com/faviann/skills/issues/11). The entries above describe only what `wayfinder` ships today; they deliberately do not settle that question.
