# Default work-on workflow

Required skills: `/tdd` (inside the delegated agent) and `/code-review` (invoked
by the primary).

Abort if:
- a required skill is unavailable
- the issue does not have the `ready-for-agent` label
- scope, acceptance criteria, readiness, or validation seam are unclear

References this workflow explicitly invokes are binding at their call site. Read
a conditional reference when its call site is reached rather than preloading it
at workflow startup. Its bytes are part of this run's frozen instruction
identity, so after the freeze verify the explicitly named Run identity with
`scripts/manifest-identity.sh verify --run "$RUN_IDENTITY"` before consuming
one. A mismatch takes the same fail-closed route as any other post-delegation
custody verification failure under Validation-surface manifest custody; do not
repair, refresh, or substitute the reference in-run.

## 1. Orient

Record the base SHA (`git rev-parse HEAD`) before any edit. Review uses the
state machine's direct comparison-base or Reviewed-anchor tree to the exact
Candidate tree; evidence regeneration uses the identity its check depends on.

Read the issue, trusted comments, linked parent/spec, and relevant repo docs.
Preserve unrelated user changes.

Record scope, non-scope, acceptance criteria, validation seams, every required
command and evidence obligation with its selected-workflow-derived owning
phase, and open questions. Done when the pre-implementation closability gate in
`references/closability-gate.md` passes and freezes this run's
Validation-surface manifest. A missing seam or unresolved owning phase aborts
there; it is never carried into implementation for the closure gate to
discover.

## Validation-surface manifest custody

The manifest frozen by `references/closability-gate.md` is this run's complete
direct-evidence obligation. At the start of every continuation or resume,
positively name the Run identity whose custody is intended for reuse. Ambiguity
fails closed. From the target repository run
`scripts/manifest-identity.sh verify --run "$RUN_IDENTITY"` before reuse,
whether before or after delegation. It accepts only complete custody whose
current governing-instruction identity exactly matches the captured one. A
mismatch refuses continuation outright; it is never classified as authorized
or unrelated and `/work-on` does not repair it.

Whether before or after delegation, recover the retained trusted snapshot,
manifest, and provenance for the explicitly named Run identity from the gate's
custody location. Do not refetch current trusted GitHub comments or recreate
any custody artifact from conversational memory. The verifier prints the base
SHA for the resumed workflow:

```bash
pre_implementation_base="$(scripts/manifest-identity.sh verify \
  --run "$RUN_IDENTITY")"
```

A successful verification proves that the retained snapshot and provenance
match the manifest's binding, the recorded full base SHA still names a commit,
all three files remain owner-only run-local state, and the current instruction
identity matches the captured one. A newly arrived
trusted comment does not join this frozen snapshot or invalidate it merely by
existing. Only an explicit trusted-maintainer contract change takes the
invalidation path below. Only after verification read the same snapshot and
manifest back, supply them verbatim to the implementation delegate and the
readiness context, freeze them into each review gate's Review index under
`references/review-state-machine.md`, and keep them available for
adjudication.

Before delegation, missing, malformed, corrupt, replaced, or mismatched custody
is invalid frozen preflight state: take the gate's settled complete
trusted-snapshot/Closability/freeze recomputation path. After delegation, a
custody verification failure
takes the fail-closed hand-back below because the run's contract is immutable;
do not rebuild, patch, or silently reuse it.

It bounds evidence, not scope. Implementation may touch any other artifact this
issue authorizes; readiness, both `code-review` axes, and the closure sweep may
inspect anything their own contracts already permit; reviewers may report
defects outside it; and the same-mechanism neighborhood brief below stays fully
available. A sibling reproduced outside the manifest does not enlarge it.

After delegation the manifest is immutable. A reproduced sibling, an adjacent
improvement, or a desirable defense outside it is a follow-up, never a new
member. Only evidence that the trusted criterion itself requires direct evidence
at an omitted instance invalidates it. Then:

- `Closes` is unavailable for this run;
- do not append the member, remediate it, and restart review here;
- record the criterion, the omitted instance, why the manifest was insufficient,
  and the source that exposed the requirement;
- classify it — the trusted contract already clearly required the instance (a
  preflight or workflow defect), or it did not make the population decidable (a
  contract amendment or triage question);
