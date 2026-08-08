# Risk-shapes discrimination eval

Run this eval after changing the independent-model rules, discriminators, or worked
examples in `skills/engineering/to-tickets/RISK-SHAPES.md`. It is hand-run and
diagnostic; it enforces nothing automatically.

## Protocol

Run every case in isolation three times: 24 fresh blind evaluations in total. Never
reuse an evaluator across cases. Each evaluator receives, in this order:

1. The complete live contents of `RISK-SHAPES.md`, assembled at run time. Never
   paste or snapshot that reference here.
2. The instructions under **Isolated prompt** below.
3. Exactly one case from **Cases**, with no other case visible, ending before
   **Expected results**.

Evaluators get no repository or web access and no expected answers. They must identify
candidate models before testing independence, then give the model count and verdict.
For each case, three unanimous answers matching its fixed key pass; three unanimous
answers that differ from the key are a stable mismatch; disagreement is instability.
Never re-key a case from its observed result.

## Isolated prompt

The proposed slice fits one fresh context window and closes as one reviewable pull
request, so capacity is never the reason to split.

For each slice, answer in this exact order:

1. **Candidates** — list the candidate models and the determination, lifecycle, or
   question each owns. Do this before considering independence.
2. **Independence** — test those candidates against each other and state whether
   one's correctness follows from another's.
3. **Verdict** — state the number of independent models, whether the risk rule fires
   (yes or no), and the risk shapes identified.

Report any contradiction or ambiguity in the reference, quoting the exact phrase.
Commit to one count and verdict.

## Cases

### Case 1 — classification and reconciliation

The slice determines a shipment's customs classification — exactly one of three
tariff codes — from its declared contents. The same slice adds a duty ledger: each
classified shipment accrues the duty owed under its code, and the ledger is
reconciled monthly against the carrier's customs statement, correcting entries that
disagree.

### Case 2 — priority and leases

The slice determines which of four priority tiers an incoming job belongs to, from
the submitting account's plan. The same slice adds a per-tier worker pool in which a
worker takes a lease on a job and renews it by heartbeat, so that only one worker
holds a given job at a time and a job whose lease lapses is picked up by another.

### Case 3 — payment response

The slice determines a payment's outcome — exactly one of captured, declined, or
requires-action. The same slice defines the canonical response body returned to the
caller for each outcome, including which fields appear for which outcome. Every
caller is on the current release; no older client must parse the response.

### Case 4 — document sensitivity

The slice determines a document's sensitivity — exactly one of public, internal, or
secret. The same slice adds an export path that refuses to emit any document above
internal, returning an error to the caller instead of the document.

### Case 5 — derived subscription expiry

The slice determines whether a subscription is trialing, active, past_due, or
canceled. The same slice computes the effective access-expiry instant implied by
each state: trialing expires at trial end, past_due at the grace deadline, canceled
immediately, active never. The expiry is recomputed from the state whenever it is
read. Nothing stores it, nothing schedules on it, and no job acts on it.

### Case 6 — hiring audit trail

The slice determines which of four stages a candidate occupies in a hiring pipeline.
The same slice adds an audit trail: every stage transition is appended as an
immutable record with the acting user and a timestamp, retained for seven years and
never rewritten.

### Case 7 — redaction compatibility

The slice adds one redaction rule for personal data. The rule decides which fields
may leave the service. The same rule defines how a redacted record is serialized so
that consumers running the previous release can still parse it.

### Case 8 — billing state and consumers

The slice defines how a subscription's billing state is determined. A subscription
is exactly one of trialing, active, past_due, or canceled. One predicate computes the
value. Three consumers read it: the billing runner, the notification emailer, and the
public API serializer.

## Expected results

| Case | Models | Fires | Shapes and purpose |
| --- | ---: | --- | --- |
| 1 | 2 | yes | A customs determination and an independent new persistence/reconciliation lifecycle. Tests a downstream lifecycle whose correctness does not follow from its input classification. |
| 2 | 2 | yes | A priority determination and an independent concurrency protocol with a lease lifecycle. Tests a consumer whose coordination can be wrong while classification is right. |
| 3 | 1 | no | One outcome determination; response fields are its current canonical representation, with no backward-compatibility protocol. This is the no-compatibility half of the Case 7 pair. |
| 4 | 1 | no | The pre-registered key treats refusal as the direct application of one sensitivity/authorization determination. The key remains fixed but unscored while issue #36 decides whether the reference supports it. |
| 5 | 1 | no | One subscription-state determination; expiry is derived on read and introduces no persistence lifecycle. Tests that several outcomes and derived behavior do not become plural models. |
| 6 | 2 | yes | A hiring-stage determination and an independent new persistence lifecycle for the immutable audit trail. Tests append-only state with its own retention invariant. |
| 7 | 2 | yes | A redaction authorization/content-policy model and a backward-compatibility protocol. Tests the single clause that distinguishes it from Case 3: consumers on the previous release must still parse the representation. |
| 8 | 1 | no | One billing-state determination with several mutually exclusive outcomes. The three consumers traverse that shared determination; their plurality does not create plural models. |

