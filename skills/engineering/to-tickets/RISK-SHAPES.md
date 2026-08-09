# Risk shapes

How to judge a slice that fits both budgets and still might be too dangerous to land at once. Assumes the vocabulary in [SKILL.md](SKILL.md) — **tracer bullet**, **vertical slice**, **blast radius**, **seam**.

Use it to answer three questions in order: which independent models this slice introduces, which risk shapes they instantiate, and where a seam can land without producing a half that is unsafe or useless. Where a settled design needs a code seam, the prefactor that creates it is its own ticket sequenced ahead of the split slices. Where an unresolved design question prevents a safe seam, the input returns to the appropriate fog-clearing flow without publishing.

A model is **independent** when it can be got wrong on its own — its correctness does not follow from another's. These shapes are where independent models usually live. Inspect them, then count the models you find:

- **Concurrency protocols** — a new ordering, locking, deduplication, or coordination rule that separate actors must agree on.
- **New persistence lifecycles** — state that something now has to create, mutate, converge, expire, or reconcile on its own schedule.
- **Migration and convergence models** — existing data, or already-running instances, must arrive at a new form; correctness depends on what was already out there.
- **Backward-compatibility protocols** — two forms coexist and something must read, write, or negotiate both.
- **Authorization boundaries** — identity or capability checks that decide who or what may act.
- **Fail-closed resource-governance authority** — a deadline, budget, quota, or size bound whose breach makes the system refuse, truncate, or degrade rather than continue.

More than one **independent model** in a single slice is what the risk rule fires on — not more than one shape. The taxonomy works in both directions: the shapes say what to inspect, and the rule counts the independent models instantiating them. Two independent concurrency protocols are one shape and two models; a slice reaching across two shapes carries one model when neither half can be got wrong without the other.

What decides is the qualitative identification of more than one independent state, lifecycle, or authorization model. Counts of files, boundaries, taxonomy categories, estimated diff size, or models merely *touched* are advisory. Three readings follow from that:

- One model may have several outcomes, authorities, code paths, and failure modes. That plurality is not plural models.
- Two independent instances of the same shape count twice.
- Alternatives within one shared determination — whose state space has to stay complete and coherent — count once. Mutual exclusivity is supporting evidence for that reading, not the test.

The skill states the rule in shorter words; these shapes are what it covers.

## Discriminators

Each of these separates ordinary work from a risk shape. Ordinary work does not count toward the split.

**Persistence.** Traversing persistence is ordinary: reading, writing, or querying through a lifecycle that already exists, whose invariants already hold, and whose failure modes are already exercised. It becomes a risk shape when the slice *introduces* a lifecycle — new state with its own creation, convergence, or expiry — or a compatibility protocol, where new writes must stay legible to old readers or old records legible to new ones.

**Authorization.** Traversing an existing authority is ordinary: the slice acts through identity or capability checks that something else already owns and enforces. It becomes a risk shape when the slice *introduces or materially widens* one. Authorization governs who or what may act; resource governance bounds how much may be consumed.

**Resource governance.** Consuming an existing bound is ordinary: the slice runs inside one named by the shape above that something else already owns and enforces. It becomes a risk shape when the slice *introduces or materially changes* one — because afterwards a caller that previously always completed can now be refused, truncated, or bounded, and every caller inherits that failure mode.

## Oversized shapes

Four capture tickets from one production wave. Each fitted both budgets and each should still have been split, because each introduced several independent models at once. Read them as failure shapes, not as sizing precedents — none of them establishes a diff-size limit.

- ***Discover stable child rollout streams*.** Child discovery, a migration model, and upgrade convergence in one slice: discovery could be correct while migration stranded existing records, and both could be correct while an upgraded instance failed to converge.
- ***Advance oversized captures with explicit omissions*.** A transport boundary and a content-policy resource boundary in one slice: two separate authorities deciding independently to refuse or omit content.
- ***Omit binary capture bytes before persistence*.** It presents as one omission rule spanning a trust boundary and a serialization boundary, and that singular framing is the trap: what may be recorded, and how it survives round-tripping, fail apart.
- ***Report fidelity loss separately from capture safety failure*.** Outcome modelling, its persistence, and its propagation across runtimes: a correct model can be persisted lossily, and a correctly persisted one can arrive wrong on the other side.

## The counterexample

One ticket settled how a record's terminality is determined: a record is exactly one of active, terminal-readable, or terminal-uninspectable. It touched several contracts and correctly stayed one ticket, because those outcomes are alternatives within one determination rather than independent models. The state space has to stay complete and coherent — any split either shipped a determination that could reach an outcome nothing handled, or outcomes no path could reach — so the slice carried one model and the risk rule never fired.

Two misreadings are worth heading off. The ticket did not centralise the authorities: the reader's terminality evidence, the adapter's mapping of that evidence to canonical form, and server fidelity policy stayed deliberately separate, because coupling them across module boundaries would have joined authorities that really are independent. One determination is not one place; what the ticket combined was the predicate, so the required mechanism has one decision point. And its branches are not kept whole because they fail together — they began as separate predicates and were combined later, and they can still fail separately. They are one model because they answer one question.

So what stops the risk rule firing on every multi-contract slice is the independence test above, not the availability of a seam. Risk decides whether a split is required; the seam rule decides where that split can land. They are one model, which is why no safe and useful split existed — the cohesion explains the missing seam, never the other way round. Where the rule does fire and no safe and useful seam is apparent, never leave the slice whole: if the design is settled, create the seam in its own prefactor ticket, sequenced ahead of the split slices by a real blocking edge; if a design question remains unresolved, stop without publishing and hand it back to the fog-clearing flow named in `SKILL.md`.

## Ownership collisions

The compaction ticket and the opaque-record ticket both claimed `context_compacted` normalization. Neither owned it. Two implementations of the same semantic case landed independently, and the overlap surfaced after publication as integration work nobody had scoped.

Catch this at decomposition time. For every semantic case and production mechanism the breakdown touches, name the one ticket that owns it. When two tickets genuinely must touch the same mechanism, publish an explicit sequence as a real blocking edge and state in the later ticket how it integrates with what the earlier one landed — a note in prose does not sequence anything a tracker can act on.

## What numbers are for

The risk-shape test above is qualitative — it asks what the slice introduces, and it decides. Tallying is not that test. The one number that decides is how many *genuinely independent* models the slice introduces, and it is reached by judging each candidate against the test above, not by adding up what the slice touches. Every other count — models merely touched, boundaries crossed, shapes present, files changed — and estimated diff size are prompts to re-examine a proposed slice. They are not verdicts. They do not establish that a slice is reviewable, and they must not become repository-independent pass/fail limits.

Keep two measurements apart:

- **Decomposition-time estimates are uncertain.** You are guessing at the size of code that does not exist yet, from a description of behaviour. Treat a large estimate as a reason to re-read the shapes above, never as a rejection on its own.
- **Closeout size is retrospective.** Measured after the fact across a body of completed tickets, it separates the clear extremes, but it does not explain borderline effort or its cause — the qualitative risk shapes do.
