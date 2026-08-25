# Wave-1 `/work-on` pilot protocol

Status: frozen before any real pilot run

Protocol semantic version: `3.0.0`

Authority: issue #102's original resolution as prospectively amended by
Protocol revisions 1, 2, and 3. Later revisions supersede conflicting earlier
wording. This file is the complete operative protocol; the issue record remains
its provenance.

## Freeze boundary

The wave-1 implementation candidate is the tree merged by skills PR #132 at
`5dba8b86945d4f5fac3cfab2d60e66722947f468`. The protocol commit is the commit
that first contains this file, `projection.mjs`, and `test-projection.sh`; record
that commit and the SHA-256 of `projection.mjs` on #107 before the first real
run. The commit is immutable for this pilot.

No real pilot run or controlled scenario had started when this protocol was
written. Protocol revision 3 was posted prospectively to #102 before this
freeze. Issue #131 is outside the pilot and is neither a blocker nor a selected
run.

The pilot is a small purposive decision instrument, not a statistical experiment
or universal performance benchmark. Population, classifications, and semantics
must not be changed in response to observed outcomes.

## Protocol revision 3

### Reason

Issue #130 landed through PR #132 after revision 2 and before any pilot run or
protocol freeze. It corrects evidence-phase ownership inside the existing
validation-evidence and reuse mechanism: evidence authority says what is owed;
the selected workflow says when it executes. It is not a new unrelated roadmap
or a third controlled scenario.

### Revision

For every owed command or direct-evidence obligation, the frozen observation
records its evidence identity, sources of obligation, selected-workflow owning
phase, whether phase ownership was resolved before delegation, actual execution
phase, Candidate/instrument identity, population membership where applicable,
reuse or rerun disposition, invalidating change, workflow attribution, and
source locators.

The validation-reuse success rule additionally requires all of the following:

- no eventually owed obligation executes earlier than its selected-workflow
  owning phase merely because it appears in a manifest, repository baseline, or
  scoped required-command list;
- no complete evidence population is produced before its workflow-owned
  post-stabilization phase, while narrow development cases remain available
  when genuinely needed earlier;
- later-phase obligations remain visible and are completely discharged by
  their owning gate or Closeout;
- a later change affecting only some evidence identities reruns only those
  identities while every unchanged qualifying member is reused; and
- exact #104/#122 sufficiency, invalidation, and reuse semantics otherwise
  remain unchanged.

The falsifier is a later-phase obligation executing during implementation or
readiness without the selected workflow assigning it there; an eventual
obligation disappearing instead of remaining visible; a complete population
being produced before its workflow-owned post-stabilization phase; or a change
to only some identities forcing unchanged members to rerun.

The #129 shapes are replayed as projection fixtures so the frozen observation
must detect them. They do not become pilot outcomes and do not add a controlled
scenario. Premature execution or coarse rerun is a conclusive validation/reuse
mechanism failure under the existing result routing. A dropped obligation also
triggers the applicable Gate-1 direct-evidence or manifest failure. All other
#102 routing semantics remain unchanged.

## Frozen real-run population

Selection facts were captured on 2026-08-25 before any run. Every primary and
alternate was open, unassigned, labelled `ready-for-agent`, had zero open native
blockers, and selected the default workflow because its repository had no
`docs/workflow.md`. Repository heads at selection were:

| Repository | Default-branch SHA |
| --- | --- |
| `faviann/homelab-iac` | `93f69bc8044172900952ceda6bf5552bfc7968a3` |
| `faviann/dotfiles` | `a2cc08210864064b6890ff9c1facd8ae369d3430` |
| `faviann/skills` | `5dba8b86945d4f5fac3cfab2d60e66722947f468` |

### Primaries

