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
validation-evidence policy and the same-mechanism brief whose deliberate
discovery applies to readiness and cumulative gates. Retain exact identities
for those inputs and verify them before every review transition. They govern
one chain; an old Reviewed anchor never crosses to a different governing state.

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
every cumulative and delta Review index; never rediscover repository standards
or reconstruct the baseline during the review chain.

If an interruption loses information required to prove the current review-chain
transition, take the existing safe hand-back. A later attempt freezes fresh
governing state and establishes a fresh cumulative baseline.

### Review index

Every gate — initial cumulative, each remediation delta, and each fresh
cumulative confirmation — dispatches from one fresh immutable Review index
built from that gate's exact inputs. Materialize the frozen governing state as
owner-only untracked scratch files. Every Review-index operation for this Run
uses the governing Review-index script, so obtain its path once per gate. Run
this from the target repository; the path below is relative to the skill root:

```bash
review_index="$(scripts/manifest-identity.sh review-index-path \
  --run "$RUN_IDENTITY")"
```

It validates this Run's complete custody and its current governing-instruction
identity first, so a Run whose governing Review-index script has changed fails
closed here rather than at a gate. Then create the index by running
`bash "$review_index" create` from the target repository, so its Git operations
resolve there. Supply the gate kind, the
pinned comparison and Candidate commit and tree identities, and one file per
frozen component: `--review-assignment` carries that gate's assignment below
together with the selected workflow's applicable common review brief,
`--trusted-contract` the frozen trusted snapshot and referenced contracts,
`--standards` the complete frozen Standards input, `--validation-evidence-policy`
the frozen evidence policy, `--validation-surface-manifest` the frozen manifest,
and each `--evidence` one qualifying validation-evidence record, carrying that
evidence's existing Reusable-evidence identity and safe provenance locator
inside the record. The index freezes those records, not the raw evidence
payloads: raw evidence stays at its provenance locator under
`validation-evidence.md` and is inspected there when an axis needs it.
Creation returns the index path and its SHA-256 only once the whole package
verifies, so an existing package proves no gate result on its own.

The index is input-only. It carries no reviewer, conclusion, confirmation, or
gate progress, and a successor gate never reuses a predecessor's index even
when every component's bytes are unchanged.

### Common dispatch

Give Standards, Spec, and closure the identical dispatch — the same Review-index
identity and the same pinned comparison and Candidate identities:

```text
- Review index: <absolute index path>
- Review-index identity: <the index SHA-256>
- Comparison identity: <the pinned comparison commit and tree>
- Exact current Candidate identity: <the pinned Candidate commit and tree>
- Review-index command: bash <the verified Review-index script path>
- Verify before judging: <command> verify --index <path>
  --index-sha256 <identity>
- Read one frozen component: <command> read --index <path>
  --index-sha256 <identity> --role ROLE [--evidence-sha256 SHA256]
- Complete changed paths: <command> changed-paths --index <path>
  --index-sha256 <identity>
```

Give the concrete command; no axis discovers the Run's custody or a skill
installation itself. Every operation runs from the target repository. Add only
that axis's starting components and its own brief. Keep the assignment blind: add no implementation context, prior reviewer conclusion, adjudication,
disposition, or convenience summary.

### Starting context and widening

Every axis begins by reading the authenticated `review-assignment` and by
obtaining the complete raw no-renames changed-path inventory from the pinned
trees; that inventory is derived on demand and is never a stored artifact.
Each axis then adds the frozen components its own obligation makes it
responsible for:

- Standards begins with `standards`, the complete frozen Standards input.
- Spec begins with `trusted-contract`.
- Closure begins with `trusted-contract`, `validation-surface-manifest`,
  `validation-evidence-policy`, and the indexed evidence records — read to
  obtain each record's existing identity and safe provenance locator, not to
  dereference every raw payload up front. Inspect raw evidence at its
  provenance locator when the closure obligation reaches it.

These are starting sets, not authority boundaries. Any axis may read any other
frozen component whenever a concrete review question requires it, through the
same verified read. Current Candidate inspection follows the existing
review-phase worktree contract. Historical source and every comparison come
from the pinned identities under one invariant: read them against the
dispatched tree identities and never against a live ref, branch, `HEAD`, or
working tree, with replacement objects disabled, and take every path or
path-set comparison literally (for example with `--literal-pathspecs`), with
ambient external-diff, text-conversion, and rename-inference behavior
disabled.

Availability is not inspection: being able to widen never discharges an
inspection obligation the axis owes.

A required frozen component or comparison that will not verify or retrieve has
no substitute. Never fall back to a similarly named live contract, Standards
source, manifest, policy, ref, or artifact.

### Axis completion

Each axis report binds itself to the exact Review-index identity it was
dispatched with and returns `COMPLETE` or `INCOMPLETE`. A `COMPLETE` report
keeps its existing conclusion-level citations, and additionally records
relied-on widening those citations do not already cite together with the
concrete question it settled. An `INCOMPLETE` report identifies the unresolved
input or query; the gate does not complete on it and no anchor advances.

### Review-input failure

Three failures stay distinct rather than collapsing into one route:

- Invalid, missing, or identity-invalid frozen review input is a hard
  review-input failure: the gate cannot complete, and the owning contract's
  route for that input applies.
- A retriable delivery, publication, or known-truncation failure may retry
  against the same still-valid gate inputs until an index verifies.
- External-evidence inadequacy is an evidence question under
  `validation-evidence.md`; it never by itself corrupts an otherwise valid
  index.

