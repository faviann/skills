# Convergence semantic state

Apply this reference after the initial cumulative gate in every selected
`work-on` workflow. It owns one Convergence lifecycle's Corrective-batch
capacity and candidate-transition record. The selected workflow owns
implementation and review sequencing; `review-state-machine.md` owns review;
`github-closeout.md` owns closure judgments.

## Authority and custody

One owner-only JSON file in the target repository's Git common directory is
the semantic authority for an issue:

```text
$(git rev-parse --path-format=absolute --git-common-dir)/work-on-convergence/
  issue-<number>.json
```

The directory is `0700` and the file is `0600`. The file is keyed by repository
and issue rather than session, branch, pull request, run handle, telemetry
segment, or review chain. It survives every supported continuation and resume
in that repository, including worktree changes. It is neither conversational
memory nor a Git-history inference, and it is not stored in or reconstructed
from the Run telemetry sink, PR-local observation, Run registry, registry
projection, Workflow provenance, or provider analytics.

Use this skill's `scripts/convergence-state.sh` from the target repository for
every state transition. The command verifies owner-only custody and atomically
replaces valid state while holding an issue-local lock. Its `candidate` command
identifies the exact clean committed Candidate as the repository plus content
tree. Do not hand-construct or abbreviate Candidate identities.

The state retains the active Convergence lifecycle identity, every associated
run handle, its exact current Candidate identity, consumed count, non-corrective
continuity transitions, and every correction's exact source Candidate,
authorization status, and exact result Candidate after completion. Completed
predecessor lifecycles remain in its history after material re-entry.

## Lifecycle continuity

After the initial cumulative gate establishes its exact Candidate, recover or
begin authority before acting on an accepted blocker:

```bash
candidate="$(scripts/convergence-state.sh candidate)"
lifecycle_id="$(scripts/convergence-state.sh begin \
  --issue "$ISSUE_NUMBER" --run "$RUN_HANDLE" --candidate "$candidate")"
```

`begin` creates authority only when none exists. If an active lifecycle already
exists, it attaches the run to that lifecycle after reconciling the Candidate;
it never creates new budget. An ended or irreconcilable lifecycle refuses this
path.

At the start of every supported continuation or resume after the initial gate,
and before synchronization, a governing-state restart, review, hand-back, or
accepted-blocker-driven correction, compute the exact Candidate and recover the
same lifecycle:

```bash
recovered="$(scripts/convergence-state.sh recover \
  --issue "$ISSUE_NUMBER" --run "$RUN_HANDLE" --candidate "$candidate")"
lifecycle_id="$(jq -r .id <<<"$recovered")"
```

The recorded lifecycle identity must accompany every later mutation of its
state. This prevents a stale session from spending or ending a successor's
budget. Session, pull request, run, continuation, telemetry segmentation,
review-chain restart, and bookkeeping never create another authority file or
reset its count.

A synchronization or legally mutable governing-state restart may change exact
Candidate content without consuming a Corrective batch. After the transition
and before any later review, correction, or hand-back, correlate its exact
source and result while retaining the count:

```bash
scripts/convergence-state.sh advance --issue "$ISSUE_NUMBER" \
  --lifecycle "$lifecycle_id" --kind synchronization \
  --source "$source_candidate" --result "$result_candidate"
```

Use `--kind governing-state-restart` for that distinct transition. These
commands describe only non-blocker-driven continuity changes; a correction may
not be relabelled as either kind. Interruption after an unrecorded Candidate
transition fails closed under recovery.

## Corrective-batch protocol

A Corrective batch is one automatic, jointly delegated, accepted-blocker-driven
correction after the initial cumulative gate that changes exact candidate
content. Candidate-controlled production code, tests, documentation, fixtures,
evidence artifacts, and other tracked or identity-bearing content use the same
rule.

Before sending accepted directives to the implementation owner, recover the
authority at the exact unchanged source Candidate, then authorize:

```bash
correction_id="$(scripts/convergence-state.sh authorize \
  --issue "$ISSUE_NUMBER" --lifecycle "$lifecycle_id" \
  --candidate "$source_candidate")"
```

Authorization checks capacity before implementation may mutate the Candidate.
One gate's jointly adjudicated and jointly delegated blockers share that one
authorization. Repeating authorization at the unchanged source returns the
same pending correction rather than reserving another unit. When two completed
batches are recorded, authorization refuses a third before delegation or
candidate mutation.

