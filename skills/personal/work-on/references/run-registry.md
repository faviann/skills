# The run registry and its observer

`scripts/run-registry.sh` keeps one bounded record of every `work-on` run's
lifecycle outside the repository the run happened in, so a run that was
interrupted, whose branch was deleted, or whose clone is gone remains visible
and finishable. It records the run; it never decides what the run does.

It is an index over runs, never a second source of truth about them. The raw
events stay where [`run-telemetry.md`](./run-telemetry.md) puts them — one
append-only JSON-lines sink under the target repository's absolute Git common
directory — and every lifecycle fact here is projected from that sink's own
deterministic summary.

## The registry

```text
${XDG_STATE_HOME:-$HOME/.local/state}/work-on/registry/
  registry.lock                        # admission, eviction, retention
  runs/<run-id>@<binding>.json         # one bounded record per run
  runs/<run-id>@<binding>.lock         # that record's own transitions
```

A run id is unique only inside the repository that minted it: #70 keeps two
repositories able to hold the same textual id and tells them apart by the
repository binding. The registry key is therefore the whole **repository-bound
handle** — the exact value `run-telemetry.sh start` printed. Every public
command that selects an existing record takes `--run HANDLE`; there is no
bare-id selection, so one repository's command can never reach another
repository's identically named run.

A user-level root is used only when it is **absolute**. A relative
`XDG_STATE_HOME`, `XDG_CONFIG_HOME`, `WORK_ON_OBSERVER`, or `HOME` is refused
outright rather than resolved against the working directory, which is the target
repository: that is how the registry stays outside the clone it must outlive and
how repository content cannot become the observer program.

The directory, its locks, and every record are created for their owner only —
`0700` and `0600`.

One record is one JSON object with exactly these fields:

| Field | Value |
|---|---|
| `schema` | registry record schema, currently `1` |
| `run_id` | the run's id, as minted by `run-telemetry.sh start` |
| `repository` | normalized lowercase `owner/repository` |
| `issue` | positive issue number |
| `telemetry_schema` | the sink's schema, `2` or `3` |
| `sink` | absolute path of the run's JSON-lines sink |
| `worktree` | absolute path of the worktree the run started in |
| `repository_binding` | the sink's opaque repository binding |
| `lifecycle` | `active`, `resolved`, or `sealed` |
| `outcome` | the resolved run outcome, or `null` |
| `summary_sha256` | hash of the sealed sink's own summary, or `null` |
| `finalization_id` | the transition identity handed to the observer, or `null` |
| `finalization` | `pending`, `finalizing`, `finalized`, `failed`, or `unreproducible` |
| `observer` | bounded observer id, or `null` |
| `control_id` | bounded control id, or `null` |
| `registered_at` / `updated_at` / `updated_epoch` | bounded timestamps |
| `failure_code` | one bounded failure code, or `null` |

Every record is validated against that closed shape before it is written, so a
field outside it — or a value outside its pattern, enumeration, or the
lifecycle/outcome combinations that can actually occur — cannot be stored. There
is no field for a prompt, a diff, a command line, an output, a credential, or a
reviewer's prose. A record is replaced whole through an atomic rename, so a
reader sees one version or the other, never a half-written one.

## Recording a run

| When | Command |
|---|---|
| Once, before implementation begins | `run-registry.sh register --run "$RUN_HANDLE"` |
| Once, on hand-back | `run-registry.sh finalize --run "$RUN_HANDLE" [--outcome O]` |
| After an interruption | `run-registry.sh recover --run "$RUN_HANDLE" [--outcome O]` |
| To inspect | `run-registry.sh status [--run HANDLE] [--repository R] [--issue N] [--pending]` |
| To reclaim retained records | `run-registry.sh prune [--older-than-days N]` |

`register` takes the identity it records from the sink's own summary; it reads
no events. It is idempotent for a run already registered, and refuses a retry
whose repository, issue, sink, or binding disagrees with the recorded one.

Applicability is part of that identity. A retry recomputes it through the
observer interface and must find exactly what the record already holds:
governance cannot be retrofitted onto a run that did its work under none,
removed from one that owes an obligation, or moved to another observer or
control. Only an unchanged answer is an idempotent retry.

For a **governed** run, first registration must be provably before
implementation, and the sink is the only admissible evidence of that. A sink
that already records a subagent launch, a reviewer delegation, a validation
execution, a resolved outcome, or a seal is refused: a missing registration
cannot be repaired after the fact by registering late. Registry timestamps prove
nothing here and are not consulted. A run nothing observes is an index entry and
may be recorded whenever the workflow reaches it.

## The observer

Whether a run carries a finalization obligation is decided by an *optional*
external program — `$WORK_ON_OBSERVER`, else `$XDG_CONFIG_HOME/work-on/observer`
when executable, both absolute. Two calls are made:

