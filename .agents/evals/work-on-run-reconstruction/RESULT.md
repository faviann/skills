# What a documented rule recovers of a `/work-on` run — result

Answers [#143](https://github.com/faviann/skills/issues/143) under Map
[#142](https://github.com/faviann/skills/issues/142). The rule is
[`RULE.md`](./RULE.md), implemented by [`reconstruct.mjs`](./reconstruct.mjs) at
version 1.0.0. Its outputs are in [`evidence/`](./evidence).

Read-only throughout: no subject was re-run, and no sink, registry record or
published body was modified.

## Subjects

| | Subject | Harness | Sink | Reconstruction |
|---|---|---|---|---|
| 1 | [`faviann/skills#138`](https://github.com/faviann/skills/issues/138) / PR [#139](https://github.com/faviann/skills/pull/139) | Codex | `20260827T021641Z-64d9f9e1` | [`evidence/skills-138.json`](./evidence/skills-138.json) |
| 2 | `faviann/dotfiles#96` / PR #104 | Codex | `20260826T151118Z-34bc65dd` | [`evidence/dotfiles-96.json`](./evidence/dotfiles-96.json) |
| C | `faviann/homelab-iac#124` / PR #180 | Claude Code | `20260822T161443Z-f194fba9` | [`evidence/claude-code-homelab-124.json`](./evidence/claude-code-homelab-124.json) |

Subject C is the bounded Claude Code capability check, not a third full
reconstruction. See *Claude Code* below for what its depth does and does not
support.

## Headline

**Three of #142's charting claims need amending, and one of them is the claim two
of its DELETE rulings rest on.**

1. **Review kind, scope and compared SHAs are recoverable from a Codex corpus.**
   #142's charting evidence 3 records them as "the only run facts the current
   sink records that a harness corpus may not be able to return", reasoning from
   evidence 2 — that the Codex `NEW_TASK` brief is `encrypted_content`. The brief
   is indeed opaque. The reviewer's *own tool calls* are not: it runs
   `git diff <base>...<head>` with full SHAs, and Moraine holds that command line.
   Across the three subjects the rule recovered **every** compared-candidate pair
   the sink recorded — 4 of 4, 22 of 22, 10 of 10 — with no false pairs, and
   recomputed `input_bytes` **byte-exact** for all 33 committed comparisons.
2. **The Codex delegate join is deterministic, not a timestamp heuristic.**
   #142's evidence 4 records the #138 run's eleven sessions as joined by hand on
   `spawn_agent` timestamp plus `cwd`. `spawn_agent` carries a plaintext
   `task_name`, and the child's `session_meta` carries `agent_path` *and*
   `parent_thread_id`. The pair is an exact join. The timestamp join is
   unnecessary and is the one that would break first under concurrency.
3. **The sink undercounts execution by more than the handoff's figure, and the
   corpus over-recovers delegation.** Subject 1's sink holds 7 wrapped executions
   against 61 commands in the primary alone and 154 across the run; subject 2's
   holds 56 against 98 and 322. In the other direction, subject 2's sink holds
   **1** implementation launch where the corpus holds 5 — one spawn and four
   `followup_task` continuations, which are exactly the four remediation rounds
   the sink's own `Remediation implementation launches` row documents itself as
   unable to count.

Against that, **four things are not recoverable at all**, and one of them is
load-bearing for sequencing. They are listed in full below.

## Per-field recovery verdict

Classification is the ticket's: recovered exactly; recovered with a stated
assumption; recovered from git or GitHub rather than the corpus; not recoverable.

### `run_start`

| Field | Verdict | Basis |
|---|---|---|
| `workflow` | git/GitHub | constant; the published body carries the workflow's mechanical sections |
| `repository` | git/GitHub | the PR's own repository |
| `issue` | git/GitHub | the body's closing keyword, corroborated by the primary's own `gh issue view N` |
| `head` | git/GitHub | the PR's merge base; on Codex also the primary `session_meta` `git.commit_hash` |
| `run_identity` | **not recoverable** | minted by the sink and by nothing else |
| `continues_run` | **not recoverable** | a handle-to-handle link between two sink files |

`run_identity` is the one that matters for sequencing. The primary session id is
a recoverable *substitute* identity, and the rule reports it — but it is a
different key. `references/closability-gate.md` keys the frozen trusted snapshot
and the Validation-surface manifest on `${RUN_HANDLE%%@*}`, and that key must
exist at freeze time, before any GitHub artifact exists. This is #142's own
coupling note, now confirmed against two runs: the corpus can *resolve* a run
after the fact; it cannot *mint* the custody key at the moment freeze needs one.

### `subagent_launch`

| Field | Verdict | Basis |
|---|---|---|
| `role` | assumption | the authored delegate name, classified lexically (Codex); the plaintext brief (Claude Code) |
| `phase` | **not recoverable** | no subject states it anywhere in the corpus |
| `round` | assumption, partial | recovered where the primary happened to write it into the name or brief: 24 of 36 review delegations across the three subjects, **24 of 24 correct**, 12 reported as unknown, none wrong |
| `tokens_in` | **recovered exactly** | Moraine holds per-event token counts per delegate |
| `tokens_out` | **recovered exactly** | as above |

The token row is the clearest case of the corpus dominating the sink: **all three
sinks recorded zero token counts** — the runtime did not expose them, and the
schema correctly refuses to estimate — while Moraine has them for every delegate
on every subject. The accounting has to be stated, though: on Claude Code almost
all input arrives as cache reads, so a bare `input_tokens` sum understates a
delegate by three orders of magnitude. The rule defines `tokens_in` as everything
that entered the model and reports the uncached part beside it.

### `review_delegation`

| Field | Verdict | Basis |
|---|---|---|
| `role` | assumption | as `subagent_launch.role`; every reviewer on every subject classified to the role the sink recorded |
| `kind` | assumption | inferable from the compared shape: worktree ⇒ readiness; base-is-run-base ⇒ full; base-is-prior-candidate ⇒ delta |
| `phase` | **not recoverable** | as above |
| `round` | assumption, partial | as above |
| `base` | **recovered exactly** | the reviewer's own `git diff` (Codex); the plaintext brief (Claude Code) |
| `head` | **recovered exactly** | as `base`, for a committed comparison |
| `head_is_worktree` | assumption | a single-SHA diff plus `git ls-files --others` is a worktree bundle |
| `input_bytes` | git/GitHub for a commit; **not recoverable** for a worktree | recomputed byte-exact from git for all 33 committed comparisons; the 3 worktree bundles are gone |

The worktree gap is real and small: one readiness sweep per run. Its bytes are
uncommitted work that no longer exists anywhere. Nothing in any of the three
layers can return it after the fact.

### `validation_start` / `validation_end`

| Field | Verdict | Basis |
|---|---|---|
| `exec_id` | **not recoverable** | a sink-local sequence number |
| `command_id` | assumption | the corpus holds the full command line — more than the name stood for — *except* where a Codex `exec` program interpolates it (12 of 476 executions across the two Codex subjects), in which case the corpus holds the template and never the command line |
| `phase` | **not recoverable** | as above |
| `round` | assumption, partial | as above |
| `outcome` | **not recoverable** | see below |
| `exit_status` | **not recoverable** | see below |
| `duration_ms` | assumption, degrading | request-to-result, following the yield handle where it is visible; within 2 s of the sink for 5 of 7, 45 of 56, and 2 of 7 executions on the three subjects |

**The count is exact and the outcome is not.** The rule found exactly the sink's
wrapped-execution count on every subject — 7, 56, 7 — and recovered the exit
status of **none** of them. Codex's `exec` is a JavaScript sandbox: what Moraine
records is what the agent's own script chose to emit. Subject 1's script wrote
`text(r.output)`, which discards the exit code the harness had; the harness's own
wrapper then prints `Script completed` for a command that failed. Subject 2's
script invented its own format — `CHECK 1 exit=running session=90959` — so the
status is present, in prose no rule can be written against. Two runs of the same
workflow, two formats. A generic rule reports `unknown` honestly; a bespoke
parser per run is not a rule.

Duration degrades with length for the same reason. A long command yields at 30 s
and is then polled, so the raw interval measures the yield window. The rule
follows the poll handle when the recorded output exposes it (subject 1's `npm
test`: 30 s uncorrected against 273 s actual, corrected) and cannot when the
agent printed the handle in its own format (subject 2's suite: reported 30 s
against 62–75 s actual).

### `outcome_resolved`, `run_sealed`, envelope

| Field | Verdict | Basis |
|---|---|---|
| `outcome_resolved.outcome` | git/GitHub | recovered correctly on all three subjects. `Closes` and `Progresses` are recoverable; `preflight-aborted`, `abandoned` and `failed` publish nothing and are indistinguishable from a run that never began |
| `run_sealed` | **not recoverable** | a sink lifecycle transition with no event in the world |
| `envelope.schema`, `.run`, `.seq` | **not recoverable** | describe the sink, not the run |
| `envelope.at`, `.epoch_ms`, `.type` | **recovered exactly** | the corpus timestamp of the act reconstructed |

### The not-recoverable list, complete

1. `run_start.run_identity` and `run_start.continues_run` — the custody key and its continuity link.
2. Every `phase`, on every event type.
3. `validation_end.outcome` and `.exit_status` — on Codex, structurally; see above.
4. `review_delegation.input_bytes` for a worktree sweep.
5. `validation_start.exec_id`, `run_sealed`, and the sink envelope's `schema`, `run` and `seq` — artefacts of the sink's own recording, not facts about the run.
6. Any outcome that was never published — `preflight-aborted`, `abandoned`, `failed`.

## The circularity finding

The primary invokes `run-telemetry.sh` through the harness, so the corpus holds
those command lines and the whole sink can be replayed out of them. **This is not
recovery and the rule never counts it.** Those command lines exist only because
the sink exists; they vanish with it, which is the decision they would be used to
justify. Every verdict above is what a corpus with no sink in it would hold.

Reporting it separately also showed it is not even a good oracle:

- a Codex `exec` input is a *program*, so subject 2's 8 recorded
  `review-delegation` programs stand behind 22 sink events — a loop over three
  reviewer roles is one program and three recordings;
- a sink event can be written by a command that never names it: subject 1's
  `run_sealed` has no `run-telemetry.sh seal` anywhere in its corpus, because
  `run-registry.sh finalize` seals internally;
- and pattern-matching command *text* has a false-positive rate. Before the rule
  distinguished shell commands from `apply_patch` programs, 5 of subject 2's 61
  apparent executions were review packages that merely *quoted*
  `run-telemetry.sh exec` in their prose.

## False-join rate

Seven joins, three deterministic, four heuristic. Measured over 48 delegate
events, 36 of them review delegations, and 1102 executions across three subjects:

| Join | Attempted | Correct | Declined | Wrong | Status |
|---|---|---|---|---|---|
| R1 PR → primary | 3 | 3 | 0 | 0 | heuristic |
| R2 delegates (Codex) | 37 | 37 | 0 | 0 | **deterministic** |
| R2 delegates (Claude Code) | 11 | 11 | 0 | 0 | heuristic |
| R3 delegate → role | 48 | 48 | 0 | 0 | heuristic |
| R3b delegate → round | 36 | 24 | 12 | 0 | heuristic |
| R4/R4b review → compared candidate | 36 | 36 | 0 | 0 | heuristic (R4), deterministic where the brief is readable (R4b) |
| R6 outcome | 3 | 3 | 0 | 0 | deterministic for published runs |

Zero wrong joins is not the same as a deterministic join, and the table is small.
What would break each:

- **R1** is the weakest and the least visible. It anchors on
  `gh pr create --head <branch>` in a recorded tool call. A PR opened from the web
  UI, from outside the harness, or in a later session leaves the run unresolvable.
  One session opening several PRs is not hypothetical: Claude Code session
  `c8d188b7` opened three, only one of which was its `/work-on` candidate.
- **R2 on Codex** breaks only if the primary reuses one task name inside one
  parent, or if a delegate spawns its own delegate — the rule joins one level.
- **R2 on Claude Code** breaks when several `Agent` calls are issued in one
  assistant message and their substreams interleave. Subject C launched its three
  reviewers 20–30 s apart, sequentially, so the ordering held. Claude Code
  launching parallel agents in one message is ordinary, and this rule has not been
  tested against it.
- **R3** was right on all 48 delegate events — 44 to a named role, every one
  matching the sink, and 4 to the residual `other`, which is also what the sink
  recorded for them — and is still ad hoc: the Standards reviewer
  was called `gate_standards_138`, `issue96_standards_r1`,
  `issue96_standards_final`, `issue96_standards_confirm3`,
  `issue96_standards_confirm4` and `Round 2 standards review`. The classifier is
  right when the author happened to be regular.
- **R3b** is the honest one. It recovered 24 of 36 rounds and got all 24 right by
  declining the other 12 rather than guessing. Every miss is round 1 or subject
  2's `_final`, which is round **2** — a classifier keyed on "final" would have
  called it the last round, and a fallback that counted review cycles would have
  been right there and wrong elsewhere.
- **R4** assumes the reviewer runs its own diff and the corpus captured it. The
  review skill requires it; the Codex brief cannot carry it.

## Disagreements against the wave-1 reconstruction of `dotfiles#96`

The wave-1 record is
[`OBSERVATION.md`](../work-on-wave-1-pilot/evidence/post-stop/dotfiles-96/OBSERVATION.md),
built from harness transcripts rather than from the sink. Four comparisons.

1. **The R1–R4 review chain: full agreement, independently derived.** The
   OBSERVATION states the exact chain — cumulative R1 at `a0214ff`, delta R1
   `a0214ff..2850ebc`, cumulative R2 at `2850ebc`, delta R2 `2850ebc..7688473`,
   cumulative R3 at `7688473`, delta R3 `7688473..19923be`, final cumulative R4
   at `19923be`. The rule recovers all seven pairs plus the readiness worktree
   sweep, from the reviewers' own diffs, with no pair the sink does not also
   hold and none it holds that the rule missed.
2. **`0f50132` was never independently reviewed, and the rule makes that
   visible.** The OBSERVATION's coarse-rerun table names two candidate
   transitions in the last stretch — `7688473..0f50132` then `0f50132..19923be`
   — while the review chain shows one delta review spanning both. The
   reconstruction confirms it: `0f50132` is in the PR's commit list and in no
   review delegation. This is a refinement of the wave-1 record, not a
   contradiction of it.
3. **Implementation launches: the rule and the sink disagree, and the rule is
   right.** The sink holds 1 `subagent_launch`; the corpus holds 5 — one
   `spawn_agent` and four `followup_task` continuations into the retained
   delegate. Those four *are* the four remediation rounds the OBSERVATION
   adjudicates. The sink's `Remediation implementation launches` row documents
   itself as counting fallback rather than logical rounds; the corpus counts the
   rounds. This is the one axis where deleting the sink strictly improves the
   evidence.
4. **The coarse-rerun timing is reproducible in identity but not in duration.**
   The OBSERVATION's same-candidate coarse repetitions are recoverable as
   commands: the rule finds all five executions of
   `bash scripts/run-tests --suite update-agent-tools-check.bash`, at the same
   candidates, in the same order. Their durations are not: the sink records
   61.7–75.5 s each, and the rule reports ~30.2 s each, because every one of them
   yielded and the agent printed the poll handle in a bespoke format. Any
   cost-of-repetition statistic built on the corpus alone would understate these
   by roughly 2.4×.

Points 3 and 4 are the two that matter for later tickets: the corpus is *better*
than the sink at counting what the workflow did, and *worse* at costing it.

## Claude Code — bounded capability and source-shape check

**Confidence: low, and stated as such.** One run, inspected as a capability
check, not a reconstruction with a population behind it. What would raise it: a
second Claude Code run with concurrent `Agent` launches in one assistant message,
which is the only join here with a known untested failure mode.

The authored inputs #145 will reason about are **all visible** on Claude Code:

| #145's input | Visible? | Where |
|---|---|---|
| delegation brief | yes, plaintext | `Agent.input.prompt`, in full |
| review kind and scope | yes | stated in the brief — "STANDARDS axis of a two-axis code review", "adversarial closure trace sweep" |
| phase | partly | implied by the brief's wording; never named |
| round | yes, where authored | `Agent.input.description` — "Round 2 standards review"; 6 of 10, all correct |
| compared candidate identity | yes | the brief states `git diff <base>...HEAD` and lists the commits; the last abbreviated SHA resolves to the exact head |

The result: with R4b reading the brief, the rule recovered subject C's compared
candidates 10 of 10 and its `input_bytes` byte-exact for all 9 committed
comparisons — the same standard as the Codex subjects, by a different path.

### The Codex/Claude asymmetry, tested rather than assumed

#142's Notes record one difference: Codex `NEW_TASK` payloads are
`encrypted_content` while Claude Code `Agent` briefs are plaintext. **The
asymmetry is confirmed** — every Codex `spawn_agent` message on both subjects is
`gAAAAA…` Fernet ciphertext in the parent rollout, and every Claude Code brief is
readable text.

It is also **smaller than it looks**, because Codex leaks the same facts through
three other channels the encryption does not cover:

- `spawn_agent`'s `task_name` argument is plaintext, and so is the child's
  `session_meta.agent_path` — which is how R3 works at all;
- the reviewer's own `git diff` names both compared SHAs in full;
- where the workflow writes a review package to disk, the authoring patch is in
  the corpus and names the kind and round outright — subject 2's eight packages
  are headed `Cumulative review assignment — issue 96, initial gate`,
  `Delta review assignment — issue 96, remediation gate 1`, and so on.

**Classification, owed for both harnesses.** For each gap, whether it is a
property of a harness, of a harness *version*, or of delegation as such:

| Gap | Classification | Reasoning |
|---|---|---|
| brief is opaque | **harness version.** Both subjects ran Codex CLI `0.149.0`. Encryption of `NEW_TASK` is a transport choice, not a consequence of delegating, and Claude Code delegates without it | evidence: `session_meta.cli_version` on both subjects; the plaintext `Agent` brief on subject C |
| compared candidate not in the brief | **not a gap on either harness** — recoverable on Codex from the reviewer's diff, on Claude Code from the brief | 36 of 36 |
| `phase` absent | **delegation as such.** Neither harness records it, and neither could: it is a workflow ruling about where in its own lifecycle it stands, with no observer | absent on all three subjects |
| `round` partly absent | **delegation as such**, mitigated by authoring. Neither harness records it; both preserve it when the primary writes it into a name or a brief | 24 of 36 |
| validation exit status absent | **harness.** Codex's `exec` returns a program's chosen output; Claude Code's `Bash` result carries an error flag. Different harness designs, not a property of delegation | 0 of 70 on Codex; Claude Code's flag is present but the status itself is not |
| worktree bundle bytes absent | **delegation as such** — and in fact not about delegation at all. Uncommitted bytes stop existing | 3 of 3 |
| token accounting differs | **harness.** Both expose it; the split between fresh input and cache reads differs and must be stated by any projection | both |

**Does any of this change #145's provider-neutral annotation decision?** One
thing does, and it is not the encryption. The facts #145 would annotate — role,
kind, compared candidate — turn out to be recoverable on **both** harnesses,
Codex included, without any annotation. The facts that stay unrecoverable —
`phase`, and `round` where nobody wrote it down — are unrecoverable on both, for
the same reason, and no annotation of a *delegation* would fix them: they are
properties of the run's lifecycle, not of the launch. That is a provider-neutral
conclusion reached from asymmetric evidence, which is what the proportional rule
was for.

**No concrete ambiguity surfaced that needs a second full Claude reconstruction.**
The one untested failure mode — concurrent `Agent` launches in a single assistant
message — is a property of R2's ordering join, not of the annotation question, and
it is named here rather than resolved.

## What Moraine could project but does not

Reported, not fixed; #142 records the fix as a Moraine ticket and out of scope
here.

1. **Codex parentage is in the raw evidence and not projected.** Every Codex child
   `session_meta` carries `parent_thread_id`, `forked_from_id`, and a `source`
   object with the full `thread_spawn` record. Moraine leaves `agent_run_id` empty
   for Codex and emits no link rows, so this rule reaches parentage by parsing
   `payload_json` itself. It works, and it means every consumer must re-implement
   the same parse. Claude Code, by contrast, *is* projected — `agent_run_id` and
   `is_substream` are populated — so the two harnesses expose the same fact
   through two different surfaces.
2. **`agent_label` and `coord_group_*` are empty on both harnesses**, on every
   subject. The columns exist; nothing fills them. Codex's `agent_path` would fit
   `agent_label` exactly.
3. **`session_meta` rows carry a misleading `event_ts`.** The exported timestamp
   is not the session's start — subject 1's primary shows `02:21:24` for a session
   that began `02:15:47`. The true start is `payload.timestamp`. Any rule using
   the column instead of the payload will place sessions wrongly, and the error is
   silent.
4. **Codex `session_meta.payload.session_id` is the *parent's* id, not the row's.**
   The row's own `session_id` column is correct; the payload field of the same
   name is not the same thing. This is a trap, not a projection gap, and it is
   recorded here so the next reader does not fall into it.

## Reproducing

```sh
node .agents/evals/work-on-run-reconstruction/reconstruct.mjs \
  --repo faviann/skills --pr 139 \
  --repo-path /home/faviann/repos/skills --window-hours 6 \
  --sink "$(git rev-parse --path-format=absolute --git-common-dir)/work-on-telemetry/runs/20260827T021641Z-64d9f9e1.jsonl"
```

`--sink` is optional and only checks the reconstruction; nothing the rule recovers
is read from it. Each subject takes two to twelve minutes, dominated by Moraine
exports.

The rule's pure joins — command extraction, role and round classification, brief
parsing, execution pairing — are held to the behaviour reported above by
[`test-reconstruct.sh`](./test-reconstruct.sh), which runs in the repository's
shell test set and needs neither Moraine nor GitHub.