## Prior experiments and null results

- Rules alone scored 19/21; rules plus examples scored 21/21. Both misses were the
  redaction-with-compatibility shape in Case 7, so the examples remain load-bearing.
- Adding verdict labels produced the same 42 judgments as examples without labels.
  Baseline performance was already perfect, so this is **no benefit detected under a
  ceiling effect**, not evidence that labels can never help.
- Adding a fifth worked example about a consumed model did not help: the arm without
  it scored 18/18, while the arm with it scored 17/18 and introduced an over-split.
- Ownership-sweep wording and an ownership incident produced no measurable change
  across 27 runs in two scenarios. Both baselines were at ceiling, so the result is
  inconclusive rather than negative. The eval also tested review-mode detection while
  the skill needs generation-mode prevention; do not preserve it as a regression test
  that implies a guarantee it cannot provide.
- Across roughly 50 reference-audit complaints, no evaluator requested an external
  link, pull request, or source artifact.

## Blocked reproduction — document sensitivity

This case is excluded from the scored baseline until
[issue #36](https://github.com/faviann/skills/issues/36) decides how authorization
fits the taxonomy:

> The slice determines a document's sensitivity — exactly one of public, internal,
> or secret. The same slice adds an export path that refuses to emit any document
> above internal, returning an error to the caller instead of the document.

Five of six reconstruction runs returned one model / does not fire. Three of three
multi-case runs and three of three isolated runs against the finished reference at
`e92a6a6` returned two models / fires, reasoning that classification can be correct
while threshold enforcement is wrong. The current reference does not determine which
answer governs: the shape narrows resource governance to bounds, the discriminator
adds refusal authority, and the deciding sentence counts authorization while no named
shape covers it. Re-keying this case would decide #36 inside the eval rather than in
the skill.

## First-run correction

The first run used an out-of-scope consumed-model scenario as Case 8. Counts varied
across all three evaluators because the case named several candidate mechanisms that
the reference deliberately does not teach how to group. It was a malformed eval case,
not a discrimination finding, and was replaced by the specified billing-state case.

## Multi-case baseline

The corrected suite ran on 2026-08-08 against `RISK-SHAPES.md` at commit
`e92a6a6`, using three fresh blind evaluators and the protocol above.

| Case | Run 1 | Run 2 | Run 3 | Expected | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | pass |
| 2 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | pass |
| 3 | 2 / yes | 2 / yes | 2 / yes | 1 / no | **fail** |
| 5 | 2 / yes | 2 / yes | 2 / yes | 1 / no | **fail** |
| 6 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | pass |
| 7 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | pass |
| 8 | 1 / no | 1 / no | 1 / no | 1 / no | pass |

Case 8 now tests the intended discrimination and passes unanimously: three consumers
of one billing-state predicate do not become three models. Cases 3 and 5 failed
unanimously. Evaluators treated outcome determination versus current response mapping,
and subscription state versus derived expiry mapping, as separately falsifiable
questions even though neither second candidate instantiates a named risk shape.

Those same two case texts returned one model / does not fire in all three runs of the
first suite against the same reference commit. Their verdict therefore changed when
unrelated cases changed, so the corrected suite does not establish a green baseline.
The recurring audit explanation was the tension between “can be got wrong on its own”
and the one-model guidance for several outcomes, code paths, and failure modes.

## Isolated baseline

Run on 2026-08-08 against `RISK-SHAPES.md` at commit `e92a6a6`: eight cases,
three fresh blind evaluators per case, with no evaluator seeing another case.

| Case | Run 1 | Run 2 | Run 3 | Fixed key | Classification |
| --- | --- | --- | --- | --- | --- |
| 1 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | pass |
| 2 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | **stable semantic mismatch** |
| 3 | 1 / no | 2 / yes | 2 / yes | 1 / no | **unstable** |
| 4 | 2 / yes | 2 / yes | 2 / yes | 1 / no | **stable mismatch — #36** |
| 5 | 0 / no | 1 / no | 1 / no | 1 / no | **unstable count** |
| 6 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | pass |
| 7 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | pass |
| 8 | 1 / no | 1 / no | 1 / no | 1 / no | pass |

Case 2 is not a pass-by-count. All three evaluators excluded priority classification
from the counted models, then split lease exclusivity from lease expiry and
reassignment. The fixed key counts priority determination plus one lease model. The
same number names different models, so the result is a stable semantic mismatch.

Cases 3 and 5 isolate the missing positive test for one determination. Payment outcome
versus its current response mapping changed verdict across runs; subscription state
versus its derived, unstored expiry changed count even though every run agreed the rule
does not fire. These findings and Case 2's model-identity mismatch are tracked in
[issue #37](https://github.com/faviann/skills/issues/37). Case 4 remains the narrower
authorization-taxonomy reproduction tracked in
[issue #36](https://github.com/faviann/skills/issues/36).

The green baseline is the stable subset whose model identity and verdict both match
the fixed key: Cases 1, 6, 7, and 8. Cases 2–5 remain in the eval as reproductions but
do not gate unrelated reference changes until their linked design decisions settle.