| Order | Issue | Frozen Pilot cells | Pre-run justification |
| --- | --- | --- | --- |
| P1 | `faviann/homelab-iac#204` | ordinary clean / expensive deterministic validation | The ticket is a bounded expand slice. Its design evidence says all 34 affected tests passed under the fixture environment before implementation; the repository's comprehensive `./validate.sh` is a minutes-long deterministic handoff command. It is expected to be clean, but becomes the required clean observation only if it has zero accepted blocker-driven Corrective batches. |
| P2 | `faviann/dotfiles#73` | contract-dense / multi-surface remediation opportunity | The ticket establishes a foreground systemd user-service contract across rendered Nix configuration, executable/PATH and restart semantics, deliberately disabled staging, preservation of the currently running detached server, behavioral coverage, and operating documentation. That density creates a genuine ordinary, unseeded opportunity for blocker-driven correction; no defect is injected and a clean outcome still counts. Its textual blocker `homelab-iac#95` was closed before selection. |
| P3 | `faviann/homelab-iac#88` | timing/concurrency/environment-sensitive | The ticket asks whether a pinned Traefik/Redis recreation exposes a startup-order race, transient provider-watch failure, or isolated event. Independent controlled recreation and provider/route observation answer that concrete assurance question; a configuration change is permitted only after reproduction. |
| P4 | `faviann/dotfiles#96` | collection-valued Validation surface | The ticket freezes eight managed npm harness identities currently repeated across three sites. Every member must be installed and version-checked from the single source while changed command shapes and query counts remain covered, creating a finite eight-member direct-evidence population. |

### Ordered alternates

Alternates are considered in this exact order against the missing frozen cells:

| Order | Issue | Eligible frozen cells | Pre-run justification |
| --- | --- | --- | --- |
| A1 | `faviann/skills#60` | ordinary clean / expensive deterministic validation; collection-valued Validation surface | Production behavior stays unchanged while two test prototypes and a report are added, so the run is expected clean. Named scenarios include a roughly 139-second deterministic suite slice, and every prototyped scenario must be individually mutation-proved, requiring a finite manifest. |
| A2 | `faviann/skills#114` | contract-dense / multi-surface remediation opportunity; collection-valued Validation surface | The issue spans CLI contract, recursive filesystem safety, URL encoding, concurrent allocation, cleanup, black-box tests, public docs, and plugin/version validation. Its prepared tree and named path/file classes form a finite direct-evidence population. Issue #113, its textual blocker, was closed before selection. |

### Eligibility and substitution

Immediately before each `/work-on` start, record issue state, label, assignee,
native blockers, trusted contract digest, default-branch head, selected workflow,
and required-command executability. A primary or alternate is eligible only
when it remains open, unassigned, `ready-for-agent`, unblocked, contract-clear,
non-conflicting, runnable, and still satisfies every cell assigned to it here.

Substitute only when a primary becomes objectively ineligible before its run
starts: closure, assignment, open blocker, trusted-contract change, conflicting
implementation, unavailable required workflow/command, or loss of its frozen
cell facts. Record the exact fact and source. Select the first eligible alternate
whose frozen cells cover a missing cell. Keep adding ordered alternates only
until all cells are covered, never exceeding four total runs. No frozen alternate
covers the timing cell; loss of P3 therefore makes that cell `INCONCLUSIVE`
rather than admitting an observed-outcome substitute. One substitute cannot
acquire an unfrozen cell. If coverage cannot be restored within four runs, the
missing cell is `INCONCLUSIVE`.

Once a run starts, no outcome authorizes replacement, relabelling, or a new
cell. A selected opportunity run may be clean. P1/A1 supplies the required clean
observation only with zero accepted blocker-driven Corrective batches. Every
started run counts.

## Exact workflow candidate and provenance

Every real run and controlled scenario must use committed, unstarred governing
inputs whose bytes match the wave-1 candidate:

- full default-workflow identity:
  `1b3cf6d962ac8df8354f7ada1fb862dbe5c46b3102be01afa0c01ae2f0585545`;
- `work-on:a9ebf0ae3a77`;
- `workflow:1b3cf6d962ac`;
- `tdd:aa54f63292bf`; and
- `review:1dc4289fabb7`.

The canonical provenance pointer must name `faviann/skills@<protocol-commit>` or
a later commit proven to leave every declared governing input byte-identical to
the protocol commit. A `*`, custom target `docs/workflow.md`, missing component,
or differing digest makes that prospective run ineligible before start; it does
not silently create a new stratum. Each ledger entry retains the canonical
provenance string, all component digests, target base/candidate identities, and
raw provenance-ledger locator.

