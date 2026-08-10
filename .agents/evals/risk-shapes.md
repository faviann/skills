# Risk-shapes discrimination eval

Run this eval after changing the independent-model rules, discriminators, or worked
examples in `skills/engineering/to-tickets/RISK-SHAPES.md`. It is hand-run and
diagnostic; it enforces nothing automatically.

## Protocol

Run every case in isolation three times: 33 fresh blind evaluations in total. Never
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
A match requires the same candidate models, not merely the same count and verdict. A
right number reached from the wrong candidate set is a semantic mismatch. Never re-key
a case from its observed result.

A **targeted single-case probe** is permitted: one case, run in isolation as many times as
the question needs, to size a defect or settle an instability. Record its case, run count,
date, reference commit, and model. A probe never substitutes for the full-suite regression
required after a change to the independent-model rules, the discriminators, or the worked
examples.

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

### Case 9 — sensitivity and retention class

The slice determines a document's sensitivity — exactly one of public, internal, or
secret — from its contents. The same slice determines the document's retention class
— exactly one of transient, standard, or permanent — from its record type. Both
values are written to the document row and read back from it. Nothing expires,
deletes, or schedules on the retention class, and no export path reads the
sensitivity.

### Case 10 — capability credentials and repeat submission

The slice adds a second credential class. Existing bearer keys keep their current access,
and the new class may call only one newly added submission endpoint: it cannot call the
existing tool surface, and it cannot read stored content. An unrecognised credential is
refused before any work executes. The same slice makes submission idempotent against a
caller-supplied locator: submitting the same locator twice records nothing the second
time and reports the repeat as a repeat, while changed content at a locator already
recorded is refused without altering what is stored. Submissions are written to the
existing records table, and nothing expires, converges, or advances on its own schedule.

### Case 11 — a new access check and repeat submission

The slice adds an access check to a submission endpoint that currently performs none.
Callers keep using the one token format they already use: no second credential form is
introduced, and nothing negotiates between old and new callers. A token that is not
recognised is refused before any work executes, and a recognised caller may submit but may
not read stored content. The same slice makes submission idempotent against a
caller-supplied locator: submitting the same locator twice records nothing the second time
and reports the repeat as a repeat, while changed content at a locator already recorded is
refused without altering what is stored. Submissions are written to the existing records
table, and nothing expires, converges, or advances on its own schedule.

## Expected results

