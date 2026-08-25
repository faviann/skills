# Review state machine

Apply this state machine in every selected `work-on` workflow. It owns review
identity, cumulative and delta transitions, reviewer blindness, and review-chain
invalidation. The selected workflow owns implementation sequencing and invokes
these gates; `github-closeout.md` owns closure judgments;
`validation-evidence.md` owns whether validation executes.

## Frozen governing state

Before the initial cumulative gate, freeze one review chain's comparison base,
trusted contract snapshot, complete Standards input, accepted full review
contract, and finite Validation-surface manifest. The accepted full review
contract is the complete Standards, Spec, and closure assignment, including the
same-mechanism brief and validation-evidence policy. Retain exact identities for
those inputs and verify them before every review transition. They govern one
chain; an old Reviewed anchor never crosses to a different governing state.

### Frozen Standards input

Before the initial gate, materialize the complete frozen Standards input:

1. Enumerate every applicable repository standards source under
   `code-review/SKILL.md`'s existing Standards-source rule. Record each source
   with its source-labelled path and exact content; record explicitly when the
   repository has no such source.
2. Append the complete Fowler smell baseline from `code-review/SKILL.md`,
   including its existing repo-overrides and judgement-call semantics and its
   rule to skip anything tooling already enforces.

Freeze the combined input and its exact identity with the other governing
inputs. The repo overrides and every smell remains a judgement call inside this
frozen Standards input. Reuse the exact frozen Standards input verbatim in
every cumulative and delta package; never rediscover repository standards or
reconstruct the baseline during the review chain.

## Recoverable stable checkpoints

Keep two owner-only run-local review-chain files beside the retained snapshot
and manifest:

```text
$(git rev-parse --path-format=absolute --git-common-dir)/work-on-manifest/
  <run-id>.review-inputs.md
  <run-id>.review-chain.json
```

Before the initial gate, write the complete frozen Standards input and accepted
full review contract verbatim to `review-inputs.md`; freeze it at `0600` and do
not rewrite it within that governing state. Packages read those exact bytes on
every cumulative and delta invocation.

Create `review-chain.json` at `0600` after those inputs freeze, and replace it
atomically at each stable checkpoint. It contains only:

- the frozen governing-input identity bundle: the comparison base, trusted
  snapshot, SHA-256 digest of `review-inputs.md`, Validation-surface manifest,
  and Workflow provenance identities;
- the current Reviewed anchor, or `null` before the initial gate completes; and
- any currently valid cumulative-confirmation Candidate together with the exact
  governing identity it confirms, otherwise `null`; and
- the pending required correction: `null`, or the exact accepted corrective
  directives bound to their Reviewed anchor and governing identity.

These files are semantic review-chain state, not telemetry, Run registry state,
an adjudication ledger, or Convergence-budget state. The governing-input identity
bundle binds the recoverable `review-inputs.md` content by digest rather than
reconstructing either input. A missing, malformed, non-owner-only,
identity-invalid, or unreproducible file after delegation is not reconstructed
from conversational memory; take the existing frozen-state fail-closed
hand-back.

On continuation or resume, verify Workflow provenance, the retained
snapshot/manifest pair, every identity in the governing bundle, the Reviewed
anchor, and any stored confirmation before reuse. The exact current Candidate is
resolved and verified from the repository under the existing Candidate-identity
rule on resume; it is not stored as duplicated authority. A stored confirmation
is applicable only when its Candidate equals that resolved current Candidate and
its governing identity equals the verified bundle. A checkpoint containing both
a confirmation and a pending required correction is invalid.

Interrupted gate work is disposable:

- during an initial or final cumulative gate, rerun all required cumulative
  axes with fresh reviewers;
- during a delta gate, rerun all required delta axes with fresh reviewers from
  the persisted Reviewed anchor to the exact resolved current Candidate.

A pending required correction on resume takes priority before any final
cumulative confirmation or Closeout transition, regardless of Candidate
relationship. Recover its exact accepted corrective directives and verify their
Reviewed anchor and governing identity before continuing correction. If the
directive cannot be recovered sufficiently to continue, fail closed; never drop
the obligation or ask a fresh reviewer to rediscover it. Clear it only after the
directive is resolved in a committed changed Candidate, then take the direct
anchor-to-Candidate delta route. This primary-only state is never included in a
review package.

