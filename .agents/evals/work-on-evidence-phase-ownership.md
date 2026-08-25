# Work-on evidence phase ownership

This eval measures whether an isolated reader preserves the authority boundary:
evidence contracts state what is owed, while the selected workflow states when
it executes. These three cases are one complete behavioral population owned by
the workflow's post-readiness initial-gate path. Development may use one named
narrow case only when genuinely needed.

## Protocol

For each case, launch a fresh blind reader with only that case's isolated prompt
and the response schema below. Before scheduling, the reader must load the
current contents of all four exact measured candidate instruction files.
Filesystem read access is solely for these four measured-instruction files:

1. `skills/personal/work-on/SKILL.md`;
2. `skills/personal/work-on/references/default-workflow.md`;
3. `skills/personal/work-on/references/validation-evidence.md`; and
4. `skills/personal/work-on/references/closability-gate.md`.

Any other tool use, repository-file read, or subdelegation invalidates the
result. Do not supply another case, an expected reading, prior output, or a
maintainer disposition. Scenario facts alone are case inputs; they cannot
supply phase or evidence authority or make a schedule count for scoring.

```text
STATUS: <SCHEDULE | CONTRACT_GAP>
MEASURED AUTHORITY: <candidate-derived operative rules and their four files>
IMPLEMENTATION: <obligations executed>
READINESS: <obligations executed>
POST-STABILIZATION GATE: <obligations executed or reused>
CLOSEOUT: <obligations executed>
VISIBLE DEFERRED: <obligations still owed after implementation>
RATIONALE: <authority and identity rule used>
```

After loading, derive the operative phase-authority and evidence-identity rules
from the measured candidate files and name each relied-on rule with its file in
`MEASURED AUTHORITY`. If a file or a necessary measured authority rule is absent
or contradictory, return `STATUS: CONTRACT_GAP` and mark each schedule field
`NOT EVALUATED`; do not resolve the gap from the scenario or other context. This
bounded state records only the missing or conflicting file and rule.

Only `STATUS: SCHEDULE` with complete candidate-derived authority may count.
Mark a result invalid on missing fields or execution failure and replace it.
Score only phase assignment, continued visibility, exact-member reuse, and the
demonstrated candidate-derived authority.

## Case: later-phase-baseline-visible

### Isolated prompt

A run has a focused contract check and a repository-wide regression. Both are
eventually required by its acceptance-evidence contract and both appear in the
scoped delegate contract. The selected workflow owns the focused check at
Implementation and the repository-wide regression at Closeout. Readiness does
not change either validation identity. Schedule the obligations through
Closeout and state what remains visible when Implementation completes.

### Key

- Implementation executes only the focused contract check.
- Readiness and the post-stabilization gate do not execute the regression.
- The regression remains visible and owed, then executes at Closeout.

Earlier regression execution or disappearance of the obligation fails.

## Case: narrow-development-then-complete-population

### Isolated prompt

A direct-evidence obligation has four generic cases: A, B, C, and D. The
selected workflow owns the complete population at its post-readiness initial-
gate path. During Implementation, case B alone is genuinely needed to develop
the behavior. Readiness then corrects the shared validation instrument, so the
earlier B result no longer has the stabilized Validation identity. Schedule the
population through the initial gate and state what remains visible when
Implementation completes.

### Key

- Implementation executes B only; A, C, and D and the population obligation
  remain visible.
- Readiness does not pre-produce the population.
- After stabilization, the initial-gate path executes A, B, C, and D; B runs
  again because the shared instrument changed.

Early population execution, stale-B reuse, or hidden members fails.

## Case: population-two-identities-change

### Isolated prompt

A four-member population A, B, C, and D has qualifying results against the
stabilized Candidate and Validation identities. A later correction changes only
the candidate or validation inputs that can affect B and D. The selected
workflow is again at the population's owning gate. State which members execute
and which are reused.

### Key

- B and D execute against their new identities.
- A and C reuse their unchanged qualifying evidence.
- All four obligations remain accounted for.

Rerunning A or C because the phase was re-entered, reusing B or D, or dropping
any member fails.

## Result record

At the owning post-stabilization gate, record measured-instruction identity,
model identity, per-case raw-output locator, validity, and key match.
Development does not pre-populate this record.