```sh
observer applies --repository owner/repository --issue N
observer finalize --record <path to the run's registry record> \
  --transition <finalization identity>
```

`applies` exits `0` and prints exactly two non-empty lines — one `observer=` and
one `control=`, in either order:

```text
observer=<token>
control=<token>
```

or exits `3` when the run is not governed. The answer is captured as bytes into
an owner-only temporary file — never straight into command substitution, which
would silently discard a NUL and let material escape the grammar before it could
be rejected — and any NUL byte is rejected before parsing. The capture is
removed on success, on failure, and on interruption, and is never written into
the registry or the telemetry sink. A token is lowercase alphanumeric
words joined by *single* hyphens — `[a-z0-9]+(-[a-z0-9]+)*` — at most 64
characters. Anything else is a policy error and the run is refused rather than
guessed at: an extra line, a bare line, a repeated or unknown key, a missing
key, an empty token, a leading, trailing, or doubled hyphen, a space, an
uppercase letter, an over-long token, or any exit status other than `0` or `3`.

Those tokens are the whole of what this mechanism learns: it knows nothing about
what any observer is measuring, which runs belong to a population, or what
becomes of a discharged obligation.

With no observer program, or an `applies` refusal, the run is recorded with no
control id. Nothing can then refuse it, block it, or make it wait.

### The finalization transition

`finalize --transition` carries a stable identity derived from the run's
immutable bound identity and the transition being finalized — the handle,
repository, issue, resolved outcome, and canonical summary hash. It is written
into the record **before** the observer is called and replayed verbatim on every
retry, including after a crash.

The obligation belongs to the observer and control the run registered with.
Before the notification, applicability is re-established through the same closed
interface and must name exactly that stored pair; an absent, unreachable, or
differently identified policy leaves the obligation outstanding
(`OBSERVER_FAILED`, `OBSERVER_IDENTITY_MISMATCH`) instead of discharging it. The
stored pair is never rewritten during finalization or recovery.

The guarantee is therefore **at-least-once delivery of one stable transition
identity**, and an observer must treat a repeated identity as the same
transition rather than a new notification. A process cannot promise exactly-once
delivery across an external side effect; deduplicating on that identity is what
makes the pair of them produce exactly one logical transition. An observer that
cannot be reached leaves the obligation outstanding rather than discharged.

## Finalization

Finalization builds on the existing lifecycle instead of adding a second one.
`finalize` and `recover` drive one path:

1. mark the record `finalizing`, so an interrupted attempt is visible as one;
2. check the sink's own `run`, `repository`, and `issue` against the record, and
   act on nothing that disagrees;
3. if the sink resolved no outcome, resolve the supplied one; if it resolved
   one, adopt it;
4. seal the run when it is not sealed already;
5. read the sealed sink's deterministic summary, require `integrity=valid`, and
   record its hash as `summary_sha256`;
6. call the observer with the transition identity when the record names a
   control;
7. mark the record `finalized`.

Outcome resolution stays distinct from sealing. A run that resolves at the
closure gate and then records closeout evidence is finalized by step 4 and
after; nothing forces the seal earlier. Success is claimed only after the run is
sealed and its own summary is valid — a run whose sink is contradictory becomes
`failed` with a bounded code, never a quiet success. The canonical summary comes
from the sink; nothing here reconstructs it.

Whenever a transition stops short, the record is first reconciled from whatever
the sink last established, then the registry-specific failure is recorded. The
registry may say that processing failed; it may never contradict a lifecycle
fact the sink already holds. When the sink cannot be read at all, the last
mechanically known state is retained and the record is marked `unreproducible`
rather than given newer facts nobody observed.

`--outcome` means one thing to each caller, and the difference is what keeps the
guard's printed command executable in every state it can report:

- `finalize --outcome X` **asserts** X. A sink that already resolved something
  else is an `OUTCOME_CONFLICT`.
- `recover --outcome X` **offers** X, and only for a run that resolved no
  outcome of its own. A run that already resolved one is finished as it is.

A finalized run answers the assertion too, and answers it from the sink. Before
any successful retry — `finalize` or `recover` — the record is reconciled with
the canonical summary: the run, repository, and issue must match, the sink must
be sealed, its lifecycle and outcome must agree with the record, its integrity
must be valid, and its summary must still hash to the stored `summary_sha256`.
Only then is repeating the same `finalize` idempotent; a different asserted
outcome is refused, and the sink's outcome — never the row's — is what the
assertion is checked against. A record is a commitment to sink facts, not a
second source of them, so corruption appended after finalization, an edited row,
or a stale hash all refuse rather than succeed, and evidence that has gone
missing takes the bounded `unreproducible` path. Recovery keeps its offer-only
meaning throughout.

