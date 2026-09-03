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

### Canonical byte recipe

`scripts/eval-canonical-identity.sh` is the one executable definition of this
identity. It takes `LABEL CANONICAL_NAME PATH` triples and prints the SHA-256 of
a canonical byte stream that frames each component as its label, its canonical
repository-relative name, its byte count, and its exact bytes, every field
NUL-terminated, in the declared order. Do not reimplement that framing here or
anywhere else; invoke the script. Run the following from the repository root.

```bash
set -euo pipefail

eval_file=.agents/evals/work-on-normative-remediation.md
base=9c32a54175af4a8e76aebc6a450ea55ed67ceda0
identity_dir="$(mktemp -d)"
trap 'rm -rf "$identity_dir"' EXIT

extract_section() {
  local heading="$1" output="$2"
  awk -v heading="$heading" '
    $0 == heading { inside = 1 }
    inside && $0 != heading && /^#{1,3} / { exit }
    inside { print }
  ' "$eval_file" >"$output"
}

mkdir "$identity_dir/prechange"
git archive "$base" -- \
  skills/personal/work-on/SKILL.md \
  skills/personal/work-on/references/default-workflow.md \
  | tar -x -C "$identity_dir/prechange"

printf 'live-primary %s\n' "$(scripts/eval-canonical-identity.sh \
  instruction skills/personal/work-on/SKILL.md \
    skills/personal/work-on/SKILL.md \
  instruction skills/personal/work-on/references/default-workflow.md \
    skills/personal/work-on/references/default-workflow.md \
  instruction skills/personal/work-on/references/normative-remediation.md \
    skills/personal/work-on/references/normative-remediation.md)"
printf 'live-reader %s\n' "$(scripts/eval-canonical-identity.sh \
  instruction skills/personal/work-on/references/normative-remediation.md \
    skills/personal/work-on/references/normative-remediation.md)"
printf 'prechange-reader %s\n' "$(scripts/eval-canonical-identity.sh \
  instruction skills/personal/work-on/SKILL.md \
    "$identity_dir/prechange/skills/personal/work-on/SKILL.md" \
  instruction skills/personal/work-on/references/default-workflow.md \
    "$identity_dir/prechange/skills/personal/work-on/references/default-workflow.md")"

extract_section '## Protocol' "$identity_dir/protocol"
extract_section '### Common prompt' "$identity_dir/common"
extract_section '### Primary role and answer format' "$identity_dir/primary-role"
extract_section '### Reader role and answer format' "$identity_dir/reader-role"

cases=(
  P1-e11-h1-none-trigger
  P2-k1-m1-obligation-weakening
  P3-structural-bounded-package
  P4-unresolved-challenge-route
  R1-e11-h1-entitlement
  R2-k1-m1-obligation
  R3-nonconsequential-prose
  R4-inadequate-context
  CF-R3-prechange
  CF-R4-prechange
)
roles=(primary primary primary primary reader reader reader reader reader reader)
packages=(
  P1-e11-h1-none-trigger
  P2-k1-m1-obligation-weakening
  P3-structural-bounded-package
  P4-unresolved-challenge-route
  R1-e11-h1-entitlement
  R2-k1-m1-obligation
  R3-nonconsequential-prose
  R4-inadequate-context
  R3-nonconsequential-prose
  R4-inadequate-context
)

for index in "${!cases[@]}"; do
  case_id="${cases[$index]}"
  package_id="${packages[$index]}"
  role_file="$identity_dir/${roles[$index]}-role"
  extract_section "### \`$package_id\`" "$identity_dir/$case_id-package"
  extract_section "### \`$case_id\`" "$identity_dir/$case_id-case"
  components=(
    protocol '## Protocol' "$identity_dir/protocol"
    common '### Common prompt' "$identity_dir/common"
    role "${roles[$index]}" "$role_file"
    package "$package_id" "$identity_dir/$case_id-package"
  )
  if [[ "$case_id" != "$package_id" ]]; then
    components+=(counterfactual "$case_id" "$identity_dir/$case_id-case")
  fi
  printf '%s %s\n' "$case_id" \
    "$(scripts/eval-canonical-identity.sh "${components[@]}")"
done
```

For an ordinary case, its package section includes the case paragraph and key.
For a counterfactual, the stream includes both the referenced live Reader
package section and the counterfactual section carrying its key. Thus the hidden
key is covered without entering the assembled evaluator message. A changed
instruction file affects its arm; a changed shared section affects every case
that includes it; a changed case or key affects only that case. Re-execute
exactly those affected cases.

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
and blocker rationale. The answer must give all five Authority-delta fields: the
governing proposition or relationship and location, current governing meaning,
intended resulting meaning, constraints expected to survive, and related
governing sites considered with how they were identified; open-ended site
discovery must carry no completeness claim. Only after interpretation may the
primary compare expected and derived semantics. The derived material mismatch
requires the retained implementation delegate to revise, followed by a fresh
semantic challenge of the revision before commit.

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
consequence. The answer must give all five Authority-delta fields: the governing
proposition or relationship and location, current governing meaning, intended
resulting meaning, constraints expected to survive, and related governing sites
considered with how they were identified; open-ended site discovery must carry
no completeness claim. Only after interpretation may the primary compare
expected and derived semantics. The derived material mismatch requires the
retained implementation delegate to revise, followed by a fresh semantic
challenge of the revision before commit.

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

