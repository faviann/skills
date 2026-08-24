# Default work-on workflow

Required skills: `/tdd` (inside the delegated agent) and `/code-review` (invoked
by the primary).

Abort if:
- a required skill is unavailable
- the issue does not have the `ready-for-agent` label
- scope, acceptance criteria, readiness, or validation seam are unclear

## 1. Orient

Record the base SHA (`git rev-parse HEAD`) before any edit; every diff, review,
and evidence regeneration compares `<base>...HEAD`.

Read the issue, trusted comments, linked parent/spec, and relevant repo docs.
Preserve unrelated user changes.

Record scope, non-scope, acceptance criteria, validation seams, required
commands, and open questions. Done when the pre-implementation closability gate
in `references/closability-gate.md` passes and freezes this run's
Validation-surface manifest. A missing seam aborts there; it is never carried
into implementation for the closure gate to discover.

## Validation-surface manifest custody

The manifest frozen by `references/closability-gate.md` is this run's complete
direct-evidence obligation. At the start of every continuation or resume, run
this skill's `scripts/workflow-provenance.sh verify` from the target repository
before any manifest reuse, whether before or after delegation. Reuse is
available only when it succeeds: because manifest freeze removes the previous
ledger, success proves provenance was captured after this manifest froze and
that the selected workflow has not changed. If provenance was not captured
after this manifest froze because the interruption preceded capture, or
verification reports drift, the manifest cannot be reused.

Whether before or after delegation, recover the retained trusted-snapshot and
manifest files for this run from the gate's custody location. Do not refetch
current trusted GitHub comments or recreate either file from conversational
memory. From the target repository, run this skill's identity helper before
reuse; the path below is relative to the skill root:

```bash
pre_implementation_base="$(scripts/manifest-identity.sh verify \
  --manifest "$manifest_file" \
  --snapshot "$trusted_snapshot_file")"
```

A successful verification proves that the retained frozen snapshot matches the
manifest's snapshot digest, the recorded full base SHA still names a commit,
both files remain owner-only run-local state, and the snapshot/base/body binding
is intact; it prints that base SHA for the resumed workflow. A newly arrived
trusted comment does not join this frozen snapshot or invalidate it merely by
existing. Only an explicit trusted-maintainer contract change takes the
invalidation path below. Only after verification read the same snapshot and
manifest back, supply them verbatim to the implementation delegate and to the
readiness, Standards, Spec, and closure contexts, and keep them available for
adjudication.

Before delegation, a missing or failing Workflow provenance ledger or a missing,
malformed, corrupt, replaced, or mismatched frozen snapshot or manifest is
invalid frozen preflight state: discard both files and take the gate's settled
complete trusted-snapshot/Closability/manifest recomputation path. After
delegation, either Workflow provenance or frozen-state verification failure
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
- Required commands: <targeted and baseline checks>
- Authority: GitHub reads and workspace edits only. Do not refetch issue
  comments, commit, mutate GitHub, or change the contract.
- Coherence pass: <copy the complete bounded coherence-pass instruction from
  `SKILL.md`'s authority invariants>
- Completion: use `/tdd` at the named seams where possible, implement only this
  contract, run the required checks, perform the populated Coherence pass, then
  stop.
```

The scoped contract is the delegate's complete implementation workflow. The
delegate returns only:

```text
Changed:
Evidence:
Unverified:
Risks:
```

Give the readiness sweep, both `code-review` axes, and closure sweep this brief:
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
primary retains adjudication and repair. Supply the frozen Validation-surface
manifest with this brief: it names the evidence each criterion owes, and never
limits what the sweep may inspect or report.

## 3. Primary checkpoint

Inspect the worktree and run affected focused checks. Before the first commit,
delegate one fresh raw-artifact readiness sweep; adjudicate it once and batch
all blockers back to the initial implementation delegate through the harness's
supported continuation mechanism, applying the implementation-owner fallback
in `SKILL.md`'s authority invariants when continuation is unavailable. Re-check
affected evidence, then commit normally; each later round adds a commit (no
amend or squash).

After committing, status only the criteria this round claims. `tested` requires
evidence of the actual artifact and mode that would fail if the behavior — or
its timing, ordering, or bound — were violated, at every instance in that
criterion's frozen Validation surface. Record anything else as a checkpoint
directive.

On later rounds, re-check only affected criteria; do not run the full closeout
sweep.

## 4. Combined candidate gate

Against the same `<base>...HEAD`, start `code-review` and the closure sweep in
`references/github-closeout.md` together, using raw artifacts only. The closure
table remains provisional until final validation.

## 5. Adjudicate and remediate

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

Batch all blockers from one combined gate back to the initial implementation
delegate through the harness's supported continuation mechanism, applying the
implementation-owner fallback in `SKILL.md`'s authority invariants when
continuation is unavailable. Run affected focused checks, commit, and rerun the
gate with fresh reviewers until clean; do not show later reviewers prior
reports, adjudications, or the ledger, and do not run the full regression suite
in this loop.

## 6. Closeout

After the combined gate is clean, run the full regression command once and
`git diff --check`. Any code change invalidates the gate and validation;
otherwise finalize the existing closure table and complete
`references/github-closeout.md`.

Report: outcome, commits, tests/checks run, review results, gate table, and
leftovers/follow-ups.