| Case | Models | Fires | Shapes and purpose |
| --- | ---: | --- | --- |
| 1 | 2 | yes | A customs determination and an independent new persistence/reconciliation lifecycle. Tests a downstream lifecycle whose correctness does not follow from its input classification. |
| 2 | 2 | yes | A priority determination and an independent concurrency protocol with a lease lifecycle. Tests a consumer whose coordination can be wrong while classification is right. |
| 3 | 1 | no | One outcome determination; response fields are its current canonical representation, with no backward-compatibility protocol. This is the no-compatibility half of the Case 7 pair. |
| 4 | 2 | yes | A sensitivity determination and an independent export-refusal authority. The threshold is a decision the three-valued determination does not contain, and the export path acts: a caller that previously received a document now receives an error. Restored to `2 / yes` by [issue #48](https://github.com/faviann/skills/issues/48) — a reversal, not a re-key; see **Case 4's key, and how it moved twice**. |
| 5 | 1 | no | One subscription-state determination; expiry is derived on read and introduces no persistence lifecycle. Tests that several outcomes and derived behavior do not become plural models. |
| 6 | 2 | yes | A hiring-stage determination and an independent new persistence lifecycle for the immutable audit trail. Tests append-only state with its own retention invariant. |
| 7 | 2 | yes | A redaction authorization/content-policy model and a backward-compatibility protocol. Tests the single clause that distinguishes it from Case 3: consumers on the previous release must still parse the representation. |
| 8 | 1 | no | One billing-state determination with several mutually exclusive outcomes. The three consumers traverse that shared determination; their plurality does not create plural models. |
| 9 | 2 | yes | Two orthogonal determinations, neither introducing a named risk shape. Tests whether a discriminator can still count a second model when the taxonomy has no shape to place it under. |
| 10 | 2 | yes | A capability-authorization model and an independent deduplication protocol. **Both halves instantiate a named shape** — the dedup half concurrency, the authorization half backward compatibility, because two credential forms coexist. Green-baseline guard, not a reproduction. Abstracted from production; see **Reality check**. |
| 11 | 2 | yes | Case 10 with the coexisting credential form removed, so the authorization half instantiates no named shape. Tests whether a reader still counts an authorization model when the taxonomy offers it no home. Keyed by argument from the deciding sentence: two determinations, neither's correctness following from the other's. |

## Case 4's key, and how it moved twice

Case 4 is a constructed case. `.agents/risk-shapes-provenance.md` maps cases 7, 8, and 10 to
production slices and maps no others, so nothing here rests on a real verdict.

Its key has moved twice, and the first move is the reason the second was needed.

**Set at `2 / fires`, by argument.** The case was written as the resource-governance slot in
a set built to vary the second model's shape, so that a worked example could not be passed by
matching one flavour of risk. Its author keyed it two before any evaluator saw it.

**Changed to `1 / no`, from observed output.** Five of six reconstruction runs returned one
model. The key was changed to match them. The file recorded that plainly at `e92a6a6`:

> One sensitivity/authorization model; refusal directly applies that determination. The
> original key said two models, but five of six blind judges converged on one: the export
> threshold introduces no separately owned question or lifecycle.

**Then the record of the change was removed.** `1d58cb8` deleted that sentence and moved the
case into a **Blocked reproduction** section. `4ffade8` — the commit that began the isolated
baseline — introduced the wording that stood until #48: *"The pre-registered key treats
refusal as the direct application of one sensitivity/authorization determination."* The key
was called pre-registered at the moment it started being used as one.

Those six runs are also the earlier population this file already sets apart; they read a
reconstructed reference, not one that shipped. Every run against a reference that shipped —
nine pre-#39 and three post-#39 — returned `2 / yes`.

**Restored to `2 / yes` by [#48](https://github.com/faviann/skills/issues/48), by argument.**
The argument comes from three keys set independently and earlier, not from the runs.

- **Case 3** (`1`) — a response body per outcome. It carries the determination's answer. It
  holds nothing, refuses nothing, and no party outside the slice constrains it; the case's
  release clause says so.
- **Case 5** (`1`) — an expiry implied by each state, derived on read. Nothing stores it and
  nothing acts on it.
- **Case 7** (`2`, corroborated in production) — a serialization that follows from the
  redaction rule and is a second model anyway, because it answers to what the previous
  release expects.

Entailment cannot be the test: case 7's serialization is entailed and still counts. What
separates case 4 from cases 3 and 5 is that its export path **acts**. The threshold is a
decision the three-valued determination does not contain — `above internal` and
`above public` were equally available — and a caller that previously received a document now
receives an error. That failure mode is not the classification's.

**Read this key with its history in mind.** It is argued, not corroborated, and it has been
wrong once. What #48 establishes is narrower than the key itself: the `1 / no` key was
adopted from evaluator output, which this file forbids everywhere else, and the record of
that was overwritten rather than kept.

## Case 9's key, and how it was set

Case 9 was added on 2026-08-08 while [issue #37](https://github.com/faviann/skills/issues/37)
was open, and its key was fixed by argument before any run and before any candidate
wording was written.

The key is **2 models / fires**. Sensitivity is determined from contents; retention
class is determined from record type. Neither value is computed from the other, so
neither determination's correctness follows from the other's, and each can be wrong
while the other is right. That is the counting sentence applied directly: more than
one independent state determination.

Neither determination introduces any of the five named shapes. Nothing expires or
schedules on the retention class, so no persistence lifecycle appears; no export path
reads the sensitivity, so no refusal authority appears. Those two clauses are
load-bearing and must not be relaxed — the first keeps the case clear of Case 6's
persistence shape, and the second keeps it clear of Case 4's unresolved authorization
question. A case 9 that gates an export on sensitivity is case 4 again.

The case therefore separates two families of discriminator that agree on every other
case. One that counts an additional candidate only when it introduces a named shape
returns 1 model here. One that counts an additional candidate when it is a distinct
state, lifecycle, or authorization model returns 2. The suite had no case that
distinguished these, so a shape-gated rule could pass all eight while systematically
under-counting.

**Read this key with its authorship in mind.** Cases 1–8 were written before any
candidate discriminator existed, so their keys cannot have been tuned to favour one.
Case 9 was written with two candidates already in view, specifically to separate them.
A case built to discriminate is at risk of being keyed toward the candidate its author
preferred. The reasoning above is recorded so a future editor can attack the key on its
merits rather than infer it from results.

## Corroborated keys and argued keys

No case here is a real slice. Every case is written in a neutral domain, and
`.agents/risk-shapes-provenance.md` maps the worked examples in `RISK-SHAPES.md` to
their sources without mapping any case in this file. But two cases are deliberate
structural abstractions of real Overmind slices, and they borrow those slices' actual
verdicts. That makes their keys corroborated rather than argued.

| Case | Abstracted from | Borrowed verdict |
| --- | --- | --- |
| 7 | *Omit binary capture bytes before persistence* — issue #153, PR #174 | Should have been split. A singular-sounding rule spanning a trust boundary and a serialization boundary. Key `2 / yes` matches. |
| 8 | The terminality counterexample — issue #154, PR #175 | Correctly stayed one ticket. One determination touching several contracts. Key `1 / no` matches. |
| 10 | *Import one Codex exchange through the capture spine* — issue #74, PR #121 | Should have been split. Shipped as one ticket across 28 files. Key `2 / yes`, and the verdict is corroborated by three blind runs against the unabstracted issue text; see **Reality check**. |

Evaluators recognised Case 7's lineage unprompted, one naming it "the *Omit binary
capture bytes* trap."

Cases 1–6 and 9 have no such anchor. They were built from the five shapes' categories,
and their keys follow from the counting sentence alone.

So the split is not grounded against invented — it is **two keys corroborated by a
production verdict that was actually made and reviewed, and seven keys resting on
reasoning**. That matters twice. Two of the four cases in the green baseline are 7 and
8, so the baseline is not merely self-consistent with the rule it tests; it agrees with
two decisions taken in production. And it prices what an anchor for Case 9 would be
worth: a real orthogonal-determination slice would make Case 9 the only case keyed
against a real outcome rather than against argument, which is a larger upgrade than it
sounds while seven of nine keys are argued.

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

## Case 4 — document sensitivity

Case 4 is scored and passes. Its key is `2 / yes`, restored by
[issue #48](https://github.com/faviann/skills/issues/48) once the provenance of the earlier
`1 / no` key was traced; see **Case 4's key, and how it moved twice** below. The observed
result against the post-#39 reference is `2 / yes` unanimously, so the case matches its key
on candidate identity as well as count and verdict.

> The slice determines a document's sensitivity — exactly one of public, internal,
> or secret. The same slice adds an export path that refuses to emit any document
> above internal, returning an error to the caller instead of the document.

**Superseded record — the pre-#39 text as it stood at `d73dd98`.** The blockquote below
reproduces this section's two prose paragraphs verbatim as they read before the post-#39
measurement; they were not contiguous in the original — the case text, unchanged and shown
above, sat between them — and they are retained as evidence of the earlier text, superseded
rather than wrong. The section's current position is the lead paragraph above, outside the
quotation.

> This case is excluded from the scored baseline until
> [issue #39](https://github.com/faviann/skills/issues/39) decides how authorization
> fits the taxonomy:
>
> Five of six reconstruction runs returned one model / does not fire. Three of three
> multi-case runs and three of three isolated runs against the finished reference at
> `e92a6a6`, plus three of three isolated controls against `d21bd3f`, returned two
> models / fires, reasoning that classification can be correct while threshold
> enforcement is wrong. The current reference does not determine which answer governs:
> the shape narrows resource governance to bounds, the discriminator adds refusal
> authority, and the deciding sentence counts authorization while no named shape covers
> it. Re-keying this case would decide #39 inside the eval rather than in the skill.

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
| 4 | 2 / yes | 2 / yes | 2 / yes | 1 / no | **stable mismatch — #39** |
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
[issue #39](https://github.com/faviann/skills/issues/39).

The green baseline is the stable subset whose model identity and verdict both match
the fixed key: Cases 1, 6, 7, and 8. Cases 2–5 remain in the eval as reproductions but
do not gate unrelated reference changes until their linked design decisions settle.
Case 9 postdates every run recorded above. Its own baseline is below; it is a stable
mismatch and joins the reproductions, not the green baseline. Case 10 also postdates them,
and its baseline puts it in the green baseline: Cases 1, 6, 7, 8, and 10.

> **Standing claims superseded.** The green-baseline membership and the "Cases 2–5 remain
> in the eval as reproductions" claim in the paragraph above, and the earlier sentence in
> this section calling case 4 "the narrower authorization-taxonomy reproduction tracked in
> [issue #39](https://github.com/faviann/skills/issues/39)", were all measured against
> `e92a6a6`. Against the post-#39 reference, cases 3 and 5 are stable passes, and case 4's
> disposition is no longer #39's: it is scored rather than blocked, and its open question
> is owned by [issue #37](https://github.com/faviann/skills/issues/37). The result table
> and prose above are retained as the `e92a6a6` record; for current standing see
> **Post-#39 re-baseline** at the end of this file.

## Pre-reorganisation control

Cases 2–5 ran in isolation three times each against the exact file at `d21bd3f`, before
the reorganisation changed heading levels, section order, or removed staged-calibration
evidence. Candidate identity, count, and verdict were all scored.

| Case | `d21bd3f` runs | `e92a6a6` runs | Comparison |
| --- | --- | --- | --- |
| 2 | 3 / yes; 2 / yes; 2 / yes | 2 / yes; 2 / yes; 2 / yes | Pre-existing semantic mismatch and count instability. Every control named priority classification, lease exclusivity, and lease expiry/recovery; two declined to count priority. The finished runs used the same wrong candidate decomposition. |
| 3 | 1 / no; 2 / yes; 2 / yes | 1 / no; 2 / yes; 2 / yes | Exact pre-existing instability. |
| 4 | 2 / yes; 2 / yes; 2 / yes | 2 / yes; 2 / yes; 2 / yes | Exact pre-existing stable mismatch; tracked in #39. |
| 5 | 1 / no; 2 / yes; 1 / no | 0 / no; 1 / no; 1 / no | Pre-existing instability. Both references disagreed about whether state and derived expiry are one candidate model; the reorganisation did not turn a stable reading into a failure. |

The control exonerates the reorganisation for every isolated defect. None of Cases 2–5
had a stable, key-matching pre-reorganisation baseline that the finished document lost.
The branch is therefore eligible to merge on the four-case green subset while #39 and
#37 track the pre-existing reference defects.

> **Standing claim superseded.** [Issue #39](https://github.com/faviann/skills/issues/39)
> has since landed. Case 4 is no longer tracked by #39: it is scored against its fixed key,
> and its open question is owned by
> [issue #37](https://github.com/faviann/skills/issues/37). The table row and closing
> sentence above are retained as the `d21bd3f`/`e92a6a6` control record; for current
> standing see **Post-#39 re-baseline** at the end of this file.

## Case 9 baseline

Run on 2026-08-08 against the live `RISK-SHAPES.md` at `b49a753`, whose content for that
file is identical to `e92a6a6` — so this baseline is comparable with the isolated
baseline above. Three fresh blind evaluators, case 9 only, no other case and no key
visible.

| Case | Run 1 | Run 2 | Run 3 | Fixed key | Classification |
| --- | --- | --- | --- | --- | --- |
| 9 | 0 / no | 0 / no | 0 / no | 2 / yes | **stable mismatch** |

**This is not a candidate-identification failure.** All three runs named exactly the two
determinations the case was built from — sensitivity from contents, retention class from
record type — and all three tested independence correctly, stating that either can be
wrong while the other is right and that they are not alternatives within one shared
determination. One recorded the two determinations in its verdict and labelled them
"advisory, not the trigger". The candidate set matches the key; only the count diverges.

The divergence is entirely the shape gate, and all three found it in the reference
unprompted. Each quoted both sides of the contradiction and each resolved it the same
way. The clearest statement of it:

> A reader who applies the definition before the discriminators gets 2 and a split; one
> who applies shapes first gets 0. I commit to shapes-first.

Two consequences worth keeping.

**A shape-gated reading returns 0 here, not 1.** The gate as evaluators actually apply
it drops the primary determination too, because a bare classification instantiates no
shape either. Any argument that a shape-gated rule "returns one model" on this case
overstates that rule's behaviour; observed behaviour is one step further from the key.

**The current wording transmits shapes-first unanimously**, not ambiguously. That makes
the transmission problem harder than a split result would have: a rewording has to
overturn a reading three of three evaluators reached independently and defended by
quotation, so a subtle patch is unlikely to move it. Reasons given were the discriminators'
unconditional "Ordinary work does not count toward the split", the shape-anchored
"the rule counts the independent models instantiating them", and the softness of "these
shapes are where independent models *usually* live".

One run also noted a gap no case had exposed: the reference has no worked example of two
determinations that each stay whole while touching no risk shape. The counterexample only
teaches how to collapse alternatives into one model. Weigh that against the recorded null
result on adding a fifth worked example, which over-taught and introduced an over-split.

### Method caveat

These three runs were subagents *instructed* not to use tools, with the reference pasted
inline, rather than evaluators with no tool access. "Told not to look" is weaker than
"could not look", and the same caveat may apply to earlier runs unless they were executed
under tighter conditions. None of the three reported using a tool, and none cited a key
or an expected answer.

A fourth run was discarded before scoring: its case text carried a stray glyph, so its
input was not identical to the other three. It returned `0 / no` and explicitly noted the
glyph and ignored it, so it corroborates the result without counting as one of the three.

## Reality check — a production umbrella

Run on 2026-08-09. Every case above is written in a neutral domain, so none of them tests
the reference against work that actually happened. This is that test, and it is the first
one this eval has ever had.

The input was the unabstracted text of a real umbrella issue — its "what to build"
paragraph and its nine acceptance criteria, verbatim apart from a removed parent link and
scope-fence section. It shipped as one ticket across 28 files and should have been
several. Three fresh blind evaluators, the live reference, no key, no other case.

| Run 1 | Run 2 | Run 3 | Should fire | Result |
| --- | --- | --- | --- | --- |
| 3 / yes | 2 / yes | 3 / yes | yes | **verdict correct and unanimous; count unstable** |

**The rule works on real umbrella work.** All three fired, and all three produced a
usable decomposition: pull the capability-scoped credential model out as a prefactor,
sequence it with a real blocking edge, and pin ownership where two proposed tickets touch
the same mechanism. One found, unprompted, that the receipt shape was claimed by two of
its own proposed tickets — the ownership-collision pattern, in a slice the reference does
not teach.

The count varied over one question: whether a stream checkpoint written *atomically* with
the record is a separate model. Run 2 folded it in, citing "a slice reaching across two
shapes carries one model when neither half can be got wrong without the other", and noted
that a checkpoint advancing on its own schedule would make it three. The other two counted
it separately. Both readings are defensible from the reference, and the verdict is
unaffected.

**All three flagged the authorization gap, unprompted and independently:**

> a reader working only from the five bullets would plausibly drop it and reach two

> would count one model here and let the slice land whole — the opposite verdict from the
> same document

> a fit of convenience, not a clean match — the taxonomy appears to be missing an
> access-control/authorization shape

That is three production-anchored reproductions of the defect tracked in
[issue #39](https://github.com/faviann/skills/issues/39).

### What this and the Case 9 baseline together show

The reference's contradiction resolves *differently depending on the slice*, and that
explains both results without either being anomalous.

- Where a slice carries shape-material — dedup, persistence, compatibility — evaluators
  trust the deciding sentence, count the authorization model, and fire correctly.
- Where a slice carries none — case 9's bare pair of classifications — the same "usually"
  hedge sends them shapes-first and they count zero.

So the realistic production hazard is not case 9. It is a slice whose *only* second model
is an authorization model, with no other shape to fire in its place. That is case 4, and
case 10 is its corroborated cousin.

### Why case 10 drops the persistence half

Case 10 abstracts this umbrella but deliberately keeps only two of its three models: the
capability-authorization model and the deduplication protocol. The persistence lifecycle
is removed, and the case says so explicitly — writes go to an existing table and nothing
advances on its own schedule.

The intent was that on the real issue, dedup and persistence fired the rule *whether or
not* authorization was counted, so a test keeping them would mask what it exists to guard.
The expectation was that with one shaped model and one shapeless one the case would
discriminate — count the authorization model and get `2 / fires`, drop it and get `1 / does
not fire`.

**The baseline falsified that expectation.** Three of three runs counted the authorization
model and returned `2 / fires` against the unamended reference. Removing the persistence
half did not starve the case of shape-material enough to provoke a shapes-first reading;
one shape was sufficient to keep readers on the deciding sentence. Case 10 therefore does
not discriminate for the authorization gap, and its role is reclassified below.

Case 10's baseline is below. It was run before any reference change, and the result
falsified the design reasoning in this section.

### Method caveat

As with the Case 9 baseline, these evaluators were instructed not to use tools rather than
sandboxed without them. A fourth run failed with a server-side error before producing
output and was relaunched with identical text; no partial result from it was scored.

One confound is inherent and worth stating: the reference's four *Oversized shapes*
examples are themselves drawn from this same production wave, so a real slice from it
shares their vocabulary. The asymmetry is what makes the result usable — a confound of
recognition can only push toward firing, so a fire is weak evidence and a failure to fire
would have been strong. In fact none of the three grounded its firing decision in those
examples; they were cited only for a collapse warning and an ownership note.

## Case 10 baseline, and what it changes

Run on 2026-08-09 against the live `RISK-SHAPES.md`, whose content was still identical to
`e92a6a6` — so this is a genuine pre-change baseline, comparable with every measurement
above. Three fresh blind evaluators, case 10 only, no key visible.

| Case | Run 1 | Run 2 | Run 3 | Fixed key | Classification |
| --- | --- | --- | --- | --- | --- |
| 10 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | **pass** |

Candidate identity matched on all three: a credential-class authorization model and a
submission idempotency/deduplication model, independent in both directions, with the
existing-table write correctly excluded as ordinary traversal and the three
new/repeat/conflict outcomes correctly collapsed into one determination.

**Case 10 is a pass, not a reproduction — which is the opposite of what it was built for.**
It was written to fail while an authorization model is uncounted, so that fixing the
taxonomy would flip it. It already passes, so it cannot show that a fix worked. Its role is
therefore a **green-baseline guard**: it records that this configuration yields `2 / fires`
today, so a later edit that drops it to `1 / does not fire` is a detectable regression.

### The pattern across every configuration tested

> **Pre-#39 argument, and one superseded fact.** This section was written before #39 landed
> and before [issue #48](https://github.com/faviann/skills/issues/48) restored case 4's key.
> "Case 4 over-counts against its key" below was true against the `1 / no` key of the time;
> against the restored `2 / yes` key those six runs are a pass. The run counts and the
> shape-material reading are unaffected, and the reasoning is retained unedited.

| Configuration | Shape-material | Reading taken | Result |
| --- | ---: | --- | --- |
| Case 9 — two bare classifications | none | shapes-first | `0 / no` ×3 |
| Case 10 — authorization + dedup | one | deciding-sentence | `2 / yes` ×3 |
| Case 4 — sensitivity + export refusal | near-fit only | deciding-sentence | `2 / yes` ×6 |
| Reality check — real umbrella | three | deciding-sentence | `2–3 / yes` ×3 |

Wherever a slice carries *any* shape-material, evaluators fall back to the deciding sentence
and count the authorization model correctly. The one configuration that under-counts carries
no shape at all, and there they under-count everything to zero rather than singling
authorization out.

**So no tested configuration shows the authorization gap causing a missed split.** Case 4
over-counts against its key; case 10 passes; the real umbrella fires correctly. What the gap
reliably produces instead is friction the reader has to resolve by hand, and a
classification filed under a shape that does not fit.

### Why the gap is still worth closing

Because the resolution is not guaranteed — it is a reader's choice the reference leaves
open, and the same evaluator population chooses differently on case 9. Every run named the
alternative explicitly before rejecting it: "A narrower reading — only listed shapes count —
would yield one model and no firing. I do not adopt it." A reader who does adopt it lands
the slice whole.

And the complaint is universal. Across the case-10 runs, the reality-check runs, and the
earlier case-4 evidence, every evaluator reported the gap unprompted, and several proposed
the same fix in their own words: add an authorization or trust-boundary entry to the shape
list, or state outright that the list is non-exhaustive.

### Mutation probe — is "usually" load-bearing?

Case 10 passes, so it cannot show a fix working. Before accepting that, the guard was
probed by mutation: does any small, *realistic* edit make case 10 go red? The candidate was
the hedge every evaluator cited when it counted the authorization model — "These shapes are
where independent models **usually** live" — deleted, so the list reads as closed. That is
exactly what an editor tightening prose would do.

Three fresh blind runs against the mutated text, case 10 unchanged. **All three still
returned `2 / yes`.** The mutation is survivable, and the runs said why.

**Case 10 supplies its own escape hatch.** All three filed the authorization model under
**backward-compatibility protocols** — "two forms coexist and something must read, write, or
negotiate both" — because case 10 adds a *second* credential class while existing bearer
keys keep their access. That is a genuine fit on the shape's own wording, so the
authorization half was never shapeless. **The expected-results rationale for case 10 was
wrong on this point and has been corrected.** One run named the remedy: "a slice introducing
a single new credential class with no legacy form to coexist with would be an authorization
model with no shape to name it." Case 11 is that slice.

**And the hedge is not the only licence.** Runs also leaned on the deciding sentence naming
authorization directly, and on "the shapes say what to inspect, and the rule counts the
independent models instantiating them" with taxonomy counts "advisory". One put it flatly:
"the count is driven by the independence test, which the reference is explicit is the
operative test."

So there are three independent routes by which a reader places an authorization model: the
backward-compatibility shape when credential forms coexist, the deciding sentence plus the
independence test, and the resource-governance near-fit through "refusal authority" — the
unscoped term #36 owns. Closing all three would mean rewriting the rule, not making a
realistic editing mistake.

**Conclusion: the reference is robust here in three redundant ways.** That is a further
argument that the authorization gap is a contradiction readers resolve rather than a defect
producing wrong splits, and it lowers the stakes of #39 again without making it not worth
fixing.

### Case 11 baseline — the gap is cosmetic, and red cannot be forced

Run on 2026-08-09 against the live reference, three fresh blind evaluators.

| Case | Run 1 | Run 2 | Run 3 | Fixed key | Classification |
| --- | --- | --- | --- | --- | --- |
| 11 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | **pass** |

**Case 11's design worked; its purpose did not.** All three runs confirmed what case 10 could
not deliver — the authorization model instantiates none of the five shapes, with the
backward-compatibility route explicitly ruled out: "no second credential form is introduced,
and nothing negotiates between old and new callers — two forms do not coexist." So the case
genuinely offers authorization no home.

All three counted it anyway, through the deciding sentence, and all three named the fork as
the one thing the verdict turns on:

> A reader who instead treats the five shapes as the closed set of countable models would
> find only B, count one, and not fire the rule. That is the single point on which this
> verdict turns, and the reference does not settle it.

### The tally across every configuration

> **Pre-#39 argument.** The run tallies and the contradiction-report claim in this section
> and the ones following it were written before the post-#39 measurement, and two of their
> facts have since been overtaken: case 4 now has nine pre-#39 runs on record rather than
> six, so the fifteen-run tally below undercounts it; and "Authorization's absence from the
> shape list is currently reported by every evaluator who meets it", in **What this means
> for validating a fix**, no longer holds — the post-#39 case-4 runs report the near-fit
> complaint is gone. The reasoning is retained unedited as pre-#39 argument; for current
> results see **Post-#39 re-baseline** at the end of this file.

Fifteen runs now bear on the authorization gap: case 4 (six), case 10 (three, plus three
against mutated text), the production umbrella (three), and case 11 (three). **Every
evaluator with an independent second model in view took the rule-first route and counted the
authorization model.** Not one under-counted it.

The only under-counting configuration on record is case 9, which carries no shape at all and
drops *everything* to zero rather than singling authorization out. That is #37's problem.

**Conclusion: the authorization gap is cosmetic across every configuration tested.** It is a
contradiction readers reliably resolve, not a defect producing wrong decompositions. Red
cannot be forced by any realistic edit — the mutation probe showed the hedge is not
load-bearing, and case 11 shows removing the shape route is not sufficient either. Producing
a red result would require stripping "authorization" from the deciding sentence and removing
the independence test's primacy, which is rewriting the rule rather than simulating a
regression.

### Case 11's standing role

Case 11 joins the green baseline: cases 1, 6, 7, 8, 10, and 11. Beyond guarding the verdict,
it is the **primary case for the contradiction-report signal**, because it isolates the fork
with no alternative shape route and all three runs named it unprompted. After a fix for the
authorization gap lands, case 11's runs should stop reporting it. If they still do, the
wording did not land.

### What this means for validating a fix

A fix for the authorization gap **cannot be validated by any case flipping**, because no case
currently fails on it. Two criteria are available instead:

1. **The green baseline holds** — Cases 1, 6, 7, 8, and 10 keep matching on candidate
   identity as well as count and verdict. Case 10's value is here.
2. **The contradiction reports stop.** The **Isolated prompt** instructs every evaluator to
   "Report any contradiction or ambiguity in the reference, quoting the exact phrase."
   Authorization's absence from the shape list is currently reported by every evaluator who
   meets it. That rate is the measurable signal: if the amended reference still draws the
   same complaint, the wording did not land.

## Post-#39 re-baseline

Run on 2026-08-09 against the live `RISK-SHAPES.md` at repo commit `d73dd98`, whose content
for that file was last changed by `fdc5cc5` — the #39 merge that added the authorization
shape. Model: `claude-opus-5`. Fifteen runs: five cases, three fresh blind evaluators each,
one case per evaluator, each receiving the **Isolated prompt** from this file, no key and no
other case visible.

This measurement exists to bring the recorded results back into correspondence with the
live reference. It re-measures only the cases whose recordings predated #39 or were never
scored against it — 2, 3, 5, 9, and 4. Cases 1, 6, 7, 8, 10, and 11 were not re-run here,
and no key changed.

| Case | Run 1 | Run 2 | Run 3 | Fixed key | Classification |
| --- | --- | --- | --- | --- | --- |
| 2 | 2 / yes | 2 / yes | 1 / no | 2 / yes | **unstable** |
| 3 | 1 / no | 1 / no | 1 / no | 1 / no | **pass** |
| 4 | 2 / yes | 2 / yes | 2 / yes | 2 / yes | **pass** |
| 5 | 1 / no | 1 / no | 1 / no | 1 / no | **pass** |
| 9 | 0 / no | 0 / no | 0 / no | 2 / yes | **stable mismatch** |

### Case 2 — candidate identity, and a changed failure mode

The key's candidate set is priority determination plus one lease model.

- Run 1 (`2 / yes`): a priority-determination-plus-per-tier-capacity model, and a lease
  model with exclusivity and expiry explicitly fused. It reached the key's count, but routed
  the priority half's countability through a *resource-governance* reading of the per-tier
  pool ("degrade rather than continue") rather than through the determination itself.
- Run 2 (`2 / yes`): tier determination plus lease ownership, with concurrency and
  persistence lifecycle explicitly fused as one model — the key's decomposition exactly.
- Run 3 (`1 / no`): the same two candidates, but it ruled tier determination *ordinary work*
  instantiating no shape, and counted only the lease model.

**Delta from the superseded recording.** The **Isolated baseline** above, measured against
`e92a6a6`, recorded `2 / yes` ×3 as a **stable semantic mismatch**: all three runs there
excluded priority classification from the counted models and split the lease model into
exclusivity and expiry/reassignment. That decomposition did not recur in any of the three
new runs. Every new run kept the lease halves fused, which is the key's reading, and every
new run treated priority determination as the candidate in question rather than discarding
it silently.

So the defect has changed character rather than disappearing: from
wrong-candidates-right-count to right-candidates-unstable-count. All three runs turn on one
fork — whether a determination instantiating no named shape counts toward the split. That
is #37's question.
The `e92a6a6` run results are retained above in **Isolated baseline**.

### Case 3 — candidate identity

The key is one outcome determination, with response fields as its current canonical
representation.

All three runs named exactly outcome determination plus canonical response body, folded the
body into the determination as its per-outcome projection, and explicitly ruled out a
backward-compatibility model by quoting the case's own release clause. Candidate identity
matches the key on all three runs, as do count and verdict.

**Delta from the superseded recording.** The **Isolated baseline** at `e92a6a6` recorded
case 3 as **unstable** (`1 / no`, `2 / yes`, `2 / yes`), and the `d21bd3f` control in
**Pre-reorganisation control** reproduced that instability exactly. Both recordings are
retained above with their commits. Case 3 is now a stable pass.

### Case 5 — candidate identity

The key is one subscription-state determination, with expiry derived on read and introducing
no persistence lifecycle.

All three runs named state determination plus expiry derivation, folded the derivation in as
per-state branches of one determination, and rejected the resource-governance reading on the
enforcement clause ("nothing acts on it"). Candidate identity matches the key on all three
runs.

**Delta from the superseded recording.** The **Isolated baseline** at `e92a6a6` recorded an
**unstable count** (`0 / no`, `1 / no`, `1 / no`); that recording is retained above. Case 5
is now a stable pass, and the `0` reading did not recur.

### Case 4 — scored against its fixed key

The key at the time of this measurement was `1 / no`: refusal as the direct application of
one sensitivity determination. [Issue #48](https://github.com/faviann/skills/issues/48) has
since restored it to `2 / yes`, so the runs recorded here are a pass. The paragraphs below
are the measurement as written, and describe the runs, not the standing.

All three runs returned `2 / yes`, naming a sensitivity determination and an independently
falsifiable export refusal authority. Each gave the same two-directional independence
argument — classification right while the gate leaks, gate right while a mislabelled secret
walks through.

**What #39 changed here, and what it did not.** Before #39 the reference had no
authorization shape, and case 4's runs filed the refusal under a resource-governance
near-fit while complaining about the gap. All three new runs file it under
**Authorization boundaries**, citing the new shape and the new discriminator's "introduces
or materially widens" line; two explicitly used the discriminator's separation of who or
what may act from how much may be consumed to reject the resource-governance filing. The
near-fit complaint is gone and the count is unchanged. #39 fixed where the model is filed,
not whether it is counted.

**Delta from the superseded recording.** No delta in count or verdict — nine pre-#39 runs
and three post-#39 runs all return `2 / yes`. The nine are those recorded in
**Case 4 — document sensitivity**: three multi-case runs, three isolated runs against
`e92a6a6`, and three isolated controls against `d21bd3f`. The six reconstruction runs
recorded in that same section are a separate, earlier population — five of them returned
`1 / no` — and are not included in the nine. The delta is in the reasoning route and in
the case's standing: the case was scored in this re-baseline and is no longer excluded, and
the exclusion condition recorded in **Case 4 — document sensitivity** is void. The key stood
at `1 / no` when this was written; #48 has since restored it to `2 / yes`.

Two of three runs still report a residual contradiction: the fail-closed shape's refusal
clause reads onto a content-policy refusal while its own headword lists only quantitative
bounds. One noted that the taxonomy still has no clean slot for a pure classification
predicate that is computed and not persisted.

### Case 9 — candidate identity

The key is `2 / fires`.

All three runs named exactly the two determinations the case was built from — sensitivity
from contents, retention class from record type — and tested independence correctly, each
stating that either can be wrong while the other is right. All three then applied the shape
gate and returned 0. Candidate identity matches the key; only the count diverges — the same
finding as the `b49a753` **Case 9 baseline**, reproduced unchanged against the post-#39
text.

**Delta from the superseded recording.** None. Adding the authorization shape did not move
this case, which is the expected result: neither of case 9's determinations instantiates it,
because no export path reads the sensitivity and nothing schedules on the retention class.

All three quoted the same contradiction — the unqualified headline sentence against "the
rule counts the independent models instantiating them" — and all three resolved it
shapes-first. One proposed the same repair the earlier baseline drew: qualify the headline
as "more than one independent model *instantiating these shapes*".

### Standing after this re-baseline

For the five cases re-measured here — 2, 3, 5, 9, and 4 — this list supersedes every
earlier enumeration of the green baseline in this file; those earlier sections predate this
measurement and were left unedited as historical record. The members not re-run in this
issue — cases 1, 6, 7, 8, 10, and 11 — carry forward on their prior record, which this
measurement neither confirms nor supersedes.

- Green baseline, unchanged and not re-run in this issue: cases 1, 6, 7, 8, 10, 11.
- Newly joining the green baseline: **cases 3 and 5**, both now stable passes on candidate
  identity as well as count and verdict.
- Reproductions: **case 2** (unstable), **case 4** (stable mismatch), **case 9** (stable
  mismatch). All three are #37's, and none is blocked on #39 any more.

> **Case 4's standing superseded.** [Issue #48](https://github.com/faviann/skills/issues/48)
> restored case 4's key to `2 / yes`, so the `2 / yes` runs above are a pass and case 4
> joins the green baseline. The reproductions are **case 2** and **case 9**. The list is
> retained as written for the record of what this measurement concluded.

### Method caveat

As with the Case 9 baseline and the reality check, these evaluators were subagents
*instructed* not to use tools, with the reference pasted inline, rather than evaluators
sandboxed without tool access. "Told not to look" is weaker than "could not look". None of
the fifteen reported using a tool, and none cited a key or an expected answer.

No run was discarded and no run errored. All three inputs within each case were identical.

## Case 2 probe — nine runs on one case

A targeted single-case probe under **Protocol**. Case 2 only. Nine fresh blind evaluators,
run on 2026-08-09 against the live `RISK-SHAPES.md` at repo commit `ae7cad8`, whose content
for that file was last changed by `fdc5cc5` — identical to the content the **Post-#39
re-baseline** measured, so the two populations pool. Model: `claude-opus-5`.

The probe exists because case 2's three-run result was `2 / yes`, `2 / yes`, `1 / no`, and
three runs cannot separate a real defect from noise. The decision rule was fixed before the
runs started: three or more of nine at one model meant a reproducible defect.

| Population | `1 / no` | `2 / yes` |
| --- | ---: | ---: |
| This probe | 6 | 3 |
| Post-#39 re-baseline | 1 | 2 |
| **Pooled, twelve runs** | **7** | **5** |

**Candidate identity matched the key on all nine runs.** Every run named a tier
determination and one lease model, and every run fused lease exclusivity with lease expiry
and reassignment — the key's own decomposition. No run split the lease. So this is a count
divergence only, the same shape as case 9's.

**Case 2 is not unstable. The majority reading is the under-split.** The superseded
`e92a6a6` recording was a semantic mismatch, and the post-#39 recording was instability with
the correct reading in the majority. Against twelve pooled runs the correct reading is in the
minority.

**Three routes lead evaluators to drop the tier determination**, all quoted from the
reference, and runs used them interchangeably:

1. The shape gate — *"the rule counts the independent models instantiating them"*, softened
   by *"these shapes are where independent models usually live"*.
2. The ordinary-work line — *"Ordinary work does not count toward the split"*, read as a rule
   about determinations rather than about work.
3. The persistence discriminator — *"Traversing persistence is ordinary"*, applied to the
   tier determination because it reads the account's plan.

Route 3 was not predicted. The discriminators sort work; evaluators applied them to a
determination, which is neither traversal nor introduction of persistence, so it fell to
*ordinary* by default.

Every run named the fork explicitly, including the three that counted correctly. The
clearest statement of it:

> Read literally, A counts and the rule fires at 2. Read through the shapes, A does not count
> and the rule stays silent.

### Method caveat

As with every baseline above, these evaluators were subagents *instructed* not to use tools,
with the reference pasted inline, rather than evaluators sandboxed without tool access. None
of the nine reported using a tool, and none cited a key or an expected answer. All nine
inputs were identical. No run was discarded and no run errored.
