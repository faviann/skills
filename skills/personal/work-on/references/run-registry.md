# The run registry and its observer

`scripts/run-registry.sh` keeps one bounded record of every `work-on` run's
lifecycle outside the repository the run happened in, so a run that was
interrupted, whose branch was deleted, or whose clone is gone remains visible
and finishable. It records the run; it never decides what the run does.

The raw events stay where [`run-telemetry.md`](./run-telemetry.md) puts them:
one append-only JSON-lines sink under the target repository's absolute Git
common directory. Nothing copies them here.

## The registry

```text
${XDG_STATE_HOME:-$HOME/.local/state}/work-on/registry/
  registry.lock              # admission and retention are serialized here
  runs/<run-id>.json         # one bounded record per run
  runs/<run-id>.lock         # that record's own transitions
```

The directory, its locks, and every record are created for their owner only —
`0700` and `0600`.

One record is one JSON object with exactly these fields:

| Field | Value |
|---|---|
| `schema` | registry record schema, currently `1` |
| `run_id` | the run's id, as minted by `run-telemetry.sh start` |
| `repository` | normalized lowercase `owner/repository` |
| `issue` | positive issue number |
| `telemetry_schema` | the sink's schema, `2` |
| `sink` | absolute path of the run's JSON-lines sink |
| `worktree` | absolute path of the worktree the run started in |
| `repository_binding` | the sink's opaque repository binding |
| `lifecycle` | `active`, `resolved`, `sealed`, or `unknown` |
| `outcome` | the resolved run outcome, or `null` |
| `summary_sha256` | hash of the sealed sink's own summary, or `null` |
| `finalization` | `pending`, `finalizing`, `finalized`, `failed`, or `unreproducible` |
| `observer` | bounded observer id, or `null` |
| `control_id` | bounded control id, or `null` |
| `registered_at` / `updated_at` / `updated_epoch` | bounded timestamps |
| `failure_code` | one bounded failure code, or `null` |

Every record is validated against that closed shape before it is written, so a
field outside it — or a value outside its pattern or enumeration — cannot be
stored. There is no field for a prompt, a diff, a command line, an output, a
credential, or a reviewer's prose. A record is replaced whole through an atomic
rename, so a reader sees one version or the other, never a half-written one.

## Recording a run

| When | Command |
|---|---|
| Once, before implementation begins | `run-registry.sh register --run "$RUN_HANDLE"` |
| Once, on hand-back | `run-registry.sh finalize --run "$RUN_HANDLE" [--outcome O]` |
| After an interruption | `run-registry.sh recover --run-id ID [--outcome O]` |
| To inspect | `run-registry.sh status [--run-id ID] [--repository R] [--issue N] [--pending]` |
| To reclaim retained records | `run-registry.sh prune [--older-than-days N]` |

`register` takes the identity it records from the sink's own summary; it reads
no events. It is idempotent for a run already registered.

## The observer

Whether a run carries a finalization obligation is decided by an *optional*
external program — `$WORK_ON_OBSERVER`, else
`${XDG_CONFIG_HOME:-$HOME/.config}/work-on/observer` when executable. Two calls
are made:

```sh
observer applies --repository owner/repository --issue N
observer finalize --record <path to the run's registry record>
```

`applies` exits `0` and prints exactly

```text
observer=<bounded token>
control=<bounded token>
```

when the run is governed, or exits `3` when it is not. Any other status, or an
answer outside that shape, is a policy error: the run might be governed, so
registration refuses rather than guessing. `finalize` exits `0` to accept the
finalization; anything else leaves the obligation outstanding.

The tokens are lowercase alphanumeric words joined by single hyphens, at most 64
characters. They are the whole of what this mechanism learns: it knows nothing
about what any observer is measuring, which runs belong to a population, or what
becomes of a discharged obligation.

With no observer program, or an `applies` refusal, the run is recorded with no
control id. Nothing can then refuse it, block it, or make it wait, and a
registry problem is reported without failing the run.

## Finalization

Finalization builds on the existing lifecycle instead of adding a second one.
`finalize` and `recover` drive one path:

1. mark the record `finalizing`, so an interrupted attempt is visible as one;
2. if the sink resolved no outcome, resolve the supplied `--outcome`; if it
   resolved one, adopt it and refuse a `--outcome` that contradicts it;
3. seal the run when it is not sealed already;
4. read the sealed sink's deterministic summary, require `integrity=valid`, and
   record its hash as `summary_sha256`;
5. call the observer when the record names a control;
6. mark the record `finalized`.

Outcome resolution stays distinct from sealing. A run that resolves at the
closure gate and then records closeout evidence is finalized by step 3 and
after; nothing forces the seal earlier. Success is claimed only after the run is
sealed and its own summary is valid — a run whose sink is contradictory becomes
`failed` with a bounded code, never a quiet success. The canonical summary comes
from the sink; nothing here reconstructs it.

`Closes`, `Progresses`, and `preflight-aborted` reach finalization through the
ordinary hand-backs in [`github-closeout.md`](./github-closeout.md) and
[`closability-gate.md`](./closability-gate.md). `abandoned` and `failed` are
honest endings too: finalize or recover the run with that `--outcome`.

Bounded failure codes: `OUTCOME_UNRESOLVED`, `OUTCOME_CONFLICT`,
`RESOLVE_FAILED`, `SEAL_FAILED`, `INTEGRITY_INCOMPLETE`, `INTEGRITY_INVALID`,
`SUMMARY_FAILED`, `OBSERVER_FAILED`, `SINK_MISSING`, `REPOSITORY_MISSING`.

## The next-run guard

`register` refuses a governed run while another run with the same control id is
`pending`, `finalizing`, or `failed`. The refusal names the blocking run, its
repository and issue, its lifecycle and finalization state, its failure code,
and exactly one recovery command to run.

The guard is keyed on the control id alone. A record without one — every run for
which no observer applies — can never block anything, and a governed run in one
repository never blocks an unrelated repository or issue unless its own observer
says they share a control.

## Recovery

`recover` finishes the same run; it never mints a replacement. It resumes a run
killed before hand-back, between resolve and seal, or during finalization
itself, and retries a `failed` obligation after its cause is fixed. It is
idempotent: recovering a finalized run reports it and changes nothing, and the
observer is notified once.

Recovery finds the run's repository from the sink path it recorded, so a removed
linked worktree does not strand it. When the sink is gone, or no repository
containing it can be reached, the run becomes `unreproducible` with the
corresponding bounded code. That state is durable: the run stays in the registry
as a run that happened and cannot be reproduced, rather than disappearing, and
it stops blocking later runs.

`recover --all` walks every outstanding record in one pass.

## Capacity and retention

The registry is bounded — `WORK_ON_REGISTRY_CAPACITY` records, 512 by default.
Registering a new run first drops the oldest record that is safe to drop: one
with no control id, or one whose obligation is already `finalized`. A record
that still owes an observer something is never dropped, and when nothing is safe
to drop, registration of a governed run refuses rather than losing the evidence.
`prune --older-than-days N` applies the same rule by age.

This is deliberately not an analytics store. It holds what is needed to find and
finish a run, and the sink holds everything else.

## Where this fits

The registry and observer seam are the generic mechanism owned by
[#9](https://github.com/faviann/skills/issues/9). A policy adapter that decides
what a control means, and what to publish when one finalizes, is
[#73](https://github.com/faviann/skills/issues/73)'s and is not part of this
mechanism.
