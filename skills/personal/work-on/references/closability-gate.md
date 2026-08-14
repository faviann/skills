# Pre-implementation closability gate

Decide whether the issue can reach `Closes` **before** implementation is
delegated — not after code, review, and remediation have already been spent on
a criterion that was never observable.

Run this once, after the trusted snapshot and the selected workflow have been
read, and before workflow-provenance capture, implementation delegation,
production or test edits, implementation commits, and any pull request.

The gate decides only whether the issue is closable in this run. It changes no
readiness, Standards, Spec, closure, remediation, validation, or closeout
semantics, and adds no artifact, ledger, or telemetry field of its own. A pass
records nothing. An abort resolves the run's existing outcome as `aborted`, as
the abort steps below require.

## The reasoning the primary produces

For every acceptance criterion, name four things:

- the production path the implementation will affect;
- the actual artifact, mode, host, or public boundary the behavior will be
  observed through;
- the concrete validation action that can run after implementation; and
- the observation that would fail if the criterion were not satisfied.

The production behavior does not have to exist yet. A seam is **available**
when it already exists, or when creating it is explicitly inside this issue's
authorized implementation scope — and, in either case, only when its validation
can be executed during this run.

A seam is **not** available when validation depends on:

- unimplemented work owned by another issue;
- an incomplete blocking prerequisite;
- unavailable hardware, account, device, service, credential, host, or
  environment;
- a future operator action not available in this run;
- an out-of-scope mechanism;
- a gate-only artifact whose sole consumer is the gate; or
- indirect inference where the closure contract requires direct evidence.

## Conditions

The gate passes only when all five hold.

1. **Every acceptance criterion has a direct validation seam**, available under
   the rules above.
2. **Every blocking prerequisite is complete.** Inspect native GitHub blocking
   relationships, explicit "blocked by" or prerequisite references in the
   trusted snapshot, parent/spec requirements needed to exercise the seams, and
   repository or environment prerequisites named by the selected workflow. A
   prerequisite is not complete because similar behavior exists elsewhere. A
   criterion depending on an open prerequisite blocks implementation.
3. **No criterion is knowingly limited to `inferred` or `unverified`.** Abort
   when the primary already knows a criterion can produce only indirect
   evidence, source-level inference for a runtime claim, shared-predicate
   reasoning without exercising the required transition, a mocked internal path
   where the contract requires a public boundary, a human assumption with no
   available verifier, or no evidence at all. Proceed when the planned
   validation would directly produce `tested` evidence after implementation.
4. **The required workflow and validation commands are executable** in this
   environment, including ordinary setup that is explicitly part of the run.
   Abort when they need a dependency or authority that cannot be established
   within this scope. A transient command failure during later validation is
   not a preflight failure: this asks whether the path is available and
   executable, not whether the unimplemented candidate already passes.
5. **The trusted contract is internally consistent.** Abort on a criterion
   requiring behavior the issue places out of scope, two trusted requirements
   demanding incompatible outcomes, a criterion requiring a mechanism the issue
   prohibits, incompatible issue-body and trusted-maintainer amendments, a
   closing condition that cannot coexist with a named prerequisite, or
   ambiguity material enough that the implementation delegate would have to
   choose the contract. Adjudicate ordinary wording against the trusted
   sources; never invent a requirement or choose between genuinely
   incompatible trusted ones.

## Manual and human seams

A manual seam counts only when the trusted contract explicitly allows that form
of verification, the required human, device, or environment is actually
available during this run, the exact observation is defined in advance, and the
result can be recorded as direct evidence.

An AFK run may not assume a human will become available later. A future request
for human confirmation at closeout is not a pre-implementation seam.

## Size is not a condition

Do not reject an issue here on file count, diff size, acceptance-criterion
count, state count, token estimate, complexity score, or any
repository-independent size threshold. Review-budget fit remains a triage and
calibration concern. A large or contract-dense issue whose every criterion has
direct, available validation passes.

## Pass

Keep the compact criterion-to-seam reasoning in the primary's working context,
capture workflow provenance, and continue the selected workflow unchanged. A
pass records nothing; the run's outcome remains the closure gate's to resolve.

## Abort

Launch no implementation delegate, make no implementation edit, and create no
implementation commit or pull request. Then:

1. resolve the run's outcome in the sink this run already opened, with
   `scripts/run-telemetry.sh finish --outcome aborted`;
2. name the exact criterion, prerequisite, command, or contract conflict that
   failed;
3. explain why direct `tested` evidence is unavailable;
4. name the one narrow route out — return to triage; split or amend the issue;
   complete a blocking prerequisite; obtain the explicitly required
   human/manual environment; create or identify a blocking tracker issue; or
   request a trusted-maintainer contract correction; and
5. stop.

Do not convert the failure into a speculative implementation plan, weaken the
criterion to continue, or manufacture a seam.

An aborted preflight is a hand-back, not a candidate closeout: it is never
`Closes`, never `Progresses`, and renders no closeout body. Follow the existing
GitHub-mutation authority and tracker conventions when a blocking issue or
triage change is genuinely required.
