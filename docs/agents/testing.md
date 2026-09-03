# Testing and deterministic checks

## Mechanical authority

This guidance applies to tests and deterministic mechanisms whose output is relied upon to establish, classify, or enforce a mechanical determination. Ordinary deterministic implementation logic is outside scope unless it is treated as authority for such a determination.

Predicate authority exists when the accepted contract or system semantics make a mechanical definition the source of the determination. It may be explicitly designated or already structurally unambiguous. The existence, consistency, or reproducibility of a checker does not itself confer authority.

Information sufficiency requires the bounded observations to expose everything the authoritative predicate needs. Apply the counterexample test: if cases indistinguishable on those observations can legitimately require different outcomes, the proposed surface is insufficient.

Evidence may move to a legitimately available surface that exposes the observations required by the authoritative rule. Failure at the current surface does not itself justify new capture, indexing, synchronization, correspondence, or other evidence machinery; that machinery requires an independent requirement.

A mechanical determination carries only the meaning and consequence granted by its authoritative mechanical definition and governing contract. If a consequence is not itself mechanically determined, the governing review or adjudication process decides it.

A deterministic check protecting an agent-facing contract is also bounded by what its assertions may enforce. The last step before such a check is done is the **shadow contract** pass from [`writing-for-agents`](../../skills/productivity/writing-for-agents/SKILL.md)'s pruning section, applied to every assertion the check makes.

Before adding or keeping such an assertion, establish that it protects an authoritative mechanical predicate or an externally observable effect. Being able to grep or parse semantic prose does not make that prose mechanically authoritative; leave such properties to review unless the contract explicitly makes their representation authoritative.

Apply the **compliant-variation test**: would the assertion still pass after a contract-preserving change to wording, formatting, naming, or source layout? If not, loosen or remove it unless that representation is explicitly contractual.

Vocabulary denylists are not substitutes for semantic or architectural rules. If a property cannot be checked without inventing machinery or a shadow specification, leave it to review.

Keep one authoritative mechanical definition. Executable checks consume that authority; prose does not independently reimplement its predicate. When tests of the mechanism are warranted, exercise its supported interface and externally observable effects without creating a competing implementation of the predicate. Independent expected values and test oracles remain valid.

An authoritative schema can establish `required field missing`; observing one implementation does not itself establish `speculative abstraction`.

Adopt this guidance prospectively. When existing invalid deterministic machinery becomes directly relevant to current work, prefer deleting, narrowing, or replacing it without auditing adjacent machinery.

## Shell test suite

Run every shell test suite from the repository root with:

```bash
npm test
```

The npm command delegates to `scripts/run-shell-tests.sh`, so the runner can also be invoked directly. It finds every tracked file named `test-*.sh`, runs all of them, reports each result, and exits nonzero when any suite fails. Adding a tracked suite with that name automatically adds it to the command and CI.

### Suite membership

There is one shell-test set. It includes the repository-level reconciliation suite, `select-issue`'s GitHub digest suite, and every `work-on` suite. Groups would make callers choose a subset and restore the list-maintenance problem this command removes; add them only if measured runtime makes the full set impractical.

### Pull-request policy

The `Shell tests` workflow runs the full set on every pull request, without path filters. Most changes are prose, but skill behavior often spans instructions and scripts, and the current few-minute runtime is cheap enough to keep the trigger simple and complete.

A failing suite fails the `Shell tests` job: it is not advisory and must be green before merge. Repository merge rules should require that check; the workflow deliberately has no `continue-on-error` escape hatch.