- create or identify a blocking tracker issue for unresolved work that must
  survive the run; and
- hand back as `Progresses` when ordinary closeout permits a safe,
  independently useful partial candidate, and as `failed` when it does not.

Frozen snapshot or manifest state that can no longer be recovered or verified
after delegation takes the same hand-back. A later attempt builds a fresh
trusted snapshot and a fresh manifest; it never inherits these objects.

Apply `references/review-state-machine.md` to every review chain. It freezes the
governing state and owns cumulative, delta, confirmation, blindness, and
invalidation semantics. The manifest custody above and
`references/validation-evidence.md` retain their stronger ownership boundaries.

## 2. Delegate implementation

Spawn a fresh subagent and give it this contract directly, populated only from
the primary's adjudicated contract and trusted snapshot:

```text
Scoped implementation contract:
- Objective: <the bounded behavior this slice must add or change>
- Acceptance criteria: <criteria this implementation round must satisfy>
- Scope: <allowed production and test surfaces>
- Non-scope: <explicit exclusions>
- Trusted snapshot: <issue body, trusted comments, and referenced contract docs>
- Raw source paths: <paths the delegate should inspect>
- Base SHA: <the primary's recorded base>
- Validation seams: <pre-agreed public boundaries and expected observations>
- Validation-surface manifest: <the frozen instances each criterion owes direct
  evidence about; it bounds evidence, not the authorized scope above>
- Validation evidence: <qualifying raw evidence and safe provenance locators;
  apply `references/validation-evidence.md` before deciding what to execute>
- Required commands and evidence obligations: <every implementation- and
  later-phase obligation, each paired with the owning phase derived from this
  selected workflow; keep later-phase obligations visible and eventually
  required>
- Authority: GitHub reads and workspace edits only. Do not refetch issue
  comments, commit, mutate GitHub, or change the contract.
- Coherence pass: <copy the complete bounded coherence-pass instruction from
  `SKILL.md`'s authority invariants>
- Completion: use `/tdd` at the named seams where possible, implement only this
  contract, run only implementation-owned obligations, perform the populated
  Coherence pass, then stop. Later-phase obligations remain visible and owed to
  their owning phases; they are not delegate-completion prerequisites.
```

The default workflow assigns implementation-owned focused evidence genuinely
needed for development to Implementation. A repository baseline, complete
direct-evidence population, or other later-phase entry remains in the scoped
contract under its resolved owner and cannot become implementation completion
merely because it is eventually owed.

The scoped contract is the delegate's complete implementation workflow. The
delegate returns only:

```text
Changed:
Evidence:
Unverified:
Risks:
```

### Same-mechanism neighborhood brief

Give the readiness sweep this brief directly, and carry it into every review
gate as part of that gate's Review-index assignment under
`references/review-state-machine.md`:
after reproducing a defect, name its mechanism and governing criterion, then
trace only its immediate neighborhood — the same boundary's branches, call
sites, and input shapes; diagnostics from the same untrusted source; or states
under the same invariant. For a failure-raising operation, enumerate its
occurrences in the same public flow and attempt the seed-shaped input at each
compatible one through its public entry point, including in-process test entry
points. Count a sibling only at a distinct branch, call site, diagnostic, or
governed state; more inputs at the seed location are reproduction evidence, not
siblings. Group the seed with minimally reproduced siblings, each with its own
location, criterion, and impact; report the seed alone when none reproduce.
State the stop boundary and stop before another criterion, subsystem, external
boundary, or speculative defense. Report reproduced instances only; the
primary retains adjudication and repair. The frozen Validation-surface
manifest accompanies this brief: it names the evidence each criterion owes, and
never limits what the sweep may inspect or report. Supply readiness with that
manifest, qualifying raw validation evidence, and
`references/validation-evidence.md` directly. Each review gate freezes the
manifest, the policy, and the qualifying evidence records into its Review
index; raw evidence stays at its safe provenance locator, where an axis
inspects it when its obligation requires. Never supply prior reviewer
conclusions, adjudications, or dispositions.

## 3. Primary checkpoint