Controlled scenarios use disposable Git repositories with no custom workflow
under the same exact component identities. Historical references remain
explicit provenance strata and are never pooled as a control group.

## Retained controlled scenarios

These execute the actual frozen workflow in disposable repositories, preserve
raw harness/tracker/repository evidence, do not count among real runs, do not
contribute cost, and do not manufacture natural exposure. Focused tests may
supplement but never replace them.

### Validation-surface omission

The trusted contract and snapshot already require a concrete collection member,
while the frozen manifest presented after delegation omits it. Later work exposes
the pre-existing omission. Pass only when `Closes` becomes unavailable, the
manifest is not amended, no candidate remediation absorbs the member, the
member/cause/source are recorded, and the attempt durably hands back as
`Progresses` or `failed`. The fixture adds no new requirement and does not mutate
the collection after freeze.

### Normative-remediation semantics

Arm 1 creates a qualifying Corrective batch whose directive calls a governing
rewording meaning-preserving while the draft materially widens an entitlement.
Pass only when the mechanism fires despite intended delta `none`; the reader is
blind to expected semantics, rationale, finding, and adjudication; independently
derives the widened entitlement; the mismatch changes the draft before commit;
and the challenge/output enter no cumulative or delta package.

Arm 2 supplies an inadequate governing slice. Pass only when the same fresh
reader returns `INSUFFICIENT_CONTEXT` naming finite minimum context, receives a
decline only as availability, remains unable to derive safely, prevents the
correction from being committed as satisfied, and routes to the settled
escalation, `Progresses`, or `failed` hand-back.

The withdrawn convergence-exhaustion scenario and numeric guard do not run.

## Natural exposure

| Subject | Classification | Frozen observation |
| --- | --- | --- |
| P1 / A1 ordinary run | Required natural exposure | Full deterministic handoff validation and the issue's direct-evidence population occur in the ordinary lifecycle. The clean designation remains conditional on zero accepted Corrective batches. |
| P2 / A2 contract run | No guaranteed natural exposure | Contract density makes correction possible, but no accepted correction or normative correction is manufactured. Delta and normative success remain `INCONCLUSIVE` if nature supplies none. |
| P3 timing cell | Required natural exposure | Controlled pinned recreation attempts and provider/route observations execute; reproducibility is not presumed. |
| P4 collection cell | Required natural exposure | Every frozen harness member receives direct install/version-query evidence and the complete suite runs. |
| A1 collection cell | Required natural exposure | Every named prototype scenario receives isolated execution and mutation evidence. |
| A2 collection cell | Required natural exposure | Every frozen prepared-tree member/path class receives black-box direct evidence. |
| Escaped defects for every run | No guaranteed natural exposure | Quiet time is not evidence. Later source-linked escapes continue to #9. |

## Evidence authority and ledger

Authority order is raw harness transcripts; repository/GitHub artifacts; exact
Workflow provenance; Moraine after applicable import; current telemetry as
corroboration only. Historical and pilot facts use this same projection.
Telemetry never carries pilot bookkeeping. Missing values are `null`/`unknown`,
never zero.

The ledger is append-only JSON Lines accepted by `projection.mjs`. Every entry
has `entry_id`, `subject_id`, `kind`, `recorded_at`, `protocol_commit`,
`projection_version`, `projection_digest`, `workflow_provenance`, and one or
more `source_locators`. A correction names `supersedes`; it never overwrites.
The executable rejects duplicate IDs, dangling/cross-subject corrections,
unknown kinds, missing provenance, and incomplete closeouts.

An `attempt-closeout` records repository, issue, eligibility/substitution,
started/completed state, cells, exact joined run/continuation identities,
candidate/base identities, source usability, natural exposure, direct evidence,
findings, Gate-1/Gate-2 classifications, Validation-surface facts, every
validation execution and evidence-phase observation, delta topology, Corrective
batches, blocker lineage, normative-remediation facts, convergence observations,
cost/material-read facts, and the clean-run commitment where applicable.

