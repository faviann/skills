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
merge; the results area is empty and is filled in one record at a time, as
append-only commits on a single long-lived draft results PR, as the window runs.

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

### 2. Window boundaries

**Opens** at the merge commit of the A3 protocol PR on `origin/main`. A run
enters the window when its telemetry run id is **strictly greater** than that
commit's UTC commit time, formatted as a run-id timestamp prefix:

```bash
TZ=UTC git show -s --format=%cd --date=format-local:%Y%m%dT%H%M%SZ \
  <protocol-merge-sha>
```

Run ids are `YYYYMMDDTHHMMSSZ-<8 hex>`, so entry is a string comparison and needs
no clock reasoning beyond UTC.

**Closes** at the end of the second containing the fifth counted run's
`finished_at` — the **boundary second**.

Closure is resolved only once that second is complete. A1 timestamps at
one-second resolution (`epoch_ms` is whole seconds carrying `000`), so several
runs can share a `finished_at` and no finer durable boundary exists to appeal
to. Until the boundary second has elapsed, a fifth-place run is *provisional*:
another run may still finish inside the same second and sort ahead of it under
§3's total order, because that order breaks ties by run id and a run that started
earlier carries the smaller id whenever it finishes.

So: let the boundary second complete, enumerate every run in the population that
recorded `run_finish` within it, apply §3's total order across all of them, and
take the first five. Only then is closure final — and it is then irreversible.

Any run that records `run_finish` after the boundary second, or inside it but
beyond fifth place, is outside the window whatever its start time. Any run still
unfinished when the window closes is `incomplete` (§8). There is no abandonment
decision to make and none to defer.

Explicitly outside the window, and never samples:

- PR #66 (A1) and PR #67 (A2) — their implementation runs are **context, not
  samples**. Both changed `work-on` itself, neither was orchestrated through
  `/work-on`, and both predate this protocol.
- The A3 protocol run that produced this file.
- Every run started before the protocol merge, whatever its outcome.
- Any run that changes this protocol, including a record, results, or extension
  PR.
- Any B1-or-later workflow-change implementation.

No run started before the merge may be admitted retroactively, even if its sink
survives and its record looks clean.

### 3. Population, unit, and order

**Population — a closed list, frozen here:**

| Repository |
|---|
| `faviann/overmind` |
| `faviann/homelab-iac` |
| `faviann/dotfiles` |

A run in any other repository is out of the window. Adding, removing, or
substituting a repository requires a **new pre-registration merged before any
further eligible run is observed** — it is a change to the sampling rule, not an
administrative detail. A list that could grow after the protocol merged would
make population completeness unauditable and would let the choice of where to
work decide which runs became samples.

`faviann/skills` is deliberately absent: a run there can edit the very
instruction files under measurement, including this protocol, and #64's own
stages land there.

Completeness is therefore mechanically auditable. In each listed repository:

```bash
ls "$(git rev-parse --absolute-git-dir)/work-on-telemetry/runs/"
```

Every run id in that listing that falls inside the window (§2) must appear in
the results as counted or as one attrition class (§8). That enumeration is the
audit; it is run per repository at closeout and its output is recorded.

**Unit.** One **finished telemetry run** — one `<run-id>.jsonl` sink that
recorded `run_finish`. That is the unit A1 measures: a run is what spends
launches, reviews, and validations. An issue or a PR can span several runs whose
sinks cannot be summed, so neither is the unit.

**One counted run per issue.** At most one run is counted per `(repository,
issue)` pair: the first finished run for that issue in the order below. This
deviates from #64's recommended "first eligible finished runs" boundary,
deliberately: a second run against an already-implemented candidate inherits work
it did not do, so its launch and review counts are not comparable to a run that
started from nothing, and one pathological issue could otherwise supply most of a
five-run control. Later runs on the same issue are recorded in full as
`continuation` attrition, so nothing is discarded — only re-scoped.

**Order — by completion, not by start.** Eligible runs are sequenced across every
listed repository by the pair

```text
(finished_at, run id)
```

— the summary's `finished_at` (UTC, `YYYY-MM-DDTHH:MM:SSZ`, lexicographic =
chronological) first, the full run id string second. Run ids are unique by
construction, so this is a strict total order with no ambiguity to resolve by
judgement, including among runs that share a `finished_at`. Sorting the pairs
sorts the sample.

