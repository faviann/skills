# `work-on` A3 instrumented control window

Date: 2026-08-14

Status: **pre-registered. The window has not started and no outcome has been
observed.**

This file pre-registers stage **A3** of the ordered roadmap in
[#64](https://github.com/faviann/skills/issues/64): a control period of `work-on`
runs measured under today's semantics, before anything in those semantics
changes. A1 ([#66](https://github.com/faviann/skills/pull/66)) made a run
attributable; A2 ([#67](https://github.com/faviann/skills/pull/67)) made
closability an objective preflight so the control and every later candidate
share one filter. A3 spends neither on a new mechanism — it fixes, in advance,
which runs count and what would make the control fail.

It is written before any prospective run exists precisely so the sampling rule
cannot be chosen after the numbers are known. The protocol below is frozen at
merge; the results area is empty and is populated later by a separate PR that
must prove the frozen text is unchanged.

This is a pre-registration for one control window, not an experiment framework.
Nothing here generalises to B2, C3, or any later comparison window; each of those
declares its own.

<!-- A3-FROZEN-BEGIN -->

## Frozen protocol

Everything between the frozen markers is immutable once the protocol PR merges.
A later PR may append to **Protocol identity** and populate **Results**. It may
not edit one byte inside the markers — not the sampling rule, the eligibility
rule, the stopping rule, the classification rules, or the completion conditions.
See [Protocol identity](#protocol-identity) for the mechanical check.

### 1. What the window measures

Ordinary `work-on` runs, unchanged, recorded by A1's sink. The control exists so
that a later topology change (B1 onward) can be compared against something
rather than asserted. It measures resource use and review behaviour — launches,
reviews and reviewed bytes, validation executions, phase elapsed, remediation —
not quality of outcome.

### 2. Start boundary

The window opens at the merge commit of the A3 protocol PR on `origin/main`. A
run is inside the window when its telemetry run id is **strictly greater** than
that commit's UTC commit time, formatted as a run-id timestamp prefix:

```bash
TZ=UTC git show -s --format=%cd --date=format-local:%Y%m%dT%H%M%SZ \
  <protocol-merge-sha>
```

Run ids are `YYYYMMDDTHHMMSSZ-<8 hex>`, so this is a string comparison and needs
no clock reasoning beyond UTC.

Explicitly outside the window, and never samples:

- PR #66 (A1) and PR #67 (A2) — their implementation runs are **context, not
  samples**. Both changed `work-on` itself, neither was orchestrated through
  `/work-on`, and both predate this protocol.
- The A3 protocol run that produced this file.
- Every run started before the protocol merge, whatever its outcome.
- Any run that changes this protocol, including a results or extension PR.
- Any B1-or-later workflow-change implementation.

No run started before the merge may be admitted retroactively, even if its sink
survives and its record looks clean.

### 3. Population, unit, and order

**Population.** Every repository in which the installed `work-on` skill runs,
**except `faviann/skills`**. The expected sources are `faviann/overmind`,
`faviann/homelab-iac`, and `faviann/dotfiles`; the population is not that closed
list, so an ordinary run in another downstream repository is eligible on the
same terms.

`faviann/skills` is excluded as a whole repository rather than per run. A run
there can edit the very instruction files under measurement — including this
protocol — and #64's own stages land there. A bright line needs no judgement
call at selection time, which is the property that matters for a control.

**Unit.** One **finished telemetry run** — one `<run-id>.jsonl` sink that
recorded `run_finish`. That is the unit A1 measures: a run is what spends
launches, reviews, and validations. An issue or a PR can span several runs whose
sinks cannot be summed, so neither is the unit.

**One counted run per issue.** At most one run is counted per `(repository,
issue)` pair: the first finished eligible run for that issue in chronological
order. This deviates from #64's recommended "first eligible finished runs"
boundary, deliberately: a second run against an already-implemented candidate
inherits work it did not do, so its launch and review counts are not comparable
to a run that started from nothing, and one pathological issue could otherwise
supply most of a five-run control. Later runs on the same issue are recorded in
full as `continuation` attrition, so nothing is discarded — only re-scoped.

**Order.** Run ids sort lexicographically into UTC chronological order across
every repository. Ties within one second break by the full run id string. No
other ordering — not merge time, not PR number, not repository — is used.

### 4. Eligibility

A run is **counted** when all of the following hold:

1. it started inside the window (§2) in a repository in the population (§3);
2. its sink records `run_finish` with outcome `Closes` **or** `Progresses`;
3. its summary reports `schema: 1`;
4. it is the first finished eligible run for its `(repository, issue)` pair; and
5. a bounded record for it was exported durably (§7) before the next eligible
   run started anywhere in the population.

`Closes` and `Progresses` both count. Filtering to `Closes` would keep only the
runs that converged, which is the churn the control exists to observe.

The A2 gate is upstream of eligibility, not a condition of it: a run that
reaches `run_finish` with `Closes`/`Progresses` necessarily passed the gate.

### 5. Sample size, selection, and stopping

**The control is exactly five counted runs.** The number is fixed here, before
any prospective run exists.

Why five is proportionate and what it does not buy:

- The forensic packet's evidence rests on six *selected* pull requests. Five
  *unselected* consecutive runs is the same order of magnitude, obtained without
  the selection that made the original sample unusable as a baseline.
- Each run is hours of real work, and B1 is blocked until the control is
  accepted. Twenty runs would stall the roadmap for months and would still not
  be a controlled experiment, because the issues are heterogeneous and the
  operator and harness are single.
- Five gives a per-run *distribution* — launches, reviews, reviewed bytes,
  validations, phase elapsed, remediation rounds — rather than a point, which is
  enough to detect a gross regression (an order-of-magnitude change) in a later
  comparison window.
- It is **not** statistically conclusive. There is no randomisation, no
  matching, no control over issue difficulty, and n=5 supports no significance
  claim. Any later comparison that turns on a small difference is not settled by
  this control and must say so.

**Selection is not a choice.** The five counted runs are the first five eligible
runs in the order defined in §3. No run may be skipped, deferred, re-run, or
substituted because it was unusually cheap, unusually expensive, unusually
clean, embarrassing, atypical, or "not a fair test". A run that is eligible when
it finishes is in the sample. The per-run export in §7 happens before the next
eligible run starts, so the sequence is fixed while the set is still incomplete.

**Stopping.** The window closes when the fifth counted run has been exported.
Elapsed time is not a stopping condition: the window does not expire, and it
does not end early because enough time has passed or enough remediation has been
seen.

**No outcome-dependent extension.** If the five counted runs contain no
remediation-bearing run (§6), A3 is **insufficient**, not successful, and the
window does not silently continue until one appears. See §9.

### 6. Remediation-bearing classification

A counted run is **remediation-bearing** when its A1 summary's
`phase_elapsed_ms` object contains a `remediation` key — that is, when at least
one recorded event inside the summary window carries `phase: "remediation"`:

```bash
skills/personal/work-on/scripts/run-telemetry.sh summary --run <run-id> \
  | jq -e '.phase_elapsed_ms | has("remediation")'
```

A single remediation-phase event is enough; a zero-millisecond elapsed value is
not a disqualifier.

Commit counts, round counts in prose, and PR narrative never establish
remediation on their own. The PR body's `Remediation rounds` and
`Measured phase elapsed` rows are corroboration only:

- **Telemetry says remediation, body says none** → remediation-bearing.
  Telemetry wins. Record the flag `telemetry-body-mismatch`.
- **Telemetry has no remediation phase, body claims rounds ≥ 1** → **not**
  remediation-bearing. The run stays a counted sample; record the flag
  `remediation-unattributed`. A primary-supplied number is not a mechanical
  observation, and the completion condition in §9 requires a mechanically
  established one.
- **No summary obtainable at all** → the run is not counted; it is
  `unattributable` attrition (§8).

Events recorded after `run_finish` are outside the summary window by
construction, so they never contribute to this classification. Their count is
recorded (§7).

### 7. Evidence and durable export

#### The record

One record per run — counted **or** attrition. Every field is either mechanical
(copied from `run-telemetry.sh summary`, which is deterministic for a finished
run) or a small bounded envelope:

| Field | Source |
|---|---|
| `repository` | `owner/repo` slug |
| `issue` | issue number |
| `pr` | PR number, or `none` |
| `run`, `schema` | summary `run`, `schema` |
| `provenance` | the PR body's `Run N:` provenance line, verbatim |
| `started_at`, `finished_at` | summary |
| `final_workflow_outcome` | summary |
| `subagent_launches` | summary `total` and `by_role` |
| `reviews` | summary `total`, `by_kind`, `input_bytes` |
| `validations` | summary `total`, `passed`, `failed`, `interrupted`, `incomplete`, `duration_ms` |
| `phase_elapsed_ms` | summary, per recorded phase |
| `tokens` | summary `input`, `output`, `coverage` |
| `remediation` | `yes` / `no` by §6, plus any flag |
| `malformed_lines`, `events_after_finish` | summary |
| `disposition` | `counted`, or an attrition class from §8, with its reason |
| `summary_sha256` | `sha256sum` of the exact summary JSON |

Never estimate an unavailable value. A field the runtime did not expose is
recorded as the summary reports it — `tokens.coverage: "none"` is a result, an
invented token count is a fabrication.

#### The surface

**The primary durable surface is a structured comment on issue #64**, one per
run, posted at that run's closeout and before the next eligible run starts
anywhere in the population.

Why the issue thread and not only a committed file: it is durable independently
of any workstation, sink, branch, or unmerged PR; it is timestamped by the
tracker and carries an edit history the author cannot erase; it sits in the
issue that owns the investigation; and it exists *before* the results PR, so a
lost checkout costs nothing already exported. The committed results table in
this file is the **secondary** copy, transcribed later, and its values must
match the comments.

A record is posted as:

````text
A3-RECORD run=<run-id>

```json
{ …the record fields above… }
```
````

**A3 adds no step to `work-on`.** The export is an operator step performed after
the run, outside the workflow, because adding it to the workflow would change
the thing being measured. That is the whole reason it is written here and not in
a skill.

#### Duplicates, corrections, tampering

Run ids are unique by construction, so a duplicate is a second record with a run
id already present:

```bash
gh issue view 64 -R faviann/skills --json comments \
  --jq '[.comments[].body
         | capture("A3-RECORD run=(?<run>[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8})").run]
        | sort'
```

Check that list before posting. **A posted record is never edited.** A wrong
record is superseded by a new comment headed
`A3-CORRECTION run=<run-id> supersedes=<comment-id>` stating what was wrong and
why; both comments survive and the results table cites both.

Tampering is detectable three ways, and the closeout applies all three:
`summary_sha256` is recomputed from the surviving sink; the committed results
table and the issue comments are two independent copies that must agree; and
GitHub's comment edit history shows any rewrite. Where a sink no longer exists,
only the two-copy check and the edit history apply — that is a weaker guarantee
and is recorded as such rather than papered over.

#### What is never exported

Full prompts, briefs, or subagent reports; issue or PR bodies; source files;
diffs; command lines; command output; credentials; raw diagnostics; and raw sink
events exported wholesale for analytics. A1's schema has no free-form field, so
the mechanical part of a record cannot carry them; the envelope is a slug,
integers, one enum, and one provenance string. Raw JSONL sinks stay untracked in
each target repository's git-dir and are never committed.

### 8. Attrition and separate reporting

These are recorded with the same record shape and the same durable export. They
are **never** counted toward the five, and they are never silently dropped:

| Class | When |
|---|---|
| `preflight-aborted` | A2 closability gate aborted the run (`finish --outcome aborted`). Preflight attrition — reported, not review-churn evidence. |
| `no-candidate` | The run created no PR and so could not resolve `Closes`/`Progresses`. Reported with whatever the sink holds. |
| `incomplete` | The run never recorded `run_finish` — interrupted, abandoned, or killed. Setup and environmental failures that prevent finishing land here, named as such. |
| `continuation` | A later finished run for a `(repository, issue)` pair already counted (§3), including a resumed `/work-on` invocation. |
| `unattributable` | No summary is obtainable: the sink is gone, or no record was exported before the next eligible run started. |
| `out-of-window` | Started before the merge boundary, in `faviann/skills`, or is itself a protocol, results, or B1-or-later run. Listed so it is not mistaken for attrition: these runs are outside the window and need no record. |

Notes that are deliberately *not* attrition:

- Validation failures during a run that still finished. A `failed` validation is
  part of what the control measures.
- `malformed_lines > 0`. The sink is append-only and a torn line costs exactly
  one ignored event; the count is recorded as a data-quality flag.
- `events_after_finish > 0`. The summary window closed at `run_finish`, so the
  counted values are the published ones; the count is recorded.
- `validations.incomplete > 0`. Recorded as reported.

### 9. Completion decision rules

A3 is **complete** only when every one of these holds:

1. exactly five counted runs, per §4 and §5;
2. at least one is remediation-bearing by §6's mechanical test — a
   `remediation-unattributed` run does not satisfy this;
3. every eligible run was included in chronological order, with no skip,
   substitution, or retrospective selection;
4. every non-counted run in the window is recorded with an attrition class and
   a reason;
5. every counted and attrition run has a durable bounded record, with duplicates
   and corrections resolved per §7;
6. the frozen protocol identity verifies (see **Protocol identity**); and
7. no post-A2 workflow semantic changed during the window (§10), evidenced by
   the provenance check there.

A3 is **insufficient** when the five counted runs are collected and complete but
none is remediation-bearing. Then: B1 stays blocked; the control is recorded as
insufficient rather than successful; and any extension requires a **new, explicit
pre-registration merged before any further eligible run is observed**, naming its
own fixed count and its own failure outcome. Continuing to observe runs under
this protocol until a remediation appears is prohibited.

A3 is **invalid** when a frozen-protocol byte changed after the start boundary,
when an eligible run was skipped, when counted runs do not share one telemetry
schema version, when a frozen semantic changed mid-window, or when more than one
eligible run was lost to `unattributable`. One lost record is an accident and is
recorded as one; a second is a bookkeeping failure that makes the sequence
unverifiable, and an unverifiable sequence is exactly how an inconvenient run
would disappear. An invalid window is not repaired by argument; it is recorded
and re-registered.

**B1 remains blocked until a separate results/adjudication step accepts this
control.** Completion of the five runs is not acceptance. No stage may be
authorised by interpretation of a partial window, by a promising trend, or by
the observation that the runs "look like" the forensic sample.

### 10. Frozen comparison surface

These stay unchanged for the whole window. Changing any of them ends the control
rather than improving it:

- implementation delegation semantics;
- the readiness sweep;
- Standards review;
- Spec review;
- the closure sweep;
- adjudication;
- remediation;
- cumulative rereview;
- final validation;
- closeout;
- #62 mechanism-neighborhood behaviour;
- smell severity;
- refactoring and coherence behaviour;
- reviewer access to prior dispositions; and
- convergence behaviour.

A1 observation and A2 closability are part of this baseline and stay active.

No `work-on`, `tdd`, `code-review`, or closeout runtime instruction changes as
part of A3. A3 changes nothing that runs.

**Mechanical check.** `scripts/workflow-provenance.sh` fingerprints the governing
instruction files, and each counted run's PR body carries the result on its
`Run N:` line. The `work-on:`, `tdd:`, and `review:` components are computed from
the skills checkout and are therefore identical across repositories; at the
protocol merge they are:

| Component | Digest |
|---|---|
| `work-on` | `6a0c6e912785` |
| `tdd` | `aa54f63292bf` |
| `review` | `1aebe11f115e` |
| `workflow` (default) | `87087d1136ae` |

Every counted run must show these three repository-independent digests, with no
`*` suffix — a star means a governing file differed from its committed bytes
during the run. The `workflow:` component may legitimately differ per repository
(a target repository's own `docs/workflow.md` is the selected input), so it is
recorded per repository and must be constant *within* each repository across the
window.

A digest mismatch on `work-on`, `tdd`, or `review` means the measured
instructions changed: the window is invalid from that run onward under §9.

<!-- A3-FROZEN-END -->

## Protocol identity

The frozen region is the byte range from the `A3-FROZEN-BEGIN` marker line
through the `A3-FROZEN-END` marker line inclusive. Its digest:

```bash
sed -n '/^<!-- A3-FROZEN-BEGIN -->$/,/^<!-- A3-FROZEN-END -->$/p' \
  .agents/evals/work-on-a3-control-window.md | sha256sum
```

| Field | Value |
|---|---|
| Frozen-region sha256 | `e1cf42b1cbdb31ec4f410d1b6cb2d37f383d67c454e92bbe63fa8fa4202fe864` |
| Protocol merge commit | _recorded by the results PR_ |
| Start boundary (UTC) | _recorded by the results PR_ |

The digest is stored outside the frozen region so it can be recorded without
changing what it measures. The results closeout must:

1. recompute the digest above and confirm it equals the value in this table;
2. record the protocol merge commit SHA and the derived start boundary; and
3. confirm `git diff <protocol-merge-sha>..HEAD -- <this file>` touches no line
   inside the markers.

A results PR that cannot reproduce the digest has not populated this protocol —
it has replaced it, and the window is invalid under §9.

## Results

**Empty. The window has not started. No run has been observed, selected, or
counted.**

Populated only by a later PR, append-only, using the templates below.

### Counted runs

| # | Run id | Repository | Issue | PR | Outcome | Launches | Reviews (kinds) | Reviewed bytes | Validations (p/f/i/inc) | Phase elapsed | Tokens | Remediation | Record |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | | | | |
| 2 | | | | | | | | | | | | | |
| 3 | | | | | | | | | | | | | |
| 4 | | | | | | | | | | | | | |
| 5 | | | | | | | | | | | | | |

`Record` links the issue-#64 comment holding that run's exported record, and any
correction superseding it.

### Attrition and separately reported runs

| Run id | Repository | Issue | Class | Reason | Record |
|---|---|---|---|---|---|
| | | | | | |

### Data-quality flags

| Run id | Flag | Detail |
|---|---|---|
| | | |

Flags: `telemetry-body-mismatch`, `remediation-unattributed`,
`malformed-lines`, `events-after-finish`, `incomplete-validations`.

### Provenance check

| Run id | Repository | `work-on` | `tdd` | `review` | `workflow` | Matches frozen |
|---|---|---|---|---|---|---|
| | | | | | | |

### Closeout decision

| Condition (§9) | Met | Evidence |
|---|---|---|
| Five counted runs | | |
| At least one remediation-bearing | | |
| Chronological, no skips | | |
| Attrition fully accounted | | |
| Durable records for every run | | |
| Frozen identity verified | | |
| No frozen semantic changed | | |

**Verdict:** _complete_ / _insufficient_ / _invalid_ — with the reason, and an
explicit statement of whether B1 is unblocked. B1 is unblocked only by a
separate acceptance of a complete control, never by this table alone.

## Change log

Append-only. Anything recorded here happened outside the frozen region.

| Date | Change |
|---|---|
| 2026-08-14 | Protocol pre-registered. Window not started. |