### Index lifetime

Each gate's index stays available through its three axes and adjudication, and
an applicable clean cumulative index stays available until Closeout verifies
and consumes its confirmation. Remove it best-effort afterwards. Existence
grants no lifecycle authority: a surviving package proves no gate result, and a
removed one restores nothing.

### Cumulative Review-index dispatch

For the initial cumulative gate and every fresh cumulative confirmation after
remediation, create one `cumulative` index whose comparison endpoint is the
frozen comparison base and whose Candidate endpoint is the exact current
Candidate, and dispatch it to Standards, Spec, and closure with this assignment
as its `--review-assignment` component:

```text
Cumulative review assignment: independently review the exact cumulative
candidate against the full accepted review contract, using the dispatched
Review index as the complete frozen governing universe. Deliberately perform
the bounded same-mechanism neighborhood discovery in the common review brief.
```

Invoke `code-review` with the common dispatch for Standards and Spec; give
closure the identical dispatch and its closure brief. The index is
authoritative, so no axis refetches or rediscovers a governing input.

## Initial cumulative gate

After the first committed candidate, capture its exact Candidate identity as
`C0`. The initial cumulative gate runs fresh Standards, Spec, and closure axes
against the same exact Candidate identity and frozen governing inputs. Give
each the same exact cumulative Review-index dispatch for `C0`.

`C0` becomes the Reviewed anchor only after fresh Standards, Spec, and closure
complete against the same exact candidate under unchanged governing inputs. A
Reviewed anchor does not mean clean, accepted, closable, or eligible for
closeout; it is only the candidate from which a later correction delta is
computed. Adjudicate all three reports after the required axes complete, then
set `C0` as the Reviewed anchor regardless of findings.

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

### Delta Review-index dispatch

Create one `delta` index whose comparison endpoint is the previous Reviewed
anchor and whose Candidate endpoint is the exact current Candidate, from the
same frozen governing state and current raw artifacts only, with this
assignment as its `--review-assignment` component:

```text
Delta review assignment: independently review the exact candidate delta against
the full accepted review contract, using the dispatched Review index as the
complete frozen governing universe.
- Review scope: Verify the exact accepted-blocker correction represented by the
  delta against the full accepted review contract. Inspect only enough unchanged
  surrounding context to determine whether the correction satisfies that
  contract or introduced a regression. Do not deliberately enumerate new
  sibling locations, input families, representations, branches, or adjacent
  variants as another same-mechanism neighborhood search. If you independently
  encounter a blocking defect, report it normally, but do not expand it into
  sibling discovery in this delta gate. Deliberate neighborhood discovery
  belongs to cumulative review.
```

The dispatched index is the review input. Separately enforce its blindness:
describe the assignment neutrally, and expose no remediation rationale, prior
finding or report text, accepted directive, adjudication, disposition, or
adjudication ledger. Add no convenience summary of why the correction exists.

### Delta gate

Start fresh Standards, Spec, and closure delta axes together against the same
exact current candidate and unchanged governing inputs. Invoke `code-review`
with the common dispatch for Standards and Spec; give the closure axis that
identical dispatch and its closure brief.

Apply the assignment's Review scope exactly. It makes the correction delta the
correction-verification surface while keeping only the unchanged-context access
needed to determine contract satisfaction or regression.

Advance the Reviewed anchor only after all three required delta axes complete
against the same exact candidate under unchanged governing inputs. Advance it
even when the gate has findings: Reviewed anchor does not mean clean, accepted,
closable, or eligible for closeout. Adjudicate the completed gate. For a clean
gate, proceed to final cumulative review. For a gate with an accepted blocker,
apply the correction before reviewing the next exact anchor-to-Candidate delta.

## Fresh cumulative confirmation after remediation

After a clean delta gate, give the exact current candidate a new fresh blind
cumulative Standards, Spec, and closure confirmation against the full accepted
review contract. Use fresh reviewers and a newly created cumulative
Review index for the exact current candidate; expose none of the delta reports or
their adjudication.

If adjudication leaves that cumulative confirmation clean and its candidate and
governing inputs stay unchanged, it is the confirmation Closeout consumes. If a
blocker from the final cumulative confirmation is accepted and correction is
allowed, apply the correction, run a fresh three-axis delta gate from the
retained Reviewed anchor, then run another fresh blind cumulative confirmation.
The route is always correction → delta gate → fresh blind cumulative
confirmation; the earlier confirmation never applies to changed content.

## Invalidation and evidence

A candidate-content change or governing-input change invalidates the applicable
confirmation or review chain. For a governing-input change, first apply the
owning contract's invalidation route, re-establish every applicable
preflight/Closability input and focused validation, then establish a new
Reviewed anchor with a fresh initial cumulative gate. A chain restart is
available only when that input is legally mutable. An old Reviewed anchor never
crosses governing identities.

A post-delegation omitted required member of the Validation-surface manifest
takes precedence over review restart. Follow the immutable-manifest hand-back;
never absorb the omission by rebuilding governing state or restarting this
review state machine.

New qualifying raw evidence for the exact unchanged candidate does not itself
invalidate a review or confirmation, and never mutates or replaces an already
dispatched index; it stays separately identified under `validation-evidence.md`
until the next applicable gate creates its own index. Apply
`validation-evidence.md`: assurance sufficiency determines whether execution is required, and a workflow-stage
transition is never itself a reason to rerun validation. Failing,
contradictory, stale, incomplete, identity-invalid, or otherwise inadequate
evidence remains blocking and is adjudicated before another execution.
