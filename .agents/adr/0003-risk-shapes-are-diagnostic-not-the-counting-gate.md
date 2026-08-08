# Risk shapes locate what the risk rule counts; they do not gate it

**Status: proposed.** Drafted from the [#39](https://github.com/faviann/skills/issues/39) grilling and awaiting the maintainer's acceptance. Nothing in `RISK-SHAPES.md`, `SKILL.md`, the docs page, or the eval has been changed to match it.

`to-tickets` splits a slice that introduces more than one independently failure-prone unit. `RISK-SHAPES.md` describes that unit two ways that do not line up. Its deciding sentence counts a **state, lifecycle, or authorization** model. Its taxonomy names five shapes — concurrency protocols, new persistence lifecycles, migration and convergence, backward compatibility, and fail-closed resource governance — and **none of them covers authorization**. Six of six blind evaluations found the mismatch, one summarising it as "authorization is a counted model kind but has no shape to be inspected under."

The gap is not confined to authorization. Any reading that treats the five shapes as the gate on counting will miss every unit whose kind the taxonomy happens not to name. Eval case 9 makes that concrete: two orthogonal determinations, a document's sensitivity and its retention class, neither introducing any named shape. A shape-gated rule returns one unit where the counting sentence plainly gives two.

That failure runs in the dangerous direction. `9f3515c` created the risk rule because "slices that cleared both [capacity budgets] still landed several independently failure-prone production contracts at once." Over-splitting wastes effort; under-splitting ships exactly the defect the rule exists to catch. So a rule whose blind spot is systematic under-counting is worse than one that occasionally over-counts.

## Considered options

**Extend the taxonomy.** Give authorization its own shape, so the shape list covers every kind the counting sentence names. Rejected: it treats the symptom. The shapes would still be the gate, so the next uncovered kind — case 9's orthogonal classifications among them — would under-count exactly as authorization does now. It also commits the reference to enumerating model kinds exhaustively, which nothing guarantees is possible.

**Demote the taxonomy.** Make the shapes diagnostic — *where to look* rather than *what you count against* — and let counting key on the identity of the unit itself. Chosen.

## Decision

- The **risk shape** is a diagnostic pattern that helps locate the units the rule counts. It is not exhaustive, and it neither admits nor excludes a unit from the count.
- The counted unit is the **correctness contract**: a coherent set of outcomes and invariants that must remain correct as one unit.
- A **responsibility** is what a correctness contract decides or governs — state, lifecycle, and authorization are examples. Responsibilities are not exhaustive either, and they do not admit or exclude a contract from the count.
- One correctness contract may hold several responsibilities, and several contracts may share a responsibility. **Authorization therefore needs no shape of its own to be countable.**

## Consequences

- A gap in the taxonomy stops being a silent under-split. This is the whole point, and it is what makes the decision worth recording rather than obvious.
- Eval case 4 becomes keyable without extending the taxonomy. An export path refusing documents above a sensitivity threshold is the direct application of the sensitivity determination — one contract carrying two responsibilities — which matches the existing `1 / no` key. That keying is [#39](https://github.com/faviann/skills/issues/39)'s remaining work, and it discharges what [#37](https://github.com/faviann/skills/issues/37) is blocked on.
- Any discriminator gated on named shapes is excluded. It fails case 9 by construction.
- The prose does not yet use this vocabulary. `SKILL.md`, `RISK-SHAPES.md`, and the eval all still say *independent model*, and `CONTEXT.md` records the pending rename under **Flagged ambiguities** rather than retiring the live name. The rename lands with [#37](https://github.com/faviann/skills/issues/37)'s positive test, since that prose has to be rewritten anyway. `SKILL.md`'s paragraph is deliberate fork-authored wording hoisted by `5dd5609` and `99e164d` — `git log -S` it and patch the minimum.
- The eval's **Isolated prompt** keeps its current wording until a candidate discriminator is ready. Renaming the vocabulary an evaluator reads would change the measured input and invalidate the baseline the change is judged against.
- Accepting this does not settle [#37](https://github.com/faviann/skills/issues/37). It rules out one family of discriminator and licenses another; the positive test that identifies one correctness contract is still undecided.
