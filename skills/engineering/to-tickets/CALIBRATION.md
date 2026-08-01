# Calibration

How to judge a slice that fits both budgets and still might be too dangerous to land at once. Assumes the vocabulary in [SKILL.md](SKILL.md) — **tracer bullet**, **vertical slice**, **blast radius**, **seam**.

Use it to answer three questions in order: which contracts in this slice are independently failure-prone, whether more than one risk shape is present, and where a seam can land without producing a half that is unsafe or useless.

## Risk shapes

A contract is **independently failure-prone** when it can fail in production without any of the others failing. Count these, not files:

- **Concurrency protocols** — a new ordering, locking, deduplication, or coordination rule that separate actors must agree on.
- **New persistence lifecycles** — state that something now has to create, mutate, converge, expire, or reconcile on its own schedule.
- **Migration and convergence models** — existing data, or already-running instances, must arrive at a new form; correctness depends on what was already out there.
- **Backward-compatibility protocols** — two forms coexist and something must read, write, or negotiate both.
- **Fail-closed resource-governance authority** — a deadline, budget, quota, or size bound whose breach makes the system refuse, truncate, or degrade rather than continue.

More than one of these in a single slice is what the risk rule fires on. The skill states that rule in shorter words; these shapes are what it covers.

## Discriminators

Both of these separate ordinary work from a risk shape. Ordinary work does not count toward the split.

**Persistence.** Traversing persistence is ordinary: reading, writing, or querying through a lifecycle that already exists, whose invariants already hold, and whose failure modes are already exercised. It becomes a risk shape when the slice *introduces* a lifecycle — new state with its own creation, convergence, or expiry — or a compatibility protocol, where new writes must stay legible to old readers or old records legible to new ones.

**Resource governance.** Consuming an existing budget is ordinary: the slice runs inside a deadline, quota, or size limit that something else already owns and enforces. It becomes a risk shape when the slice *introduces or materially changes* a deadline, budget, refusal authority, or bounded representation — because afterwards a caller that previously always completed can now be refused, truncated, or bounded, and every caller inherits that failure mode.

## Oversized shapes

Four capture tickets from Overmind's Phase 2 wave. Each fitted both budgets and each should still have been split, because each carried several independently failure-prone contracts at once. Read them as failure shapes, not as sizing precedents — none of them establishes a diff-size limit.

- **[overmind#160](https://github.com/faviann/overmind/pull/160) — *Discover stable Codex child rollout streams*.** Child discovery, a migration model, and upgrade convergence in one slice: discovery could be correct while migration stranded existing records, and both could be correct while an upgraded instance failed to converge.
- **[overmind#168](https://github.com/faviann/overmind/pull/168) — *Advance oversized captures with explicit omissions*.** A transport boundary and a content-policy resource boundary in one slice: two separate authorities deciding independently to refuse or omit content.
- **[overmind#174](https://github.com/faviann/overmind/pull/174) — *Omit binary capture bytes before persistence*.** One omission rule spanning a trust boundary and a serialization boundary: what may be recorded, and how it survives round-tripping, fail apart.
- **[overmind#176](https://github.com/faviann/overmind/pull/176) — *Report fidelity loss separately from capture safety failure*.** Outcome modelling, its persistence, and its propagation across runtimes: a correct model can be persisted lossily, and a correctly persisted one can arrive wrong on the other side.

## The counterexample

[overmind#154 / PR #175](https://github.com/faviann/overmind/pull/175) modelled mutually exclusive terminality states. It touched several contracts, and it correctly stayed one ticket: the states formed a single cohesive state machine, so no seam produced two independently safe and useful halves. Any split either shipped a machine that could reach a state nothing handled, or shipped states no path could reach. Neither half was safe, and neither was useful alone.

This is what keeps the risk rule from firing on every multi-contract slice. Risk decides whether a split is required; the seam rule decides where that split can land.

## Ownership collisions

Overmind #147 and #148 — the compaction ticket and the opaque-record ticket — both claimed `context_compacted` normalization. Neither owned it. Two implementations of the same semantic case landed independently in [PR #162](https://github.com/faviann/overmind/pull/162) and [PR #163](https://github.com/faviann/overmind/pull/163), and the overlap surfaced after publication as integration work nobody had scoped.

Catch this at decomposition time. For every semantic case and production mechanism the breakdown touches, name the one ticket that owns it. When two tickets genuinely must touch the same mechanism, publish an explicit sequence as a real blocking edge and state in the later ticket how it integrates with what the earlier one landed — a note in prose does not sequence anything a tracker can act on.

## What numbers are for

The risk-shape test above is qualitative — it asks what the slice introduces, and it decides. Tallying is not that test. Counts — models touched, boundaries crossed — and estimated diff size are prompts to re-examine a proposed slice. They are not verdicts. They do not establish that a slice is reviewable, and they must not become repository-independent pass/fail limits.

Keep two measurements apart:

- **Decomposition-time estimates are uncertain.** You are guessing at the size of code that does not exist yet, from a description of behaviour. Treat a large estimate as a reason to re-read the risk shapes above, never as a rejection on its own.
- **Closeout size is retrospective.** Measured after the fact across a body of completed tickets, it separates the clear extremes, but it does not explain borderline effort or its cause — the qualitative risk shapes do.