With no pending correction, the verified stable identities choose the route
without active-gate state: when the anchor is `null`, run the initial cumulative
gate; when the anchor differs from the current Candidate, run the delta gate
between them; when the anchor equals the current Candidate and confirmation is
`null`, run the final cumulative gate. A matching verified confirmation proceeds
toward Closeout.

Do not persist per-axis completion, active-gate progress, reviewer reports, or
other partial-gate machinery. Only after all required delta axes complete and
their reports are adjudicated may the new Reviewed anchor become durable. At
that stable checkpoint, atomically persist the completed gate's Candidate as the
Reviewed anchor regardless of findings and before any correction or final
confirmation begins. An interruption before replacement leaves the preceding
checkpoint authoritative and reruns the whole gate. Only after a cumulative
confirmation completes and adjudication leaves it clean does that confirmation
become durable and reusable.

### Cumulative-review package

For every initial or final cumulative gate, populate one neutral package from
the frozen governing state and exact current artifacts, and give that same exact
package to Standards, Spec, and closure:

```text
Cumulative review assignment: independently review the exact cumulative
candidate against the full accepted review contract.
- Comparison-base identity: <full exact identity>
- Exact current Candidate identity: <full exact identity>
- Mechanically exact cumulative diff: <git diff comparison-base^{tree} candidate^{tree}>
- Full trusted contract: <the frozen trusted snapshot and referenced contracts>
- Binding Standards input: <applicable repository standards source-labelled
  paths and exact content, followed by the complete frozen Fowler smell
  baseline with its repo-overrides and judgement-call semantics>
- Validation-surface manifest: <the frozen complete direct-evidence population>
- Qualifying raw validation evidence: <evidence tied to the current candidate,
  with safe provenance locators under references/validation-evidence.md>
```

Invoke `code-review` with these caller-pinned inputs for Standards and Spec;
give closure the identical package and its closure brief. The package is
authoritative, so no axis refetches or rediscovers a governing input. Keep the
assignment blind: add no implementation context, prior reviewer conclusion,
adjudication, disposition, or convenience summary.

## Initial cumulative gate

After the first committed candidate, capture its exact Candidate identity as
`C0`. The initial cumulative gate runs fresh Standards, Spec, and closure axes
against the same exact Candidate identity and frozen governing inputs. Give
each the same exact cumulative-review package for `C0`.

`C0` becomes the Reviewed anchor only after fresh Standards, Spec, and closure
complete against the same exact candidate under unchanged governing inputs. A
Reviewed anchor does not mean clean, accepted, closable, or eligible for
closeout; it is only the candidate from which a later correction delta is
computed. Adjudicate all three reports after the required axes complete, then
atomically persist `C0` as anchor regardless of findings. The same replacement
also records `C0` as cumulative confirmation when the gate is clean, and records
no confirmation plus the exact accepted corrective directives when blockers
require correction. Thus a dirty initial gate followed by interruption recovers
that correction remains required. An interruption before that stable checkpoint
reruns the whole initial gate.

A clean initial cumulative gate, while candidate content and governing inputs
remain unchanged, satisfies the required fresh blind
cumulative confirmation. Proceed toward Closeout using it; Closeout launches no
second identical cumulative gate merely because the workflow stage changed.

## Remediation delta loop

An accepted blocker-driven candidate-content change invalidates the prior
confirmation while retaining the previous Reviewed anchor. After the correction
and applicable focused checks, capture the exact current Candidate identity and
produce the mechanically exact direct delta from the previous Reviewed anchor
to the current Candidate. Use a two-endpoint tree comparison; a three-dot range
is a merge-base comparison and is not the remediation subject.

### Delta-review package

Give every delta reviewer the same neutral package, populated from frozen state
and current raw artifacts only:

