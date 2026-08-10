# Do not add a short correctness-contract boundary rule

**Status: accepted, 2026-08-10.** Six boundary-rule drafts and one separate
shape-scoping repair were attempted between 2026-08-09 and 2026-08-10, and none
shipped. No eval was run for any of them and no wording in `RISK-SHAPES.md` was
changed; each was killed by construction. This ADR records the decision to stop
iterating on either approach, and the evidence that makes that decision defensible
rather than merely tired.

## The problem

`RISK-SHAPES.md` defines the counted unit negatively: _"A model is
**independent** when it can be got wrong on its own — its correctness does not
follow from another's."_ It also says one model may have several outcomes, code
paths, and failure modes, and that alternatives within one shared determination
count once. It never says what makes a shared determination one determination.

[Issue #37](https://github.com/faviann/skills/issues/37) asked for the positive
test: what identifies one correctness contract, _before_ independence is applied
to it. Without it, a reader cannot tell where the first contract ends, and the eval
measured that as instability rather than as a reasoned disagreement.

## Considered options

### Six boundary rules, all failing through undecidable application

Each defined the boundary of one contract, then sorted the remaining candidates
against it. Each reproduced the eleven eval keys when applied by an author who
already knew them. **Each then failed on a case-independent counterexample** — a
slice on which the rule returns a count its author would not defend. Some of those
counterexamples came from cold review and some from the author's own re-checking;
the record does not claim a uniform review process.

**Every counterexample answer below is argued, not measured.** None was put to a
blind evaluator. Each rests on the argument stated beside it.

| Draft | What it keyed on                         | The counterexample that killed it                                                                                                                                                                                                                                                                                                                                                               |
| ----- | ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Outside input, refusal, own state        | A current-release response echoing a caller's correlation value: an input the determination does not contain, deciding nothing. Returned 2; correct answer 1. The draft also stated no precedence between its limbs                                                                                                                                                                             |
| 2     | Copy versus compute                      | A current-release response localized from `Accept-Language` and a translation catalogue. Returned 2; correct answer 1. Dropping the state limb also cost case 6 the limb that carried it                                                                                                                                                                                                        |
| 3     | One question, one input, one state space | Tax owed from an amount **and** a jurisdiction: two inputs, one determination. Returned 2; correct answer 1                                                                                                                                                                                                                                                                                     |
| 4     | Attach-or-add with a refusal limb        | Case 10 double-counts — its gate refuses while its credential determination is already counted — appearing to yield 3 against a key of 2                                                                                                                                                                                                                                                        |
| 5     | Phase-of-a-counted-model                 | Rebuilt draft 4's defect: case 10's gate refuses, so the clause denied it phase status and returned 3                                                                                                                                                                                                                                                                                           |
| 6     | Attachment by default, with three limbs  | _Discover stable child rollout streams_ — the reference's own worked example, counted at three — dropped to 1, because migration and convergence each hold no store, refuse nothing, and emit to nobody. Case 8's serializer also fired the third limb against a production-corroborated key of 1, and no case-independent reading of "contains" places cases 4 and 10 where their keys require |

Two properties recur across all six, and they are the finding rather than the
individual counterexamples.

**Each draft grew a limb, and each new limb broke a case the previous version
held.** Six rounds produced no convergence in length or in coverage.

**Each reproduced the keys only with the expected decomposition already in hand.**
That is the defect a blind eval exists to catch, and it is invisible from the
inside: the author reads the answer off material the rule does not contain, then
credits the rule. Drafts 5 and 6 were both written by an author who had just
recorded that this was the failure mode, and both did it anyway.

A further finding, recorded because it prices what any future rule must do: **no
short general rule produced case 4 at two while keeping cases 3, 5, and 8 at one.**
All four are total functions of a determination. Every draft needed a special
clause for case 4's refusal, and every such clause broke something else.

### A separate shape-scoping repair, failing through split-instability

This was deliberately not a boundary rule. It proposed scoping the migration
shape to state that predates the slice, on the evidence that both blind runs
reaching three on eval case 1 had built their third candidate out of that bullet:

> **Migration and convergence models** — data or running instances that exist
> before the slice lands must arrive at a new form; correctness depends on what was
> already out there. State introduced by the slice does not instantiate this shape,
> even if it later converges or is reconciled.

It passed the then-eleven-case construction check and kept _Discover stable child
rollout streams_ at three. It was killed by a property none of the boundary rules
had.

**The counterexample.** A slice introduces a canonical event envelope and moves
ingest onto it, and the same slice adds a converger that rewrites any envelope not
yet in canonical shape — including envelopes the new writer emits during a staged
rollout. Every envelope in scope was introduced by this slice, so the proposal
denies the converger the migration shape, and the persistence discriminator reads
writer and converger as one introduced lifecycle. The proposal returns 1. **The
answer of 2 is argued, not measured** — no evaluator was run on this slice; it is a
constructed counterexample, and its correctness rests on the argument that the
writer can be correct while the converger strands envelopes or is non-idempotent
across re-runs, and the converger can be correct over a writer whose shape was
wrong from the start.

**Why that is worse than a wrong case.** Split the same work into _add writer_ then
_add converger_, and the identical converger now instantiates the shape, because
the writer's envelopes pre-exist it. Same code, opposite verdict, decided by the
split the rule was being used to compute. **A rule for deciding how to split work
cannot change its answer because the proposed split boundary changed** — and this
one changes it in the direction that rewards leaving a slice whole, which is the
under-split the risk rule exists to catch.

Three further findings stand with it:

- **"Before the slice lands" has a referent but not a stable one.** The shapes are
  consumed at decomposition time, while the slice's boundary is the open question.
  Under expand-contract migration the phrase also excludes exactly the window —
  after cutover, before backfill completes — where migration defects live.
- **The second sentence was new policy, not a clarified qualifier.** The bullet is
  founding design from `9f3515c` and its qualifier _"correctness depends on what
  was already out there"_ was present from the first day. But that qualifier says
  positively when the shape fires; it licenses no exclusive reading. `9f3515c`'s
  own worked example counts _upgrade convergence_ on grounds of convergence
  failure, not of pre-existence.
- **As scoped it could not pass an isolated full-suite gate.** It moves neither
  case 2 nor case 9, both of which stand as reproductions against the live
  reference, so the then-all-eleven pass condition was unreachable for it in
  isolation.

### Keep iterating

Rejected. Six boundary rules and one separate shape-scoping repair produced at
least ten distinct defects, with no reduction in either the rate of new
counterexamples or the length of the candidate. Each round's fix created the next
round's failure. The marginal return is negative and there is no test that tells
you when a discriminator is right — only whether readers happen to apply it.
Another draft would be tuned rather than argued.

## Decision

- **No short, case-independent boundary rule for one correctness contract is added
  to `RISK-SHAPES.md`.** The reference keeps its negative definition of
  independence and says nothing positive about where one contract begins.
- **The three-property observation is recorded as evidence, not promoted to a
  rule.** For a candidate that is not itself a determination, the split between
  the keys of 1 and the keys of 2 tracks whether it **holds state**, whether it can
  **refuse**, and whether it must **satisfy a party outside the slice**. Cases 3, 5,
  and 8 have none of the three; cases 1, 4, 6, and 7 each have one. It reproduced
  every key across the four construction rounds in which it was checked and was
  never broken on its own substance.
- **It is not a rule for two stated reasons.** _Attach-or-add_ is unresolved: when
  a property fires, nothing says whether the reader adds a contract or attaches
  the candidate to one already counted, and case 10 is the standing instance. And
  _"outside party"_ is undefined: every API response satisfies an outside caller,
  and nothing states why case 3 sits at 1 while case 7 sits at 2 beyond case 3's
  release clause. Drafts 4, 5, and 6 each died on the first of these.
- **Categorical exclusion by pre-slice provenance is ruled out.** A rule that
  denies a candidate a shape _because the state it acts on was introduced by this
  slice_ is unstable under the split it is used to compute. This is narrow: it
  does not condemn every rule that mentions introduced state — the persistence
  discriminator's existing introduced-versus-traversed line is untouched and
  remains in force.

## Consequences

- The boundary stays open. A reader of `to-tickets` still has no positive test,
  and the reference still supplies material on both sides of the
  persistence-versus-migration fork — three of six blind evaluators reported that
  ambiguity unprompted on 2026-08-10, one adding that _"the sentence bears
  tightening"_. **That defect is real, unrepaired, and now known not to be fixable
  by editing the migration shape.** It lives in candidate independence and
  attachment, not in a shape heading.
- **The eval's case 1 was narrowed as an instrument, measured, and retired.** Its
  version-2 clause narrowed reconciliation to entries created by the ledger and no
  separate reconciliation state. It cleared cold construction review, then
  returned `7 × 2, 2 × 3` against a key of 2 over nine valid runs. It was retired
  from the scored suite by an explicitly post-measurement decision. The clause
  narrowed the mechanism; it did not repair the reference ambiguity. Case 6
  preserves the downstream-lifecycle coverage case 1 was built to test.
- **The scored baseline is coherent over ten cases.** Case 8's current probe
  returned `1 / no` ×9 with correct candidate identity. With case 1 retired, every
  scored case has a scoreable standing. Coherent does not mean all green: cases 2
  and 9 remain reproductions against the live reference and are expected to move
  only under #50's parked change.
- Every future boundary proposal must resolve **attach-or-add**. Every future
  boundary or shape-scoping proposal must be **stable under splitting** — the same
  work must receive the same count whether it is assessed whole or in parts. A
  proposal that uses the three-property observation must also define **"outside
  party"**.
- The vocabulary rename recorded in `CONTEXT.md`'s **Flagged ambiguities** — from
  _independent model_ to **correctness contract** — was scheduled to land with
  #37's discriminator wording. No such wording is landing, so the rename needs its
  own occasion and its own full-suite pass under the then-current **Protocol**. It
  does not become due here.
- With the probe record and ten-case Protocol landed, this ADR completes #37's two
  deliverables: the boundary investigation has an accepted negative disposition,
  and the scored suite has a coherent baseline. Close
  [#37](https://github.com/faviann/skills/issues/37) after this ADR and its eval
  pointer land. Closing the investigation does not claim that a positive boundary
  rule now exists.
- This decision is reversible on new production evidence, a measured failure
  traceable to the missing boundary, or a proposal satisfying the applicable bars
  above without another case-tuned limb.