Because `finished_at` has one-second resolution, a same-second tie is settled by
run id — which means the fifth place is not knowable until the boundary second is
over. §2 states how closure resolves; the order itself never changes.

Start time governs *entry* into the window; completion time governs *sequence*
and *closure*. Ordering by start would let a long-running run that started
earlier finish later and retroactively displace a run already counted, which
would make the sample a function of when work happens to end. Under completion
order a run takes its place only once it has one, and closure at the fifth
`run_finish` cannot be reopened.

No other ordering — not merge time, not PR number, not repository, not export
order — decides the sequence.

### 4. Eligibility

Eligibility is decided **only from telemetry facts**. A run is **counted** when
all of the following hold:

1. it entered the window (§2) in a listed repository (§3);
2. its sink records `run_finish` with outcome `Closes` **or** `Progresses`;
3. its summary reports `schema: 1`;
4. it is the first run satisfying 1–3 for its `(repository, issue)` pair in
   completion order (§3); and
5. it is among the first five runs satisfying 1–4, in completion order.

Condition 5 is what closes the window: the fifth such run's `finished_at` fixes
the boundary second in §2, and every run finishing later — or inside that second
but behind it in the total order — fails condition 5. The sequence is therefore a
function of the sinks alone: sort by `(finished_at, run id)`, deduplicate by
issue, take five, once the boundary second is complete. It cannot be reopened by
a later finish.

Nothing about bookkeeping appears in this list. Exporting a run's record is an
**obligation** (§7), not a qualifying condition: a run that satisfies 1–5 is
counted and holds its chronological position, and a missing, deleted, or
unreproducible required record invalidates the window (§9) rather than removing
the run from it. Eligibility that depended on the record would let an
inconvenient run be dropped by simply not writing one down.

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
runs in completion order (§3). No run may be skipped, deferred, re-run, or
substituted because it was unusually cheap, unusually expensive, unusually
clean, embarrassing, atypical, or "not a fair test". A run that satisfies §4 is
in the sample from the moment it finishes, whether or not anyone has written it
down yet.

**Stopping.** The window closes at the fifth counted run's `run_finish` (§2).
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
  observation, and §9's completion condition requires a mechanical one.

Events recorded after `run_finish` are outside the summary window by
construction, so they never contribute to this classification. Their count is
recorded (§7).

### 7. Evidence and durable export

#### The record

One record per run in the window — counted **and** attrition. Every field is
either mechanical (copied from `run-telemetry.sh summary`, which is
deterministic for a finished run) or a small bounded envelope:

| Field | Source | Nullable |
|---|---|---|
| `seq` | position in export order, from 1 | no |
| `prev_record_sha256` | §7's chain | no |
| `repository` | `owner/repo` slug from §3's list | no |
| `issue` | issue number the run targeted | no |
| `pr` | PR number, or `null` | per §8 |
| `run`, `schema` | summary `run`, `schema` | no |
| `provenance` | the PR body's `Run N:` provenance line, verbatim | per §8 |
| `runtime_digests` | §10's runtime-script digest table, captured at export | no |
| `started_at`, `finished_at` | summary | `finished_at` per §8 |
| `final_workflow_outcome` | summary | per §8 |
| `subagent_launches` | summary `total` and `by_role` | no |
| `reviews` | summary `total`, `by_kind`, `input_bytes` | no |
| `validations` | summary `total`, `passed`, `failed`, `interrupted`, `incomplete`, `duration_ms` | no |
| `phase_elapsed_ms` | summary, per recorded phase | no |
| `tokens` | summary `input`, `output`, `coverage` | no |
| `remediation` | `yes` / `no` by §6, plus any flag | counted runs only |
| `malformed_lines`, `events_after_finish` | summary | no |
| `disposition` | `counted`, or an attrition class (§8), with its reason | no |
| `summary_sha256` | `sha256sum` of the exact summary JSON | no |

Never estimate an unavailable value. A field the runtime did not expose is
recorded as the summary reports it — `tokens.coverage: "none"` is a result, an
invented token count is a fabrication. A field this table marks nullable for the
run's class is `null`, never filled in from memory or inference.