The recorded changed-version population comprised eight live plus two prechange
counterfactual executions (ten total). Every verdict matched its current key and
named the rule the case was built to exercise. P1 and P2 were re-executed after
their keys changed. The other eight evaluator prompts and case/key inputs are
byte-unchanged; their identity columns were recalculated under the newly
specified canonical recipe rather than pooled from different inputs. The
harness evaluator identities below retain the exact assembled prompts and
responses.

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
| `P1-e11-h1-none-trigger` | `/root/eval3_p1` | `44fd4d5414490148b0a5ee4fe73305dc5d5fb772f5952b1d62e704b78ce36d61` | `8150afe33d4f7e4d99fc305e62cdd4bbb43113584c1d5f79bd8c9259bed353a8` | `challenge-required` | Qualification despite intended `none`; all five Authority-delta fields with bounded/no-completeness site treatment; status-context unit/package/withholds; compare, retained-delegate revision, and fresh rechallenge before commit | No instruction contradiction; `New capture work` ambiguously excludes future projections | pass |
| `P2-k1-m1-obligation-weakening` | `/root/eval3_p2` | `44fd4d5414490148b0a5ee4fe73305dc5d5fb772f5952b1d62e704b78ce36d61` | `dcedf7c4feb072e37090d9e775074523d54ad34685a1c5efbd7bc8a78e79eeda` | `material-challenge` | Required-to-advisory weakening; all five Authority-delta fields with bounded/no-completeness site treatment; ordered entries and precedence; compare, retained-delegate revision, and fresh rechallenge before commit | No instruction contradiction; narrower replacement wording remains underspecified but routes to revision | pass |
| `P3-structural-bounded-package` | `/root/eval2_p3` | `44fd4d5414490148b0a5ee4fe73305dc5d5fb772f5952b1d62e704b78ce36d61` | `0d90c30bef96299aa61bf93e9671309a220d169a6e8d0f5b81d07d87aabb676c` | `bounded-challenge` | Relocation uses source and destination contexts; no whole-document expansion | The proposed AFTER has a binding-versus-historical tension; no instruction contradiction | pass |
| `P4-unresolved-challenge-route` | `/root/eval2_p4` | `44fd4d5414490148b0a5ee4fe73305dc5d5fb772f5952b1d62e704b78ce36d61` | `565530ca164ffb1b3b7b906f8446dfc44ae8d3b5c00eaefa178bd79118d07989` | `progresses-uncommitted` | Unresolved finite-context route; named-criterion nondeferral | Surface tension between general next-committed-round language and the specific unresolved-challenge rule; the specific route is deterministic and noncontradictory | pass |
| `R1-e11-h1-entitlement` | `/root/eval2_r1` | `cfc3bdd8743cd42c98d5ac69f5c4cf6d23198251437d46d419987d978e0ec6fc` | `8b348fcc3359cbcf94cffce3b15e88e8f3820bc671e781e66013cfbdc1d4534b` | `MATERIAL_SEMANTIC_DELTA` | Projection-scope narrowing | `new capture work` has a boundary ambiguity, but all plausible narrower readings are material | pass |
| `R2-k1-m1-obligation` | `/root/eval2_r2` | `cfc3bdd8743cd42c98d5ac69f5c4cf6d23198251437d46d419987d978e0ec6fc` | `f0c5e80f1d6a3c03d71ae119a74dc0c42b3f767dc5c30dcf7bfcd27dce089db6` | `MATERIAL_SEMANTIC_DELTA` | Required separation becomes required consideration/advisory | None | pass |
| `R3-nonconsequential-prose` | `/root/eval2_r3` | `cfc3bdd8743cd42c98d5ac69f5c4cf6d23198251437d46d419987d978e0ec6fc` | `4ddb64d9ab7779766bfe3cf745de0e18524e79fd9c6372f22799b5bd0fafada6` | `NO_MATERIAL_SEMANTIC_DELTA` | Timing, scope, and obligation are unchanged | None | pass; non-discriminating control |
| `R4-inadequate-context` | `/root/eval2_r4` | `cfc3bdd8743cd42c98d5ac69f5c4cf6d23198251437d46d419987d978e0ec6fc` | `fcaad2e3895dc43f187eee6bbe3c9451b67a8a24e0a26bf63ed520bcf6126c28` | `INSUFFICIENT_CONTEXT` | Finite definitions for both named scopes and staging membership are required | None | pass; non-discriminating control |
| `CF-R3-prechange` | `/root/eval2_cf_r3` | `3ae4898d06dd53eb2e17c87862f62ee63865daa40b8bcb1407e3df6190df1700` | `6095ba6dd06e7a095856deada61ebe555763bf45136b58e500142456019c385b` | `NO_MATERIAL_SEMANTIC_DELTA` | Same non-consequential clause-order reason as R3 | Shared ambiguity about where raw output is recorded creates no semantic delta | keyed pass; R3 retired from causal evidence |
| `CF-R4-prechange` | `/root/eval2_cf_r4` | `3ae4898d06dd53eb2e17c87862f62ee63865daa40b8bcb1407e3df6190df1700` | `78ff79e065de26ae41f53e7cb753573d3ce12246b496557f78d670d5d58c29ac` | `INSUFFICIENT_CONTEXT` | Pre-change unclear-scope rule; missing named scope definitions | None | keyed pass; R4 retired from causal evidence |

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