A `controlled-scenario` records scenario identity, arms, pass/fail, Gate-1
failures, exact workflow provenance, and sources. A `maintainer-adjudication`
records the classified subject, candidate class, final class, rationale,
maintainer, date, and sources. A `pilot-decision` records the mechanically
projected result and maintainer confirmation only after all adjudications.

After every run and before the next begins, append its evidence and applicable
adjudications. Judgment-bearing calls retain source locators, projection version,
rationale, adjudicator, and date. The maintainer is final authority for rerun
justification, bounded delta expansion, causal episode linkage, substitution,
wave-1 attribution, normative classes, and proportionality. Ambiguity stays
unresolved. Corrections replay the complete corpus.

## Semantic projection

One observation is a logical `/work-on` attempt joined across continuation,
session, and telemetry segments. Causally connected successor attempts may be
grouped into one Convergence episode for observation only. No numeric
convergence threshold exists.

### Validation and evidence phase

A duplicate repeats the same Validation identity against the same still-
qualifying reusable-evidence identity: relevant Candidate content, check inputs,
artifacts, toolchain/environment, external inputs, and provenance remain valid.
After relevant invalidation it is new required execution. Classify duplicates as
justified independent execution with a concrete assurance reason, unjustified
workflow duplicate, or external/manual duplicate. Both explicit mandates and
participant discretion encouraged by ambiguous workflow instructions remain
workflow-attributable.

Record expensive executions with the projection's observational `>=60s`
primary definition and `30/60/120s` sensitivity; this is not workflow policy.
Record exact Candidate, Validation, reusable-evidence and member identities,
duration, producer, raw result, assurance question, reuse/rerun trigger, owning
phase, actual phase, population-completion time, and attribution. Revision 3's
four falsifier shapes project mechanically from these fields.

### Delta, blocker lineage, and convergence observation

A legitimate delta expansion reads unchanged context only for a recorded
minimum concrete changed-mechanism/contract question, concrete finding, or #62
same-mechanism neighborhood. Routine cumulative rereading is full-candidate
packaging or broad unchanged-context reconstruction without such a reason. No
numeric breadth cutoff is invented.

Every accepted blocker has exactly one primary cause and zero or more secondary
tags from: `remediation-introduced`, `remediation-worsened`,
`pre-existing-missed`, `sibling`, `re-raised`, `contract-or-surface`,
`delta-miss`, `cumulative-only`, `nondeterministic-environmental`, `unknown`.
Classes may overlap. `remediation-introduced` needs a directive/verdict causal
link or repository provenance placing the defect in a remediation commit;
adjacency is insufficient. `unknown` is never imputed.

Observe correction-chain length, repeated/displaced work by Convergence episode,
blocker lineage, remediation-generated defects, cost by round, human cost stops,
delta misses, and cumulative-only findings. Guard integrity, exhaustion, reset,
re-entry, premature stop, harmful budget pressure, Class A/B/C, Convergence
lifecycle, and every numeric convergence rule are withdrawn.

### Normative remediation

For each Corrective batch record qualifying governing-proposition edits,
challenge launches, derived deltas or `NO_MATERIAL_SEMANTIC_DELTA`, expected/
derived mismatch, draft change before commit, every `INSUFFICIENT_CONTEXT`
request/supply/decline, material read/cost, blindness, review-package fencing,
and qualifying-batch count.

Challenge outcome classes are `no-material-semantic-delta`,
`material-mismatch-caught-before-commit`, `insufficient-context-resolved`,
`unresolved-context`, and `false-positive`. Later same-chain recurrence classes
are `qualification-miss`, `semantic-challenge-failure`, `under-slice`,
`unrelated-recurrence`, and `unknown`. The two subjects remain separate.
`under-slice` is adverse topology evidence but not itself semantic-challenge
failure. The primary never self-certifies causal interpretation.

## Assurance gates

Gate 1 is non-negotiable. It fails on prohibited Candidate/Validation/reusable-
evidence identity crossing; governing-state or frozen-manifest violation;
broken Reviewed-anchor transition or missing required axis; blindness loss or
#62 suppression; insufficient direct evidence; unresolved hard failure reaching
`Closes`; prohibited evidence reuse; accepted Candidate without valid fresh
blind cumulative confirmation; challenge substitution for review; challenge
contamination of review packages; or a dropped owed obligation. A material
post-acceptance escaped defect linked to wave 1 or to a preserved assurance
property is also Gate 1.