`Closes`, `Progresses`, and `preflight-aborted` reach finalization through the
ordinary hand-backs in [`github-closeout.md`](./github-closeout.md) and
[`closability-gate.md`](./closability-gate.md). `abandoned` and `failed` are
honest endings too: finalize or recover the run with that `--outcome`.

Bounded failure codes: `OUTCOME_UNRESOLVED`, `OUTCOME_CONFLICT`,
`RESOLVE_FAILED`, `SEAL_FAILED`, `INTEGRITY_INCOMPLETE`, `INTEGRITY_INVALID`,
`SUMMARY_FAILED`, `IDENTITY_MISMATCH`, `OBSERVER_FAILED`,
`OBSERVER_IDENTITY_MISMATCH`, `SINK_MISSING`, `REPOSITORY_MISSING`.

## The next-run guard

`register` refuses a governed run while another record with the same control id
is `pending`, `finalizing`, or `failed`. The refusal names the blocking run's
bound handle, its repository and issue, its lifecycle and finalization state,
its failure code, and exactly one recovery command — which is executable exactly
as printed, including for a run that was interrupted before it resolved any
outcome. That command names `--outcome abandoned` for such a run, because
recovery never guesses an outcome on a run's behalf.

The guard is keyed on the control id alone. A record without one — every run for
which no observer applies — can never block anything, and a governed run in one
repository never blocks an unrelated repository or issue unless its own observer
says they share a control.

## Recovery

`recover` finishes the same run and never mints a replacement. It resumes a run
killed before hand-back, between resolve and seal, or during finalization
itself, and retries a `failed` obligation after its cause is fixed. It is
idempotent: recovering a finalized run reports it and changes nothing, and a
crash after the observer accepted replays one transition identity rather than
starting a second transition.

It finds the run's repository from the sink path it recorded, so a removed
linked worktree does not strand it. When the sink is gone, or no repository
containing it can be reached, the run becomes `unreproducible` with the
corresponding bounded code. That state is durable: the run stays in the registry
as a run that happened and cannot be reproduced, rather than disappearing, and
it stops blocking later runs.

`recover --all` walks every outstanding record in one pass.

## Locking

There is one lock order, used everywhere a record can be created, transitioned,
evicted, pruned, or removed:

```text
registry lock  →  record lock
```

A record transition holds the registry lock **shared** for its whole command and
then its own record lock exclusively. Admission, eviction, and retention hold
the registry lock **exclusive**, and still take a record's own lock before
unlinking it. Cleanup therefore cannot run while any transition is in flight, a
row can never be unlinked underneath a live holder, and a lock pathname can
never be split into two independent lock domains. No path ever takes the two in
the other order, so no deadlock cycle exists.

A record is written by staging a validated file and renaming it into place. The
staged file is removed if its writer exits early, and any that a killed writer
still stranded is reaped by the next admission or prune, so crash artifacts do
not escape the registry's bound.

## Capacity and retention

The registry is bounded — `WORK_ON_REGISTRY_CAPACITY` records, 512 by default.
Registering a new run first drops the oldest record that is safe to drop: one
with no control id, or one whose obligation is already `finalized`. A record
that still owes an observer something is never dropped, and when nothing is safe
to drop, registration of a governed run refuses with the capacity-specific
diagnostic rather than losing the evidence.

An ordinary run is never blocked by the registry: once applicability has
established that nothing observes it, control-support pressure *and* local
storage trouble — an unusable state root, an unusable lock, a record that cannot
be written — all take the same route. Admission says so, the run continues
**unregistered**, and its hand-back still completes — with no
registry row, `finalize` performs #71's own resolve/seal directly and reports
`finalized <run-id> unregistered`. Skipping the registry is all that path skips:
it rereads the sink afterwards and requires the same run identity, the same
asserted outcome, a sealed lifecycle, and `integrity=valid` before reporting
success, so it is never a weaker substitute for #71's contract. A *governed* run that reaches hand-back with
no record is the failure this mechanism exists to surface, and is refused.

For a governed run those same failures stay fail-closed: an obligation that
cannot be recorded is an obligation that must not be started.

`prune --older-than-days N` applies the same safe-to-drop rule by age.

This is deliberately not an analytics store. It holds what is needed to find and
finish a run, and the sink holds everything else.

## Where this fits

The registry and observer seam are the generic mechanism owned by
[#9](https://github.com/faviann/skills/issues/9). No policy adapter consumes
them: the formal control window they were intended to serve was retired in
[ADR 0006](../../../../.agents/adr/0006-retire-the-formal-control-window-for-pr-local-observation.md),
and observation is now PR-local. Leaving the seam in place is not an
endorsement; removing it is a separate maintenance decision.