After the implementation owner returns, run affected focused checks and commit
the exact current candidate as the selected workflow requires. If candidate
content changed, compute its exact clean result identity and complete the
transition before delta review, another correction, synchronization, or
hand-back:

```bash
scripts/convergence-state.sh complete --issue "$ISSUE_NUMBER" \
  --lifecycle "$lifecycle_id" --correction "$correction_id" \
  --source "$source_candidate" --result "$result_candidate"
```

Completion atomically changes that authorization to a correlated
source-to-result transition and increments the consumed count. Repeating the
same completion is idempotent; it returns the existing count. A different
source or result for that correction is an identity conflict.

If the candidate remains exactly at the authorized source, no Corrective batch
completed and no unit is consumed. Keep the pending authorization for a
supported continuation, or durably end the lifecycle when the workflow hands
back. Findings, adjudication without candidate mutation, reviewer fan-out,
delta or cumulative review, validation, elapsed time, qualifying evidence
gathering against an unchanged candidate, and ordinary bookkeeping do not
consume a unit.

Recovery distinguishes all interruption cases:

1. An authorized correction whose Candidate remains at its exact source stays
   pending with the unit available.
2. A completed exact source-to-result transition is already one consumed unit
   and cannot increment again.
3. Any different Candidate without its correlated result transition marks the
   lifecycle irreconcilable. It restores no capacity and grants no further
   mutation authority; take a durable non-success hand-back.

Git history alone never resolves case 3. It may help a human investigate, but
it cannot decide whether the semantic transition consumed a unit.

## Exhaustion and durable hand-back

The lifecycle permits two completed Corrective batches. A clean Candidate after
both may still reach `Closes` after every existing review, direct-evidence, and
fresh blind cumulative-confirmation requirement passes. When another accepted
blocker requires candidate mutation, preserve the blocker and exact Candidate,
then stop before sending directives or editing.

Choose the existing durable outcome under ordinary partial-closeout semantics:

- `Progresses` when the exact exhausted Candidate is safe, independently useful,
  and eligible for ordinary `Progresses` closeout;
- `failed` otherwise.

Write every unresolved blocker to an owner-only untracked file and record a
concrete material re-entry condition. End the exhausted lifecycle atomically:

```bash
scripts/convergence-state.sh exhaust --issue "$ISSUE_NUMBER" \
  --lifecycle "$lifecycle_id" --candidate "$candidate" \
  --outcome "$OUTCOME" --blockers-file "$blockers_file" \
  --reentry-condition "$material_condition"
```

Preserve the same blocker, exact candidate state, exhausted count, and material
condition in the ordinary pull-request or hand-back narrative and durable
tracker state. Finalize the Run registry with the chosen existing outcome. An
exhausted lifecycle never uses `Closes`, `preflight-aborted`, or `abandoned`
merely because its budget ended, and adds no convergence-specific outcome,
reason, registry field, or telemetry.

For any other durable hand-back after a lifecycle exists, use `end` before Run
registry finalization. `Progresses` and `failed` require a concrete material
re-entry condition; `Closes` does not manufacture future work.

## Material re-entry

A successor receives fresh capacity only when the predecessor durably ended
and its exact recorded material re-entry condition is actually satisfied. A
material contract amendment, completed prerequisite, corrected governing
state, issue split or rescope, or materially changed implementation/review
strategy may qualify. A new session, pull request, run, telemetry segment,
continuation, or request to try again does not.

After verifying the condition from durable source evidence, create the
successor and record that evidence:

```bash
lifecycle_id="$(scripts/convergence-state.sh reenter \
  --issue "$ISSUE_NUMBER" --run "$RUN_HANDLE" --candidate "$candidate" \
  --condition "$recorded_condition" --evidence "$durable_evidence")"
```

The condition must match the predecessor's record exactly. The successor gets
a new lifecycle identity and zero consumed units while retaining the full
predecessor in history.

## Precedence and AFK

A post-delegation trusted requirement omitted from the frozen
Validation-surface manifest takes precedence over Convergence handling. It is
not a Corrective batch, consumes no unit, and cannot be repaired, appended, or
restarted with remaining capacity. Follow the manifest's settled
`Progresses`/`failed` hand-back and end any active Convergence lifecycle with a
material condition requiring fresh valid governing state.

AFK follows this exact state machine. It recovers the same authority, refuses a
third mutation, preserves blockers, chooses `Progresses` or `failed` by the same
safe-and-independently-useful rule, records material re-entry, and hands back.
It has no override, extension, blocker downgrade, or reset path.
