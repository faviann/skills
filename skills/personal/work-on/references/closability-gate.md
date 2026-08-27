# Pre-implementation closability gate

Decide whether the issue can reach `Closes` **before** implementation is
delegated — not after code, review, and remediation have already been spent on
a criterion that was never observable.

Run this once, after the trusted snapshot and the selected workflow have been
read, and before contract freeze, implementation delegation, production or test
edits, implementation commits, and any pull request.

The gate decides only whether the issue is closable in this run. It changes no
readiness, Standards, Spec, closure, remediation, validation, or closeout
semantics, and adds no tracked artifact, ledger, or telemetry field of its own.
A pass records nothing beyond the custody that contract freeze authors. An abort
hands back as `preflight-aborted`, as the abort steps below require; no contract
froze and there is no Run identity or lifecycle to finalize.

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

## The Validation surface each criterion must materialize

A criterion's **Validation surface** is the complete finite set of concrete
artifact, mode, host, or public-boundary instances whose behavior it requires
direct evidence about for the issue to close. It is not the criterion's input or
state domain — coverage inside a seam may stay parameterized, property-based, or
representative — and it is not the implementation diff. It answers which
instances must carry direct evidence, never where implementation or review may
look; the selected workflow owns that boundary.

Materialize every surface here, in one of two forms:

- an explicit finite enumeration; or
- a deterministic, non-interpretive finite selection rule.

Either form must actually be evaluated during this preflight and produce the
complete concrete list for the trusted snapshot — the one list any later
execution against that same snapshot would also produce. `all relevant
authority` and `whatever implementation touches` fail, because later judgement
can grow their population. A deterministic traversal or tracked-path rule passes
only when executing it here yields that list.

A surface may name an exact artifact this issue authorizes creating, but only
when its identity, location, and criterion role are already determinable from
the trusted contract. An artifact implementation merely turns out to touch never
joins a surface.

Finiteness does not weaken evidence: every member still requires the direct
evidence its criterion demands under conditions 1 and 3.

Together, these surfaces are the run's **Validation-surface manifest**.

## Phase ownership

Enumerate every definitely owed validation command and direct-evidence
obligation from the trusted contract, Validation-surface manifest, repository
baseline, and planned scoped-delegate contract. Resolve each one's owning phase
deterministically from the selected workflow, interpreted alongside the
governing validation authority that establishes what is owed. The selected
workflow alone supplies execution timing; the other sources cannot pull an
obligation earlier merely by listing it.

Keep every resolved obligation and owning phase available for the scoped
delegate contract, including obligations owned by later phases. If the selected
workflow does not deterministically resolve an obligation's phase, condition 4
fails and the unresolved phase aborts Closability. Infer no implementation,
earliest, next-gate, or Closeout default.

Where an enumerated owed obligation is a command the manifest records as the
discharging action for a criterion's Validation surface, what is owed is that
surface's enumerated members' required observations. The command is the default
vehicle that produces them and carries the obligation's owning phase.
Re-executing that exact command is not itself the discharge condition; the
obligation is discharged when every owed member of that surface has qualifying
evidence at the owning phase.

## Conditions

The gate passes only when all six hold.

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
4. **The required workflow and validation commands are executable, and every
   definitely owed obligation has a resolved owning phase.** Abort when a
   command needs a dependency or authority that cannot be established within
   this scope, or when the selected workflow cannot deterministically resolve
   its phase. Ordinary setup explicitly included in the run is available. A
   transient command failure during later validation is not a preflight
   failure: this asks whether the path is available and executable, not whether
   the unimplemented candidate already passes.
5. **The trusted contract is internally consistent.** Abort on a criterion
   requiring behavior the issue places out of scope, two trusted requirements
   demanding incompatible outcomes, a criterion requiring a mechanism the issue
   prohibits, incompatible issue-body and trusted-maintainer amendments, a
   closing condition that cannot coexist with a named prerequisite, or
   ambiguity material enough that the implementation delegate would have to
   choose the contract. Adjudicate ordinary wording against the trusted
   sources; never invent a requirement or choose between genuinely
   incompatible trusted ones.
6. **Every criterion's Validation surface is finite and materialized here.**
   Abort when a criterion's direct-evidence population can be settled only by
   later judgement — an interpretive rule, an open-ended traversal, or a
   population the implementation delegate would have to discover. A criterion
   whose surface the trusted contract does not make decidable — evaluated
   against the trusted snapshot and the pre-implementation base — takes this
   abort; it is never rescued by reading the criterion more narrowly than the
   trusted contract states it.

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

## Freeze and custody

