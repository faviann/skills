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
in `references/closability-gate.md` passes. A missing seam aborts there; it is
never carried into implementation for the closure gate to discover.

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
- Required commands: <targeted and baseline checks>
- Authority: GitHub reads and workspace edits only. Do not refetch issue
  comments, commit, mutate GitHub, or change the contract.
- Completion: use `/tdd` at the named seams where possible, implement only this
  contract, run the required checks, then stop.
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
primary retains adjudication and repair.

## 3. Primary checkpoint

Inspect the worktree and run affected focused checks. Before the first commit,
delegate one fresh raw-artifact readiness sweep; adjudicate it once and batch
all blockers to a fresh implementation delegate. Re-check affected evidence,
then commit normally; each later round adds a commit (no amend or squash).

After committing, status only the criteria this round claims. `tested` requires
evidence of the actual artifact and mode that would fail if the behavior — or
its timing, ordering, or bound — were violated. Record anything else as a
checkpoint directive.

On later rounds, re-check only affected criteria; do not run the full closeout
sweep.

## 4. Combined candidate gate

Against the same `<base>...HEAD`, start `code-review` and the closure sweep in
`references/github-closeout.md` together, using raw artifacts only. The closure
table remains provisional until final validation.

## 5. Adjudicate and remediate

Adjudicate checkpoint directives, both review axes, and closure findings
together. A directive with a mechanical seam is blocking and must be resolved
in the next committed round. If proof would require a gate-only artifact, use
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

Batch all blockers from one combined gate to one fresh implementation delegate.
Run affected focused checks, commit, and rerun the gate until clean; do not run
the full regression suite in this loop.

## 6. Closeout

After the combined gate is clean, run the full regression command once and
`git diff --check`. Any code change invalidates the gate and validation;
otherwise finalize the existing closure table and complete
`references/github-closeout.md`.

Report: outcome, commits, tests/checks run, review results, gate table, and
leftovers/follow-ups.