```text
Delta review assignment: independently review the exact candidate delta against
the full accepted review contract.
- Previous Reviewed-anchor identity: <full exact identity>
- Exact current Candidate identity: <full exact identity>
- Mechanically exact delta: <git diff previous-anchor^{tree} current-candidate^{tree}>
- Full trusted contract: <the frozen trusted snapshot and referenced contracts>
- Binding Standards input: <applicable repository standards source-labelled
  paths and exact content, followed by the complete frozen Fowler smell
  baseline with its repo-overrides and judgement-call semantics>
- Validation-surface manifest: <the frozen complete direct-evidence population>
- Qualifying raw validation evidence: <evidence tied to the current candidate,
  with safe provenance locators under references/validation-evidence.md>
- Review scope: Begin at the exact correction delta. Inspect unchanged context
  only for a recorded concrete contract question, changed-mechanism question,
  reproduced finding or seed, or #62 same-mechanism neighborhood investigation.
  For #62, stay inside the same mechanism, governing criterion, and public flow;
  stop before another criterion, subsystem, external boundary, or speculative
  defense. Do not routinely reconstruct, repackage, or reread the full
  cumulative candidate.
```

The package is the review input. Separately enforce its blindness: describe the
assignment neutrally, and expose no remediation rationale, prior finding or
report text, accepted directive, adjudication, disposition, or adjudication
ledger. Add no convenience summary of why the correction exists.

### Delta gate

Start fresh Standards, Spec, and closure delta axes together against the same
exact current candidate and unchanged governing inputs. Invoke `code-review`
with these caller-pinned inputs for Standards and Spec; give the closure axis
that identical package and its closure brief.

Apply the package's Review scope exactly. It makes the correction delta the
initial review search surface while keeping concrete unchanged-context access
and #62's same-mechanism investigation and stop boundaries reachable.

Advance the Reviewed anchor only after all three required delta axes complete
against the same exact candidate under unchanged governing inputs. Advance it
even when the gate has findings: Reviewed anchor does not mean clean, accepted,
closable, or eligible for closeout. Adjudicate the completed gate. For a clean
gate or a gate with an accepted blocker, atomically persist the advanced anchor
with no cumulative confirmation before final cumulative review or correction.
Record pending correction as `null` for the clean gate, and as the exact accepted
corrective directives for the blocked gate. Partial axis results never alter the
durable checkpoint. A dirty delta gate followed by interruption recovers that
correction remains required. A clean delta gate followed by interruption has no
pending correction, so final cumulative confirmation remains its next
transition.

## Fresh cumulative confirmation after remediation

After a clean delta gate, give the exact current candidate a new fresh blind
cumulative Standards, Spec, and closure confirmation against the full accepted
review contract. Use fresh reviewers and a newly populated cumulative-review
package for the exact current candidate; expose none of the delta reports or
their adjudication.

If adjudication leaves that cumulative confirmation clean and its candidate and
governing inputs stay unchanged, atomically persist its Candidate and governing
identity with pending correction `null`; it is the confirmation Closeout
consumes. If a blocker from the final cumulative confirmation is accepted and
correction is allowed, atomically persist its exact corrective directives as the
pending required correction with no confirmation, apply the correction, run a
fresh three-axis delta gate from the retained Reviewed anchor, then run another
fresh blind cumulative confirmation. The route is always correction → delta gate
→ fresh blind cumulative confirmation; the earlier confirmation never applies
to changed content. A dirty final cumulative confirmation followed by
interruption recovers that correction remains required.

## Invalidation and evidence

A candidate-content change or governing-input change invalidates the applicable
confirmation or review chain. For a governing-input change, first apply the
owning contract's invalidation route, re-establish every applicable
preflight/Closability input and focused validation, then establish a new
Reviewed anchor with a fresh initial cumulative gate. A chain restart is
available only when that input is legally mutable. Replace the checkpoint only
with the newly verified governing bundle and its empty anchor/confirmation state;
set pending correction to `null`. An old checkpoint never crosses governing
identities.

A post-delegation omitted required member of the Validation-surface manifest
takes precedence over review restart. Follow the immutable-manifest hand-back;
never absorb the omission by rebuilding governing state or restarting this
review state machine.

New qualifying raw evidence for the exact unchanged candidate does not itself
invalidate a review or confirmation. Apply `validation-evidence.md`: assurance
sufficiency determines whether execution is required, and a workflow-stage
transition is never itself a reason to rerun validation. Failing,
contradictory, stale, incomplete, identity-invalid, or otherwise inadequate
evidence remains blocking and is adjudicated before another execution.