Inspect the worktree and, unless qualifying evidence for the exact current
Candidate and Validation identity already settles their assurance question,
run affected focused checks owned by Implementation or needed to settle the
readiness question. Before the first commit, delegate one fresh
raw-artifact readiness sweep; adjudicate it once and batch
all blockers. Apply the Accepted-blocker correction self-check's dispatch rule,
owned by
`references/default-workflow/accepted-blocker-correction-self-check.md` and
read there now, to derive and include any directive-known minimum obligations,
supplying that contract's content verbatim in the dispatch rather than its
path, then send the batch back to the initial implementation delegate through
the harness's supported continuation mechanism, applying the
implementation-owner fallback in `SKILL.md`'s authority invariants when
continuation is unavailable. Re-check the returned correction through that
shared self-check's pre-commit completion rule, then re-check affected evidence
and commit normally; each later round adds a commit (no amend or squash).

After readiness corrections are complete and the commit stabilizes the exact
Candidate and Validation identity, execute the remaining direct evidence owned
by this workflow's pre-gate or initial-gate path. For a complete multi-case
population, Implementation may execute only narrow cases genuinely needed for
development; the complete population waits for this post-stabilization
transition. Apply `references/validation-evidence.md` so qualifying unchanged
members are reused and only invalidated members execute again.

After committing, status only the criteria this round claims. `tested` requires
evidence of the actual artifact and mode that would fail if the behavior — or
its timing, ordering, or bound — were violated, at every instance in that
criterion's frozen Validation surface. Record anything else as a checkpoint
directive.

On later rounds, re-check only affected criteria; do not run the full closeout
sweep.

## 4. Initial cumulative candidate gate

Enter only after the Primary checkpoint has discharged the remaining evidence
owned by the pre-gate or initial-gate path against the stabilized Candidate and
Validation identity. Later-phase evidence remains visible under its owner.

Apply the initial cumulative gate in `references/review-state-machine.md`.
Standards and Spec come from `code-review`; the closure sweep comes from
`references/github-closeout.md`. The closure table remains provisional until
final validation.

## 5. Adjudicate and remediate through delta review

Adjudicate checkpoint directives, both review axes, and closure findings
together. A directive with a mechanical seam is blocking and must be resolved
in the next committed round unless `SKILL.md`'s Fowler/baseline-smell authority
invariant leaves it advisory. If proof would require a gate-only artifact, use
the closure gate's human/escalation path instead of inventing one.

Never forward raw findings. For each blocking finding, first trace the
mechanism it concerns to an acceptance criterion; mechanism no criterion
requires is removed, not repaired. Then classify:

- **Contract-backed** — forward a precise directive naming the criterion.
- **Defensive** (guards what no criterion requires) — reject unless it names
  a criterion existing code leaves unprotected. When the primary judges a
  rejected concern a real contract gap: complete the slice, open a follow-up
  issue, flag it in the PR body; abort only when a named criterion becomes
  false or unverifiable on completion.
- **Ambiguous** — resolve against the contract; forward a specific directive.

Log one rationale line per decision in an untracked ledger at
`$(git rev-parse --git-dir)/work-on-adjudication.log`. Decisions are sticky:
dismiss re-raised findings by prior rationale unless the reviewer brings new
evidence. Reviewers never see the ledger.

Sticky adjudication has one bounded exception. When an **Ambiguous** ruling `R`
forwards a directive `D`, carry a run-local note that `D` descends from `R` and
name the frozen criterion `R` interpreted. That note is transient working state
for the immediately following delta gate only: keep no lineage store, registry,
lifecycle, event protocol, telemetry, or persistent correlation state for it,
and drop it once that gate is adjudicated.

### Implementation-mechanism reset

Remediation sometimes preserves machinery an earlier implementation approach
created instead of reconsidering the premise this blocker exposed. One bounded
reset covers both ways that surfaces, as one operation with two entries:

- **Support loop** — the blocker reaches support machinery introduced because of
  an earlier implementation approach, that support has no independent contract
  reason to survive if the approach changes, and the proposed correction would
  introduce or materially expand another state, authority, representation,
  protocol, synchronization or recovery rule, or proof or validation strategy
  principally to keep that support trustworthy rather than to enforce or observe
  the accepted contract boundary directly.
