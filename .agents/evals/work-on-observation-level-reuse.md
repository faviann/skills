# Work-on observation-level reuse

This eval measures whether an isolated reader treats a manifest-recorded
validation command as the default vehicle for a Validation surface's owed
observations rather than as the discharge condition. These four cases are one
complete behavioral population owned by the workflow's post-readiness Primary
checkpoint. The eval measures scheduling only and introduces no scoring
subsystem.

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
supply evidence authority or make a schedule count for scoring.

```text
STATUS: <SCHEDULE | CONTRACT_GAP>
MEASURED AUTHORITY: <candidate-derived operative rules and their four files>
EXECUTE: <validation invocations scheduled at the owning phase>
REUSE: <owed observations satisfied by qualifying evidence>
VISIBLE OWED: <all owed observations and how each is accounted for>
RATIONALE: <sufficiency, identity, positive-establishment, and hard-rule reasoning>
```

After loading, derive the operative phase-authority, evidence-identity,
observation-level sufficiency, and conservative-fallback rules from the measured
candidate files and name each relied-on rule with its file in `MEASURED
AUTHORITY`. If a file or a necessary measured authority rule is absent or
contradictory, return `STATUS: CONTRACT_GAP` and mark every schedule field `NOT
EVALUATED`; do not resolve the gap from the scenario or other context. This
bounded state records only the missing or conflicting file and rule.

Only `STATUS: SCHEDULE` with complete candidate-derived authority may count.
Mark a result invalid on missing fields or execution failure and replace it.
Score only required execution, qualifying reuse, complete accounting of owed
observations, and the demonstrated candidate-derived authority.

## N1 — isolated one-case change reuses and stays narrow

### Isolated prompt

A frozen Validation surface has four owed cases A, B, C, and D. Its manifest
records `run-checks --suite behavior` as the discharging action, and repository
authority documents both that suite and `run-checks --case <name>`. Qualifying
evidence for all four cases exists against the exact stabilized candidate. A
later candidate delta changes only case B's addressable case body; production,
shared helpers, shared fixtures, configuration, and all other validation inputs
are unchanged. The validation definitions and repository authority positively
establish that only B is affected. Schedule the owning-phase validation.

### Key

- Execute `run-checks --case B`.
- Reuse qualifying evidence for A, C, and D.
- Do not execute `run-checks --suite behavior`.
- Account for all four owed observations.

Executing the broad vehicle fails.

## N2 — shared or ambiguous change runs the broader check

### Isolated prompt

A frozen Validation surface has four owed cases A, B, C, and D. Its manifest
records `run-checks --suite behavior` as the discharging action, and repository
authority documents both that suite and individually addressed cases. A later
candidate delta changes a shared helper. The affected member set cannot be
positively established from the candidate change, validation definitions, and
available repository authority. No documented dependency mapping identifies the
affected cases. Schedule the owning-phase validation.

### Key

- Execute `run-checks --suite behavior`.
- Do not guess, derive, or construct a helper-to-case dependency mapping.
- Account for all four owed observations through the broad adequate check.

Narrowing on a guessed or constructed dependency mapping fails.

## N3 — repository hard rule survives

### Isolated prompt

A frozen Validation surface's constituent observations have qualifying targeted
evidence for the exact current Candidate identity. The repository's agent-facing
authority separately requires the exact command `run-checks --suite behavior`
at this owning phase. Schedule the validation.

### Key

- Execute `run-checks --suite behavior` because the documented hard rule creates
  a distinct assurance requirement for that exact command.
- Do not optimize the required broad execution away because targeted evidence
  covers its constituent behavior.

Optimizing the hard-rule command away fails.

## N4 — inadequate evidence is never reused

### Isolated prompt

A frozen Validation surface has four owed cases A, B, C, and D. Repository
authority documents adequate individual case invocations and a broad suite
vehicle. Evidence for A is failing, B is stale, C is contradicted by another
result, and D has uncertain Candidate identity. The affected cases are otherwise
positively established from the candidate, validation definitions, and
repository authority. Schedule the owning-phase validation and state whether
the repetition guardrail applies.

### Key

- Reuse none of A, B, C, or D.
- Execute documented invocations that directly produce qualifying evidence for
  every owed member; use the broader adequate check if those invocations cannot
  cover them all.
- Failing, stale, contradictory, and identity-uncertain evidence remains
  blocking and never reaches the repetition guardrail.

Reusing any inadequate evidence fails.

## Bounded #96 counterfactual

At evidence commit `badeaeabfd5616bee11bdf00e4cf936004e7e3b0`, this repair
removes approximately 268 seconds of demonstrated same-candidate coarse
repetition in `faviann/dotfiles#96`, not all suite execution. The gross four
coarse executions total 274.6 seconds; approximately 6.5 seconds is genuinely
owed targeted work that the repair makes explicit rather than incidental. The
manifest owes roughly nine to ten addressable cases from the sixty-seven in
`tests/update-agent-tools-check.bash`; the remainder is repository regression
breadth owned by Closeout.

- `a0214ff..2850ebc`: the delta changes only
  `test_managed_npm_inventory_drives_install_and_version_checks`'s case body.
  `e033` (2.9s) replaces `e034` (61.7s), and `e034` does not execute. The narrow
  runner still parses the whole suite file, so file-level breakage cannot hide.
- `2850ebc..7688473`: production `load_managed_npm_metadata` gains a
  `require_versions` parameter with different call-site semantics, and the
  shared npm stub and shared `run_tool` change. `e039`–`e043` plus approximately
  five actually uncovered invalidated owed cases (about 6.5s) replace `e045`
  (69.7s). This produces more targeted evidence than the original run did.
- `7688473..0f50132`: the delta changes only the same case body. `e048` (2.1s)
  replaces `e049` (67.7s), and `e049` does not execute.
- `0f50132..19923be`: the ShellCheck SC2126 delta changes only the same case
  body. `e051` (2.2s) and required `nix run .#shellcheck` evidence `e053`
  (22.7s) replace `e052` (75.5s). The hard-rule ShellCheck execution remains.

`e029`/`e030` is only partially owned by this repair. `e029` (1.9s) discharged
the inventory case at the stabilized checkpoint candidate, and `e030` (65.3s)
repeated that case inside the suite. The remaining fifty-seven cases answer the
different assurance question of cross-case interference and unrelated-suite
regression at the first stabilized candidate; they are not manifest members.
Do not claim `e030`'s time.

No result may claim that suite execution is generally wasteful, that broad
checks are disfavored, or that `e030`, `e031`, `e035`, `e044`, `e050`, `e053`,
or `e056` was avoidable.

## Result record

At the owning post-readiness Primary checkpoint, record measured-instruction
identity, model identity, per-case raw-output locator, validity, and key match.
Development does not pre-populate this record.
