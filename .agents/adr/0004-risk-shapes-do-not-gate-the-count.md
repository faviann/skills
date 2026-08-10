# Risk shapes do not gate the count

**Status: accepted**, 2026-08-10. Narrow in scope, and deliberately narrower than [ADR 0003](./0003-risk-shapes-are-diagnostic-not-the-counting-gate.md), which stays rejected.

`to-tickets` splits a slice that introduces more than one independently failure-prone unit. `RISK-SHAPES.md` lists six **risk shapes** and, until this decision, also told the reader to count only the models instantiating them. That gate is removed. The shapes say where to look. They do not decide what is counted.

## What changes

Two words are deleted from the deciding paragraph:

> the shapes say what to inspect, and the rule counts the independent models ~~instantiating them~~

And one paragraph is added after it:

> Count the determinations the slice introduces, whether or not they instantiate a listed shape. The discriminators sort work; they do not decide whether a determination counts.

The six shapes are unchanged. No worked example is added — the recorded null result on a fifth example stands, where the arm with it scored 17/18 and introduced an over-split.

## The deleted words were deliberate design, not a drafting error

`git log -S "instantiating them"` returns `99e164d`, the commit that created the risk rule. The clause was written there in one piece, and every later commit carried it forward unchanged. So this is a **reversal of a founding design choice**, and it is recorded as one.

That provenance also explains the measurements. Readers resolve toward the gate because the gate is what the document says. The eval's case 9 baseline recorded three of three evaluators reaching a shapes-first reading independently and defending it by quotation. They were reading the design as written.

## Why it is reversed now

The earlier evidence was case 9 — two orthogonal determinations, keyed `2 / fires` by argument, measured at `0` across two references. ADR 0003 leaned on it and was rejected for doing so: the key is argued rather than corroborated, the case was authored with candidate rules already in view, and no production slice has ever resembled it.

The new evidence is **case 2**, and it is a different kind of case. A priority determination plus a job lease is ordinary work, not a case built to discriminate.

| Population | Date | Reference | `1 / no` | `2 / yes` |
| --- | --- | --- | ---: | ---: |
| Post-#39 re-baseline | 2026-08-09 | `d73dd98` | 1 | 2 |
| Targeted nine-run probe | 2026-08-09 | `ae7cad8` | 6 | 3 |
| **Pooled** | | | **7** | **5** |

Model `claude-opus-5` throughout. The two populations read identical reference content, so they pool.

Candidate identity matched the key on all nine probe runs: a tier determination plus one lease model, with exclusivity and expiry fused. No run split the lease. The divergence is count only, and the under-split is now the **majority** reading of an ordinary slice.

Under-splitting is the failure the rule exists to catch. `9f3515c` created it because "slices that cleared both [capacity budgets] still landed several independently failure-prone production contracts at once." Over-splitting wastes effort; under-splitting ships the defect.

The probe also exposed a third route into the gate that no earlier measurement had shown. Evaluators disqualified the tier determination through the **persistence discriminator** — "Traversing persistence is ordinary" — because the determination reads an account's plan. The discriminators sort *work*; a determination is neither traversal nor introduction, so it fell to *ordinary* by default. That is why the added paragraph names the discriminators explicitly rather than only the shapes.

## The reversal is narrow

Three things this decision does **not** do.

- **It does not demote the taxonomy.** ADR 0003 proposed making the shapes diagnostic *and* renaming the counted unit to **correctness contract** across roughly 60 sites. That ADR stays rejected. Only the counting gate is removed here.
- **It does not rename anything.** The prose keeps *independent model*. `CONTEXT.md` still records the pending rename under **Flagged ambiguities**.
- **It does not define a determination.** See below.

## The positive boundary stays unresolved

[Issue #37](https://github.com/faviann/skills/issues/37) asks for a positive test that identifies one determination before independence is tested. This decision does not supply one, and the attempt is recorded rather than hidden.

Four successive drafts were checked against all eleven eval cases and against constructed counterexamples. Each reproduced the keys and then failed:

| Draft | Failed on |
| --- | --- |
| Outside-input plus refusal plus own state | A response echoing a caller's correlation value; no stated precedence between limbs |
| Copy versus compute | A response localized from a translation catalogue; case 6 lost the limb that carried it |
| One question, one input, one state space | A tax owed from an amount *and* a jurisdiction — two inputs, one determination |
| Attach-or-add, with a refusal limb | Case 10 double-counts: its gate refuses, and its credential determination is already counted |

Every failure sat in the same place — the boundary of one determination — and every fix needed another boundary rule. Four rounds is enough evidence to record that the boundary does not reduce to a paragraph, and to stop.

So `RISK-SHAPES.md` now tells a reader to count determinations without telling them where one ends. That is a real gap, and it is smaller than the one it replaces: a reader who mis-draws a boundary makes a judgement, while a reader following the gate drops a determination the rule was written to count.

## Consequences

- **Cases 2 and 9 must move to their keys**, and no case may move away from its key. The change is gated on a full 33-run isolated pass in which all eleven cases return three unanimous key-matching results with correct candidate identity. Any mismatch, instability, over-split, under-split, or green-baseline drop rejects and reverts it.
- **Cases 3, 5, and 8 are the over-split guard.** Nothing in the added paragraph stops a reader promoting a response body, a derived expiry, or a consumer to a determination. They pass today; if they stop passing, the change caused it.
- **`SKILL.md` and `docs/engineering/to-tickets.md` were checked and need no prose change.** Both already state the rule without a gate — `SKILL.md` calls the counted unit "a state, lifecycle, or authorization model that can be got wrong on its own", and the docs page says a slice "that introduces more than one independent state, lifecycle, or authorization model gets split". `SKILL.md`'s paragraph is deliberate fork-authored wording hoisted by `5dd5609` and `99e164d`, and it is left untouched.
- **`CONTEXT.md` gains *Determination* under Flagged ambiguities**, not as a headword. The term becomes load-bearing in the counting rule while its boundary stays unresolved, and a glossary entry written before the decision settles records the drift it exists to stop.
- **[#37](https://github.com/faviann/skills/issues/37) stays open**, holding the boundary question and the four-round record.
