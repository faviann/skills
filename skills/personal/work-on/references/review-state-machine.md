# Review state machine

Apply this state machine in every selected `work-on` workflow. It owns review
identity, cumulative and delta transitions, reviewer blindness, and review-chain
invalidation. The selected workflow owns implementation sequencing and invokes
these gates; `github-closeout.md` owns closure judgments;
`validation-evidence.md` owns whether validation executes.

## Frozen governing state

Before the initial cumulative gate, freeze one review chain's comparison base,
trusted contract snapshot, binding standards snapshot, accepted full review
contract, and finite Validation-surface manifest. The accepted full review
contract is the complete Standards, Spec, and closure assignment, including the
same-mechanism brief and validation-evidence policy. Retain exact identities for
those inputs and verify them before every review transition. They govern one
chain; an old Reviewed anchor never crosses to a different governing state.

## Initial cumulative gate

After the first committed candidate, capture its exact Candidate identity as
`C0`. The initial cumulative gate runs fresh Standards, Spec, and closure axes
against the same exact Candidate identity and frozen governing inputs. Give
each the full cumulative `<base>...C0` subject, trusted inputs, frozen
Validation-surface manifest, and qualifying raw evidence, but no prior
conclusion.

`C0` becomes the Reviewed anchor only after fresh Standards, Spec, and closure
complete against the same exact candidate under unchanged governing inputs. A
Reviewed anchor does not mean clean, accepted, closable, or eligible for
closeout; it is only the candidate from which a later correction delta is
computed. Adjudicate all three reports after the required axes complete.

A clean initial cumulative gate, while candidate content and governing inputs
remain unchanged, satisfies the required fresh blind
cumulative confirmation. Proceed toward Closeout using it; Closeout launches no
second identical cumulative gate merely because the workflow stage changed.

## Remediation delta loop

An accepted blocker-driven candidate-content change invalidates the prior
confirmation while retaining the previous Reviewed anchor. After the correction
and applicable focused checks, capture the exact current Candidate identity and
produce the mechanically exact delta from the previous Reviewed anchor to the
current Candidate.

### Delta-review package

Give every delta reviewer the same neutral package, populated from frozen state
and current raw artifacts only:

```text
Delta review assignment: independently review the exact candidate delta against
the full accepted review contract.
- Previous Reviewed-anchor identity: <full exact identity>
- Exact current Candidate identity: <full exact identity>
- Mechanically exact delta: <git diff previous-anchor...current-candidate>
- Full trusted contract: <the frozen trusted snapshot and referenced contracts>
- Binding standards: <the frozen standards snapshot>
- Validation-surface manifest: <the frozen complete direct-evidence population>
- Qualifying raw validation evidence: <evidence tied to the current candidate,
  with safe provenance locators under references/validation-evidence.md>
```

The package is the review input. Separately enforce its blindness: describe the
assignment neutrally, and expose no remediation rationale, prior finding or
report text, accepted directive, adjudication, disposition, or adjudication
ledger. Add no convenience summary of why the correction exists.

### Delta gate

Start fresh Standards, Spec, and closure delta axes together against the same
exact current candidate and unchanged governing inputs. Invoke `code-review` in
its delta-package mode for Standards and Spec; give the closure axis that
identical package and its closure brief.

The correction delta is the initial review search surface. A reviewer may
inspect unchanged context only for a recorded concrete contract question,
changed-mechanism question, reproduced finding or seed, or #62 same-mechanism
neighborhood investigation. For #62, stay inside the same mechanism, governing
criterion and public flow, then apply the existing stop boundary before another
criterion, subsystem, external boundary, or speculative defense. This access
does not license routine reconstruction, repackaging, or rereading of the full
cumulative candidate.

Advance the Reviewed anchor only after all three required delta axes complete
against the same exact candidate under unchanged governing inputs. Advance it
even when the gate has findings: Reviewed anchor does not mean clean, accepted,
closable, or eligible for closeout. Adjudicate the completed gate. An accepted
blocker and allowed correction repeats this loop from the newly advanced anchor.

## Fresh cumulative confirmation after remediation

After a clean delta gate, give the exact current candidate a new fresh blind
cumulative Standards, Spec, and closure confirmation against the full accepted
review contract. Use fresh reviewers, the full `<base>...current-candidate`
subject, frozen governing inputs, and qualifying raw evidence; expose none of
the delta reports or their adjudication.

If that cumulative confirmation is clean and its candidate and governing inputs
stay unchanged, it is the confirmation Closeout consumes. If a blocker from the
final cumulative confirmation is accepted and correction is allowed, apply the
correction, run a fresh three-axis delta gate from the retained Reviewed anchor,
then run another fresh blind cumulative confirmation. The route is always
correction → delta gate → fresh blind cumulative confirmation; the earlier
confirmation never applies to changed content.

## Invalidation and evidence

A candidate-content change or governing-input change invalidates the applicable
confirmation or review chain. For a governing-input change, first apply the
owning contract's invalidation route, re-establish every applicable
preflight/Closability input and focused validation, then establish a new
Reviewed anchor with a fresh initial cumulative gate. A chain restart is
available only when that input is legally mutable.

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
