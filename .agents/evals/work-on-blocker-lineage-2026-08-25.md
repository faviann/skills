# work-on blocker lineage — 2026-08-25

Reproducible census of **why** accepted blockers arose across the mechanism-matched
`/work-on` reference runs, and of what a numeric Corrective-batch guard would have
done to them.

This file exists so the result "24 of 33 accepted post-initial-gate blockers in
overmind PR 211 were introduced by a prior remediation directive" is auditable and
replayable rather than resident in a conversation. It is evidence, not a decision.
The decision it fed is recorded on
[skills#101](https://github.com/faviann/skills/issues/101) (supersession comment)
and [skills#98](https://github.com/faviann/skills/issues/98).

Companion to the 2026-08-13 review-churn packet in this directory, which asked
*how much* repeated work happened. This one asks *what caused each repetition*.

## Status

Complete for the three post-#91 Claude runs named by
[skills#102](https://github.com/faviann/skills/issues/102) as the mechanism-matched
historical comparison set. Not a population estimate; not a statistical experiment.

## Evidence authority

Per skills#98, in order:

1. **Raw harness transcripts** — authoritative for agent, tool, and adjudication
   activity. Reached here through Moraine (see *Substrate*), which indexes the same
   `~/.claude/projects/**/*.jsonl` files rather than replacing them.
2. **Repository and GitHub artifacts** — authoritative for candidate identity,
   commits, and outcomes.
3. `work-on` telemetry and PR tables — corroboration only. The sink is known to
   undercount; no count below is taken from it except where explicitly labelled as
   a PR-table phase measurement.

## Substrate

Moraine 0.7.3, local, ClickHouse-backed. At the time of this census:

| Fact | Value |
|---|---|
| `moraine.events` rows | 562,674 |
| `moraine.ingest_errors` rows | 0 |
| Ingested harnesses | `claude-code`, `codex` |
| Claude Code source glob | `~/.claude/projects/**/*.jsonl` |

Moraine ingests both the main session stream and the per-subagent streams
(`<session>/subagents/agent-<id>.jsonl`), which is what makes reviewer reports and
their prompts reachable. The raw `.jsonl` files and the harness `tasks/*.output`
files are independently retained on disk; Moraine is an index over them, not the
system of record.

Project identifiers used below:

| `project_id` | Repository |
|---|---|
| `git:b11613658de57aa1656b449dd5c415f8c22e5f1d7e365f7df652b49e6a0b9b02` | `overmind` |
| `git:f61a97bd2a1f327a04d202ad962b454d1c540d3843bdba5cab38bd531740f880` | `homelab-iac` |

## Source locators

| Run | Session id | Span | Subagent runs |
|---|---|---|---|
| overmind PR 211, main | `59062897-4c5b-4ace-a66e-0d27e97cc289` | 2026-08-21 22:59:12 → 2026-08-22 02:18:36 | 24 |
| overmind PR 211, corrective pass | `d4705aba-93f3-40b9-973e-7628560fba05` | 2026-08-22 14:34:06 → 14:48:03 | 0 |
| homelab-iac PR 180 | `a159436f-d21e-4731-bbd9-3e7cdfb0692c` | 2026-08-22 16:14:24 → 2026-08-23 20:28:25 | 11 |

homelab-iac PR 177 (the clean fixed-floor reference) needed no transcript work: it
carries one commit, therefore zero Corrective batches.

## Queries

All against `http://127.0.0.1:8123/` (`POST`, body = query).

Session inventory for a repository and date window:

```sql
SELECT session_id, harness, min(event_ts) st, max(event_ts) en,
       count() n, uniqExact(agent_run_id) runs
FROM moraine.events
WHERE project_id = '<project_id>'
  AND session_date BETWEEN '<from>' AND '<to>'
GROUP BY session_id, harness
ORDER BY st FORMAT TSV
```

Subagent fan-out and per-agent cost within a session:

```sql
SELECT agent_run_id, min(event_ts) st, max(event_ts) en, count() n,
       sum(input_tokens) inp, sum(output_tokens) outp,
       sum(cache_read_tokens) cache_read, sum(cache_write_tokens) cache_write
FROM moraine.events
WHERE session_id = '<session_id>'
GROUP BY agent_run_id
ORDER BY st FORMAT TSV
```

Reviewer prompts, verbatim (establishes each gate's review scope):

```sql
SELECT event_ts,
       JSONExtractString(JSONExtractString(payload_json, 'input'), 'prompt')
FROM moraine.events
WHERE session_id = '<session_id>'
  AND tool_name = 'Agent' AND tool_phase = 'request'
ORDER BY event_ts FORMAT TSV
```

Remediation directives, verbatim (the accepted-blocker record):

```sql
SELECT event_ts,
       JSONExtractString(JSONExtractString(payload_json, 'input'), 'message')
FROM moraine.events
WHERE session_id = '<session_id>'
  AND tool_name = 'SendMessage' AND tool_phase = 'request'
ORDER BY event_ts FORMAT TSVRaw
```

Primary adjudications and subagent reports:

```sql
SELECT event_ts, agent_run_id, text_content
FROM moraine.events
WHERE session_id = '<session_id>'
  AND event_kind = 'message' AND actor_kind = 'assistant' AND payload_type = 'text'
ORDER BY event_ts FORMAT TSVRaw
```

Role split (`agent_run_id = ''` is the primary; the implementation delegate and the
readiness reviewer are identified by their launch prompts):

```sql
SELECT agent_run_id, count() ev, sum(input_tokens + output_tokens) io,
       sum(cache_read_tokens) cache_read
FROM moraine.events
WHERE session_id = '59062897-4c5b-4ace-a66e-0d27e97cc289'
GROUP BY agent_run_id FORMAT TSV
```

## Projection and classification semantics

**Unit.** One **accepted blocker** is one enumerated item in a primary remediation
directive (`E1`, `G2`, `H4`, …). Directives are the accepted-blocker record because
adjudication happens before dispatch: a reviewer finding that is rejected never
becomes a directive item. Rejections are recorded separately in the primary's
verdict messages and are counted here only where a rejected finding later becomes
an accepted one.

**Corrective batch.** One automatic, accepted-blocker-driven correction after the
initial cumulative gate that changes exact candidate content identity. Operationally:
one dispatched directive whose result is committed. Many items in one directive are
one batch.

**Population for the headline result.** Accepted blockers raised *after* the initial
cumulative gate — that is, everything except the items produced by the first gate
against the initial implementation. This is the population a convergence guard would
act on.

**Primary cause plus secondary tags.** Each blocker takes exactly one primary cause
and zero or more secondary tags from:

| Class | Meaning |
|---|---|
| `remediation-introduced` | The defect did not exist before a prior accepted directive created it. |
| `remediation-worsened` | The defect pre-existed but a prior directive made it worse or harder to see. |
| `pre-existing-missed` | Present in the initial candidate or at base; earlier gates with the scope to see it did not. |
| `sibling` | A further instance of a mechanism whose earlier instances were already corrected. |
| `re-raised` | Previously raised and rejected, or previously excluded by a primary decision. |
| `contract-or-surface` | The contract, criterion, or validation surface is the defect's source. |
| `delta-miss` | Inside a completed delta gate's legitimate scope, and that gate missed it. |
| `cumulative-only` | Reachable only from context spanning documents, rounds, or files no single scoped read covers. |
| `nondeterministic-environmental` | Timing, concurrency, host, or environment produced it. |
| `unknown` | Not determinable from retained evidence. |

**The classes are not disjoint.** overmind PR 211's flagship defect is simultaneously
born in the initial implementation and worsened by remediation; forcing one label
loses the fact that decides the question. Primary-plus-tags is therefore required and
a single label is insufficient.

**Attribution rule.** `remediation-introduced` is asserted only where the primary's
own directive or verdict names the causal link, or where `git log -S` places the
defective text in a remediation commit. Inference from adjacency is not sufficient;
where evidence is absent the class is `unknown`.

**Judgment.** Classification of `sibling` versus `pre-existing-missed` is a judgment
call where a mechanism's instances were never enumerated. Both readings are recorded
in the notes column where they differ.

## overmind PR 211

*Supersede Phase 2 capture authority with the Moraine evidence boundary (#205)* —
[overmind#211](https://github.com/faviann/overmind/pull/211). Documentation-only,
23 Markdown files. Base `714c821`.

### Structure

Nine Corrective batches after the initial implementation. Every gate reviewed
`git diff 714c821...HEAD` — cumulative, never delta; verified by reading all 21
reviewer prompts. Remediation reused one persistent implementation delegate
(`a61433a389bf6e29f`) addressed by `SendMessage`, which is why the PR telemetry
records "Remediation implementation launches: 0".

| Batch | Commit | Committed | Directive items | Raised by |
|---|---|---|---|---|
| — | `421b265` | 23:14:00 | — | initial implementation |
| B1 | `ea2be74` | 23:23:47 | `E1`–`E13` (13) | initial cumulative gate |
| B2 | `bfde435` | 23:29:35 | `G1`–`G3` (3) | gate 2 |
| B3 | `f3f76ec` | 23:38:35 | `H1`–`H6` (6) | gate 3 |
| B4 | `305d0d8` | 01:43:30 | `J1`–`J5` (5) | gate 4 |
| B5 | `76fd53a` | 01:52:58 | `K1`–`K6` (6) | gate 5 |
| B6 | `ebd466a` | 02:04:29 | `M1`–`M7`, `N1` (8) | gate 6, plus the delegate |
| B7 | `8a97b61` | 02:10:34 | `P1`–`P3` (3) | gate 7 |
| B8 | `85b205c` | 02:14:08 | `Q1`–`Q2` (2) | final closure sweep |
| B9 | `68991ef` | 14:36:03 (next day) | maintainer rulings | maintainer, outside `/work-on` |

46 enumerated directive items across B1–B8. **33 of them were raised after the
initial cumulative gate** (B2–B8). 32 came from a review gate; `N1` came from the
implementation delegate pushing back on its own directive.

### Classification of the 33 post-initial-gate blockers

| Item | Primary cause | Secondary tags | Evidence |
|---|---|---|---|
| `G1` | `remediation-introduced` | `sibling`, `re-raised` | "Round 2 told you to leave `moraine-trace-event-model.md` alone. That was my error and I am reversing it" — B1's `E8` deliberately excluded it |
| `G2` | `remediation-introduced` | — | `CONTEXT.md` "states nothing further about Moraine" was written by B1's `E6`, and is false |
| `G3` | `sibling` | `pre-existing-missed` | `north-star.md` was the 5th of 7 documents stating the datastore prohibition; `E1` annotated 4 |
| `H1` | `remediation-worsened` | `pre-existing-missed` | see *Provenance checks*; the never-store banner |
| `H2` | `remediation-introduced` | — | "Round 3 had you stamp … That over-applies" — B2's `G1` |
| `H3` | `remediation-introduced` | — | B1's `E7` partitioned the glossary and left entries unassigned |
| `H4` | `remediation-introduced` | — | B1's `E1` added the gloss that "applies unamended" now contradicts |
| `H5` | `pre-existing-missed` | — | title/banner disagreement present since `421b265`, missed by gates 1–2 |
| `H6` | `re-raised` | `contract-or-surface` | deletion-gate clause rejected in B1 and B2; accepted here only as an attribution reframe. The removal itself was rejected six times across the run |
| `J1` | `remediation-introduced` | — | "My H3 wording is wrong" |
| `J2` | `remediation-introduced` | `cumulative-only` | blanket freeze in `decisions.md` (B1) versus the `AGENTS.md` carve-out and Phase 1 §5; reachable only across three documents |
| `J3` | `remediation-introduced` | — | B3's `H4` rewrote the preamble and broke its own cross-reference |
| `J4` | `pre-existing-missed` | — | present-tense ownership claims from `421b265`, missed by gates 1–4 |
| `J5` | `remediation-introduced` | — | B1 wrote both halves of the "when"/"because" disagreement |
| `K1` | `remediation-introduced` | — | "my J1 wording, again … The fix I asked for last round overcorrected" |
| `K2` | `sibling` | `re-raised` | 6th and 7th instances of the datastore mechanism; "This reverses my round-1 instruction to leave the handoff untouched" |
| `K3` | `pre-existing-missed` | `contract-or-surface` | live v1.0.0 blocker pointing at the retired capture track, present at base, missed by gates 1–5 |
| `K4` | `remediation-introduced` | `contract-or-surface` | B1 wrote the harness claim; #206 scope contradicts it |
| `K5` | `remediation-introduced` | — | B1 wrote both the "not a specification" disclaimer and the "amends" phrasing |
| `K6` | `remediation-introduced` | — | B3's `H4` preamble narrates its own edit |
| `M1` | `remediation-introduced` | `contract-or-surface` | supersession dropped the credential-separation rules; "my K1 wording explicitly demoted them to mere description" |
| `M2` | `remediation-introduced` | `pre-existing-missed` | "my K3 instruction had you annotate the dated v1.3 changelog record in place"; the missing version bump dates to `421b265` |
| `M3` | `remediation-introduced` | — | the pointer being relocated was written by B5's `K3` and is inaccurate |
| `M4` | `remediation-introduced` | `cumulative-only` | the preamble grew across B1, B3 and B4 to ~17 lines; no single round created it |
| `M5` | `pre-existing-missed` | `sibling` | `deterministic-secret-detection.md`, unmarked at base, missed by gates 1–6; further instance of the status-marker mechanism |
| `M6` | `remediation-introduced` | — | B5's `K5` reconciled one side of the wording only |
| `M7` | `sibling` | — | parallel `decisions.md` statement to the one `K3` annotated |
| `N1` | `remediation-introduced` | — | "my M7 directive was wrong" — same-batch reversal, raised by the delegate, not a gate |
| `P1` | `remediation-introduced` | — | B6's `M2` chose `v1.5`, colliding with a pre-existing `v1.5` label |
| `P2` | `remediation-introduced` | — | B6's `M6` changed `AGENTS.md` only, so `design-rules.md` drifted |
| `P3` | `remediation-introduced` | — | B4's `J4` added the tracker status now being removed |
| `Q1` | `remediation-introduced` | — | B6's `M1` added the preserved invariant without widening the three scope descriptions |
| `Q2` | `pre-existing-missed` | `sibling` | `capture-synthetic-slice.md` banner over-claims; further instance of the status-marker mechanism |

### Tally

| Primary cause | Count | Share |
|---|---:|---:|
| `remediation-introduced` | 23 | 70% |
| `remediation-worsened` | 1 | 3% |
| `pre-existing-missed` | 5 | 15% |
| `sibling` | 3 | 9% |
| `re-raised` | 1 | 3% |
| **Total** | **33** | |

`remediation-introduced` and `remediation-worsened` together: **24 of 33 (73%)**.

No blocker in this run classified `delta-miss` — no delta gate existed — or
`nondeterministic-environmental`. One blocker (`unknown`): none.

### The long chains

**Chain 1 — one paragraph, six batches.** The capture-safety / credential-separation
paragraph:

```
421b265  ships "Only new capture work falls outside it"        pre-existing
  E11 (B1)  reworded the banner
  H1  (B3)  SECURITY: banner lets a future projection skip the never-store scan
  H3  (B3)  the fix leaves glossary entries unassigned
  J1  (B4)  "authorization invariant still binds" re-grants withdrawn authority
  K1  (B5)  the overcorrection deletes credential separation outright
  M1  (B6)  SECURITY: deployed capture endpoints left unguarded
  Q1  (B8)  restoring it leaves three authority-scope lines too narrow
```

Both security-relevant findings in the entire run were created inside this chain and
caught inside it.

**Chain 2 — historical-record mutation.** `K3` (B5) → `M2` (B6) → `N1` (B6) → `P1`
(B7). A directive to annotate a dated changelog entry in place, corrected, then
repeated in a second file, then corrected again, then colliding with an existing
version label.

**Chain 3 — partial application producing siblings.** `E1` annotated 4 of the 7
documents carrying the datastore prohibition; `G3` found the 5th, `K2` the 6th and
7th. `E8` marked 3 of 6 capture research documents; `G1` found the 4th, `M5` the
5th, `Q2` the 6th. This is the unbounded validation surface skills#103 now bounds,
surfacing as serial sibling discovery.

### Cost distribution

Measured from Moraine, session `59062897-…`:

| Role | Events | `cache_read` tokens | `input+output` tokens |
|---|---:|---:|---:|
| Primary | 554 | 49,635,910 | 258,357 |
| Reviewers (21 runs) | 1,234 | 36,773,299 | 279,794 |
| Implementation delegate | 235 | 13,796,756 | 75,621 |
| Readiness reviewer | 67 | 2,043,291 | 15,922 |

Reviewers account for **69.9%** of subagent `cache_read` volume. Per-gate reviewer
read tokens (`cache_read + input`):

| Gate | Reviewed | Read tokens |
|---|---|---:|
| 1 | `421b265` | 3,435,543 |
| 2 | `ea2be74` | 3,707,519 |
| 3 | `bfde435` | 3,964,597 |
| 4 | `f3f76ec` | 4,568,773 |
| 5 | `305d0d8` | 5,411,316 |
| 6 | `76fd53a` | 5,420,821 |
| 7 | `ebd466a` | 7,014,324 |
| final sweep | `8a97b61` | 3,251,940 |

Read volume rises monotonically with cumulative diff size, not with the size of the
correction under review.

### How the run ended

Not on a convergence judgement. Maintainer message at 02:08:14:

> If we need another remediation round (or review) we're running low on usage I'll
> resume the work with another agent?

The PR narrative records the same fact: "the final two commits were verified directly
rather than by a further sweep, at the maintainer's instruction to stop spending on
review." Defect size was decreasing, not oscillating.

## homelab-iac PR 180

*test(workstation): remove the live Bitwarden archive dependency from workstation
regressions (#124)* —
[homelab-iac#180](https://github.com/faviann/homelab-iac/pull/180). Base `8b22faa`.

Two Corrective batches. All three gates reviewed `git diff 8b22faa...HEAD` —
cumulative; verified by reading all six reviewer prompts.

| Batch | Commit | Committed | Blockers |
|---|---|---|---|
| — | `0f2c330` | 16:55:13 | initial implementation |
| B1 | `f65a010` | 17:34:43 | 4, from gate 1 |
| B2 | `e05b53f` | 22:46:56 | 2, from gate 2 |

### Classification of the 6 accepted blockers

| Blocker | Primary cause | Secondary tags | Evidence |
|---|---|---|---|
| origin-firewall fixture drives the full role with no boundary | `pre-existing-missed` | `contract-or-surface` | Contract-backed against "every workstation regression fixture"; contested by three of seven reviewer reports and disclosed as contested |
| extra-vars marshalling loop duplicated per call site | `pre-existing-missed` | — | Present in `0f2c330`; the gate-1 directive would have added a fourth copy |
| `_serve_directory` never called `server_close()` | `pre-existing-missed` | — | fd leak in the newly added helper |
| uncited `os.chmod` on the staged binary | `pre-existing-missed` | — | Uncited mechanism in the newly added helper |
| install-task deletion leaves the suite green | `pre-existing-missed` | — | Same scope as gate 1, missed by method: gate 1 verified the tests pass, gate 2 mutation-tested whether they can fail |
| asset-selection deletion leaves the suite green | `pre-existing-missed` | `sibling` | Same mechanism as the preceding row |

### Tally

| Primary cause | Count |
|---|---:|
| `pre-existing-missed` | 6 |
| `remediation-introduced` / `remediation-worsened` | **0** |

Two of the six are a **reviewer-method miss, not a scope miss**. The primary's own
note: "Round 1's sweep produced a clean trace table and missed both gaps because it
verified that the tests *pass*; round 2 verified that they *can fail* … That
difference is the whole value of the gate."

### Cost distribution

From the PR's own phase table (telemetry, corroboration only — the sink is known to
undercount):

| Phase | Elapsed |
|---|---:|
| implementation | 0 s |
| checkpoint | 446 s |
| gate | 21,110 s |
| remediation | **488 s** |
| closeout | 2,316 s |

Corrective work is ~2% of the run. Review is ~84%.

### How the run ended

Also on a cost instruction, at 17:29 — "Understood — I'll stop after this round
rather than starting another gate" — after which the run resumed the next day and
completed.

## Provenance checks

`git log -S` in `faviann/overmind`, establishing the lineage of the flagship
security-relevant defect:

```console
$ git log --oneline -S'falls outside it' --all -- docs/capture-safety-budgets.md
f3f76ec Keep every Overmind write path under the never-store gate (#205)
ea2be74 Reconcile remaining capture authority surfaces (#205)

$ git log --oneline -S'Only new capture work' --all
ea2be74 Reconcile remaining capture authority surfaces (#205)
421b265 Supersede capture authority with the evidence boundary (#205)
```

Read: the phrase entered at `421b265` (the initial implementation), was reworded at
`ea2be74` (Corrective batch 1), and was removed at `f3f76ec` (Corrective batch 3).
Hence `H1`'s primary class is `remediation-worsened` with a `pre-existing-missed`
tag, not `remediation-introduced` — the run's own retrospective attributes it wholly
to the `E11` directive, and the git record shows that is not quite right.

Commit counts, establishing the batch totals:

```console
$ gh pr view 211 -R faviann/overmind --json commits   # 10 commits → 9 batches
$ gh pr view 180 -R faviann/homelab-iac --json commits # 3 commits → 2 batches
$ gh pr view 177 -R faviann/homelab-iac --json commits # 1 commit  → 0 batches
```

## The two-batch counterfactual

Applying skills#101's provisional bound — at most two automatic Corrective batches
after the initial cumulative gate, exhausting before a third candidate mutation — to
each mechanism-matched reference:

| Run | Batches | Guard behaviour |
|---|---:|---|
| homelab-iac 177 | 0 | never fires |
| homelab-iac 180 | 2 | never fires; exactly at the limit |
| overmind 211 | 9 | fires |

For overmind 211, exhaustion is detected when gate 3 produces a blocker requiring a
third mutation. Timeline:

| Event | Time | Elapsed from run start |
|---|---|---:|
| Run start | 22:59:12 | 0 |
| B1 `ea2be74` | 23:23:47 | 24m 35s |
| B2 `bfde435` | 23:29:35 | 30m 23s |
| Gate 3 verdict; B3 would be authorized | 23:36:52 | **37m 40s** |
| In-session run end | 02:14:32 | 3h 15m 20s |

The candidate handed back at exhaustion is `bfde435`. What it still contains:

- the `capture-safety-budgets.md` banner that `H1` (`f3f76ec`, batch 3) removes —
  the wording the primary judged would let a future Moraine-to-Overmind projection
  skip the deterministic never-store secret scan on ingested external content;
- the missing credential-separation invariant that `M1` (`ebd466a`, batch 6)
  restores, on capture endpoints that still ship.

Both are the guard's own doing in the sense that matters: the guard stops the
cleanup, and the cleanup is where both security fixes live.

Review volume avoided: gates 1–3 total 11,107,659 reviewer read tokens against
36,774,833 for the full run — roughly 70% avoided, at the cost of a defective
hand-back at 19% of elapsed time, with 7 further batches of real accepted blockers
outstanding.

skills#101's own class-C signal — "maintainers repeatedly create re-entry solely to
authorize the obvious next correction" — is what the maintainer would then have had
to do.

## Limitations

- **Directives are the accepted-blocker record.** A finding rejected at adjudication
  never appears. Rejection counts here come from the primary's verdict messages and
  are not independently reconstructed.
- **`sibling` versus `pre-existing-missed`** is a judgment call wherever a
  mechanism's instances were never enumerated; both readings are noted in the table.
- **No `delta-miss` observations exist** in this corpus, because no run under this
  workflow provenance used delta gates. The class is defined here for the pilot, not
  populated by it.
- **Token figures are Moraine's accounting** of the harness's reported usage.
  `cache_read` dominates and is priced differently from fresh input; it is reported
  as read *volume*, not as cost.
- **PR 211's own retrospective says "roughly four" rounds serviced its own
  directives.** This census finds the self-inflicted share materially higher (24 of
  33 blockers, 6 of 9 batches touching one chain). The retrospective was written
  from memory in the same session; this reconstruction is from the directive record.
- **The census does not establish that a smaller bound would have been better, or
  worse.** It establishes what the mechanism the bound meters actually was.
