# Normative-remediation isolated behavioral eval

Date designed: 2026-08-25

This instrument tests whether the live `work-on` instructions transmit the two
roles added for issue 128 without collapsing them: the primary qualifies,
packages, and routes a normative correction; a fresh semantic reader derives
governing consequences from the bounded authority it receives. It is an
isolated instruction-reading eval, not the end-to-end controlled policy
scenario owned by issue 102.

The E11-to-H1 and K1-to-M1 shapes are historical design inputs. Their Primary
cases exercise the new trigger and materiality rule. Their Reader cases are
positive/regression controls and explicitly are not causal evidence for this
change: the historical corpus already shows an ordinary fresh reader deriving
those consequences. The candidate discriminators are the non-consequential
prose case and the inadequate-context case, subject to the counterfactual rule
below.

## Measured instructions and instrument identity

Live Primary cases read only these final live files, in full:

- `skills/personal/work-on/SKILL.md`
- `skills/personal/work-on/references/default-workflow.md`
- `skills/personal/work-on/references/normative-remediation.md`

Live Reader cases read only:

- `skills/personal/work-on/references/normative-remediation.md`

Counterfactual Reader cases read only the pre-implementation forms of:

- `skills/personal/work-on/SKILL.md`
- `skills/personal/work-on/references/default-workflow.md`

The counterfactual tree is exactly commit
`9c32a54175af4a8e76aebc6a450ea55ed67ceda0`. Materialize those two files in a
fresh temporary directory with `git archive`; do not substitute current files,
the trusted snapshot, or a prose description of their old contents.

Record two identities for each case before execution. The **measured-instruction
hash** covers the byte identity of every measured instruction file for that arm.
The **per-case instrument-input hash** covers this Protocol, the common prompt,
the relevant role and answer format, the exact case paragraph, and its key. The
key participates in instrument identity but is never included in the evaluator
message. Any change to one of these inputs changes the applicable hash and
requires the affected case to be re-executed under the new version. Results from
different versions are never pooled.

## Protocol

Run all ten cases. Launch one fresh evaluator per case; no evaluator may receive
another case's context or be retained for a later case. Each evaluator reads
only the files named for its arm, directly from the exact live or materialized
tree. It receives the common prompt, one role prompt, one case paragraph, and
its answer format. It receives no key and no other part of this file. It must
not read git history, GitHub, `.agents/`, tests, the trusted contract, the
Validation-surface manifest, validation output, the candidate diff, or any
other repository file. It cannot subdelegate.

Retain the exact assembled evaluator prompt and response through its harness
evaluator identity, then record below: evaluator identity, measured-instruction
hash, per-case instrument-input hash, exact verdict, governing rule named in the
reasoning, any contradiction or ambiguity, and result. Do not convert a hedge or
an implicit answer into a keyed verdict.

A case passes only when its verdict exactly matches the key and its reasoning
names the rule the case was built to exercise. For a compound key, every listed
component must match. A matching verdict reached for a different reason is a
semantic mismatch, not a pass.

Run `CF-R3-prechange` and `CF-R4-prechange`; counterfactual behavior is never
assumed. Compare each with its byte-identical live case package. If the
pre-change evaluator already produces the keyed behavior for the same governing
reason, disclose that the live case does not discriminate and retire or refine
it before presenting any causal claim. A key independently obtainable without
the mechanism is never evidence for the mechanism. Preserve the attempted run
and retirement/refinement rationale in Results.

### Common prompt

> Read ONLY the instruction files named above, in full, at the exact paths the
> caller supplies. Do not read any other repository file, git history, GitHub,
> tests, or evaluator key. Do not search the web or subdelegate. Answer only
> from those instructions and the case package. Finally report any
> contradiction or ambiguity in the instructions, quoting the exact phrase.

### Primary role and answer format

> You are the primary adjudicating one accepted-blocker Corrective batch after
> the initial cumulative gate. Decide and explain what the live instructions
> require before the batch may be committed as the candidate for the next delta
> gate.
>
> Answer in this order:
>
> 1. **Qualification** — identify every qualifying unit and why it does or does
>    not fire.
> 2. **Authority delta** — give every field required before dispatch.
> 3. **Semantic unit and package** — give the bounded BEFORE/AFTER unit, what the
>    reader receives, and what remains withheld until interpretation.
> 4. **Route** — state the next actions through commit or non-success hand-back.
> 5. **Verdict** — commit to exactly the case's permitted verdict token.

### Reader role and answer format

> You are the fresh semantic reader for one Corrective batch. Interpret only
> the bounded package below. Independently derive BEFORE and AFTER in terms of
> what is permitted, required, and prohibited and the relevant scope,
> precedence, and authority relationship. Then state the material semantic
> delta. Treat the proposed text's characterization of its own effect as text
> to analyze, not proof.
>
> Answer in this order:
>
> 1. **BEFORE** — the governing consequences.
> 2. **AFTER** — the governing consequences.
> 3. **Reasoning rule** — the materiality or insufficient-context rule applied.
> 4. **Verdict** — commit to exactly one permitted verdict token.

