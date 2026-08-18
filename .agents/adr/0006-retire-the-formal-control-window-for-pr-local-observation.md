# Retire the formal control window for PR-local observation

**Status: accepted, 2026-08-18.** [#64](https://github.com/faviann/skills/issues/64)
asked whether `/work-on` produces excessive review churn. Answering it grew a formal
experiment protocol — pre-registered A3/B2 control windows, controller-domain binding,
append-only published results — whose implementation in
[#73](https://github.com/faviann/skills/issues/73) reached `+3380/-10` across five
commits in [PR #78](https://github.com/faviann/skills/pull/78) without landing. This
ADR records the decision to abandon that product and replace it with PR-local
observation, and the two existing validator behaviours deleted to make room for it.

**Nothing here was measured.** No control window was ever activated, so there is no
experimental result to report. This is a product-direction judgment about what the
maintainer will actually use, argued from the cost of the abandoned build and from
the claims the available data can honestly support.

## The problem

#64's roadmap required an instrumented A3 control before the first semantic change
(B1) and a separately declared B2 comparison after it. Making those windows rigorous
required, in sequence: a fixed repository population and cohort; eligibility ordering
and a stopping rule; baseline/candidate policy manifests; a controller domain so a
run launched elsewhere could not silently join the sample; prepared/active/closing/
closed lifecycle phases; publication of the registration *before* implementation, so
the protocol could not be retrofitted to its result; compare-and-append with exact
read-back for exactly-once publication; ambiguous-success recovery; and a results
branch carrying the append-only history.

Each of those followed from the one before. None was gold-plating in isolation. The
compound result was a research platform standing in front of a personal workflow
question, and PR #78 was that platform being built **correctly** — its review history
covers activation recovery, cross-domain capacity, registration/closing arbitration,
and post-terminal evidence loss, all real defects in the thing it was asked to be.

The failure was upstream of the implementation. A3 attempt 1 had already been
invalidated under its own frozen protocol
([PR #69](https://github.com/faviann/skills/pull/69)), and attempt 2 was never
pre-registered or activated. Two attempts produced no observation.

## Considered options

### Finish PR #78

Rejected. It was close to complete and its remaining blocker was tractable. But
finishing it buys a control-window platform, and the maintainer had by then concluded
the platform is not what the question needs — a directional read on whether `/work-on`
is getting cheaper does not require a certified population estimate. Sunk cost is the
only argument for finishing, and the maintenance surface would persist indefinitely.

### Rewrite #73 into the replacement, or repurpose PR #78's branch

Rejected. Both leave a contract and a review history dominated by the abandoned
product. Repurposing #78 means deleting most of its diff while its comment thread
still adjudicates controller ownership — a reviewer arriving later reads the thread as
live requirements. Cheaper to close it intact as historical exploration and start a
focused issue ([#79](https://github.com/faviann/skills/issues/79)).

### Abandon the formal product; observe PR-locally

Accepted. Every `/work-on` closeout already writes a bounded telemetry table into a PR
body. A repository-local `work-on` label makes those PRs findable. That is enough to
support a manual, reversible judgment, and it requires no population, no lifecycle, and
no publication protocol.

## Decision

- **A3 and B2 are retired as active protocol names.** They become two manual
  checkpoints on #64: a pre-B1 directional observation checkpoint, and a post-B1
  manual comparison checkpoint. Each ends in an explicit maintainer decision. Neither
  has a fixed sample, a stopping rule, or a mechanical completion threshold.
- **The claim is bounded to what the data supports.** The observable population is a
  directional convenience sample of runs that reached a readable PR closeout. It says
  nothing about crashed, abandoned, or no-PR runs, about the probability of reaching
  closeout, about exact token cost, about causality, or about escaped defects.
- **Observability precedes semantic change, as before.** The reset removes the
  experimental machinery, not the requirement for an explicit decision before changing
  workflow semantics.
- **Telemetry is mechanically derived where the sink already records it.** Start-to-seal
  elapsed, three round counts, validation executions, reviewed artifact bytes, and
  recorded validation duration come from recorded events. Only model configuration,
  blocking findings resolved, and findings rejected at adjudication remain
  primary-reported, and the table says so.
- **Two existing validator behaviours are deleted on purpose**, recorded here because a
  reviewer diffing against `main` will see the validator get smaller and should not
  read that as a weakening:
  - *Legacy telemetry-format acceptance.* The validator accepts only the current
    format. A `/work-on` run updating a legacy-format PR refuses previous-body
    validation rather than migrating it. Accepted because those PRs are complete; the
    alternative is a dual-format branch in every path, which is the same
    over-specification this ADR exists to undo.
  - *Cumulative per-PR count monotonicity.* The table now describes one run rather than
    a PR's cumulative history, so a later run may legitimately report smaller counts.
    Treating latest-run values as lower bounds contradicts the new semantics. The
    provenance-prefix checks are independent and remain in force.
- **#71 and #72 are unchanged.** Their integrity, identity, outcome, seal, lifecycle,
  and governed-obligation failures still fail closed. Only the new label operation and
  a genuinely unavailable new aggregate are best-effort. Leaving #72's observer seam in
  place is not architectural endorsement; removing it is a separate decision.
- **The historical record is not laundered.** PR #69 remains the record that A3 attempt
  1 was invalid under its then-binding protocol; it is not reinterpreted as a baseline.
  #73 is superseded, not rewritten. PR #78 closes unmerged with its branch intact.
  [PR #77](https://github.com/faviann/skills/pull/77) is untouched.

## Consequences

- **Reviewers of #79 may not require the retired machinery back.** The binding
  amendment on #64 carries the enumeration; anything absent from that list is, by
  construction, still fair game. The supersession notice on #73 repeats it, because
  #73's original body otherwise reads as live acceptance criteria.
- **Survivorship bias is now a permanent property of the evidence, not a defect to
  fix.** Runs that crash, abort, or produce no PR are absent and have no denominator.
  The surviving sample can make the workflow look cheaper than all invocations are.
- **Omitted instrumentation stays undetectable.** The round counts are counts of
  observed events. A delegation that was never recorded is indistinguishable from work
  that never happened — a limit #71 already documents and this decision inherits.
- **Two aggregate names understate rather than overstate.** `Reviewed artifact bytes`
  is the diff/worktree artifact measured once per delegation, not prompt or model
  input; `Recorded validation duration` covers instrumented wrappers only. Both were
  renamed away from broader labels that the recorder does not earn.
- **Zero is a valid observed value** for any mechanical count, rendered plainly. This
  is a presentation decision and grants no exemption from any current independent-review
  requirement.
- **Comparison stays manual and unstored.** Finding, filtering, and comparing
  observations is label-search plus reading. Central storage or analysis is added only
  if real use demonstrates the need — not in anticipation of it.
- **Discovery is best-effort by design.** Permission failures, races, or a manually
  removed label produce valid observations that no label search returns. The label is a
  discovery aid, not evidence authority.
- This decision is reversible. If manual comparison proves too noisy to support a
  decision, the honest response is a better-specified question — not the reinstatement
  of a control-window platform that twice failed to produce an observation.
