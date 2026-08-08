# Risk shapes locate what the risk rule counts; they do not gate it

**Status: proposed.** Drafted from the [#39](https://github.com/faviann/skills/issues/39) grilling and awaiting the maintainer's acceptance. Nothing in `RISK-SHAPES.md`, `SKILL.md`, the docs page, or the eval has been changed to match it.

`to-tickets` splits a slice that introduces more than one independently failure-prone unit. `RISK-SHAPES.md` describes that unit two ways that do not line up. Its deciding sentence counts a **state, lifecycle, or authorization** model. Its taxonomy names five shapes — concurrency protocols, new persistence lifecycles, migration and convergence, backward compatibility, and fail-closed resource governance — and **none of them covers authorization**. Six of six blind evaluations found the mismatch, one summarising it as "authorization is a counted model kind but has no shape to be inspected under."

The gap is not confined to authorization, and it is a gap in **shape** coverage rather than in the kinds the deciding sentence names. Eval case 9 makes that concrete: two orthogonal determinations — a document's sensitivity and its retention class — both of which the deciding sentence already covers, since both govern state, and neither of which instantiates any named shape. A shape-gated rule returns one unit where the counting sentence plainly gives two. Authorization is the same phenomenon read from the other side: a kind the deciding sentence names, with no shape to inspect it under.

That failure runs in the dangerous direction. `9f3515c` created the risk rule because "slices that cleared both [capacity budgets] still landed several independently failure-prone production contracts at once." Over-splitting wastes effort; under-splitting ships exactly the defect the rule exists to catch. So a rule whose blind spot is systematic under-counting is worse than one that occasionally over-counts.

## Considered options

**Extend the taxonomy while keeping it as the counting gate.** Give authorization its own shape, so the shape list covers every kind the counting sentence names. Rejected: it repairs the known omission and leaves in place the mechanism that produced it. The shapes would still gate the count, so anything instantiating none of the five still under-counts — case 9 included, even though its determinations are state determinations the deciding sentence already covers. It also commits the reference to enumerating shapes exhaustively, which nothing guarantees is possible.

This rejection is narrow, and worth stating narrowly: the taxonomy must not be the **gate**. Nothing here rules out authorization becoming a useful diagnostic shape later. What is decided is that it does not need one in order to be counted.

**Demote the taxonomy.** Make the shapes diagnostic — *where to look* rather than *what you count against* — and let counting key on the identity of the unit itself. Chosen.

## Decision

- The **risk shape** is a diagnostic pattern that helps locate the units the rule counts. It is not exhaustive, and it neither admits nor excludes a unit from the count.
- The counted unit is the **correctness contract**: a coherent set of outcomes and invariants that must remain correct as one unit.
- A **responsibility** is what a correctness contract decides or governs — state, lifecycle, and authorization are examples. Responsibilities are not exhaustive either, and they do not admit or exclude a contract from the count.
- One correctness contract may hold several responsibilities, and several contracts may share a responsibility. **Authorization therefore needs no shape of its own to be countable.**

## Consequences

- A gap in the taxonomy stops being a silent under-split. This is the whole point, and it is what makes the decision worth recording rather than obvious.
- Demoting the taxonomy removes risk-shape coverage as the source of eval case 4's ambiguity. It does **not** determine whether sensitivity classification and export refusal form one correctness contract or two. **Case 4 remains unkeyed until [#37](https://github.com/faviann/skills/issues/37) supplies the positive discriminator.** An earlier draft of this ADR claimed the settled semantics key it `1 / no`, on the grounds that refusal is the direct application of the sensitivity determination. That reasoning is entailment — exportability follows from sensitivity plus a threshold — and entailment is the excluded candidate B. Case 7 is the proof it cannot be the test: its serialization follows from the redaction rule and is still a second contract. The semantics permit case 4 to be one contract; they do not establish it.
- Because keying case 4 is downstream of #37's discriminator, it cannot be the work that unblocks #37. What #39 owed #37 is the direction recorded above, and that is delivered. The remaining #39 work — keying case 4, and rewording the reference — depends on #37 rather than preceding it. The native edge `#37 blocked_by #39` therefore points the wrong way once this ADR is accepted, and should be removed rather than left to deadlock both issues.
- Any discriminator gated on named shapes is excluded. It fails case 9 by construction.
- The prose does not yet use this vocabulary. `SKILL.md`, `RISK-SHAPES.md`, and the eval all still say *independent model*, and `CONTEXT.md` records the pending rename under **Flagged ambiguities** rather than retiring the live name. The rename lands with [#37](https://github.com/faviann/skills/issues/37)'s positive test, since that prose has to be rewritten anyway. `SKILL.md`'s paragraph is deliberate fork-authored wording hoisted by `5dd5609` and `99e164d` — `git log -S` it and patch the minimum.
- The eval's **Isolated prompt** keeps its current wording until a candidate discriminator is ready. Renaming the vocabulary an evaluator reads would change the measured input and invalidate the baseline the change is judged against.
- Accepting this does not settle [#37](https://github.com/faviann/skills/issues/37). It rules out one family of discriminator and licenses another; the positive test that identifies one correctness contract is still undecided.