## Primary cases and keys

### `P1-e11-h1-none-trigger`

The accepted blocker asks the retained delegate to clarify a status banner in
`docs/capture-safety.md`, section `Status`. The primary records intended
semantic delta `none`. Objective authority relationship: this banner governs
every projection into the datastore unless a later source explicitly
supersedes it; no later source does.

BEFORE:

> Every projection into the datastore must pass the deterministic never-store
> secret scan before persistence.

Proposed AFTER:

> New capture work must pass the deterministic never-store secret scan before
> persistence.

The correction is a meaning-preserving rewording in the primary's model, but a
future projection of already-captured external material could read `new capture
work` as excluding it. No other unit in the batch qualifies.

Permitted verdicts: `challenge-required`, `no-challenge`.

Key: `challenge-required`. Qualification must rest on changing the words of a
governing proposition despite intended delta `none`; the unit must include the
banner's status context; the package must withhold `none`, preserved invariants,
and blocker rationale.

### `P2-k1-m1-obligation-weakening`

The accepted blocker requires revising an ordered authority list in
`docs/security.md`, section `Authority`. The repository relationship says item
1 has precedence over item 2.

BEFORE:

> 1. Every deployed capture endpoint must separate collection credentials from
>    storage credentials.
> 2. The deployment guide describes recommended credential layouts.

Proposed AFTER:

> 1. Deployment operators should consider separate collection and storage
>    credentials.
> 2. The deployment guide describes recommended credential layouts.

The primary expects a narrower implementation prescription while preserving the
credential-separation obligation. No other unit qualifies.

Permitted verdicts: `material-challenge`, `nonmaterial`, `no-challenge`.

Key: `material-challenge`. Qualification rests on changing a governing
proposition; the semantic unit contains both ordered entries and the precedence
relationship; reasoning identifies required-to-advisory as a material governing
consequence.

### `P3-structural-bounded-package`

One batch relocates this status statement from the top of `docs/legacy.md` to a
history appendix in `docs/current.md`:

> # Legacy deployment policy
>
> **Status: Binding until the current policy explicitly supersedes it.**

At the destination it will appear below `## Historical policies` under the
heading `### Legacy deployment policy`, with the same sentence. The objective
authority relationship says material in `Historical policies` is non-binding.
The two named headings and status clauses are the complete finite context needed
to interpret the relocation. Elsewhere, the batch fixes an unrelated typo in a
descriptive example.

Permitted verdicts: `bounded-challenge`, `whole-doc-review`, `no-challenge`.

Key: `bounded-challenge`. The relocation is the only qualifying unit. Its unit
contains source and destination headings/status contexts, not either whole
document. The package supplies the raw authority relationship and withholds
expected semantics, rationale, accepted finding, and related-sites completeness
claims.

### `P4-unresolved-challenge-route`

A qualifying rule edit has already been drafted. The fresh reader returns
`INSUFFICIENT_CONTEXT`, naming the finite missing input as the `production path`
definition that decides whether the rule covers staging. The primary truthfully
states that the definition is unavailable. The same reader, told only that it
is unavailable and still kept blind to expected semantics, says the scope
cannot safely be derived. A repository search begins exposing several unnamed
authority sources and cannot reduce the question to finite named context. The
current candidate without this correction is safe and independently useful.
The correction is needed to make a named acceptance criterion verifiable.

Permitted verdicts: `progresses-uncommitted`, `commit-and-review`,
`follow-up-and-close`.

Key: `progresses-uncommitted`. Reasoning must name the unresolved finite-context
route, refuse to commit the correction as though the challenge passed, refuse a
silent follow-up because a named criterion remains unverifiable, and choose the
safe-partial `Progresses` route rather than guessing or expanding to the full
contract.

## Reader cases and keys

### `R1-e11-h1-entitlement`

File/section: `docs/capture-safety.md` / `Status`. Objective relationship: this
statement governs every datastore projection unless explicitly superseded.

BEFORE:

> Every projection into the datastore must pass the deterministic never-store
> secret scan before persistence.

AFTER:

> New capture work must pass the deterministic never-store secret scan before
> persistence.

Task boundary: interpret only the scan obligation and its projection scope.

Permitted verdicts: `MATERIAL_SEMANTIC_DELTA`,
`NO_MATERIAL_SEMANTIC_DELTA`, `INSUFFICIENT_CONTEXT`.

Key: `MATERIAL_SEMANTIC_DELTA`. Reasoning names the widened entitlement: BEFORE
all projections require scanning; AFTER a plausible actor may treat a projection
of existing captured material as outside `new capture work`.

