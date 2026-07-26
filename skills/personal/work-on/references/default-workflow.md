# Default work-on workflow

Required skills: `implement` and `tdd` (inside the delegated agent),
`code-review` (invoked by the primary).

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
commands, and open questions. Done when every criterion has a seam, or its
missing seam is flagged for the closure gate.

## 2. Delegate implementation

Spawn a fresh subagent with the trusted issue snapshot, raw source paths, base
SHA, and required commands. Tell it not to refetch issue comments. It uses
`implement`/`tdd` mechanics, stops after workspace edits and validation, and
returns only:

```text
Changed:
Evidence:
Unverified:
Risks:
```

## 3. Primary checkpoint

Inspect the actual worktree and run the baseline checks yourself. Commit with a
normal, well-messaged commit; each later round adds a new commit (no amend, no
squash).

After committing, status only the criteria this round claims. `tested` requires
evidence of the actual artifact and mode that would fail if the behavior — or
its timing, ordering, or bound — were violated. Record anything else as a
checkpoint directive.

On later rounds, re-check only affected criteria; do not run the full closeout
sweep.

## 4. Independent review

Invoke `code-review` from the base SHA. Supply raw artifacts only — exact diff
command, trusted issue snapshot, binding doc paths, repo rules, raw command
output — never the implementer's conclusions.

## 5. Adjudicate and remediate

Adjudicate checkpoint directives with review findings. A directive with a
mechanical seam is blocking and must be resolved in the next committed round
before closeout. If proof would require a gate-only artifact, use the closure
gate's human/escalation path instead of inventing one.

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

After each round: commit, regenerate evidence, rerun both review axes. Loop
until no blocking findings remain.

## 6. Closeout

Run the closure gate and closeout in `references/github-closeout.md`.

Report: outcome, commits, tests/checks run, review results, gate table, and
leftovers/follow-ups.
