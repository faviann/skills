# `work-on` review-churn diagnosis

Date: 2026-08-13

This document records hypotheses derived from the evidence in
[`work-on-review-churn-2026-08-13-evidence.md`](work-on-review-churn-2026-08-13-evidence.md).
They are ranked investigation targets, not established causal weights.

## Current diagnosis

The strongest current hypothesis is:

> The main inefficiency is not adversarial review itself. It is stateless,
> cumulative, multi-agent, unlimited, post-hoc adversarial review.

Confidence is high that the topology repeats work. Confidence is moderate about
which mechanism dominates because current telemetry does not expose launches,
tokens, repeated findings, or cumulative material reread.

## Suspicious elements

### 1. Blind cumulative rereview after every remediation

The workflow pins one base SHA and reviews `<base>...HEAD`. Reviewers receive raw
artifacts and are deliberately denied prior conclusions and the adjudication
ledger. The ledger may stop the primary from acting twice on a rejected concern,
but it does not stop fresh reviewers from spending tokens rediscovering it.
Any changed `HEAD` invalidates reuse of the candidate gate.

A candidate alternative is one comprehensive cumulative review, delta-focused
remediation review, and one final blind cumulative confirmation. That is an
experiment, not an approved replacement.

### 2. Nominal review telemetry hides agent fan-out

One recorded review round can contain separate Standards, Spec, and closure
agents. The telemetry therefore makes the orchestration appear substantially
smaller than the documented workflow.

### 3. The convergence loop has no budget

The workflow batches blockers, remediates, and reruns until clean. It has no
remediation limit, token or elapsed-time budget, diminishing-return threshold,
or mandatory human/retriage checkpoint. Eight rounds are valid ordinary output
instead of a signal that the ticket or workflow needs reconsideration.

### 4. Closability can fail only at closure

The workflow calls unclear validation seams an abort condition, yet orientation
can finish with a missing seam merely flagged for closure. Closure later
requires every criterion to be directly `tested` for `Closes`.

`overmind#202` completed eight implementation rounds before a known prerequisite
left one criterion only `inferred`. That should have blocked implementation.

### 5. Reviewer instructions expand findings

After reproducing a defect, reviewers trace its immediate mechanism
neighborhood and group reproduced siblings. Closure additionally maps every
mechanism a reviewer could name to a criterion and treats uncited mechanisms as
removal candidates; removals re-enter review.

This bounded search was added by #62 to reduce serial sibling discovery. It may
reduce rounds in one dimension while increasing each gate's volume in another.
The interaction must be measured. Current briefs still lack a materiality
threshold or finding budget.

### 6. TDD and review can manufacture cleanup

TDD asks for one minimal vertical slice at a time, says not to anticipate future
tests, and defers refactoring to review. Mandatory Standards review then applies
a broad smell baseline including duplication, primitive obsession, shotgun
surgery, and speculative generality.

The predictable loop is: accumulate minimal local solutions, defer coherence,
flag the deferred smells, remediate, then rerun the complete cumulative gate.
Several sampled PRs spent adjudication effort on helper extraction or
duplication suggestions that were ultimately rejected.

### 7. Tight reviewer output limits may serialize discovery

Each `code-review` axis is asked to report every relevant issue in under 400
words. On a large PR, both requirements cannot reliably be satisfied. A
plausible pattern is that one pass reports the highest-salience findings that
fit; after those are fixed, a fresh reviewer exposes the next layer.

`overmind#175` reached six numbered gates, and an implemented response was later
superseded after a stronger resource constraint was found. This does not prove
the word limit caused the sequence, but it is a credible contributor.

### 8. Mechanical reproducibility can collapse severity

A checkpoint directive with a mechanical seam is treated as blocking.
Mechanically testable is not equivalent to materially blocking. Standards may
raise subjective smell judgments, but the workflow does not say clearly enough
that a smell-only finding cannot block without a documented hard-rule breach or
acceptance-criterion impact.

### 9. Fresh implementers receive lossy handoffs

Every remediation uses a fresh delegate with a scoped contract and a four-field
return format: `Changed`, `Evidence`, `Unverified`, and `Risks`. Previous
implementation reasoning and rejected alternatives are not durable context.
Fresh reviewers are valuable; it is less clear that every remediation
implementer should rediscover the architecture from a narrow handoff.

### 10. `ready-for-agent` does not guarantee one reviewable PR

Some issues are clear but contract-dense. A handful of acceptance bullets can
contain many independently reviewable states, boundaries, failure modes, and
operational proofs. Issue clarity and one-context implementation capacity do
not establish one-PR reviewability.

### 11. Closure duplicates other review axes

After readiness, TDD, focused checks, Standards, and Spec review, closure
independently rereads the contract and cumulative diff, hunts for wrong
artifacts and fake seams, reruns high-risk checks, maps mechanisms to criteria,
and builds the evidence table. This assurance is useful but overlaps
substantially with defect discovery in the other axes.

### 12. Telemetry does not measure the optimized resource

Current telemetry omits top-level and nested agent launches, per-agent tokens,
prompt/snapshot/diff sizes, cumulative bytes reread, review scope, finding
fingerprints, first discovery round, repeated versus new findings, cost of
rejected findings, validation duration/outcome, and phase-specific elapsed time.
The workflow can show that churn happened but cannot attribute it.

## Causal model

1. A contract-dense ticket becomes `ready-for-agent`.
2. A fresh implementer works through minimal TDD slices.
3. Closability, prerequisite completeness, and review-budget fit are not fully
   established before coding.
4. Three fresh reviewers inspect the cumulative change without prior
   conclusions.
5. Their bounded reports expose one layer of problems.
6. A fresh implementer repairs that layer.
7. The cumulative change is reviewed blindly again.
8. The loop continues without a budget until clean or until closure discovers
   that the issue was never closable.

## What this diagnosis does not claim

- It does not claim adversarial review should be removed.
- It does not claim every remediation was waste.
- It does not infer token totals from elapsed time.
- It does not treat the selected sample as a population estimate.
- It does not assume #62 made the workflow worse; its interaction must be measured.
- It does not establish a universal numeric ticket-size or remediation limit.

A lower-cost workflow is not better if it increases final hard findings,
escaped defects, operational regressions, or unverifiable acceptance criteria.