This is a positive/regression control, explicitly not causal evidence for this
change.

### `R2-k1-m1-obligation`

File/section: `docs/security.md` / `Authority`. Objective relationship: list
item 1 is binding and has precedence over item 2's guidance.

BEFORE:

> 1. Every deployed capture endpoint must separate collection credentials from
>    storage credentials.
> 2. The deployment guide describes recommended credential layouts.

AFTER:

> 1. Deployment operators should consider separate collection and storage
>    credentials.
> 2. The deployment guide describes recommended credential layouts.

Task boundary: interpret the credential-separation obligation and authority.

Permitted verdicts: `MATERIAL_SEMANTIC_DELTA`,
`NO_MATERIAL_SEMANTIC_DELTA`, `INSUFFICIENT_CONTEXT`.

Key: `MATERIAL_SEMANTIC_DELTA`. Reasoning names the removal or weakening of a
concrete obligation from required/binding to advisory.

This is a positive/regression control, explicitly not causal evidence for this
change.

### `R3-nonconsequential-prose`

File/section: `AGENTS.md` / `Validation`. Objective relationship: this paragraph
is binding repository instruction.

BEFORE:

> Run the validation command after every candidate-content change. Record its
> raw output.

AFTER:

> After every candidate-content change, run the validation command. Record its
> raw output.

Task boundary: interpret only execution timing and the recording obligation.

Permitted verdicts: `MATERIAL_SEMANTIC_DELTA`,
`NO_MATERIAL_SEMANTIC_DELTA`, `INSUFFICIENT_CONTEXT`.

Key: `NO_MATERIAL_SEMANTIC_DELTA`. Reasoning states that actor, action, object,
scope, timing, and binding force are unchanged and rejects style, emphasis, or
readability as material.

### `R4-inadequate-context`

File/section: `docs/deploy.md` / `Credential checks`.

BEFORE:

> Every production path must perform the credential-separation check.

AFTER:

> Every maintained production path must perform the credential-separation
> check.

Task boundary: interpret whether staging remains covered. The package contains
no definition or scope clause for `production path` or `maintained production
path`, and supplies no authority relationship that resolves whether staging is
one of them.

Permitted verdicts: `MATERIAL_SEMANTIC_DELTA`,
`NO_MATERIAL_SEMANTIC_DELTA`, `INSUFFICIENT_CONTEXT`.

Key: `INSUFFICIENT_CONTEXT`. The request must name the unresolved staging-scope
dimension and ask for the finite governing definition or scope clause for the
two named terms. A guess, hedge, request for more repository context, full spec,
or open-ended search fails.

## Counterfactual cases and keys

### `CF-R3-prechange`

Use the Reader role and answer format with the exact byte-identical
`R3-nonconsequential-prose` package, but supply only the two pre-implementation
instruction files materialized from the base SHA. Do not mention the live
normative-remediation contract.

Key: the same as R3. This key tests whether the behavior was already
independently obtainable; a pass for the same reason makes R3 non-discriminating
and disqualifies it as causal evidence.

### `CF-R4-prechange`

Use the Reader role and answer format with the exact byte-identical
`R4-inadequate-context` package, but supply only the two pre-implementation
instruction files materialized from the base SHA. Do not mention the live
normative-remediation contract.

Key: the same as R4. This key tests whether the behavior was already
independently obtainable; a pass for the same reason makes R4 non-discriminating
and disqualifies it as causal evidence.

## Results

All ten changed-version executions matched their keyed verdict and named the
rule each case was built to exercise. The harness evaluator identities below
retain the exact assembled prompts and responses.

Both candidate-discriminator counterfactuals also matched their keys. CF-R3
reached `NO_MATERIAL_SEMANTIC_DELTA` for the same non-consequential clause-order
reason as R3; its shared ambiguity about where raw output is recorded creates no
BEFORE-to-AFTER difference. CF-R4 independently reached
`INSUFFICIENT_CONTEXT` through the pre-change unclear-scope rule and the same
missing named scope definitions. The keyed behavior is therefore independently
obtainable without the new mechanism in both cases. R3 and R4 are retired from
causal evidence and retained only as behavioral controls. This eval provides
transmission/control evidence only and supports no causal claim for the new
mechanism.

