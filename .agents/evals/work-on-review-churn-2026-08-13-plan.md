# `work-on` review-churn investigation plan

Date: 2026-08-13

This plan follows the evidence and diagnosis preserved beside this file. It is
staged deliberately: improve observability first, then change one workflow
variable at a time. A cheaper workflow is not successful if it is weaker.

## Stage 0: instrument the current workflow

Record enough structured evidence to attribute cost without turning every run
into a new analytics subsystem.

Candidate fields:

- lifecycle, parent-round, and agent-launch identifiers;
- model configuration and agent role;
- review kind and scope (`readiness`, `standards`, `spec`, `closure`;
  `cumulative`, `delta`, `final-cumulative`);
- input byte counts by artifact type: trusted snapshot, diff, standards,
  repository docs, and prior finding fingerprints;
- input/output token counts when exposed by the runtime;
- validation command identity, duration, exit status, and focused/full class;
- finding fingerprint, mechanism, governing criterion, severity, first
  discovery round, and `new`/`repeat` status;
- adjudication and resolution (`accepted`, `rejected`, `follow-up`, `removed`);
- elapsed time split into implementation, review, validation, and live
  operations; and
- final outcome.

Use hashes and counts. Do not persist full prompts, secrets, raw untrusted
diagnostics, or repository content merely for analytics.

## Stage 1: pre-implementation closability and review-budget gate

Before implementation delegation, require the primary to establish:

- every acceptance criterion has a direct observable seam;
- every prerequisite required to exercise those seams is complete and
  available;
- no criterion is knowingly limited to `inferred` or `unverified` evidence;
- the ticket fits one implementation context and one reviewable PR budget;
- contract density and state space do not require a staged split; and
- repository-local workflow requirements can run in the current environment.

Failure returns the issue to triage/splitting or creates a blocking tracker
issue before code is written. It is not merely flagged for closure.

## Stage 2: compare review topologies

Run a blinded comparison between the current topology and this candidate.

### Current topology

- Full cumulative Standards, Spec, and closure review after every remediation.

### Candidate topology

1. One pre-implementation closability/readiness pass.
2. Implementation and focused checks.
3. One comprehensive cumulative Standards/Spec/closure review.
4. One batched remediation.
5. Delta-focused review of remediation commits, expanding to affected criteria
   or neighboring mechanisms only when reproduced evidence requires it.
6. One fresh blind cumulative confirmation before full validation and closeout.

Delta reviewers may receive stable finding fingerprints and adjudicated
dispositions solely to avoid rediscovering unchanged rejected findings. They
must not inherit conclusions as truth. The final confirmation remains blind and
cumulative.

## Stage 3: explicit convergence guard

Choose a small explicit remediation budget during triage. Exceeding it forces
one of:

- human inspection;
- issue split or contract amendment;
- a prerequisite or follow-up issue; or
- a recorded decision to continue for named reasons.

It must not silently continue indefinitely. The exact budget must be tested,
not selected from the current sample as a universal threshold.

## Stage 4: reconcile TDD and review responsibilities

Test one or both of:

- permit a bounded coherence/refactor pass before the first candidate review;
  or
- make baseline smell findings non-blocking unless they reproduce a documented
  standard breach or acceptance-criterion impact.

The goal is not to suppress maintainability feedback. It is to avoid designing
TDD to defer refactoring and then treating the predictable deferred work as a
surprise blocker.

## Stage 5: consider risk-tiered review only after telemetry exists

A one-line configuration correction, documentation-only change, live migration,
and new authentication lifecycle should not necessarily pay the same
orchestration cost. Risk tiers may be useful, but this plan does not prescribe
them before measured evidence exists.

## Evaluation metrics

### Resource metrics

- total and per-role agent launches;
- input/output tokens;
- cumulative diff and snapshot bytes reread;
- wall-clock time by phase;
- validation executions and duration; and
- implementation, review, and remediation rounds.

### Review-behavior metrics

- blockers found in the first comprehensive gate;
- genuinely new findings after remediation;
- repeated unchanged findings;
- rejected findings reraised without new evidence;
- findings discovered only at final cumulative confirmation;
- superseded or reverted remediations; and
- criteria or subsystems entered after the original contract.

### Quality and outcome metrics

- final hard findings;
- escaped post-merge or live defects;
- regression, rollback, and follow-up rate;
- `Closes` versus `Progresses` outcome;
- human interventions; and
- direct evidence coverage for every criterion.

A candidate succeeds only if it reduces resource use and serial churn without
increasing final hard findings or escaped defects. Lower round counts alone are
not success.

## Non-goals and guardrails

- Do not remove independent review.
- Do not weaken documented hard rules, safety boundaries, or direct acceptance
  evidence.
- Do not remove the final fresh cumulative confirmation.
- Do not optimize PR-body length while leaving agent work unchanged.
- Do not reclassify blockers merely to improve telemetry.
- Do not derive a universal ticket-size threshold from the selected sample.
- Do not undo #62 without measuring its interaction with review topology.
- Do not merge this investigation into a general `to-tickets` rewrite; ticket
  sizing is a co-factor while #64 is focused on `work-on` execution and
  convergence.

## Open questions

- Can reviewers receive prior finding fingerprints without compromising
  independent judgment?
- Which remediation changes truly invalidate the entire cumulative review?
- Should one implementer retain ownership through remediation while reviewers
  remain fresh?
- How can token telemetry be captured across Codex, Claude Code, and other
  harnesses?
- What stable fingerprint identifies the same finding across differently worded
  reports?
- Should closure evidence accounting be separated from defect discovery?
- How should risk tiers account for operational work when the tracked diff is
  small?
- What signal should force issue splitting before implementation?

## Recommended first frontier

The first implementation frontier should improve observability without changing
review semantics:

1. add attributable agent-launch, review-scope, validation, and
   finding-fingerprint telemetry;
2. add a pre-implementation closability report that blocks known untestable
   criteria; and
3. collect comparable current-workflow baselines before changing review
   topology.

Only after that evidence exists should #64 choose among delta review,
risk-tiered gates, implementer continuity, or a convergence budget. This
prevents a lower-cost but weaker workflow from being declared successful by
construction.
