# Normative remediation

This reference owns the qualification and its reconciliation, Authority delta,
semantic unit, blind reader package, materiality test, and unresolved-challenge
routing for a Corrective batch. It adds a pre-commit checkpoint; it owns no
review gate, Reviewed anchor, or durable lifecycle state.

## Qualification

Apply this mechanism to every qualifying Corrective batch, including the first.
A batch qualifies when it changes the words, structure, or placement of a
governing proposition or relationship: something a future agent, reviewer,
operator, or implementation is entitled to rely on as authority. The object
being changed decides qualification. Record the intended semantic delta,
including `none`; intended semantic delta never gates the mechanism.

Descriptive and history-only material does not qualify merely because it lives
in an authoritative file. The proposition is the unit. Status and lifecycle
markers qualify because whether an authority still binds is governing meaning.

## Qualification reconciliation

Qualification before dispatch is provisional. Entitlement is determined from the
actual correction, for the exact current `Candidate identity`, before that batch
is committed.

Qualification may inspect the correction to determine which semantic units
exist. The Authority delta may not use the correction to determine what those
units were intended to mean.

The correction from the Reviewed anchor to the exact current `Candidate
identity` is the evidence for what changed; within a Corrective batch no delta
gate completes, so that comparison spans the whole batch correction rather than
the latest revision alone. The delegate's `Changed:` channel is a locator only
and never the basis of the verdict; the primary owns qualification. Widen into
bounded surrounding or frozen governing authority where changed material cannot
otherwise be classified; this never becomes a cumulative reread of the
candidate.

Reconciliation is recomputational, not additive. Recompute the qualifying set
from the complete current correction, so a unit that qualifies only because of
what the delegate actually changed enters it and a provisionally predicted unit
the actual correction does not change leaves it. Removal of a provisionally
predicted unit establishes only that the actual correction does not change that
unit; it does not establish that the corresponding accepted blocker or
adjudicated directive has been satisfied, which the existing accepted-blocker
machinery continues to own.

Any change to `Candidate identity` after the latest qualification reconciliation
makes that reconciliation stale. Every commit of the batch, `Progresses`
hand-backs included, requires a reconciliation bound to the exact pair of
Reviewed anchor and current `Candidate identity`. Where the reconciled set is
non-empty, commit only once the Authority delta for that same comparison covers
the actual qualifying set and the required semantic challenge has completed.
Where the reconciled set is empty, record that empty set against the same pair;
no semantic-reader package or semantic challenge is required, and no
justification for the empty set is required.

Provisional qualification state and reconciliation history are primary-side run
working-record material, on the same footing as the primary's untransmitted
reason for a declined supplement. They are not durable state, and they never
enter the semantic-reader package.

## Authority delta

The primary records one Authority delta covering every qualifying unit in the
batch and containing, for each:

- the governing proposition or relationship and its location;
- its governing meaning at the Reviewed anchor;
- the intended resulting meaning, including `none`;
- the constraints expected to survive; and
- the related governing sites considered and how they were identified.

Site discovery remains the primary's responsibility. Enumerate a finite
authority relationship already supplied by an ordered authority block, explicit
cross-reference, routing table, or other bounded source. Repository search may
help identify sites, but lexical matches are not proof of semantic completeness.
Where identification would require open-ended semantic search, record that fact
and claim no completeness. The fresh reader is not responsible for proving that
the primary found every governing site. A later omission caused by authority
absent from the unit is under-slice/site-discovery evidence, not a semantic
challenge failure.

Every creation or revision of a unit's intended resulting meaning and expected
surviving constraints derives from the adjudicated directive and the governing
authority at the Reviewed anchor, never from the correction. Where the
adjudicated directive determinately requires no semantic change to a unit,
preservation of that unit's Reviewed-anchor meaning is the intended semantic
position; that default selects nothing where the directive and Reviewed-anchor
authority admit several materially defensible consequences.

Where an Authority delta entry exists at dispatch, the retained implementation
delegate drafts the correction under it, retaining the `Risks:` channel and
authority relationship the corrective dispatch preserves, and reports conflicts
between the directive and repository authority. It is not asked to pre-answer
the entitlement analysis; its answer is not a substitute for the fresh reader's
interpretation. A unit first discovered as qualifying during qualification
reconciliation may have been drafted before its Authority delta entry existed.
The primary records that entry from the adjudicated directive and
Reviewed-anchor authority before the unit enters the semantic challenge.

## Semantic unit

For each qualifying proposition or relationship, construct the smallest bounded
BEFORE/AFTER representation that preserves both the governing proposition and
the local structure or placement that gives it binding force. Use these settled
treatments:

- An ordinary rule uses its paragraph or block.
- A table uses the affected row or cell plus the headers and legend needed to
  interpret its force.
- An ordered authority list uses the affected entry plus enough of the order to
  expose changed precedence.
