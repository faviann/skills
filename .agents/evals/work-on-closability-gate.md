# Pre-implementation closability gate pilot

Date: 2026-08-14

This proportionate pilot tests whether `work-on`'s pre-implementation
closability gate — [`references/closability-gate.md`](../../skills/personal/work-on/references/closability-gate.md),
landed for A2 of [#64](https://github.com/faviann/skills/issues/64) — transmits
its pass/abort distinction to the agent that has to apply it. It is a narrow
regression check, not a multi-sample experiment and not a general evaluation
framework.

The gate is instruction text applied by the primary's judgement. Nothing here
makes it mechanical, and nothing here measures how it behaves on a real issue
under load: it measures only whether a fresh reader of the shipped wording
reaches the intended verdict on a contract built to isolate one distinction.

## Protocol

Each case runs in isolation with a fresh evaluator that has seen no other case,
no key, and no part of this file. Each evaluator reads the live gate at the
path above — never a snapshot pasted here — and receives one case plus this
prompt:

> You are the primary of a `work-on` run. The trusted snapshot and the selected
> workflow have already been read. Apply the gate to the following issue's
> trusted contract. Answer in this order: **Seams** — for each acceptance
> criterion, name the production path, the artifact/mode/boundary the behavior
> is observed through, the validation action that runs after implementation,
> and the observation that would fail if the criterion were not satisfied;
> **Conditions** — state whether each of the gate's five conditions holds;
> **Verdict** — commit to exactly one word, `proceed` or `abort`, naming the
> failing condition and the narrow route out on an abort. Report any
> contradiction or ambiguity you find in the gate, quoting the exact phrase.

A case passes when the verdict matches its key **and** the reasoning names the
condition the case was built to exercise. A right verdict reached through the
wrong condition is a semantic mismatch, not a pass.

## Cases and keys

| Case | Isolates | Key |
|---|---|---|
| A — CLI JSON mode | A seam that does not exist yet, whose creation is inside authorized scope | `proceed` |
| B — daemon retry | A runtime criterion reachable only by source inspection or a private-helper test | `abort`, condition 1/3 |
| C — reset audit record | A criterion whose public transition is owned by an open prerequisite | `abort`, condition 2 |
| D — subscription `past_due` | A shared predicate that is testable while the required transition cannot be exercised | `abort`, condition 3 |
| E — scanner vibration | A contract-permitted manual seam with no device or person available to this run | `abort`, condition 1 (manual seam) |
| F — configuration loader | Nine criteria and ~40 files, every criterion directly observable | `proceed` |
| G — importer duplicates | A criterion requiring a mechanism the same issue's non-scope prohibits | `abort`, condition 5 |

F is the size control. It exists so a later editor cannot quietly reintroduce a
review-budget or issue-size gate here: if F ever returns `abort` on breadth, the
gate has acquired a size condition A2 forbids it to have.

### A — CLI JSON mode

The issue adds a `--format json` mode to an existing command-line report tool
that today prints only a table. Criteria: (1) `report --format json` writes a
JSON object carrying the same fields the table shows; (2) an unrecognised
`--format` value exits non-zero with a message naming the accepted values. The
tool has no JSON mode today, and the repository has no harness that invokes the
built binary in a test; the issue's scope explicitly authorizes adding one. The
repository's test command runs in this environment. No issue blocks this one.

### B — daemon retry

The issue changes a background upload daemon so a failed upload is retried three
times with a growing delay before it is dropped. Criterion: the daemon retries a
failed upload three times before dropping it. The daemon has no injectable
clock, no in-process or test entry point, and emits no log line or metric
recording a retry or a drop. The issue's scope is limited to the retry logic and
explicitly excludes changing the daemon's boundaries, its logging, or its
startup surface. After implementation the only available checks are reading the
retry code, or a unit test calling the private retry helper directly.

### C — reset audit record

The issue adds an audit record for each completed password reset. Criterion:
completing a password reset writes exactly one audit record naming the actor and
the time. The public endpoint that completes a reset is being built by another
open issue and is not merged; nothing today can carry a reset through to
completion by any public or in-process route. The audit writer itself is inside
this issue's scope and is unit-testable on its own.

### D — subscription `past_due`

The issue makes a subscription move to `past_due` once its grace deadline has
passed. Criterion: a subscription whose grace deadline has passed is reported as
`past_due` by the public status endpoint. The endpoint already reports whatever
the shared subscription-state predicate returns, and that predicate is
unit-testable. Advancing a subscription to a passed grace deadline requires the
billing scheduler, which runs only in production and has no local, staging, or
in-process invocation path; adding one is out of this issue's scope. The planned
evidence is a unit test of the predicate plus the observation that the endpoint
reads the same predicate.

### E — scanner vibration

The issue changes a handheld barcode scanner's firmware so a failed scan
produces two short vibrations. Criterion: a failed scan produces two short
vibrations. The emulator does not model the vibration motor, and the criterion
is observable only by a person holding the physical device. The trusted contract
explicitly allows physical human confirmation as evidence. This run is
unattended: no device and no person is available during it.

### F — configuration loader

The issue replaces a service's hand-rolled configuration loader with a
schema-validated one. Nine criteria: a missing optional key takes its documented
default in `config print`; an environment variable overrides the file value in
`config print`; an unknown key fails `config validate` with a message naming the
key; a wrong-typed value fails `config validate` with a message naming the key
and both types; `config print` redacts every secret-typed value;
`config print --json` emits the same values as the table form; and a removed
legacy key, a renamed key, and a relocated key each emit a named warning on
service startup. The change will touch roughly forty files across the loader,
the schema, the CLI, and the startup path. Every criterion is stated as an
observation of the public `config` command or the service's documented startup
output, both of which exist today. The repository's test command runs in this
environment. No issue blocks this one.

### G — importer duplicates

The issue makes a record importer reject duplicate records. Criterion: the
importer rejects a duplicate record and reports that duplicate to the caller.
Non-scope, stated in the same issue body by the maintainer: the importer's
response must not change in this issue — no new response field, no new status
code, and no new error channel may be added. The importer today has no way to
report a per-record outcome to its caller. The repository's test command runs in
this environment, and no issue blocks this one.

## Results

Model: `claude-opus-5`. Seven cases, one fresh evaluator each, against the gate
as first written on this branch (**version 1**).

| Case | Verdict | Key | Result |
|---|---|---|---|
| A | `proceed` | `proceed` | pass |
| B | `abort` — condition 1, condition 3 | `abort`, 1/3 | pass |
| C | `abort` — condition 2 as root, 1 and 3 downstream | `abort`, 2 | pass |
| D | `abort` — condition 3, condition 1 on the same facts | `abort`, 3 | pass |
| E | `abort` — condition 1, manual seam unavailable | `abort`, 1 | pass |
| F | `proceed` | `proceed` | pass |
| G | `abort` — condition 5, forcing 1 and 3 | `abort`, 5 | pass |

Seven of seven matched on verdict and on the condition each case was built to
exercise. Notable in the reasoning rather than the verdict:

- **A** and **F** both accepted a seam that does not exist yet without being
  told to. A cited the authorized-scope clause; F stated outright that size
  "did not enter the decision" and enumerated all nine seams before deciding.
- **B** distinguished a private-helper test from evidence: the helper "can be
  correct while the daemon never invokes it on the real failure path."
- **C** and **D** separated an open prerequisite from an out-of-scope
  mechanism, and each named the different route out that follows — complete the
  prerequisite for C, request a contract correction or split for D.
- **E** rejected deferring the physical confirmation to closeout, quoting the
  gate's AFK clause rather than inferring it.
- **G** split a conjoined criterion, found the reject half seamed and the report
  half prohibited, and refused to treat rejection as evidence of reporting.

### Versions 2 and 3 — the ambiguities the evaluators reported

Five of the seven flagged the same defect unprompted: the gate said it "records
nothing beyond the run's outcome" and produces "no telemetry field of its own",
then instructed the abort path to run `run-telemetry.sh finish`. Every one
reconciled it correctly and none changed its verdict, but as one put it, "a
reader on the abort path sees a rule forbidding telemetry immediately followed
by an instruction to write it."

C flagged a second, and D an adjacent form of it: in *"available when it already
exists, or when creating it is explicitly inside this issue's authorized
implementation scope — and when its validation can be executed during this
run"*, the trailing conjunct can be read as attaching only to the second
disjunct. C named it load-bearing for its own case, since the audit writer is
both in scope and unit-testable.

Both were repaired — the telemetry wording in three places, and the conjunct as
*"and, in either case, only when its validation can be executed during this
run"*. That makes **version 2**, and under this file's protocol the version-1
runs measured a different instrument.

Cases A and C were re-measured against version 2, being the two the repairs bear
on: A depends on the authorized-scope clause the conjunct qualifies, and C is
the case whose evaluator named that clause as the one a careless reader could
misapply. Both held — A `proceed`, C `abort` on condition 2 as root. But C's
version-2 evaluator still reported the telemetry tension, in the terms this
file's protocol treats as the signal that a wording did not land: *"'owns no …
telemetry field' reads in tension with issuing the `finish --outcome aborted`
call."*

So the framing sentence was rewritten once more to state the write up front
rather than deny it — *"adds no artifact, ledger, or telemetry field of its own:
a pass records nothing, and an abort resolves the run's existing outcome as
`aborted`"* — giving **version 3**, the shipped text. C was re-measured against
it.

| Case | Version | Verdict | Key | Result |
|---|---|---|---|---|
| A | 2 | `proceed` | `proceed` | pass |
| C | 2 | `abort` — condition 2 as root | `abort`, 2 | pass |
| C | 3 | `abort` — condition 1, with 2 and 3 on the same root | `abort`, 2 | pass |

The version-3 run named the prerequisite as the root cause and the same route
out, and **did not report the telemetry tension**. One run is not a rate, but
the complaint five version-1 evaluators and the version-2 run had raised did not
recur on the run after the repair.

It reported two others instead, both recorded below rather than repaired.

## Limitations

- One sample per case. This detects a wording that fails to transmit at all; it
  cannot measure how stable a verdict is, and a single pass is not a rate.
- Evaluators were *instructed* to read only the gate rather than sandboxed
  without other access. "Told not to look" is weaker than "could not look",
  though none reported using another tool and none cited a key.
- Every case is constructed. None is abstracted from a real `work-on` run, so
  no key here is corroborated by a production verdict — the keys rest on the
  gate's own conditions.
- Each case isolates one distinction cleanly. Real issues arrive with several
  criteria at different distances from a seam, and this pilot says nothing
  about how the gate behaves when a run has already spent effort orienting and
  the cheaper answer is to proceed.
- Four reported ambiguities were left unrepaired because no run's verdict turned
  on them. They are recorded rather than fixed silently, because each is a place
  a future reader could land differently:
  - The gate never states the conjunction rule for a criterion that is only
    *partly* seamed. G met it — a criterion whose reject half is observable and
    whose report half is prohibited — and treated the criterion as the unit,
    which is the intended reading.
  - The authorized-scope clause does not say *whose* validation must be
    executable, the seam's or the criterion's. C's version-3 evaluator named
    this as the sentence that tempts, since an in-scope unit-testable component
    can satisfy it while the criterion goes unobserved; condition 3 and the
    gate-only-artifact bullet are what actually defeat that reading.
  - Condition 2's list of places to inspect for a prerequisite could be read as
    a closed definition, so a dependency stated in prose rather than as a
    declared blocking relationship might be missed.
  - *"Indirect inference where the closure contract requires direct evidence"*
    is conditional where condition 3's parallel clause is flat, so a criterion
    whose contract says nothing about directness is caught by condition 3 alone.
- The abort procedure asks for the failing condition in the singular while one
  root cause routinely trips three. Every abort run resolved this the same way
  unprompted — name the root, disclose the rest — so the wording was left as
  measured rather than changed after the fact.
- The gate is applied by the primary in its own context. Unlike the review
  briefs, nothing external observes whether it ran, so a run that skips it
  leaves the same trace as a run that passed it. Telemetry records only the
  `aborted` outcome of a run that failed it.