#### Two surfaces, both required

A record is durable only if losing or deleting one copy is visible. Each record
is published to **both** of these before the next run in any listed repository
starts:

1. **One commit on the A3 results branch** — appending the record to the Results
   area of this file. Git history orders the commits and dates them, and the
   published branch makes a later rewrite a force-push rather than an edit.
2. **A structured comment on issue #64** — immediate, timestamped, with an edit
   history, independent of any workstation, sink, or branch, and naming the
   record's digest and the commit SHA from surface 1.

Neither alone is sufficient. A GitHub comment can be deleted by its author; a
branch can be rewritten. Requiring both means an omission has to be performed
twice, in two systems with different histories, and disagreement between them is
itself the alarm.

**One long-lived draft results PR, not one PR per record.** Every commit on that
branch is a record; there is no setup, scaffolding, or placeholder commit, so the
branch comes into existence with its first record rather than before it:

- the branch is cut from the protocol merge commit and named
  `agent/work-on-a3-results`;
- **the draft PR is opened by pushing the first record commit** — titled `A3
  results: control window records` — at that record's export deadline: after the
  run it describes has ended, and before the next run in any listed repository
  starts. The first record is whichever comes first in `seq`, counted or
  attrition;
- every later record is one further commit appended to the same branch;
- **append only** — push each new commit with no rebase, amend, squash, reorder,
  or force-push, ever;
- each record commit's parent is the previous record commit, and the first record
  commit's parent is the protocol merge commit;
- the commit is pushed before the matching #64 comment is posted, so the comment
  can name a SHA that already exists; and
- **any rewrite of that branch's history invalidates the window** (§9). A
  force-push is not a tidy-up here; it is the one action the surface exists to
  make impossible.

Opening the PR earlier would need a commit that is not a record, which the
ancestry rule above forbids and which an empty branch cannot supply anyway. The
window does not wait on the PR: eligibility is decided from telemetry facts (§4),
so a run that finishes before the branch exists is already in the sequence, and
its record is what creates the branch.

The results PR stays draft for the whole window and is merged exactly once, at
close, after the chain verifies (§9). Five records plus attrition do not need
five merges into `main` — they need one ordered, published, append-only history,
which a single branch already is.

**A3 adds no step to `work-on`.** Both exports are operator steps performed after
the run, outside the workflow, because instrumenting the workflow to export its
own record would change the thing being measured.

#### The chain

Records are chained so that removing, reordering, or replacing one is
mechanically detectable. Each record carries `seq` (export order, from 1) and
`prev_record_sha256`, both inside the digested JSON:

```bash
# a record's digest: canonical JSON, sorted keys, compact
jq -S -c . record.json | sha256sum
```

- `seq: 1` carries `prev_record_sha256` = the frozen-protocol digest recorded
  under **Protocol identity**.
- every later record carries the digest of the record at `seq - 1`.

Verification walks the chain from the protocol digest and recomputes every link.
A deleted record breaks it at that point; a rewritten record breaks every link
after it; and reproducing a doctored chain requires rewriting both surfaces.

The comment header repeats the same values for greppability, and names the
commit that carries the same record on the results branch:

````text
A3-RECORD run=<run-id> seq=<n> prev=<prev-record-sha256> commit=<sha>

```json
{ …the record fields above… }
```
````

The commit SHA binds the two surfaces to each other. Every SHA named in a comment
must still be an ancestor of the results branch head, in `seq` order:

```bash
git merge-base --is-ancestor <commit-from-comment> <results-branch-head>
```

A rewritten branch orphans those SHAs, which is why history rewriting is
invalidation rather than an inconvenience.

#### Duplicates, corrections, tampering

Run ids are unique by construction, so a duplicate is a second record with a run
id already present:

```bash
gh issue view 64 -R faviann/skills --json comments \
  --jq '[.comments[].body
         | capture("A3-RECORD run=(?<run>[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8})").run]
        | sort'
```