- **Accepted incompatibility** — conflicting reproduced witnesses plus a causal
  explanation show the mechanism's discriminator cannot jointly satisfy the
  required properties, or contract-distinct states are indistinguishable using
  the information available to the mechanism.

A direct correction at the accepted boundary, an ordinary helper fix, an
ordinary fixture correction, and an unrelated defect in the same subsystem
continue through ordinary remediation. Repeated blockers, complexity,
implementation size, and review count establish neither entry.

When either entry qualifies, apply
`references/default-workflow/implementation-mechanism-reset.md`, read there and
binding at this point in remediation. It owns which side may act on a qualifying
detection, the bounded instruction carried to the retained implementation
delegate, the Uphold/revise dispositions, and the prohibition on any recorded
reset artifact. Both dispositions return control to ordinary remediation here
with the accepted blocker still open.

Before dispatching the accepted blockers, apply the Accepted-blocker correction
self-check's dispatch rule, owned by
`references/default-workflow/accepted-blocker-correction-self-check.md` and read
there now, to derive and include any directive-known minimum obligations,
supplying that contract's content verbatim in the dispatch rather than its path.
Then apply `references/normative-remediation.md` to predict provisionally which
units of the Corrective batch qualify. Where at least one does, identify every
predicted unit and record its Authority delta to accompany the adjudicated
directives at dispatch; do not ask the delegate to pre-answer the entitlement
analysis. That prediction never settles entitlement, and this branch never
widens into general remediation review.

Batch all accepted blockers from one gate, with any Authority deltas, back to
the initial implementation delegate through the harness's supported
continuation mechanism, applying the implementation-owner fallback in
`SKILL.md`'s authority invariants when continuation is unavailable. For every
batch dispatched here, the retained implementation delegate keeps its `Risks:`
channel and authority relationship unchanged. That delegate may itself reach a
qualifying entry with no authorization round trip, so read
`references/default-workflow/implementation-mechanism-reset.md` at this dispatch
and supply it, together with the Implementation-mechanism reset qualification
above, as content rather than as a path. Apply the shared correction
self-check's pre-commit completion rule to the returned correction, then run
affected focused checks under the same Candidate and Validation identity rule,
applying `references/validation-evidence.md`.

Before committing the exact current candidate, perform qualification
reconciliation against the actual correction through
`references/normative-remediation.md`. Where the reconciled qualifying set is
non-empty, satisfy that reference's semantic checkpoint for every qualifying
unit before commit. Where the set is empty, proceed without a semantic-reader
package or semantic challenge. An unresolved challenge means the qualifying
correction is not committed as though the challenge passed; take the settled
escalation, `Progresses`, or `failed` route. Only a completed challenge permits
committing the normative correction as the candidate reviewed by the next delta
gate.

Apply the remediation delta loop and fresh cumulative confirmation in
`references/review-state-machine.md`. Run no full regression in the remediation
loop.
After a remediation commit stabilizes the Candidate and Validation identity,
execute only invalidated members of the pre-gate or initial-gate evidence
population; reuse every unchanged qualifying member under
`references/validation-evidence.md` before the next gate.

### Bounded re-adjudication of an Ambiguous ruling

Where a run-local `R` → `D` note is still live at that gate and an accepted
blocker there is attributable to the mechanism introduced for `D`, apply
`references/default-workflow/bounded-re-adjudication.md`, read there and binding
before ordinary remediation continues. It owns the full eligibility test, the
fresh blind non-reviewing reader, and the Uphold and Supersede outcomes. Uphold
returns to ordinary remediation; Supersede returns through the ordinary
correction, delta gate, and fresh blind cumulative confirmation path.

## 6. Closeout

At Closeout, reuse qualifying full-regression evidence for the exact final
Candidate and Validation identity when it already exists and settles its
assurance question, under `references/validation-evidence.md`; otherwise execute
the full regression there. Never pre-produce it earlier to be reused. Run
`git diff --check`. Any candidate-content or governing-input change invalidates
the applicable confirmation and returns to the review-chain rules above; new
qualifying raw evidence against the exact unchanged candidate does not.
Otherwise finalize the existing closure table and complete
`references/github-closeout.md`.

Report: outcome, commits, tests/checks run, review results, gate table, and
leftovers/follow-ups.