The contract freezes when the complete gate passes — after the trusted snapshot
and the selected workflow have been read, and before implementation delegation.
That successful freeze is the single authority point that mints the Run identity
and makes the complete custody visible: the Validation-surface manifest, trusted
snapshot, and captured Workflow provenance. It identifies the manifest with the
trusted snapshot and the pre-implementation base it was materialized from.

Before applying the gate, retain the exact selected-workflow identity in the
primary's working context; the path below is relative to the skill root:

```bash
selected_workflow_identity="$(scripts/workflow-provenance.sh identify-workflow)"
```

This shell value is not manifest identity or another durable record. It is the
comparison input for the atomic freeze. Losing it before freeze takes complete
recomputation; identifying the workflow again cannot authorize a contract
already derived.

Before applying the gate, retain the exact source-labelled trusted snapshot it
will read. Preserve each trusted source's attribution and body in that one
snapshot; it is the run's contract, not a serialization a later context must
recreate. Record the committed base before the gate as
`pre_implementation_base="$(git rev-parse HEAD)"`.

Materialize the snapshot and manifest in owner-only untracked scratch files.
The successful freeze moves their exact content and the captured provenance
into owner-only custody in the target repository's Git common directory:

```text
$(git rev-parse --path-format=absolute --git-common-dir)/work-on-manifest/
  <run-identity>.md
  <run-identity>.trusted-snapshot.json
  <run-identity>.provenance.json
```

The Run identity carries no repository binding. Consumers treat it as an opaque
`[A-Za-z0-9._-]{8,64}` token; the mint currently uses
`<UTC timestamp>-<16 hex>`. Custody survives branch switches and linked-worktree
removal, never becomes tracked state, and remains `0700`/`0600` for its owner.
From the target repository, freeze the materialized scratch inputs; the path
below is relative to the skill root:

```bash
RUN_IDENTITY="$(scripts/manifest-identity.sh freeze \
  --manifest "$materialized_manifest" \
  --snapshot "$trusted_snapshot" \
  --base "$pre_implementation_base" \
  --workflow-identity "$selected_workflow_identity")"
```

The helper verifies that the selected workflow still has the retained identity,
captures the complete governing-instruction identity, binds all three custody
artifacts, delivers the minted Run identity only after pending publication and
cleanup succeed, then makes atomic accepted-manifest replacement its final
operation. It publishes the pending manifest after its siblings; incomplete
staging or interrupted publication never verifies or renders as frozen custody.
A failure before delegation takes complete recomputation. No expectation
argument, workflow sidecar, singleton ledger, delete-on-freeze bridge,
repository binding, or mutable current-run pointer participates.

The selected workflow supplies the manifest to the implementation delegate and
to the readiness, Standards, Spec, and closure contexts, and keeps it available
to the primary for adjudication. It is contract input, not a prior review
conclusion: reviewers stay independent about whether the evidence satisfies a
criterion, and may report that the manifest conflicts with the trusted contract.

## Invalidation before delegation

Any change to an input the manifest was derived from invalidates it — the
trusted contract or snapshot, the selected workflow, or an enumeration rule or
its inputs.

While no implementation delegate has launched and no implementation work has
begun, discard the manifest, rebuild the affected trusted preflight state, and
rerun the complete gate over it. Rerunning it is not a second gate: the run
passes one complete gate, over whichever trusted preflight state it finally
delegates from. Never patch one entry in place: re-materialize every criterion's
surface, including those whose own inputs did not move. If no valid replacement
can be established, abort as below.

After implementation is delegated the manifest is immutable for this run, and
the selected workflow owns what happens when a trusted criterion turns out to
require an omitted member.

## Pass

Keep the compact criterion-to-seam reasoning in the primary's working context,
freeze the complete custody, retain the printed Run identity, and continue the
selected workflow unchanged. A pass records nothing else; the run's outcome
remains the closure gate's to resolve.

## Abort

Launch no implementation delegate, make no implementation edit, and create no
implementation commit or pull request. Then:

1. name the exact criterion, prerequisite, command, unmaterializable validation
   surface, or contract conflict that failed;
2. explain why direct `tested` evidence is unavailable;
3. name the one narrow route out — return to triage; split or amend the issue;
   complete a blocking prerequisite; obtain the explicitly required
   human/manual environment; create or identify a blocking tracker issue; or
   request a trusted-maintainer contract correction; and
4. stop.

Do not convert the failure into a speculative implementation plan, weaken the
criterion to continue, or manufacture a seam.

An aborted preflight is a hand-back, not a candidate closeout: it is never
`Closes`, never `Progresses`, and renders no closeout body. Follow the existing
GitHub-mutation authority and tracker conventions when a blocking issue or
triage change is genuinely required.