Check that list before posting. **A posted record is never edited, and a pushed
record commit is never rewritten.** A wrong record is superseded by a new record
at the next `seq` — one further commit on the results branch and one further
comment headed
`A3-CORRECTION run=<run-id> seq=<n> prev=<...> commit=<sha> supersedes=<comment-id>`,
stating what was wrong and why. Both survive on both surfaces, the chain stays
intact, and the results table cites both.

Tampering is detectable five ways, and the closeout applies all five: the chain
is recomputed end to end; every commit SHA named in a comment is confirmed an
ancestor of the results branch head, in `seq` order; `summary_sha256` is
recomputed from the surviving sink; the two surfaces are compared record by
record; and GitHub's comment edit history is inspected. Where a sink no longer
exists the `summary_sha256` check is unavailable — that is a weaker guarantee, is
recorded as such rather than papered over, and does not excuse a missing record
(§9).

#### What is never exported

Full prompts, briefs, or subagent reports; issue or PR bodies; source files;
diffs; command lines; command output; credentials; raw diagnostics; and raw sink
events exported wholesale for analytics. A1's schema has no free-form field, so
the mechanical part of a record cannot carry them; the envelope is a slug,
integers, one enum, one provenance string, and digests. Raw JSONL sinks stay
untracked in each target repository's git-dir and are never committed.

### 8. Attrition: ordered precedence, fields, and triggers

Every run in the window is classified by the **first** matching rule below. The
order is the classification: a run is never assigned a class by choosing among
several that fit.

| # | Class | Test | Export trigger |
|---|---|---|---|
| 1 | `out-of-window` | Entered before the window opened (§2), ran in a repository not on §3's list, or recorded `run_finish` after the window closed — including inside the boundary second but beyond fifth place | none — no record required |
| 2 | `preflight-aborted` | Sink records `run_finish` with outcome `aborted` (A2 closability hand-back) | at the hand-back |
| 3 | `incomplete` | Sink records no `run_finish`, including a run still unfinished when the window closed | when the run stops, or at window close |
| 4 | `no-candidate` | Finished `Closes`/`Progresses`, but no pull request exists | at the run's end |
| 5 | `continuation` | Finished `Closes`/`Progresses`, and `(repository, issue)` already has a counted run | at that run's closeout |
| 6 | `counted` | §4 holds | at that run's closeout |

Every class from 2 to 6 is exported to both surfaces (§7) — one appended commit
on the results branch, then the matching #64 comment naming its SHA — before the
next run in any listed repository starts. A run whose `finished_at` could be a
boundary second is exported once that second has elapsed, so its `disposition` is
the settled one and never a provisional fifth place. Every class shares the one results
branch and the one `seq` sequence; an attrition record is a commit and a comment
exactly like a counted one. `out-of-window` runs are listed here only so they are
not mistaken for attrition; they are outside the window and are not recorded.

**Fields available per class.** The A2 gate aborts before workflow-provenance
capture and before any pull request exists, and an unfinished run has no
`run_finish` event, so those records are complete when they carry what exists:

| Class | `pr` | `provenance` | `finished_at`, `final_workflow_outcome` | `remediation` |
|---|---|---|---|---|
| `preflight-aborted` | `null` | `null` | `finished_at` from the `run_finish` event; outcome `aborted` | omitted |
| `incomplete` | PR number if one exists, else `null` | provenance line if a PR body carries one, else `null` | `null` | omitted |
| `no-candidate` | `null` | `null` | present | omitted |
| `continuation` | present | present | present | present |
| `counted` | present | present | present | present |

A `null` here is a fact about the class, not a gap to fill by inference. Every
other field in §7's table is mechanical and is present for every class, because
the summary produces it from whatever the sink holds.

**Environmental and setup failures are a reason, not a class.** A run that died
in setup is `incomplete` with that reason recorded; a run that hit environmental
trouble and still finished is classified by rules 4–6 like any other, with the
failure visible in its validation counts. There is no separate environmental
class to select into.

**Deliberately not attrition**, recorded instead as data-quality flags on an
otherwise normal record: failed validations in a finished run, `malformed_lines
> 0` (the sink is append-only; a torn line costs exactly one ignored event),
`events_after_finish > 0` (the summary window closed at `run_finish`, so the
counted values are the published ones), and `validations.incomplete > 0`.

### 9. Completion decision rules

A3 is **complete** only when every one of these holds:

1. exactly five counted runs, per §4 and §5;
2. at least one is remediation-bearing by §6's mechanical test — a
   `remediation-unattributed` run does not satisfy this;
3. the per-repository sink enumeration (§3) accounts for every run id in the
   window as counted or as one class from §8, in completion order, with no skip,
   substitution, or retrospective selection;
4. every run of class 2–6 has a record on **both** surfaces, and the two agree
   field for field;
5. the record chain verifies end to end from the frozen-protocol digest, with
   corrections superseded rather than edited;
6. the results branch is intact — every commit SHA named in a comment is an
   ancestor of its head, in `seq` order, and its history was never rewritten;
7. the frozen protocol identity verifies (see **Protocol identity**); and
8. no post-A2 workflow semantic or governing runtime file changed during the
   window (§10).

Only when all eight hold is the results PR taken out of draft and merged — once,
at close. Merging it is the record of completion, not a step that produces one.

A3 is **insufficient** when the five counted runs are collected and complete but
none is remediation-bearing. Then: B1 stays blocked; the control is recorded as
insufficient rather than successful; and any extension requires a **new, explicit
pre-registration merged before any further eligible run is observed**, naming its
own fixed count and its own failure outcome. Continuing to observe runs under
this protocol until a remediation appears is prohibited.

A3 is **invalid** when a frozen-protocol byte changed after the start boundary,
when an eligible run was skipped or displaced, when counted runs do not share one
telemetry schema version, when a frozen semantic or runtime file changed
mid-window, when the chain does not verify, **when the results branch's history
was rewritten by any rebase, amend, squash, reorder, or force-push**, or when
**any** required record is missing, deleted, or unreproducible — including a
record lost because its sink was destroyed before export. A missing record is not
attrition and never removes its run from the sequence: the run stays eligible and
the window is invalid. An invalid window is not repaired by argument; it is
recorded and re-registered.

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

#### Frozen instructions

`scripts/workflow-provenance.sh` fingerprints the governing instruction files,
and each counted run's PR body carries the result on its `Run N:` line. The
`work-on:`, `tdd:`, and `review:` components are computed from the skills
checkout and so are identical across repositories. At the protocol merge:

| Component | Digest |
|---|---|
| `work-on` | `6a0c6e912785` |
| `tdd` | `aa54f63292bf` |
| `review` | `1aebe11f115e` |
| `workflow` (default) | `87087d1136ae` |