Gate 2 records a final-confirmation defect that all legitimate delta axes should
have found, residual fixed cost, disproportionate challenge cost/false positive,
and material escaped defects without supported wave-1 attribution. A cumulative-
only finding outside legitimate delta scope is not a delta miss.

Every material finding records source, discovery stage, criterion/hard rule,
disposition, remediation, blocker lineage, assurance class, rationale,
adjudicator, and date.

## Mechanism success

- **Finite Validation surface:** at least one qualifying collection criterion
  materializes a complete frozen manifest before delegation; every member gets
  required direct evidence; review/#62 stay unrestricted; no post-delegation
  amendment occurs; and the omission scenario passes.
- **Validation reuse and phase ownership:** at least one qualifying expensive
  deterministic result is reused against unchanged identity; zero unjustified
  workflow duplicates occur; every extra expensive execution has an accepted
  assurance reason; warranted independent execution remains available and
  occurs; and every revision-3 requirement/falsifier is satisfied/absent.
- **Delta review:** at least one real accepted candidate correction receives all
  fresh delta axes; routine cumulative rereading does not occur between
  corrective candidates; #62 remains reachable; and the exact accepted
  candidate has valid fresh blind cumulative confirmation. With no accepted
  correction this mechanism is `INCONCLUSIVE`.
- **Normative remediation:** every retrospectively qualifying real batch invokes
  the mechanism; blindness and fencing hold; the normative controlled scenario
  passes; no `qualification-miss` or `semantic-challenge-failure` is established;
  and no challenge cost/false positive is maintainer-adjudicated
  disproportionate. With no real qualifying batch it is `INCONCLUSIVE`.

Normative mechanism failure without assurance loss precludes `PASS` but routes
`INCONCLUSIVE` to repair/removal of the experimental challenge. `under-slice`
stays adverse but does not alone fail the normative rule. Convergence is
observational only and has no mechanism status.

## Behavioral proportionality commitment

Immediately after the qualifying clean run and before viewing aggregate output,
the maintainer records `YES` or `NO` with a reason answering:

> For the next ordinary implementation issue of comparable risk and validation
> cost, would I choose `/work-on` without needing a special high-risk
> justification?

The reason addresses residual fixed review and validation overhead. Aggregate
savings cannot override `NO`; `YES` cannot override assurance failure.

## Aggregation and routing

There is no averaging or weighting. `projection.mjs` applies adverse routing
before missing-evidence routing.

`DO NOT RESUME` results from any Gate-1 failure; conclusive finite-surface,
validation/reuse/phase-ownership, or delta failure; conclusive residual-cost or
Gate-2 `NO`; or clean-run commitment `NO`.

`INCONCLUSIVE` results when no adverse rule fires but the pilot lacks 3–4
completed runs, two repositories, a cell, a retained controlled scenario pass,
usable source/provenance/projection, required natural exposure, accepted real
correction, real qualifying normative batch, or has an experimental normative
failure or result-affecting semantic revision.

`PASS` requires 3–4 completed runs across at least two repositories; every cell;
both retained scenarios; usable evidence and exact provenance; zero Gate-1
failures; every mechanism conclusively successful; and clean commitment `YES`.

Route assurance breach to implicated repair/rollback; missing opportunity only
to the missing pilot part; disproportionate clean floor to residual
proportionality without preselecting a mechanism; persistent iterative cost only
to its demonstrated mechanism; experimental normative failure to repair/removal
including operative-clause preservation reconsideration; and `PASS` to routine
`/work-on` resumption and mechanical completion of #98. No result automatically
creates wave 2.

## Projection changes

An executable bug may be fixed only without changing these semantics. Record
old/new digests and defect, replay every applicable historical/pilot source,
and retain both outputs. Any meaning change is a protocol revision. If it can
affect result, the original pilot is `INCONCLUSIVE` and requires a redeclared
evaluation; never choose the semantic version yielding the preferred result.