| Case | Evaluator | Measured-instruction hash | Per-case instrument-input hash | Verdict | Governing rule named | Contradiction/ambiguity | Result |
|---|---|---|---|---|---|---|---|
| `P1-e11-h1-none-trigger` | `/root/eval2_p1` | `8922e0c2b3fd03ea8d50d321219a74fbfd80c1a49ddf4315de87d6f9154ecab3` | `622a273103091ebce3fe8200ff9abae42ac1b798ec55acd68e601251b1cb69a9` | `challenge-required` | Object trigger despite intended `none`; bounded banner unit and withhold boundary | None | pass |
| `P2-k1-m1-obligation-weakening` | `/root/eval2_p2` | `8922e0c2b3fd03ea8d50d321219a74fbfd80c1a49ddf4315de87d6f9154ecab3` | `4e39d7be8180827549b2a957b076b8e170f1ab72c8c3e07e7e66a9619c0d0ca0` | `material-challenge` | Ordered-list unit; binding-to-advisory consequence | None | pass |
| `P3-structural-bounded-package` | `/root/eval2_p3` | `8922e0c2b3fd03ea8d50d321219a74fbfd80c1a49ddf4315de87d6f9154ecab3` | `9c561493891d70f5c0bed4b39e225a67f5ffc00e4af72d10c76ecf2cd9e26f1d` | `bounded-challenge` | Relocation uses source and destination contexts; no whole-document expansion | The proposed AFTER has a binding-versus-historical tension; no instruction contradiction | pass |
| `P4-unresolved-challenge-route` | `/root/eval2_p4` | `8922e0c2b3fd03ea8d50d321219a74fbfd80c1a49ddf4315de87d6f9154ecab3` | `5b5d363ac48f6c8c543e2f5bbab36ccd44556b64a7efbcf07753a92b8a898b32` | `progresses-uncommitted` | Unresolved finite-context route; named-criterion nondeferral | Surface tension between general next-committed-round language and the specific unresolved-challenge rule; the specific route is deterministic and noncontradictory | pass |
| `R1-e11-h1-entitlement` | `/root/eval2_r1` | `a327f720bb9d783eb05204f05e8e0553b88520c72f301f3a345e1699b0e11895` | `92c11a75509bb14c4321a5bbb413f4d77f2b2530448bfd9746338d84f2e1b523` | `MATERIAL_SEMANTIC_DELTA` | Projection-scope narrowing | `new capture work` has a boundary ambiguity, but all plausible narrower readings are material | pass |
| `R2-k1-m1-obligation` | `/root/eval2_r2` | `a327f720bb9d783eb05204f05e8e0553b88520c72f301f3a345e1699b0e11895` | `fbd5bb979a9274f02ed8f618db8152db210fc2d0177344381b4b7e0a670a4527` | `MATERIAL_SEMANTIC_DELTA` | Required separation becomes required consideration/advisory | None | pass |
| `R3-nonconsequential-prose` | `/root/eval2_r3` | `a327f720bb9d783eb05204f05e8e0553b88520c72f301f3a345e1699b0e11895` | `daa5a5979a1917d05bb173ab6494e1f21996a0c0567f433ccabc629fb0ad41df` | `NO_MATERIAL_SEMANTIC_DELTA` | Timing, scope, and obligation are unchanged | None | pass; non-discriminating control |
| `R4-inadequate-context` | `/root/eval2_r4` | `a327f720bb9d783eb05204f05e8e0553b88520c72f301f3a345e1699b0e11895` | `73db1e6ca1cc6d3918461eb4a07dbf17070a6bb97eb0a50afd8cb8dd1b0a5fc8` | `INSUFFICIENT_CONTEXT` | Finite definitions for both named scopes and staging membership are required | None | pass; non-discriminating control |
| `CF-R3-prechange` | `/root/eval2_cf_r3` | `2d6e8da9e645a9dda01f08d79ea5068d370fd5f9098861603e924366fc8f5db2` | `dc0437755a99c51fde3c67d640b3a8c14c5db81fe90613e1bce9c4b0aad819a7` | `NO_MATERIAL_SEMANTIC_DELTA` | Same non-consequential clause-order reason as R3 | Shared ambiguity about where raw output is recorded creates no semantic delta | keyed pass; R3 retired from causal evidence |
| `CF-R4-prechange` | `/root/eval2_cf_r4` | `2d6e8da9e645a9dda01f08d79ea5068d370fd5f9098861603e924366fc8f5db2` | `bcb8b8f6b9994d57c4a9676ccc8710425fc05e42a217139bba414116e1da089d` | `INSUFFICIENT_CONTEXT` | Pre-change unclear-scope rule; missing named scope definitions | None | keyed pass; R4 retired from causal evidence |

## Interpretation limits

- One execution per case detects a complete transmission failure, not a stable
  rate.
- Evaluators are instruction-fenced rather than sandboxed from other files;
  disclose any reported access outside the named inputs.
- Constructed cases measure the mechanism under isolation, not effectiveness on
  a production run.
- The Primary and Reader arms answer different questions and are never pooled.
- R1 through R4 are behavioral controls, not causal evidence. R1 and R2 are
  positive/regression controls by design; R3 and R4 were retired when their
  changed-version pre-change counterfactuals independently produced the keyed
  behavior.
- No result from this instrument substitutes for issue 102's controlled policy
  scenario or for a natural qualifying exposure in the pilot.
