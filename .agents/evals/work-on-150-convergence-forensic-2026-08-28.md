# work-on #150 convergence forensic — 2026-08-28

Reconstruction of the `/work-on` run that implemented
[skills#150](https://github.com/faviann/skills/issues/150) as
[PR #152](https://github.com/faviann/skills/pull/152), asking why a comparatively
simple final design needed 47 subagent launches, 15 review triads and ~2h 57m to
reach.

Commissioned by [skills#153](https://github.com/faviann/skills/issues/153). This
file is the deliverable that issue names.

## Status

**Investigative record. Not an approved workflow change.** Nothing here amends
`/work-on`, `#150`, or PR `#152`. No file under `skills/personal/work-on/` was
touched by this investigation. The routing in *Counterfactual* is a
recommendation to the maintainer, not a decision.

Single-run reconstruction. Not a population estimate and not a statistical
experiment. Companion to
[`work-on-blocker-lineage-2026-08-25.md`](./work-on-blocker-lineage-2026-08-25.md),
whose instrument this reuses, and to the 2026-08-13 review-churn packet in this
directory.

## Evidence authority

Per skills#98, in order:

1. **Raw harness transcripts** — authoritative for agent, tool, adjudication and
   review activity. Reached through Moraine (see *Substrate*), which indexes the
   same on-disk session files rather than replacing them.
2. **Repository and GitHub artifacts** — authoritative for candidate identity,
   commits, diffs, the issue contract and the published PR.
3. **The run's captured workflow provenance** — authoritative for the governing
   instructions in force.
4. **The old closeout telemetry table** — corroboration only. skills#143
   established it undercounts; every count below is re-derived from (1) or (2)
   except where explicitly labelled as a PR-table figure.

One deviation from the ideal is recorded in *Limitations*: on the `codex`
harness, the primary's `spawn_agent` / `followup_task` / `send_message` payloads
are stored encrypted, so reviewer launch prompts and remediation directives are
**not** readable from the primary session. They were reconstructed from the child
sessions' own transcripts and the primary's plaintext adjudication messages
instead. This is an extension of the 2026-08-25 instrument, not a replacement.

## Substrate

Moraine `0.7.3+g196bb7132871`, local, ClickHouse-backed at
`http://127.0.0.1:8123/`. At the time of this reconstruction:

| Fact | Value |
|---|---|
| `moraine.events` rows | 627,819 |
| `moraine.ingest_errors` rows | 0 |
| Ingested harnesses | `claude-code`, `codex` |
| Run harness | `codex` |
| Skills `project_id` | `git:b0930841b16f32f2c89906c6fdcd65e1a873c35cadd59161a52f087505ce21d9` |

On `codex`, each spawned agent is a **separate `session_id`**, not an
`agent_run_id` inside the parent. The 2026-08-25 instrument's per-`agent_run_id`
fan-out query therefore does not apply; role attribution here is by session
window and by reading each child's own first turns.

## Source locators

| Role | Session id | Span | Events |
|---|---|---|---|
| Primary | `01a044e7-bf9f-7e91-8181-4026dfbf6a0e` | 20:27:18 → 23:24:10 | 2,448 |
| Implementation delegate (retained throughout) | `01a044ec-b708-70a3-a035-072b261a47c9` | 20:32:39 → 23:00:11 | 1,922 |
| Readiness reviewer | `01a044fc-db33-7260-a03b-1d4d1926db8a` | 20:50:17 → 20:54:19 | 124 |
| Gate reviewers | 47 sessions, 21:11:00 → 23:17:47 | see *Wave map* | 5,313 |

All timestamps are `2026-08-27` UTC. Roles were confirmed from launch behaviour
in each child session, not from ordering: the primary is the only session
spawning *named workflow roles*; the delegate is the only child receiving
`followup_task` across the whole span; each reviewer opens by verifying a pinned
package SHA-256 and declares its axis. The primary is **not** the only session
carrying `spawn_agent` — see the reconciliation below.

Repository locators:

| Fact | Value |
|---|---|
| Base | `e90beb13018b1a4b572863e7ff0f540b552e472a` |
| Candidates | 10 commits, `87744de` → `c298820` |
| PR head at closeout | `c298820b7b547eea5b0bf495cc4b11ae0d7f6d9c` |
| Merge commit on `main` | `9201505` |
| Run identity (old closeout) | `20260827T202741Z-b05f10bb` |

**Session-count reconciliation.** The primary issued exactly 47 `spawn_agent`
calls (1 implementation + 1 readiness + 45 review), matching the old closeout's
figure. Moraine indexes **49** non-primary `codex` sessions in the run window.
The two extra sessions are **second-level delegates, not gate reviewers**: the
`closure_delta7` and `closure_delta8` reviewers each invoked this repository's
`code-review` skill, which spawns its own `standards_axis` and `spec_axis`
sub-agents.

```sql
SELECT session_id, event_ts,
       JSONExtractString(JSONExtractString(payload_json,'arguments'),'task_name')
FROM moraine.events
WHERE project_id = '<project_id>' AND tool_name = 'spawn_agent'
  AND tool_phase = 'request' AND session_id != '<primary>'
ORDER BY event_ts FORMAT TSV
```

```text
01a04565-3754-…  (closure_delta7)  22:45:47  standards_axis
01a04565-3754-…  (closure_delta7)  22:46:10  spec_axis
01a04575-83c4-…  (closure_delta8)  23:04:24  standards_axis
01a04575-83c4-…  (closure_delta8)  23:04:29  spec_axis
```

`01a04566-9d12-…` (22:45:48) is the child of the first; `01a04577-a6fa-…`
(23:04:24) is the child of the third. Both open by declaring the `code-review`
skill. Of the four nested spawns, Moraine indexes two child sessions: the
23:04:29 `spec_axis` output appears inside `01a04577-a6fa-…` rather than in a
session of its own, and the 22:46:10 `spec_axis` spawn has no indexed session at
all. That is a Moraine coverage gap, recorded in *Limitations*.

The `delta7` and `delta8` rows of the wave table count these as a fourth session
because their tokens are real and were spent reviewing that candidate. They are
**nested** review inside one axis, not a fourth independent axis, and the
independence properties skills#98 protects are unaffected. `delta8`'s 2,860,443
includes 707,133 of nested cost.

Five concurrent `homelab-iac` sessions in the same window (`01a04558-4501`,
`01a0455d-2bb0`, `01a04560-e77b`, `01a0456a-3d39`, `01a0456a-4ff2`) are a
separate `/work-on 202` run — verified from each session's own opening turns —
and are excluded.

## Queries

All against `http://127.0.0.1:8123/` (`POST`, body = query). These extend the
2026-08-25 set; the first two are that file's queries adapted to the `codex`
session model.

Session inventory for the run window:

```sql
SELECT session_id, harness, min(event_ts) st, max(event_ts) en, count() n
FROM moraine.events
WHERE project_id = '<project_id>'
  AND event_ts BETWEEN '2026-08-27 20:20:00' AND '2026-08-27 23:40:00'
GROUP BY session_id, harness ORDER BY st FORMAT TSV
```

Token decomposition per session (`input_tokens` is the harness's **total** input,
inclusive of cache reads; fresh input is `input_tokens - cache_read_tokens`):

```sql
SELECT session_id, min(event_ts) st, sum(input_tokens) inp, sum(output_tokens) outp,
       sum(cache_read_tokens) cr, sum(cache_write_tokens) cw
FROM moraine.events
WHERE project_id = '<project_id>'
  AND event_ts BETWEEN '2026-08-27 20:20:00' AND '2026-08-27 23:40:00'
GROUP BY session_id ORDER BY st FORMAT TSV
```

Orchestration shape and wave map (`task_name` is plaintext even where the
message body is not):

```sql
SELECT event_ts, tool_name,
       JSONExtractString(JSONExtractString(payload_json,'arguments'),'task_name')
FROM moraine.events
WHERE session_id = '01a044e7-bf9f-7e91-8181-4026dfbf6a0e'
  AND tool_name IN ('spawn_agent','followup_task','send_message','interrupt_agent')
  AND tool_phase = 'request'
ORDER BY event_ts FORMAT TSV
```

Primary adjudications, verbatim (the accept/reject record, plaintext):

```sql
SELECT event_ts, text_content
FROM moraine.events
WHERE session_id = '01a044e7-bf9f-7e91-8181-4026dfbf6a0e'
  AND event_kind = 'message' AND actor_kind = 'assistant'
ORDER BY event_ts FORMAT TSVRaw
```

Maintainer messages into the run:

```sql
SELECT event_ts, text_content
FROM moraine.events
WHERE session_id = '01a044e7-bf9f-7e91-8181-4026dfbf6a0e'
  AND event_kind = 'message' AND actor_kind = 'user'
ORDER BY event_ts FORMAT TSVRaw
```

Reviewer final reports, one row per reviewer session (the findings record):

```sql
SELECT min(event_ts) st, session_id, argMax(text_content, event_ts)
FROM moraine.events
WHERE project_id = '<project_id>'
  AND event_ts BETWEEN '<wave_start>' AND '<wave_end>'
  AND event_kind = 'message' AND actor_kind = 'assistant'
  AND session_id NOT IN ('<primary>','<delegate>')
GROUP BY session_id ORDER BY st FORMAT TSVRaw
```

Delegate work narrative (used to date mechanism introduction between commits):

```sql
SELECT event_ts, text_content
FROM moraine.events
WHERE session_id = '01a044ec-b708-70a3-a035-072b261a47c9'
  AND event_kind = 'message' AND actor_kind = 'assistant'
ORDER BY event_ts FORMAT TSVRaw
```

Mechanism lineage in git (the provenance check that fixes introduction and
deletion to commits):

```console
$ git log --oneline -S'freeze-state' e90beb1..c298820 -- skills/personal/work-on
c298820 Simplify frozen custody publication (#150)
2a63eb8 Harden frozen Run custody acceptance (#150)

$ git log --oneline -S'pending' e90beb1..c298820 -- skills/personal/work-on
c298820  9d22396  2a63eb8
```

Read: `freeze-state` and the pending/accepted variants **entered at `2a63eb8`**,
the fifth candidate, and left at `c298820`, the tenth. They were never in the
initial implementation.

## Classification semantics

**Material transition.** One candidate commit. Ten exist; each is classified
below on the six axes `#153` names. A commit may carry more than one axis; the
table gives the dominant one and notes the rest.

**Concern family.** A set of findings sharing one mechanism and one requested
remedy, regardless of which reviewer raised it or how it was worded. Families are
built from the reviewers' own reports, not from the primary's summaries.

**Accepted blocker.** One finding the primary adjudicated as contract-backed and
returned to the delegate. Because the `codex` directives are encrypted, accepted
blockers are counted from the primary's plaintext adjudication messages and
cross-checked against the resulting commit's diff. This is weaker than the
2026-08-25 census, which counted enumerated directive items directly; see
*Limitations*.

**Ratchet chain.** `mechanism A → defect in A → mechanism B to make A safe →
defect in A+B → mechanism C`, where the later deletion of A makes B and C
unnecessary. Asserted only where `git log -S` places the mechanism's introduction
in a remediation commit *and* the reviewer report naming the defect is on record.

## The short answer

The simpler design was never discovered late. **It was the initial
implementation.**

`manifest-identity.sh` at the first candidate commit `87744de` (21:05:42) already
published the fully bound manifest last, as the single commit point, with no
lifecycle state. It survived four review waves unchallenged on that axis. At
21:37 a closure reviewer reproduced a real criterion-3 boundary defect by
`SIGKILL`ing the freeze between the final `mv` and its stdout. The primary
adjudicated that finding under a **strict** reading of criterion 3 — a failed
invocation must leave nothing readable — and the remediation for it introduced
the `pending`/`accepted` freeze lifecycle at `2a63eb8` (21:48:34). Everything the
maintainer later deleted descends from that one adjudication.

The maintainer's intervention at 22:49:41 did not supply a missing fact. It
supplied the **opposite reading of criterion 3**: the final manifest rename *is*
the success point, so an interruption after it is a committed freeze rather than
a failed one. Under that reading the lifecycle has nothing to do, and it was
deleted at `c298820`.

Diffing the first candidate against the last, the freeze publication model is
structurally identical. The whole net semantic delta across ten commits in that
file is one accepted blocker: binding `run-identity` into the manifest header and
the binding digest.

```console
$ git diff 87744de c298820 -- skills/personal/work-on/scripts/manifest-identity.sh
# adds:  run-identity header line, identity in binding_digest, header 5→6 lines
# removes: rmdir/staging_dir reset (trap already covers it)
# publication order, commit point, and reader predicate: unchanged
```

So the causal mechanism is **not** "the workflow could not see the simple
design." It is: *a mid-run contract interpretation became a fixed premise that no
later gate was chartered to re-open, and the mechanism required by that premise
then generated its own defects for two further rounds.*

## Wave map

Fifteen review triads, each Standards + Spec + closure, launched with
`fork_turns: none`. `dN` waves review only the last correction; `final*` waves
are blind cumulative confirmations from the base.

| Wave | Launched | Candidate under review | Reviewer sessions | Input tokens | of which cache-read | Fresh input | Output | Accepted | Rejected |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| readiness | 20:50 | uncommitted worktree | 1 | 1,013,243 | 917,504 | 95,739 | 9,418 | 2 | 0 |
| c0 | 21:11 | `4fc9e49` (cumulative) | 3 | 5,185,653 | 4,761,600 | 424,053 | 27,561 | 4 | 2 |
| d1 | 21:27 | `4fc9e49→56f19fd` | 3 | 2,626,846 | 2,393,600 | 233,246 | 18,467 | 1 | 1 |
| d2 | 21:34 | `56f19fd→40208d8` | 3 | 1,272,924 | 1,135,872 | 137,052 | 12,656 | 0 | 1 |
| final | 21:37 | `e90beb1→40208d8` (cumulative) | 3 | 3,810,118 | 3,509,760 | 300,358 | 29,694 | **3** | 2 |
| delta3 | 21:51 | `40208d8→2a63eb8` | 3 | 1,593,978 | 1,394,688 | 199,290 | 17,229 | **3** | 0 |
| delta4 | 22:00 | `2a63eb8→9d22396` | 3 | 1,759,363 | 1,562,624 | 196,739 | 17,949 | 0 | 1 |
| final2 | 22:05 | cumulative to `9d22396` | 3 | 3,414,522 | 3,124,992 | 289,530 | 22,752 | 1 | 2 |
| delta5 | 22:11 | `9d22396→f76741d` | 3 | 1,420,307 | 1,275,392 | 144,915 | 14,285 | 0 | 0 |
| final3 | 22:15 | cumulative to `f76741d` | 3 | 3,129,377 | 2,865,152 | 264,225 | 24,149 | 0 | 2 |
| delta6 | 22:30 | `f76741d→83f9414` | 3 | 1,531,965 | 1,362,432 | 169,533 | 12,916 | 0 | 1 |
| final4 | 22:33 | cumulative to `83f9414` | 3 | 3,687,190 | 3,406,336 | 280,854 | 28,825 | 1 | 1 |
| delta7 | 22:44 | `83f9414→9f6ac62` | 4 | 2,748,475 | 2,548,224 | 200,251 | 19,863 | 1 (evidence) | 0 |
| final5 | 22:48 | cumulative to `9f6ac62` | 3 | 1,590,271 | 1,410,560 | 179,711 | 11,788 | **interrupted** | — |
| delta8 | 23:02 | `9f6ac62→c298820` | 4 | 2,860,443 | 2,637,312 | 223,131 | 24,151 | 0 | 1 |
| final6 | 23:09 | cumulative to `c298820` | 3 | 9,329,218 | 8,985,600 | 343,618 | 29,786 | 0 | 0 |

`final5` produced **no reports**: the maintainer's message arrived at 22:49:41
and the primary called `interrupt_agent` three times at 22:49:50 / :53 / :56,
stopping all three readers mid-review against a candidate the amendment had just
superseded. 1.59M input tokens, zero findings — correctly spent, in the sense
that continuing would have been worse.

`final6`'s 9.33M is the largest wave by a factor of two and a half. Its closure
reader independently re-executed the frozen public suites rather than trusting
supplied evidence, a discipline the primary explicitly tightened at 22:47:25
after a delta7 evidence-handling finding.

## Token decomposition

Descriptive harness evidence. Not cost, and not waste. `input_tokens` on this
harness is total input inclusive of cache reads.

| Role | Sessions | Input (total) | of which cache-read | Fresh input | Output | Cache-write |
|---|---:|---:|---:|---:|---:|---:|
| Primary | 1 | 47,568,165 | 46,950,912 | 617,253 | 94,417 | 0 |
| Gate reviewers | 47 | 45,960,650 | 42,374,144 | 3,586,506 | 312,071 | 0 |
| Implementation delegate | 1 | 39,933,662 | 39,245,312 | 688,350 | 115,284 | 0 |
| Readiness reviewer | 1 | 1,013,243 | 917,504 | 95,739 | 9,418 | 0 |
| **Total** | **50** | **134,475,720** | **129,487,872** | **4,987,848** | **531,190** | **0** |

96.3% of input volume is cache read. **Fresh** input — the part that reflects
genuinely new material entering a context — is 4.99M, and 72% of that belongs to
the 47 reviewers. No conclusion in this file rests on any of these figures.

## Chronological timeline

| Time | Event | Class |
|---|---|---|
| 20:27:19 | `$faviann-skills:work-on 150` | run start |
| 20:28:08 | primary self-corrects workflow source: no `docs/workflow.md`, falls back to `work-on` default | — |
| 20:31:01 | trusted snapshot frozen; 33 acceptance surfaces materialized | — |
| 20:32:11 | closability passes; manifest frozen against `e90beb1` | — |
| 20:32:39 | implementation delegate spawned (retained for the whole run) | — |
| 20:46:32 | delegate self-finds a real defect pre-handoff (custody-backed `read` touched the live workflow file) | correctness |
| 20:50:17 | readiness reviewer over the uncommitted worktree | gate |
| 20:54:19 | readiness: 2 blockers — fabricated custody trio accepted; 4 evidence branches lack discriminating fixtures | **A1**, **A2** |
| 20:58:09 | primary's own checkpoint finding: base suites were replaced, not reused (#150 says reused) | **A11a**, test-only |
| 21:05:42 | **`87744de`** — initial candidate. `prod +265/−925, prose +163/−307, test +583/−2059` | production/correctness |
| 21:06:33 | primary finds a flaky `awk \| grep -q` SIGPIPE assertion | **A11b**, test-only |
| 21:09:17 | **`4fc9e49`** — one-line flake fix | proof/test-only |
| 21:11 | **wave c0** cumulative gate | gate |
| 21:16:02 | accepts 4: legacy previous-body detection; real interruption fixture; static evidence for criteria 14/31–33. Rejects glossary (slice 2) and duplicated regex | adjudication |
| 21:25:49 | **`56f19fd`** — `prod +22/−10, test +143/0` | proof/test-only (+ production/correctness) |
| 21:30:17 | **d1**: Spec finds the c0 fix incomplete — a counterfeit `## Closure gate` *before* the real one still wins | **A3′**, remediation-introduced |
| 21:33:01 | **`40208d8`** — anchor to the *last* closure gate | production/correctness |
| 21:36:12 | **d2** clean. Standards repeats duplicated-parser | — |
| 21:37 | **wave final** — first blind cumulative confirmation | gate |
| 21:37:11 | **closure reviewer reproduces the criterion-3 defect**: `SIGKILL` after the final manifest `mv` gives `freeze_status=137`, zero stdout, and `read --run` exit 0 | **A8 — chain root** |
| 21:41:44 | primary accepts three: unbound run-identity (**A6**), tab-vs-space grammar (**A7**), and A8 under the **strict** reading of criterion 3 | **adjudication that fixes the run's direction** |
| 21:45:05 | delegate: "The freeze protocol now publishes a deliberately pending…" | mechanism **B** born |
| 21:48:34 | **`2a63eb8`** — `run-identity` + `freeze-state pending/accepted` + two manifest variants; header 5→7 lines | reviewer-induced defensive hardening (+ 1 required correctness fix) |
| 21:54:45 | **delta3**: acceptance becomes visible *before* fallible `rmdir` and stdout; reproduced via `/dev/full` and an injected cleanup failure. Plus a stale comment and an opacity-coverage regression | **defect in A+B** |
| 21:58:54 | **`9d22396`** — acceptance-candidate staging path, expanded `cleanup` trap, `exec mv` as the last operation | mechanism **C** |
| 22:04:10 | **delta4** clean. Standards' helper-extraction rejected | — |
| 22:08:18 | **final2**: `default-workflow.md` still directs `--kind/--phase` telemetry recording — criterion 14 incomplete | **A5′**, pre-existing-missed |
| 22:10:15 | **`f76741d`** — two prose clauses removed | documentation/instruction |
| 22:14:22 | **delta5** clean | — |
| 22:18:22 | **final3** clean but for the twice-rejected glossary and parser families | — |
| 22:21:39 | closeout-owned `npm test` fails 17/18: retained schema-2 suite calls the removed singleton provenance bootstrap | **A9**, remediation-introduced by `87744de` |
| 22:28:20 | **`83f9414`** — `test +9/−78`, sink-only again | proof/test-only |
| 22:32:30 | **delta6**: a closure reader reads "telemetry suites must pass unchanged" as forbidding the removal; primary rejects on the more specific frozen ruling | rejected |
| 22:37:34 | **final4**: Spec finds nested `telemetry` inside an acceptance row bypasses the top-level guard | **A10**, genuine |
| 22:42:35 | **`9f6ac62`** — closed five-key acceptance-row allowlist | reviewer-induced defensive hardening (over-broad remedy) |
| 22:47:25 | **delta7** clean on code; one evidence-handling correction accepted; primary *tightens* review expectations for the next wave | — |
| 22:47:59 | **final5** launched | gate |
| 22:49:41 | **maintainer intervention** — cumulative simple-design cleanup, four numbered instructions | contract amendment |
| 22:49:50–56 | primary interrupts all three `final5` readers | — |
| 22:50:27 | primary, with **no new implementation fact**: "no #150 criterion inherently requires `pending`/`accepted`… criterion 4 needs a mechanical distinction, and 'final manifest absent vs present' provides it" | adjudication |
| 22:59:50 | **`c298820`** — deletes `freeze-state`, both manifest variants, acceptance-candidate staging, its cleanup, the mechanism-specific fixtures, and the row-key allowlist; replaces the shallow `has("telemetry")` with a recursive key refusal | simplification/deletion |
| 23:08:28 | **delta8** clean on all three axes; explicitly confirms no criterion blocks the simpler model | — |
| 23:17:46 | **final6** clean: Standards 0, Spec 0, closure 33/33 `tested`, `npm test` 18/18 | — |
| 23:23:58 | PR #152 opened; run sealed | closeout |

### Candidate classification

| Commit | Time | Dominant class | Also | Prod / prose / test |
|---|---|---|---|---|
| `87744de` | 21:05 | production/correctness | simplification/deletion (1,011 insertions against 3,291 deletions; net −2,280) | +265/−925 · +163/−307 · +583/−2059 |
| `4fc9e49` | 21:09 | proof/test-only | — | 0 · 0 · +1/−1 |
| `56f19fd` | 21:25 | proof/test-only | production/correctness | +22/−10 · 0 · +143/0 |
| `40208d8` | 21:33 | production/correctness | — | +10/−8 · 0 · +9/0 |
| `2a63eb8` | 21:48 | **reviewer-induced defensive hardening** | production/correctness (`run-identity` binding) | +36/−24 · 0 · +69/−41 |
| `9d22396` | 21:58 | **reviewer-induced defensive hardening** | documentation | +11/−5 · +7/−6 · +65/−6 |
| `f76741d` | 22:10 | documentation/instruction | — | 0 · +4/−5 · +1/0 |
| `83f9414` | 22:28 | proof/test-only | incidental integration | 0 · 0 · +9/−78 |
| `9f6ac62` | 22:42 | **reviewer-induced defensive hardening** | — | +1/0 · 0 · +7/0 |
| `c298820` | 22:59 | **simplification/deletion** | production/correctness (recursive telemetry refusal) | +21/−36 · +6/−7 · +45/−67 |

Three of ten candidates are dominantly reviewer-induced hardening. Two of those
three (`2a63eb8`'s lifecycle half, `9d22396` entirely) were deleted whole by
`c298820`; the third (`9f6ac62`) was narrowed. No commit is dominantly incidental.

## Causal graph

```text
#150 criterion 3: "an interrupted or failed freeze leaves nothing
                   any later reader accepts as frozen custody"
        │  ← ambiguous: is the rename the success point, or is exit 0?
        │
87744de  manifest published last; presence = complete custody   [mechanism A]
        │      survives c0, d1, d2 unchallenged on this axis
        ▼
21:37  closure reviewer: SIGKILL after final mv → status 137, no stdout,
       read exit 0.  Real, reproduced, contract-backed under the STRICT reading.
        │
21:41  PRIMARY ADJUDICATION — strict reading accepted.  ← the fixed premise
        │
2a63eb8  pending/accepted freeze-state + two manifest variants  [mechanism B]
        │      (same commit also lands run-identity binding — genuinely required)
        ▼
21:54  delta3: acceptance visible before fallible rmdir/stdout
       (/dev/full, injected cleanup failure)                    [defect in A+B]
        │
9d22396  acceptance-candidate path + expanded trap + exec mv    [mechanism C]
        │
        ├── delta4 clean, final2 clean on this axis, delta5/final3 clean …
        │
22:49  MAINTAINER AMENDMENT — the rename IS the success point.
       Premise reversed.  B and C have nothing left to do.
        ▼
c298820  B and C deleted.  A restored, plus run-identity.  [final == initial]
```

A parallel, shorter chain:

```text
criterion 27 "any telemetry material at all is refused"
  87744de  top-level  has("telemetry")                      [A]
  22:37    final4 Spec: nested row telemetry slips through   [real defect in A]
  9f6ac62  closed five-key acceptance-row allowlist          [B — over-broad]
  22:49    amendment §2: enforce the requirement narrowly
  c298820  recursive exact-key refusal; unknown row keys allowed again
```

Here the defect was real and the fix was necessary; only the *breadth* of the
chosen remedy was ratcheted, and only the breadth was rolled back.

## Concern families

### Accepted — 13 families

**Count reconciliation.** The wave table's *Accepted* column sums to **16**
wave-sourced blockers. Adding the two primary-checkpoint findings that belong to
no review wave (base-suite replacement at 20:58, SIGPIPE flake at 21:06) and the
one closeout-suite blocker (A9 at 22:21) gives **19**, against the old closeout's
**18**. Two grouping ambiguities in the plaintext record each resolve the
difference on their own: at c0 the primary says it accepts *"four unique blocker
groups"* while naming three, and at delta7 it classifies its acceptance as *"an
evidence-handling correction rather than a code blocker"* (A12 below, excluded
from the family table for that reason). Per skills#143 the sink's 18 is
corroborating only; neither number is taken as authoritative, and no conclusion
in this file depends on which is right.

| # | Family | First wave | Raises | Fate at `c298820` | Required by #150's contract, or by an earlier implementation choice? |
|---|---|---|---:|---|---|
| A1 | Fabricated custody trio accepted by `read`/`verify` | readiness | 1 | survives | **contract** (criteria 1–4) |
| A2 | Frozen evidence population incomplete (criteria 8, 26–28) | readiness | 1 | survives | **contract** |
| A3 | Legacy previous-body format detection | c0 | 1 | survives | **contract** (criteria 20–24, 30) |
| A3′ | …the c0 fix was incomplete: counterfeit gate before the real one | d1 | 1 | survives | **earlier remediation** |
| A4 | No real interrupted-freeze fixture | c0 | 1 | survives | **contract** (criterion 3) |
| A5 | Static evidence over the frozen instruction surface (14/31–33) | c0 | 1 | survives | **contract** |
| A5′ | Residual `--kind/--phase` recording directives in prose | final2 | 1 | survives | **contract**, pre-existing-missed by three earlier gates |
| A6 | Run identity not bound into custody | final | 1 | **survives — the run's only net addition to the freeze model** | **contract** (criteria 1, 7, 8) |
| A7 | Validator accepted tabs where the contract says literal spaces | final | 1 | survives | **contract** |
| **A8** | **Failed freeze leaves acceptable custody (post-`mv` window)** | **final** | **2** (final, delta3) | **mechanism deleted** | **earlier implementation choice — and, upstream of that, one adjudication of an ambiguous criterion** |
| A9 | Retained schema-2 suite broken by the cutover | closeout suite | 1 | survives | **earlier implementation choice** (`87744de` removed the bootstrap it called) |
| A10 | Nested `telemetry` inside acceptance rows | final4 | 1 | **remedy narrowed** | **contract** (criterion 27); remedy breadth was not |
| A11 | Test-instrument defects (base-suite replacement; SIGPIPE flake; stale comment; opacity coverage regression) | checkpoint | 4 | 2 survive, 2 deleted with the mechanism | mixed |

**Nine of the thirteen families — A1, A2, A3, A4, A5, A5′, A6, A7, A10 — were
required directly by #150's trusted contract.** Three families, carrying four
raises, were required by an earlier implementation choice: A3′ (an incomplete
prior fix), A8 (twice, the ratchet), and A9 (the cutover breaking a suite the
contract requires to keep passing). The remaining family, A11, is four defects in
the proof instrument itself.

A12 — *supplied telemetry metadata is not reusable validation evidence*, raised
by a delta7 Standards reader at 22:44 and accepted at 22:47 — changed no code.
The primary's response was to require the next wave's reviewers to execute any
surface whose supplied event was insufficient, which is why `final6` costs 9.33M.

### Rejected — 3 families, 15 raises

| # | Family | Waves raised | Raises | Authority for rejection | Ever accepted? |
|---|---|---|---:|---|---|
| R1 | `CONTEXT.md` glossary is stale — update it | c0, final, final2, final3 | **4** | #150 + inherited ruling #147 assign vocabulary migration to slice 2 (#151) | never |
| R2 | Extract a shared helper (previous-body parser ×7; custody-cloning loops; `date`/`od` PATH shims; test assertion matrix) | c0, d1, d2, final, delta3, delta4, final2, final3, final4, delta8 | **10** | frozen Fowler baseline is advisory; no divergence or acceptance defect reproduced | never |
| R3 | "Telemetry suites must pass unchanged" forbids removing their renderer assertions | delta6 | 1 | more specific frozen decisions require every telemetry rendering rule to disappear | never |

**R1 and R2 account for 14 of ~33 adjudications and were rejected every time
under an authority that never moved.** Standards raised R1 in four of the six
cumulative waves; the answer was identical each time and was already written into
the frozen contract before the run started. R2 was raised in **ten of the fifteen
waves** by readers who could not know it had been rejected nine times, because
each was launched `fork_turns: none` with no adjudication ledger — by design.

Two of R2's raises are not visible in the wave table's *Rejected* column, which
is built from the primary's plaintext adjudications: at delta3 the primary
narrated only its three acceptances, and at final2 it rejected *"the repeated
glossary/duplication findings"* as one phrase covering both families. The
reviewer reports are the authority for the family table, and both waves carry an
R2 raise.
This is skills#134's mechanism, observed cleanly.

The maintainer's amendment independently ruled on R2 (§3: *"Do not extract a
shared legacy parser… unless the existing duplication has produced a real
divergence"*), agreeing with all ten rejections.

## Question 2 — when did the simple design become available?

**It was available from `87744de` at 21:05:42, because it *was* `87744de`.**
Pinned by:

- the initial file's own comment: *"The manifest is published last, so readers
  mechanically reject interrupted publication that exposes only one or two
  siblings"*;
- `git log -S 'freeze-state'` placing the lifecycle's introduction at `2a63eb8`,
  four waves later;
- the `87744de → c298820` diff of `manifest-identity.sh`, whose entire semantic
  content is the `run-identity` binding;
- the c0 closure reviewer's own criterion-3 row at 21:11, which read the
  manifest-last design as satisfying criterion 3 (*"staged publication,
  manifest-last acceptance marker… rejects partial custody"*).

Against `#153`'s four options, the answer is the third — **already available
before first independent review** — with a sharpening the issue's framing did not
anticipate: the simpler formulation was not merely *available*, it was *shipped*,
and was subsequently removed by remediation and then restored.

The one thing genuinely not knowable at 21:05 is the criterion-3 boundary defect
itself. That was real, and finding it was worth the wave. What was knowable, and
what nothing in the run was chartered to ask, is whether the *cheapest correct
response* to that defect was a lifecycle state machine or a one-sentence ruling
on what "failed freeze" means.

## Question 6 — the intervention, and the maintainer's hypothesis

The maintainer's testimony makes two claims. The transcript settles both.

**Claim 1 — no fact was missing. CONFIRMED.**

At 22:50:27, 46 seconds after the amendment landed, the primary produced the
complete analysis. In that window it launched no agent (only the three
`interrupt_agent` calls) and read no implementation file: its two `exec` calls,
at 22:50:03 and 22:50:08, read `SKILL.md`, `default-workflow.md` and
`closability-gate.md` — workflow governance on how to handle a trusted-maintainer
contract correction, not code or contract material bearing on the question:

> My current read is that no #150 criterion inherently requires `pending`/`accepted`
> state: criterion 4 needs a mechanical distinction, and "final manifest absent vs
> present" provides it. The one tension is criterion 3's earlier interpretation
> around stdout failure after commit; your amendment clarifies that the atomic
> final manifest rename is the freeze's success/linearization point…

No new implementation fact entered the session between 22:47 and 22:50. The
primary held the contract, the candidate, every reviewer report, and its own
adjudication ledger. The delegate held the code. Both had everything needed for
the contract-versus-mechanism comparison. The testimony's factual claim is
correct.

**What this does and does not establish.** It establishes that the primary could
*evaluate* a reversed reading of criterion 3 in 46 seconds against context it
already held, and that no fact was missing. It does **not** establish that the
primary would have *generated* that reading unprompted. The primary's own
framing throughout is receipt, not authorship — *"The simpler design is
authorized as a contract amendment"*, *"Your message is an explicit
trusted-maintainer contract correction"*, *"your amendment clarifies that…"*.
Validation on demand and generation on initiative are different capabilities,
and only the first is on the record. This distinction is a judgment call, flagged
as such, and it is why the recommendation below asks for a re-adjudication
*trigger* rather than asserting the primary would have converged on its own.

**Claim 2 — the distinction was attention level rather than information. CONFIRMED,
with one correction that matters for routing.**

The primary's own sentence names what actually changed: *"criterion 3's **earlier
interpretation**"*. The intervention's operative content was not a simplification
insight. It was a **reversal of an adjudication the primary had made at 21:41 and
never revisited**. Both readings of criterion 3 are defensible from the issue
text; the primary chose the strict one in good faith, on a reviewer's reproduced
evidence, and then treated it as settled — correctly, under the workflow's own
rules, since re-litigating adjudicated findings is exactly what the review-state
machine exists to prevent.

So the compressed form of the maintainer's hypothesis — *"no workflow role was
responsible for periodically discarding the accumulated implementation frame and
re-deriving the minimum mechanism from the contract"* — is right in substance but
one level too general. The specific gap this run demonstrates is narrower and
more actionable:

> **No role re-opens a prior contract *interpretation* when the mechanism that
> interpretation requires keeps generating defects.** The workflow re-reviews
> code every wave and never re-reviews its own rulings.

The distinguishing evidence is what the primary was doing at 22:47:25, two
minutes before the intervention: launching `final5` with a **stricter** evidence
expectation. The run was not converging toward simplification. It was adding
assurance to the complex candidate and heading for closeout. Left alone, `#152`
would very likely have shipped `pending`/`accepted` and its fixtures.

**The side agent.** Not present in Moraine. Every session active in the
22:30–22:50 window is accounted for: the `/work-on 150` run itself, and a
concurrent unrelated `/work-on 202` run in `homelab-iac`
(`01a04558-4501-…`, `01a04560-e77b-…`). The long-lived `claude-code` session
`39f7820d-…` records a single event in the entire run window. The side agent
therefore ran in a harness Moraine does not ingest, and its context cannot be
compared to the primary's from evidence. The distinction `#153` asks for — *"no
role owned this"* versus *"no role could have done this"* — is nonetheless
narrowed, not closed, by Claim 1: the primary held every fact the comparison
needs and could evaluate the reversed reading in under a minute, so "no role
could have done this" is not supported on the information axis. Whether any role
was *disposed* to generate it is not settled by this evidence. Reported as an
evidence gap rather than inferring the side agent's context.

## Question 7 — was the assurance worth the cost?

### Review work that materially improved final correctness

Every one of these survives in `c298820` and none was reachable from the
delegate's own green suite:

| Finding | Wave | Why it mattered |
|---|---|---|
| Fabricated custody trio verified and rendered (A1) | readiness | Direct criteria 1–4 violation; the delegate's own tests *asserted the broken behaviour* |
| Four criteria lacked discriminating fixtures (A2) | readiness | Four `tested` rows would have been false |
| Legacy previous-body misclassification (A3, A3′) | c0, d1 | Silent loss of historical provenance on migration |
| Run identity not in the binding (A6) | final | Copying a valid trio to any legal filename minted an identity freeze never produced — a direct break of freeze-only authority. **The single net addition to the freeze model across the whole run.** |
| Tab-separated body forms accepted (A7) | final | Published-surface grammar |
| Criterion-14 recording directives still in prose (A5′) | final2 | Static checks passed; the *instructions* still told the primary to call a deleted script. Three prior gates missed it |
| Retained schema-2 suite broken (A9) | closeout suite | `npm test` 17/18; caught only by the closeout-owned full run, not by any focused surface |
| Nested row `telemetry` (A10) | final4 | The exact quiet-regrowth path criterion 27 exists to close |

That is a strong return. Two of them (A9, A5′) were found only because the
workflow insists on a repository-wide suite and a *fresh blind cumulative* pass
after every delta — the properties skills#98 protects. A counterfactual with
fewer reviewers or delta-only gates loses both.

### Review work that was superseded, repeated, or spent on machinery later deleted

| Category | Measure |
|---|---|
| Findings whose requested mechanism was itself later deleted | **2** (A8 at `final`, A8 at `delta3`) |
| Findings invalidated by the later simplification | **2** (same), plus A10's remedy narrowed |
| Rejected findings re-raised under an unchanged authority | **14 raises across 2 families** (R1 ×4, R2 ×10) |
| Waves whose entire blocking content was the ratchet | **delta3** (reviewing `2a63eb8`), **delta4** (reviewing `9d22396`) |
| Reviewer input tokens on those two waves | 3,353,341 (2,957,312 cache-read; 396,029 fresh) |
| Reviewer input tokens on the interrupted `final5` | 1,590,271, zero findings |
| Reviewer input tokens on `delta8` (re-reviewing the deletion of B and C) | 2,860,443 |
| Elapsed on the ratchet: `2a63eb8` directive → `delta4` verdict (21:41:51 → 22:04:10) | **22m 19s** |
| Elapsed on undoing it: amendment → `delta8` verdict (22:49:41 → 23:08:28) | **18m 47s** |
| Combined, against 2h 56m 52s start-to-seal | **≈23%** |

Roughly **7.8M reviewer input tokens and ~41 minutes** are attributable to
mechanism B and C — their construction, their review, their own defects, and
their removal. `final6` would have run regardless and is not counted.

The remaining assurance cost is not obviously excessive. Of the fifteen triads,
**seven** produced an accepted blocker (c0, d1, final, delta3, final2, final4,
and delta7's evidence-handling correction), **seven** confirmed a clean state on
a candidate that had just moved (d2, delta4, delta5, final3, delta6, delta8,
final6), and one — the interrupted `final5` — produced nothing. Fourteen of
fifteen returned a usable verdict.

## Counterfactual — routing across #119, #120, #133, #134

### skills#119 — remediation ratchets complexity instead of reconsidering the mechanism. **Strongly supported. Primary route.**

This run supplies the cleanest instance yet of #119's exact shape, with the
introduction and deletion of the ratcheted mechanism both pinned to commits by
`git log -S`, and with the maintainer's amendment §4 stating the missing rule in
one sentence: *"Treat existing code and passing tests as liabilities, not reasons
for retention."*

But the run also **corrects #119's implicit model**. #119 frames the ratchet as
remediation preferring to harden over reconsidering. Here, remediation behaved
correctly at every step — each fix was minimal, TDD-driven, and adjudicated
against the contract. The ratchet's root is one level up: an **adjudicated
interpretation** of an ambiguous criterion, which then made B and C the only
correct responses available. Hardening was the *consequence*; the un-revisitable
ruling was the *cause*.

A #119 remedy that only asks the delegate or the primary "could this be simpler?"
would not have fired here. At every wave, the answer under the standing
interpretation was *no*.

### skills#120 — a local simple-design assessment before first independent review. **Not supported. Aimed at the wrong lifecycle point.**

The candidate entering first independent review already carried the final design.
A pre-review simple-design assessment would have found nothing to remove, and
would have cost a step. The complexity entered at remediation round five, roughly
36 minutes and four gates after the point #120 proposes to intervene.

This run is evidence that #120's intervention point is too early for this failure
mode. It is not evidence against #120 for other failure modes, and this file does
not argue for closing it.

### skills#134 — fresh review rediscovers settled concern families. **Strongly supported. Secondary route.**

14 raises across 2 families, every one rejected under an authority that was
frozen before the run began and never moved. R1 (`CONTEXT.md`) is the sharper
case: #150 and #147 explicitly assign it to slice 2, and the frozen contract
handed to every reviewer says so — yet four Standards readers raised it anyway.

The tax is real but bounded, and it is a **cost** tax, not the convergence cause.
Removing all 14 repeats changes no candidate and no commit. Note the tension #134
must resolve: `fork_turns: none` and a withheld adjudication ledger are exactly
what makes these reviewers independent, and skills#98's assurance properties
depend on that independence. R2's ten raises came from readers who each
correctly applied the frozen Fowler baseline to code they were seeing for the
first time. A remedy that leaks the ledger buys cheapness with independence.

### skills#133 — proof/test machinery becomes the dominant reviewed object. **Weakly supported. Do not force it.**

The surface reading fits: tests dominate every diff, `4fc9e49` and `83f9414` are
test-only candidates, and two of delta3's three accepted findings were instrument
defects. But the reviewed object that *moved* across the run was production
semantics, not the proof instrument. The mechanism-specific fixtures were downstream of mechanism B, not an
independent driver. Taking `test-validation-surface-manifest.sh` alone, the file
that carried them: `+50/−33` at `2a63eb8`, `+47/−2` at `9d22396`, `+40/−66` at
`c298820`.

So 97 lines entered that file across the two hardening commits and 66 left at
the cleanup — the same order of magnitude, as expected when a mechanism and its
fixtures are added and removed together. Real, and worth recording, but a symptom
of the #119 chain rather than a separate #133 instance. `#153` asked not to force this
analogy; it should not be forced.

### The problem this run discovers

Not covered cleanly by any of the four:

> **A contract interpretation made during adjudication becomes an unreviewable
> premise for the rest of the run.** The workflow re-reviews the candidate after
> every change and never re-reviews the ruling that shaped it. When an ambiguous
> criterion is adjudicated strictly, every downstream mechanism is *correct
> given the ruling* — so no reviewer, no delta gate, and no cumulative
> confirmation can surface the cheaper alternative, because the cheaper
> alternative is not a defect. Only an authority that can amend the reading can
> reach it, and in this run the only such authority was the human.

This is adjacent to #119 and should be recorded against it, not as a fifth
parallel issue. #153's completion condition asks for a route, and the honest
route is: **#119, with its causal model corrected to name adjudicated
interpretation rather than remediation preference as the ratchet's origin; #134
as a secondary, cost-only finding; #120 explicitly not supported by this run;
#133 not demonstrated.**

## Recommendation — what to grill next

One recommendation, per `#153`.

**Grill whether `/work-on` should re-adjudicate an interpretation when the
mechanism it requires produces a second defect.**

The concrete trigger is visible in this run and is mechanical, not a judgment
call: at delta3 (21:54), the mechanism introduced by the previous remediation
produced its own blocking defect. That is the `A → B → defect(A+B)` signature.
It occurred once, in a 15-wave run, 68 minutes before the human noticed the same
thing.

The question to grill is whether a trigger of that shape can be made to fire
without weakening skills#98:

- it must not re-open findings, only the interpretation that generated a chain —
  otherwise it becomes the re-litigation the review-state machine forbids;
- it must not read the adjudication ledger into a *reviewing* context —
  otherwise it buys convergence with independence and takes #134's tax the wrong
  way round;
- it must not fire on the ten R2 raises or the four R1 raises, which are
  repetition without chains;
- and it must be able to answer "the mechanism is correct but the premise is
  expensive," which no current axis (Standards, Spec, closure) is chartered to
  say.

The counterfactual worth pricing: had that trigger fired at 21:54, the run would
have re-derived the criterion-3 reading before building mechanism C, saving
`9d22396`, delta4 and delta8, and shortening the cleanup — **4,619,806 reviewer
input tokens** (delta4 1,759,363 + delta8 2,860,443) and roughly 30 minutes —
while keeping every finding in the *materially improved correctness* table above,
including A8's discovery, which is what made the ambiguity visible in the first
place. Whether the interrupted `final5` (1,590,271) also disappears depends on
where the trigger lands the run, so it is excluded from the figure.

**What not to grill.** Not the reviewer count: fourteen of fifteen triads
returned a usable verdict, and seven found real defects. Not #150's architecture. Not a second comparison run for symmetry —
`#148` is the collection point if one becomes worth reconstructing.

## Limitations

- **Directives and launch prompts are unreadable on this harness.** `codex`
  encrypts the `message` field of `spawn_agent`, `followup_task` and
  `send_message` in the primary's stream. The 2026-08-25 instrument's verbatim
  reviewer-prompt and remediation-directive queries return ciphertext here.
  Accepted blockers were therefore counted from the primary's plaintext
  adjudication messages and cross-checked against each resulting commit's diff,
  rather than from enumerated directive items. This is the one place where this
  reconstruction is weaker than its predecessor, and it is why the accepted-blocker
  count (19 groups) differs from the closeout's (18) without either being wrong.
  *This is a Moraine/harness observation, not a request to build capture.*
- **The side agent is not in the index.** See *Question 6*. Its context cannot be
  compared to the primary's from evidence; the conclusion there rests on what the
  primary itself did at 22:50:27, not on inference about the side agent.
- **Rejection counts are approximate.** The primary sometimes adjudicates a
  family in aggregate (*"the repeated glossary/duplication findings"*). Family
  membership is reconstructed from the reviewers' own reports, which are complete;
  the mapping to the closeout's "seventeen rejected" is not attempted.
- **Two of four nested `code-review` spawns have no dedicated indexed session.**
  The `closure_delta7` and `closure_delta8` reviewers each spawned a
  `standards_axis` and a `spec_axis` sub-agent (four spawns); Moraine indexes two
  child sessions, one of which carries both axes' output, and the 22:46:10
  `spec_axis` spawn has none. Nested review cost is therefore a floor, not a
  total. *This is a Moraine coverage observation, not a request to build
  capture.*
- **Token figures are Moraine's accounting of harness-reported usage.**
  `input_tokens` includes cache reads on this harness; the decomposition above
  subtracts them. Reported as read *volume*, never as cost, and no conclusion
  rests on them.
- **"Strict versus permissive reading of criterion 3" is a judgment call**, and
  it is the load-bearing one in this file. Both readings are defensible from
  #150's text; the transcript establishes which was chosen and when, not which
  was correct. The maintainer's amendment settled it prospectively.
- **No raw transcript content is reproduced here** beyond short quotations
  necessary to fix a claim, per `#153`'s guardrail. Every query needed to
  reproduce the underlying evidence is in *Queries*.