Every counted run must show these three repository-independent digests with no
`*` suffix — a star means a governing file differed from its committed bytes
during the run. The `workflow:` component may legitimately differ per repository
(a target repository's own `docs/workflow.md` is the selected input), so it is
recorded per repository and must be constant *within* each repository across the
window.

#### Frozen runtime scripts

Provenance hashes instruction Markdown only. The scripts that *measure* the run
and *render* its closeout are equally capable of changing what a number means, so
they are frozen here too — sha256, first 16 hex, of each file's bytes:

| Digest | File (under `skills/personal/work-on/scripts/`) |
|---|---|
| `63142a42ec65e069` | `run-telemetry.sh` |
| `166d163837f139ea` | `render-closeout.sh` |
| `d6d62761f2dd959b` | `validate-closeout-body.sh` |
| `294ad32e787c3b8b` | `workflow-provenance.sh` |

Reproduce from a skills checkout:

```bash
for f in run-telemetry.sh render-closeout.sh validate-closeout-body.sh \
         workflow-provenance.sh; do
  printf '%s  %s\n' \
    "$(sha256sum <"skills/personal/work-on/scripts/$f" | cut -c1-16)" "$f"
done
```

Two checks use them. Each record captures this table from the live skills
checkout at export time (`runtime_digests`, §7). And each counted run's
provenance line ends with `(faviann/skills@<sha12>)`, so the commit it names is
checked directly:

```bash
for f in run-telemetry.sh render-closeout.sh validate-closeout-body.sh \
         workflow-provenance.sh; do
  printf '%s  %s\n' \
    "$(git show "<sha12>:skills/personal/work-on/scripts/$f" \
       | sha256sum | cut -c1-16)" "$f"
done
```

Any mismatch — in a record, or against a run's recorded commit — means the
measurement or closeout behaviour changed mid-window, and the window is invalid
from that run onward under §9.

**Known limit.** The commit check proves which committed revision a run pointed
at; provenance's `*` marker covers the instruction files, not these scripts, so
an *uncommitted* edit to a script in the live checkout is not detectable after
the fact. The operator's obligation is that no such edit exists during the
window, and `runtime_digests` captures the live checkout at each export so a
drift that persists is caught. A drift introduced and reverted between exports
would not be. This is stated rather than papered over.

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
| Frozen-region sha256 | `468d2321e15273de61a160e0f1e251635f6f92bd1e74736300d0bd8f92a14557` |
| Protocol merge commit | _recorded by the first record commit_ |
| Start boundary (UTC) | _recorded by the first record commit_ |
| A3 results PR | _recorded when the first record commit opens it_ |
| Results branch | `agent/work-on-a3-results`, cut from the protocol merge commit |

The digest is stored outside the frozen region so it can be recorded without
changing what it measures. It is also the genesis link of the record chain (§7).

Every record commit and the closeout must:

1. recompute the digest above and confirm it equals the value in this table;
2. confirm `git diff <protocol-merge-sha>..HEAD -- <this file>` touches no line
   inside the markers; and
3. at closeout, walk the chain from this digest through every record, and confirm
   every commit SHA named in a #64 comment is an ancestor of the results branch
   head in `seq` order.

A commit that cannot reproduce the digest has not populated this protocol — it
has replaced it, and the window is invalid under §9.

## Results

**Empty. The window has not started. No run has been observed, selected, or
counted.**

Filled in append-only, one commit per record on a single long-lived draft
results PR (§7), using the templates below. That PR is merged once, at close,
after §9's conditions verify.

### Counted runs

| # | Run id | Repository | Issue | PR | Finished (UTC) | Outcome | Launches | Reviews (kinds) | Reviewed bytes | Validations (p/f/i/inc) | Phase elapsed | Tokens | Remediation | `seq` | Record |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | | | | | | |
| 2 | | | | | | | | | | | | | | | |
| 3 | | | | | | | | | | | | | | | |
| 4 | | | | | | | | | | | | | | | |
| 5 | | | | | | | | | | | | | | | |

`Record` links the issue-#64 comment holding that run's exported record, and any
correction superseding it. Its results-branch commit is in the chain table.

### Attrition and separately reported runs

| Run id | Repository | Issue | Class | Reason | `seq` | Record |
|---|---|---|---|---|---|---|
| | | | | | | |

### Record chain

| `seq` | Run id | `prev_record_sha256` | Record sha256 | #64 comment | Results-branch commit | Ancestor of head |
|---|---|---|---|---|---|---|
| 1 | | _frozen-protocol digest_ | | | | |

### Data-quality flags

| Run id | Flag | Detail |
|---|---|---|
| | | |

Flags: `telemetry-body-mismatch`, `remediation-unattributed`,
`malformed-lines`, `events-after-finish`, `incomplete-validations`.

### Population enumeration

Per repository, the in-window run ids from §3's listing and where each is
accounted for.

| Repository | In-window run ids | Counted | Attrition | Unaccounted |
|---|---|---|---|---|
| `faviann/overmind` | | | | |
| `faviann/homelab-iac` | | | | |
| `faviann/dotfiles` | | | | |

### Frozen-file check

| Run id | Repository | `work-on` | `tdd` | `review` | `workflow` | Runtime scripts | Matches frozen |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

### Closeout decision

| Condition (§9) | Met | Evidence |
|---|---|---|
| Five counted runs | | |
| At least one remediation-bearing | | |
| Enumeration complete, order preserved | | |
| Records on both surfaces, agreeing | | |
| Chain verifies | | |
| Frozen identity verified | | |
| No frozen semantic or runtime file changed | | |

**Verdict:** _complete_ / _insufficient_ / _invalid_ — with the reason, and an
explicit statement of whether B1 is unblocked. B1 is unblocked only by a
separate acceptance of a complete control, never by this table alone.

## Change log

Append-only. Anything recorded here happened outside the frozen region.

| Date | Change |
|---|---|
| 2026-08-14 | Protocol pre-registered. Window not started. |
