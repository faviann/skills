# `work-on` review-churn investigation plan

Date: 2026-08-13

Status: revised after one independent review and one bounded resolution verification

This plan follows the evidence and diagnosis preserved beside this file. It is
staged deliberately: establish an attributable control, close the TDD/refactor
hole, change one review-topology variable at a time, and retain one fresh blind
cumulative confirmation. A cheaper workflow is not successful if it is weaker.

Issue [#64](https://github.com/faviann/skills/issues/64) owns the review-topology
investigation. Issue [#9](https://github.com/faviann/skills/issues/9) owns the
telemetry mechanisms consumed by this plan and records the assigned A1/C1
frontiers in its
[ownership comment](https://github.com/faviann/skills/issues/9#issuecomment-5288561372).
Issue [#62](https://github.com/faviann/skills/issues/62) owns bounded
same-mechanism sibling discovery; delta review must preserve its search radius.

## Independent-review adjudication

The local review produced five findings. All were accepted, with one typo
clarification: its reference to `#6` is interpreted as `#62`.

1. An instrumented control window is required before review semantics change.
2. A delta may bound seed discovery, but not the mechanism-neighborhood sweep
   after a defect reproduces.
3. Final cumulative confirmation needs an explicit loop-back rule, and fixes it
   triggers consume the same convergence budget.
4. Smell-severity changes and a behavior-preserving coherence pass must land as
   one paired change; otherwise the workflow temporarily contains no refactor
   phase at all.
5. Telemetry must be split into a small mechanical foundation and later
   finding-identity support, with #9 as owner.

## Resolution-verification adjudication

The bounded verification found one partially resolved item and one
revision-introduced blocker. Both are accepted and resolved here.

- **Telemetry ownership:** the split and sink design were already resolved, but
  ownership was recorded only from #64. The #9 ownership comment now records A1
  and C1 from the owning issue's side.
- **Budget predicate:** final-confirmation invalidation and convergence-budget
  consumption now use the same transition predicate. If a change makes the
  confirmation's exact base, HEAD, trusted snapshot, or covered artifacts differ,
  it both invalidates confirmation and consumes one remediation batch. This
  includes standards-only source, test, documentation, naming, comment, or
  formatting corrections when they change the reviewed candidate. No
  invalidating change can occur outside the budget.

## Phase A: establish an attributable control

### A1. Mechanical run telemetry — owned by #9

Land the smallest mechanically derivable foundation:

- every subagent launch, role, phase, and round;
- review kind and scope (`readiness`, `full`, or `delta`), compared SHAs, and
  input byte count;
- validation command, stable execution ID, duration, and outcome;
- phase-specific elapsed time where observable; and
- final workflow outcome.

Do not make stable finding identity a prerequisite for this step. Do not put
per-launch event rows into the human PR-body summary table. The implementation
frontier under #9 must name a run-scoped machine-readable sink and mechanically
aggregate bounded summary fields into closeout telemetry. Do not persist full
prompts, repository contents, raw untrusted diagnostics, or secrets merely for
analytics.

Record token counts where the runtime exposes them. Their absence does not
block the roadmap.

### A2. Hard pre-implementation closability gate

Before implementation delegation, require:

- every acceptance criterion has a direct validation seam available in the
  current run;
- every blocking prerequisite is complete;
- no criterion is knowingly limited to `inferred` or `unverified` evidence;
- the selected repository workflow and required commands are executable; and
- the trusted contract is internally consistent.

Failure returns to triage, prerequisite work, issue splitting, or human contract
amendment before code is written.

A subjective “one reviewable PR” estimate is not part of this hard mechanical
gate. Review-budget fit remains a triage/sizing tripwire until attributable
evidence supports a stronger rule.

### A3. Instrumented control window

After A1 and A2 are active, keep implementation, readiness, review,
remediation, and closeout semantics otherwise unchanged for a predeclared
number of completed runs.

The telemetry implementation ticket states the run-count target before outcomes
are observed; elapsed time is not the stopping rule. The window includes at
least one run that reaches remediation, otherwise it cannot establish a control
for review churn.

A2 precedes this window so control and candidate populations share the same
objective closability filter. Do not land smell-severity, coherence,
delta-review, or convergence changes during the control window.

## Phase B: close the TDD/refactor hole without hiding defects

### B1. Pair blocker severity with a behavior-preserving coherence pass

These two changes land together.

#### Blocker severity

A Fowler/baseline smell is advisory unless it reproduces either:

1. a documented repository-standard violation; or
2. an acceptance-criterion defect with observable impact.

A mechanically testable cleanup preference is not automatically blocking. Hard
safety rules, contract failures, and direct evidence defects remain blocking.

#### Coherence/refactor pass

After the issue's red-green slices are complete and focused tests are green,
the same implementation delegate performs one bounded behavior-preserving pass
before the first independent cumulative gate.

Allowed work:

- remove obvious local duplication introduced across the TDD slices;
- improve misleading local names;
- simplify unnecessarily indirect local control flow; and
- restore locality or domain coherence without changing the contract.

Required invariants:

- existing focused tests are unchanged and green before and after the pass;
- no new behavior or acceptance criterion is introduced;
- no public interface, public seam, or validation seam is removed;
- no speculative abstraction or unrelated cleanup is added; and
- a cleanup requiring test changes or observable behavior changes returns to an
  explicit red-green slice instead of being called refactoring.

Unused or test-only production seam removal does not happen in this pass. It
remains subject to the existing mechanism trace, adjudication, and review
invalidation rules.

Shipping advisory smells without this pass would create a period in which TDD
defers refactoring and no later stage performs or enforces it.

### B2. Measure the paired change

Use a separately declared comparison window before changing review topology.
Do not call the pair successful merely because blocker counts fell. Compare
launches, phase cost, final-confirmation findings, regressions, and escaped
defects against Phase A's control.

## Phase C: change the review topology

### C1. Finding identity telemetry — owned by #9

Add only the finding-level support needed by later delta-review experiments:

- a primary-assigned stable fingerprint after adjudication;
- governing acceptance criterion or documented hard rule;
- normalized mechanism identity and sorted repo-relative locations;
- first-discovery round;
- `new`, `repeated`, or `superseded` status; and
- accepted, rejected, follow-up, or unresolved disposition.

Do not hash a reviewer's free-form wording and call that stable identity. The
primary already adjudicates the mechanism and criterion; derive identity from
that normalized decision.

Use the run-scoped telemetry/ledger mechanism owned by #9. Put bounded aggregate
counts, not every event, in the PR body.

### C2. Delta remediation-review topology

Use this state machine:

1. one fresh, blind cumulative Standards/Spec/closure gate after initial
   implementation and the coherence pass;
2. one primary adjudication pass batching all accepted blockers;
3. one committed remediation batch;
4. delta review of `previous-reviewed-HEAD...HEAD`, accepted directives,
   affected criteria, and immediately changed production paths;
5. repeated remediation and delta review only while unresolved blockers and
   budget remain; and
6. one fresh, blind cumulative Standards/Spec/closure confirmation before final
   validation and closeout.

#### Preserve #62's mechanism neighborhood

The delta bounds the **seed search**, not the neighborhood investigation. Once a
defect reproduces in the delta, inspect matching branches, call sites,
diagnostics, governed states, and compatible occurrences in the same public
flow as required by the shipped #62 brief, including relevant locations outside
the remediation diff.

Stop at the existing cross-criterion, cross-subsystem, external-boundary, and
speculative-defense boundaries. This is not a repository-wide audit; the radius
remains the same mechanism and public flow.

Evaluation distinguishes seed findings from reproduced siblings so a shorter
delta prompt cannot appear successful merely because it stopped looking.

#### Final-confirmation loop-back and budget predicate

A final blind cumulative confirmation is valid only for its exact base, HEAD,
trusted snapshot, and covered artifacts. Any accepted remediation that changes
one of those identity inputs invalidates the confirmation **and consumes one
convergence-budget batch**. The predicates are intentionally identical: no
change may invalidate confirmation without consuming budget, and no unchanged
candidate consumes budget merely because prose was discussed.

An invalidating batch includes any committed source, test, configuration,
documentation, naming, code-comment, formatting, or evidence/artifact change
made in response to an accepted blocker. It does not matter whether the change
alters runtime behavior; what matters is that the reviewed candidate identity
changed.

After an invalidating remediation, run the affected delta review and then
another fresh blind cumulative confirmation. No changed candidate proceeds to
final validation without a clean confirmation.

### C3. Measure topology before exposing prior dispositions

First evaluate C2 with delta reviewers receiving accepted remediation
directives and reviewed-head identity, but not a list of prior rejected
findings. This isolates topology from the independence risk of exposing prior
dispositions.

Use a separately declared comparison window and keep the mandatory final blind
cumulative confirmation.

### C4. Pilot fingerprint/disposition passing separately

Only after C1 and C2 have evidence, test giving delta reviewers stable
fingerprints and dispositions for unchanged prior findings. The purpose is to
avoid spending tokens rediscovering an unchanged rejected concern; reviewers
must not inherit a prior conclusion as truth or suppress new evidence.

Measure reraised rejections, genuinely new evidence, and final-confirmation
discoveries. Reject this optimization if it creates anchoring or missed hard
findings.

### C5. Explicit convergence guard

Allow at most **two automatic invalidating remediation batches after the initial
full cumulative gate**. Use exactly the C2 identity predicate: every batch that
changes the confirmation's base, HEAD, trusted snapshot, or covered artifacts
counts, including one triggered by final blind confirmation. A standards-only
rename, documentation correction, code-comment fix, or formatting change counts
when it changes the reviewed candidate. No invalidating transition is exempt.

If final confirmation finds a blocker and budget remains:

1. adjudicate it;
2. remediate, consuming one batch if the candidate identity changes;
3. run affected delta review; and
4. run another fresh blind cumulative confirmation.

If budget is exhausted, unresolved findings are never marked green. Choose a
durable non-success path:

- split or amend the issue;
- complete missing prerequisite work;
- create or identify a blocking tracker issue;
- render/update the candidate as `Progresses` where ordinary closeout is
  available; or
- abandon the candidate with a recorded rationale.

Record `convergence-budget-exhausted` as a distinct telemetry outcome instead of
folding it into rejected findings.

An unattended/AFK run cannot request human authorization. On budget exhaustion
it creates or identifies the blocking tracker, leaves any `Progresses` PR
unmerged, and hands back. The existing `--require-closes` guard preventing merge
is expected behavior, not another remediation round.

Treat two batches as a provisional pilot value, not a universal threshold.
Measure C5 in its own comparison window after C2.

## Phase D: simplify only after the core loop is attributable

### D1. Decide whether to fold the readiness sweep

The pre-implementation closability gate cannot replace an independent
raw-artifact reviewer because it runs before an implementation artifact exists.
The coherence pass and primary inspection reduce defects but are also not
independent.

Keep readiness until A1/C1 data shows:

- which unique hard findings it discovers;
- whether the first cumulative gate also finds them;
- whether final blind confirmation catches any class lost by removal; and
- its launch, token, and material-read cost.

Only then pilot removal. Its independent responsibility would move to the first
fresh cumulative gate; coherence and primary checks are supporting defenses,
not substitutes for independence.

### D2. Improve remediation implementer continuity

Either retain the same implementation delegate for remediation or provide a
durable handoff containing:

- accepted directive and governing criterion;
- prior design summary;
- touched production paths and invariants;
- established evidence;
- rejected alternatives and why; and
- exact requested delta.

Do not forward raw reviewer prose or let the delegate reinterpret the contract.

### D3. Remove duplicate architecture/spec review from closeout

After final blind cumulative review produces an immutable reviewed-candidate
identity, make closeout focus on:

- exact acceptance-criterion evidence;
- actual artifact, mode, host, and public seam;
- final regression and diff checks;
- issue/follow-up reconciliation; and
- PR-body rendering and read-back validation.

Do not launch another architecture/spec hunt over an unchanged candidate merely
because closeout begins. Any base, HEAD, snapshot, or covered-artifact change
invalidates the identity, consumes budget under C5, and returns to final
confirmation.

### D4. Introduce risk-tiered orchestration last

Use attributable results to decide whether distinct paths are justified for
tiny documentation/configuration changes, ordinary isolated code, broad
state/compatibility work, security/authorization work, and live operations. Do
not prescribe tiers from the selected anecdotal sample.

## Authoritative dependency order

`A1 mechanical telemetry (#9) → A2 objective closability → A3 instrumented control → B1 severity + behavior-preserving coherence (paired) → B2 comparison → C1 finding identity (#9) → C2 delta topology with #62 preserved and unified confirmation/budget predicate → C3 comparison → C4 disposition-passing pilot → C5 convergence guard → D1 readiness decision → D2 implementer continuity → D3 closeout reuse → D4 risk tiers`

## Evaluation metrics

### Resource metrics

- total and per-role agent launches;
- input/output tokens when exposed;
- cumulative diff and snapshot bytes reread;
- wall-clock time by phase;
- validation executions and duration; and
- implementation, review, and remediation rounds.

### Review-behavior metrics

- blockers found in the first comprehensive gate;
- genuinely new findings after remediation;
- repeated unchanged findings;
- rejected findings reraised without new evidence;
- seed versus same-mechanism sibling findings;
- findings discovered only at final cumulative confirmation;
- superseded or reverted remediations; and
- criteria or subsystems entered after the original contract.

### Quality and outcome metrics

- final hard findings;
- escaped post-merge or live defects;
- regression, rollback, and follow-up rate;
- `Closes` versus `Progresses` outcome;
- `convergence-budget-exhausted` outcomes;
- human interventions; and
- direct evidence coverage for every criterion.

A stage succeeds only if it reduces attributable launches, tokens/material
reread, validation cost, or serial remediation without increasing final hard
findings, regressions, or escaped defects. Reclassification alone is not
evidence of improvement.

## Non-goals and guardrails

- Do not remove independent review.
- Do not weaken documented hard rules, safety boundaries, or direct acceptance
  evidence.
- Do not remove final fresh cumulative confirmation.
- Do not optimize PR-body length while leaving agent work unchanged.
- Do not reclassify blockers merely to improve telemetry.
- Do not derive a universal ticket-size threshold from the selected sample.
- Do not undo #62 or narrow its neighborhood radius when moving to delta review.
- Do not allow a confirmation-invalidating change outside the convergence
  budget.
- Do not merge this investigation into a general `to-tickets` rewrite; ticket
  sizing is a co-factor while #64 is focused on `work-on` execution and
  convergence.

## Remaining open questions

- What predeclared control and comparison run count is proportionate?
- Can prior finding dispositions be exposed without anchoring delta reviewers?
- Should one implementer retain ownership through remediation while reviewers
  remain fresh?
- How can token telemetry be captured across Codex, Claude Code, and other
  harnesses?
- What normalized mechanism vocabulary is stable enough for finding identity?
- How should risk tiers account for operational work when the tracked diff is
  small?
