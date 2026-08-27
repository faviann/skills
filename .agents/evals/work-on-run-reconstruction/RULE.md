# Reconstructing a `/work-on` run from Moraine, GitHub and git

Rule version **1.0.0**, implemented by [`reconstruct.mjs`](./reconstruct.mjs),
which digests itself and stamps the digest on every document it produces.

This is evidence tooling for
[#143](https://github.com/faviann/skills/issues/143) under Map
[#142](https://github.com/faviann/skills/issues/142). It lives with the evals; it
is not part of the skill, and it changes nothing about how `/work-on` runs. It is
read-only against all three sources: it never writes a sink, a registry record,
or a published body.

## What it answers

Given a `/work-on` run that already happened, how much of what the run telemetry
sink recorded can a documented rule recover from Moraine plus GitHub and git —
and which fields cannot be recovered at all.

## Usage

```sh
node reconstruct.mjs --repo OWNER/NAME --pr N \
  [--harness auto|codex|claude-code] \
  [--repo-path DIR] [--window-hours N] \
  [--sink PATH] [--out FILE]
```

[`test-reconstruct.sh`](./test-reconstruct.sh) holds the joins to the behaviour
[`RESULT.md`](./RESULT.md) reports rates for; it is part of the repository's shell
test set and needs neither Moraine nor GitHub.

`--sink` is optional and is used only to *check* the reconstruction. The sink is
evidence authority 4 — a corroborating transitional summary, never the
population. Nothing the rule recovers is read from it.

## The circularity rule, stated first

The primary invokes `run-telemetry.sh` through the harness, so the harness corpus
holds those command lines verbatim. Every sink event can therefore be replayed
out of the corpus today, exactly, including the fields nothing else can supply.

**That is not recovery.** Those command lines exist only because the sink exists;
they disappear the moment the sink is deleted, which is the decision they would
be used to justify. The rule reports them separately, under `sink_echo`, and
never counts them toward a verdict. Every verdict below is what a corpus with no
telemetry sink in it would still hold.

The echo is also not exact, in two ways that are worth knowing before anyone
proposes leaning on it:

- **A Codex `exec` input is a program, not a command line.** A loop over three
  reviewer roles is one recorded program and three sink events. On subject 2 the
  echo saw 8 `review-delegation` programs behind 22 recordings.
- **A sink event can be written by a command that never names it.**
  `run-registry.sh finalize` seals the run internally, so subject 1's
  `run_sealed` has no `run-telemetry.sh seal` anywhere in its corpus.

## The joins

Each join is numbered, states its assumptions, and says what would break it. A
join that is right on two runs is not thereby deterministic.

### R1 — a pull request resolves to its primary session

**Anchor.** The workflow's authority invariant reserves every GitHub mutation for
the primary, so the session that ran `gh pr create` naming this PR's head branch
*is* the primary. The anchor is authored by the workflow, not by the sink, so it
survives the sink's deletion. Where the harness exposes session ancestry, the
anchor is lifted to the run's root session.

**Corroborator (Codex only).** A `session_meta` in the window whose
`git.repository_url` is this repository and whose `git.branch` is the PR's head
branch. Note the primary's *own* `session_meta` will usually **not** match: that
snapshot is taken at session start, before the primary creates the branch, so the
primary looks like it is on whatever branch it was on when the human opened the
terminal. It is the delegates that match.

**Assumptions.** The PR was opened from the run, by `gh`, in a recorded tool
call; the head branch is on that command line.

**Breaks when.** The PR is opened from the web UI, from a script outside the
harness, or in a later session; one session opens several PRs — observed, a
Claude Code session that opened three, only one of which was its `/work-on`
candidate; a branch name is reused inside the query window.

### R2 — a primary session resolves to its delegate sessions

The two harnesses need different rules here, and neither one is the timestamp
join the charting session used by hand.

**Codex — exact, two-key, deterministic.** `spawn_agent` carries a plaintext
`task_name` in its arguments and returns it in its result. The child's
`session_meta` carries `agent_path` (`/root/<task_name>`) *and*
`parent_thread_id`. Matching on the pair is exact.

This supersedes the hand join recorded on #142 (`spawn_agent` timestamp plus
`cwd`, child starting ~70 ms after the call). The timestamp join happens to be
right on both subjects; it is not needed, and it is the join that would break
first under concurrency.

*Assumes* task names are distinct within one parent session, and that a
`followup_task` continuation targets a delegate already joined by name.
*Breaks when* the primary reuses one task name, or a delegate spawns its own
delegate — this rule joins one level, and while ancestry is transitive, role is
not.

**Claude Code — ordered, heuristic.** A Claude Code delegate has no session of
its own. Its events sit in the parent session with `is_substream` set and an
`agent_run_id` that Moraine projects. The launch-to-substream join is by stream
order: the first event bearing an unseen `agent_run_id` after an `Agent` request
belongs to that request.

*Breaks when* several `Agent` calls are issued in one assistant message and their
substreams interleave — which Claude Code does routinely, and Codex does not.

### R3 — a delegate resolves to a role

The delegate's name is authored by the primary, and the workflow does not fix its
spelling. Across the two subjects the Standards reviewer was called
`gate_standards_138`, `issue96_standards_r1`, `issue96_standards_final`,
`issue96_standards_confirm3` and `issue96_standards_confirm4`.

The rule is a lexical classifier over that name — separated on non-alphanumeric
characters first, because the names join their words with underscores — plus the
plaintext brief where the harness has one. An unmatched delegate is classified
`other`, which is the sink's own residual launch role, and is reported as a
residual: nothing about its purpose was recovered.

**This is a heuristic and stays one.** See *False joins* below.

### R3b — a delegate resolves to a round

Same source, same weakness, worse odds. Nothing in either harness records a
round: the workflow authors it, and whether it survives into the corpus depends
on how the primary chose to name and brief the delegate. The rule reads
`round N`, `gate N`, `remediation N`, and the `rN`/`deltaN`/`confirmN` suffixes,
and reports per subject how many it recovered and how many it got right. It never
substitutes a count of review cycles for the authored number.

### R4 — a review delegation resolves to a compared candidate

The Codex brief is `encrypted_content`, so the compared identity is not read from
what the reviewer was *told*. It is read from what the reviewer *did*: the first
`git diff` in the delegate's own tool calls that names SHAs.

- two SHAs — a committed comparison, `base` and `head`;
- one SHA together with `git ls-files --others` — the worktree bundle a readiness
  sweep reads, so `head_is_worktree`.

`input_bytes` is then **recomputed** from git, byte-identically to the sink's own
`diff_git` — the same pinned `core.quotePath`, `diff.noprefix`,
`diff.mnemonicPrefix`, `--no-ext-diff --no-color --no-textconv`. It is a git
fact, not a corpus fact, and it is exact only for a committed comparison. A
worktree bundle is unmeasurable after the fact: the uncommitted bytes are gone.

*Assumes* the reviewer executes its own diff and the corpus captured it. The
review skill requires it; the Codex brief does not carry it.

### R4b — the same, from a plaintext brief

Where the brief is readable the rule prefers it, because it states what the
reviewer was *told* to compare rather than what it happened to run. A Claude Code
reviewer is briefed `git diff <base>...HEAD` together with a commit list, so the
base is literal and the head is the last abbreviated SHA in that list, resolved
through `git rev-parse`. Codex has no equivalent path: its `NEW_TASK` payload is
`encrypted_content` in both the parent and the child rollout, which is exactly why
R4 exists.

### R5 — a validation execution resolves to identity, duration and outcome

**Identity** is the literal command line. The corpus holds it in full; the sink
deliberately holds nothing but a caller-supplied `--command-id`. On this axis the
corpus is strictly better than the sink.

**Duration** is the request-to-result interval, with one correction. Codex yields
on a long command, returning a `session_id` the agent then polls with
`write_stdin`, so the raw interval is the yield window and not the command. The
rule follows the yield handle to its last poll. On subject 1 the uncorrected
interval for `npm test` would have been 30 s against an actual 273 s.

**Outcome** is the weak one. Codex's `exec` is a JavaScript sandbox, and what
Moraine records is what the agent's own script chose to emit. A script written as
`text(r.output)` discards the exit code the harness had, and the harness's own
wrapper prints `Script completed` for a command that failed. On subject 1, all 70
of the primary's `exec` results say `Script completed` and none carries an exit
status except where a yield forced a poll to surface `exit_code`.

**One tool call is not one execution.** A Codex `exec` input is a program, and a
`Promise.all` of two `exec_command` calls is one tool call and two executions.
The rule extracts every `cmd` in the program.

### R8 — authored review packages

Where the workflow writes a review assignment to disk, the corpus captures the
patch that wrote it, and that text names the review's kind and round in the
primary's own words — `Delta review assignment — issue 96, remediation gate 1`.

This is not harness metadata. It is a workflow-*authored* marker that happens to
be observable because writing it was a tool call, and it is the one place in
either subject where round and kind are recoverable at full fidelity. It is
present on subject 2, which writes packages to
`work-on-review/<run-id>.<kind>-r<n>.md`, and absent on subject 1, which briefed
its reviewers directly.

It is reported because it is the concrete precedent for the transcript-marker
option #142 leaves open under *Not yet specified*. Nothing here proposes it.

### R6 — the run's outcome

GitHub holds it: the closing keyword in the published body, corroborated by the
issue's state. `Closes` and `Progresses` are recoverable. `preflight-aborted`,
`abandoned` and `failed` publish nothing, so they are indistinguishable from a
run that never started.

### R7 — run identity

The sink mints `<UTC timestamp>-<8 hex>` and nothing else does. The primary
session id is a recoverable *substitute* identity, but it is a different key: it
is not what `references/closability-gate.md` keys the frozen trusted snapshot and
the Validation-surface manifest on, and it does not exist before the session's
first event. See #142's coupling note; this rule reports the substitution and
does not propose it.

## False joins

Three of the seven joins are heuristic, and each fails in a different way.

| Join | Status | What breaks it |
|---|---|---|
| R1 PR → primary | heuristic | a PR opened outside the harness; one session, several PRs |
| R2 Codex primary → delegates | **deterministic** | reused task names; depth > 1 |
| R2 Claude primary → delegates | heuristic | concurrent `Agent` calls in one message |
| R3 delegate → role | heuristic | an authored name outside the vocabulary |
| R3b delegate → round | heuristic | a name or brief that does not state the round |
| R4 review → compared candidate | heuristic | a reviewer that reads the diff some other way |
| R4b review → compared candidate, from the brief | deterministic where the brief is readable | a ciphertext brief — every Codex run |
| R5 execution → identity | deterministic | none observed |
| R6 outcome | deterministic for published runs | an unpublished outcome is invisible |

R3 is the one that most looks deterministic and is not. It classified every
delegate on all three subjects correctly, and still cannot be trusted on the
neighbouring question: `_r1`, `_final`, `_confirm3`, `_confirm4` are review rounds
1, 2, 3 and 4 of subject 2, and a classifier keyed on `final` would have called
round 2 the last round. The name is authored ad hoc; the classifier is right when
the author happened to be regular.

## Where a projection would go from here

Phase is the field no join recovers on any subject, and round is recovered only
where the primary happened to write it down. Both are *authored* facts — the
workflow decides that this delegation is round 3 of remediation — with no observer
in the corpus. R8 shows what it looks like when the workflow does write one down.
The option #142 already names under *Not yet specified* is a workflow-authored
transcript marker; that is a D-ticket question, not this rule's.