- A status banner uses the status statement, the document title, and the local
  status context that determines whether it binds.
- A relocation uses both source and destination contexts.
- A deletion includes enough surrounding context to show that no adjacent
  proposition absorbed the obligation.
- Coupled propositions use the smallest coupled set as one unit.

A structural edit does not entitle the unit to a whole section or document. If
no bounded representation is sufficient, use the `INSUFFICIENT_CONTEXT` route;
the unit never expands into cumulative review.

## Fresh blind reader

Launch one fresh semantic reader per qualifying Corrective batch. It handles
every qualifying unit in that batch in one invocation. Launch a new agent each
batch; never retain a reader across batches. Never reuse that reader as a
review-axis agent in the same chain.

Before interpretation, supply only:

- the BEFORE text;
- the proposed AFTER text or bounded normative diff for the qualifying units;
- file and section identity;
- bounded raw governing-authority context;
- the repository's objective authority relationship or order where relevant;
  and
- the concrete passages forming the task boundary, stated without any claim of
  global completeness.

The reader does not receive the full candidate diff, a cumulative review
package, the full trusted contract by default, the Validation-surface manifest,
validation execution, or subdelegation.

Withheld until after interpretation are the primary's expected BEFORE-to-AFTER
semantics, including `none`; preserved-invariant claims; remediation rationale;
the accepted finding and its adjudication; prior reviewer findings or
dispositions; and the related-sites list as an assertion of completeness. Raw
governing context from a related site may be supplied without its completeness
claim.

The reader independently derives BEFORE and AFTER: what is permitted, required,
and prohibited, plus the relevant scope, precedence, and authority relationship.
It then states the material semantic delta. Derive governing effect from the
authority as written. A draft's own characterization of its effect is not proof
of that characterization.

## Materiality

A semantic delta is material only when, under the same supplied governing
context, BEFORE and AFTER differ for an identifiable actor, action, object,
scope, or authority relationship in at least one concrete governing
consequence: what is permitted, required, or prohibited; where an obligation or
prohibition applies; which exception is available; precedence and governing
authority; or whether something is binding, advisory, historical, or
superseded. Express the difference as the changed governing consequence.
Otherwise return `NO_MATERIAL_SEMANTIC_DELTA`.

Style, tone, prose elegance, emphasis, readability, and wording nuance without a
governing consequence are not reported. Ambiguity is material only when two
plausible readings produce different governing consequences under this test. No
output-count cap applies.

## `INSUFFICIENT_CONTEXT`

Return `INSUFFICIENT_CONTEXT` only when the reader cannot safely derive the
governing BEFORE-to-AFTER semantics. Name the specific unresolved semantic
dimension and the minimum concrete governing context needed, such as a named
term's definition, the scope clause governing the proposition, a named
exception, or a precedence rule between named sources. A request for general
repository context, the full specification, open-ended search, or cumulative
review is not sufficient.

The primary supplies the named raw context or declines. A decline reaches the
reader as availability, never as the primary's judgment: state only that the
context is unavailable and ask whether interpretation can complete without it.
Record the primary's reason in the run's working record without transmitting it.
Return the supplement or decline to the same fresh reader, still blind to the
expected semantics.

If that reader still cannot safely derive the semantics, the challenge is
unresolved. The same is true when supplementation requires open-ended discovery,
repeatedly exposes new authority surfaces, or cannot be reduced to finite named
context. In either case, the qualifying correction is not committed as though
the challenge passed; take the settled escalation, `Progresses`, or `failed`
route. Supplementation never ratchets toward the full trusted contract. There is
no numeric supplementation limit.

## Semantic reconciliation before candidate commit

The semantic challenge is a blocking pre-commit checkpoint. Only after
interpretation completes does the primary compare its expected semantics with
the derived semantics. Reconcile every material semantic mismatch; where that
reconciliation requires a correction, the retained implementation delegate
revises before commit and the qualifying unit is challenged again.

Where the primary cannot state the intended semantic change safely, it does not
dispatch exact wording as a substitute for understanding. Complete the slice,
open a follow-up Issue and flag it at closeout, or escalate genuine maintainer
wording judgment. Hand back `Progresses` where a safe independently useful
partial candidate stands and `failed` where it does not. This deferral is
unavailable when a named acceptance criterion would remain false or
unverifiable; that case takes `Progresses` or `failed`, never a silent follow-up.

A second semantic reader is escalation only for unresolved material ambiguity,
never routine fan-out.

## Boundaries

This mechanism makes no change to #103's Validation-surface manifest, #104/#122
validation-evidence rules, or #105's review chain. It creates no
`review-state-machine.md` gate, no Reviewed anchor, and no durable lifecycle
state. The semantic reader's existence and output never enter a cumulative or
delta package. The mechanism adds no provider analytics and no pilot
bookkeeping.
