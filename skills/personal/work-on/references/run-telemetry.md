# Run-scoped telemetry

`scripts/run-telemetry.sh` records what one `work-on` run actually did, so the
workflow can be measured before its review semantics change. It records the
current workflow; it does not change it. Every stage still runs in the same
order, with the same authority, for the same reasons.

## The sink

One run is one append-only JSON-lines file:

```text
$(git rev-parse --path-format=absolute --git-common-dir)/work-on-telemetry/
  repository-binding       # opaque binding shared by linked worktrees
  runs/<run-id>.jsonl      # that run's events, one JSON object per line
```

It sits in the target repository's absolute Git common directory, so it is
untracked by construction, survives a branch switch and linked-worktree
removal, and never reaches a published artifact. A run id is
`<UTC timestamp>-<8 hex>`; starting a run mints a new id and a new file, so two
runs never share events. The owner-only repository binding is outside the event
schema; `start` combines it with the run id as `<run-id>@<binding>`, so a handle
minted by another repository cannot select a same-named local sink.

Every line carries `schema`, `run`, `seq`, `at`, `epoch_ms`, and `type`. New
runs use schema **2**; the rendered pull-request body names the schema and its
bounded integrity state. Schema-1 sinks remain read-only forensic inputs.

Schema-2 `run_start` records the normalized lowercase GitHub slug from `origin`,
the positive issue number, committed starting HEAD, and run identity. Optional
`continues_run` is accepted only when its repository-bound handle names a
schema-2 run for the same repository and issue. It records continuity only;
readiness is neither skipped nor reused because a continuation exists.

Several subagents and validation wrappers may record at the same time, so
sequence numbers, execution ids, lifecycle transitions, and the append itself
are allocated under an exclusive lock on the run's file. Two writers can never
be handed the same number, and no append can land inside another.

The directory, binding, lock, and every sink are created for their owner only —
`0700` and `0600`. A run's record of a workstation's work is not group- or
world-readable.

## Recording a run

Run these from the target repository. Each one appends and exits; nothing is
buffered, so an abandoned run leaves exactly what it had recorded.

| When | Command |
|---|---|
| Once, when the run begins | `RUN_HANDLE="$(run-telemetry.sh start --issue N [--continues-run HANDLE])"` |
| Every implementation-agent launch | `run-telemetry.sh launch --run "$RUN_HANDLE" --role implementation --phase P --round N [--tokens-in N --tokens-out N]` |
| Every reviewer delegation | `run-telemetry.sh review-delegation --run "$RUN_HANDLE" --role R --kind K --phase P --round N --base REF (--head REF \| --worktree)` |
| Every top-level validation command | `run-telemetry.sh exec --run "$RUN_HANDLE" --command-id ID --phase P --round N -- <command>` |
| Once, when the run's outcome resolves | `run-telemetry.sh resolve --run "$RUN_HANDLE" --outcome (Closes\|Progresses\|preflight-aborted\|abandoned\|failed)` |
| Once, after final evidence is recorded | `run-telemetry.sh seal --run "$RUN_HANDLE"` |

Keep the printed handle for this operation. Every recording, summary, render,
and closeout command requires it; none consults a mutable current-run selection.
A malformed handle, a handle bound to another repository, or one whose sink is
missing from this repository's common directory is refused. A plain schema-1 id
remains accepted only for read-only summary and renderer access to forensic
sinks in the common directory or the current linked worktree's legacy location.
A bound handle that selects schema 1 is likewise forensic-only; schema-2
writers refuse it before torn-line repair or append.

- `launch --role` is `implementation` or `other`. Reviewer roles cannot be
  launched separately from their measured scope.
- `review-delegation --role` is one of `readiness`, `review-standards`,
  `review-spec`, or `closure-sweep`. One invocation is exactly one reviewer.
- `--phase` is one of `orient`, `implementation`, `checkpoint`, `gate`,
  `remediation`, `closeout`.
- `--kind` is one of `readiness`, `full`, `delta`. `delta` exists in the schema
  so the recorder does not need changing later; the current workflow never
  emits it.
- The accepted review combinations are readiness/readiness/checkpoint;
  Standards, Spec, or closure/full/gate; Standards, Spec, or
  closure/delta/remediation; and closure/full/closeout. Recording delta does
  not authorize a delta-review workflow.
- `review-delegation` resolves both refs to full SHAs itself and measures the
  reviewed artifact's byte count itself. Use `--worktree` for a sweep that reads
  uncommitted work; the [worktree-review bundle](#the-worktree-review-bundle)
  below defines exactly what is measured.
- `--command-id` names the validation: lowercase alphanumeric words joined by
  single hyphens, at most 48 characters — `work-on-tests`, `lint`,
  `npm-check-plugin-version`. Give the same check the same id every time, so
  repeated executions of one check are recognisable as one check. It is the
  only thing the sink learns about a command, so choose a name that is safe to
  keep: never derive it from a path, a URL, an argument, or a credential.
- `exec` runs the command, passes its stdout, stderr, and exit status straight
  through, and records the execution around it. Wrap the top-level command, not
  its child processes.
- `resolve` is recorded once when the run's outcome becomes known. `seal` is a
  separate, singular end-of-recording transition. See
  [The run's outcome and seal](#the-runs-outcome-and-seal).

Token counts are optional. A runtime that does not expose them records launches
without `--tokens-in`/`--tokens-out`; the summary then reports token coverage as
`none` or `partial` and nothing fails. Never estimate a token count.

## The worktree-review bundle

`--worktree` measures one deterministic bundle — exactly the material a
readiness sweep is told to inspect, assembled the same way every time:

1. every tracked change against `--base`, staged and unstaged alike; then
2. every untracked, non-ignored regular file, whole, in git's sorted path order.

A staged addition is already a tracked change, so it is counted once, not twice.
Files the repository ignores are not part of the review and are not counted.
Paths needing quoting are passed through exactly, and the presentation
configuration that would otherwise vary the bytes — colour, quoted paths,
external and textconv drivers, prefixes — is pinned. The bundle is measured as
it streams and is never written anywhere.

Measuring `git diff` alone would report a readiness sweep whose whole subject is
new code as a zero-byte review, which is the opposite of what it cost.

## The run's outcome and seal

A run resolves exactly one of `Closes`, `Progresses`, `preflight-aborted`,
`abandoned`, or `failed`. `preflight-aborted` is refused after an implementation
launch or reviewer delegation. Outcome resolution does not end recording:
closeout validation and evidence may follow it. `seal` explicitly ends the
record; every later event is an integrity violation. Duplicate resolutions and
seals are refused.

Rendering a schema-2 `Closes` or `Progresses` closeout requires one compatible
resolution, one seal, and `integrity=valid`. Its normalized repository, issue,
and outcome must match the structured closeout facts.

## Deterministic integrity

`summary` evaluates schema 2 as `valid`, `incomplete`, or `invalid` and returns
only bounded reason codes. It checks the unique start identity, schema and run
consistency, event shapes and sequence, review combinations, validation pairs,
lifecycle order, outcome resolution, sealing, and post-seal events. An
unfinished outcome, unsealed resolved run, or dangling validation is
`incomplete`; malformed or contradictory evidence is `invalid`. Invalidity
dominates incompleteness.

Reason codes are closed and machine-readable:

- incomplete — `OUTCOME_UNRESOLVED`, `RUN_UNSEALED`,
  `VALIDATION_INCOMPLETE`;
- invalid structure/identity — `MALFORMED_LINE`, `MIXED_SCHEMA`,
  `RUN_START_COUNT_INVALID`, `RUN_START_IDENTITY_INVALID`,
  `RUN_IDENTITY_MISMATCH`, `SEQUENCE_INVALID`, `EVENT_SHAPE_INVALID`, and
  `TERMINAL_NEWLINE_MISSING`;
- invalid review/validation — `REVIEW_DELEGATION_INVALID`,
  `VALIDATION_PAIR_INVALID`, `VALIDATION_IDENTITY_MISMATCH`,
  `VALIDATION_COMPLETION_INVALID`;
- invalid lifecycle — `OUTCOME_RESOLUTION_COUNT_INVALID`,
  `OUTCOME_RESOLUTION_INVALID`, `SEAL_COUNT_INVALID`,
  `LIFECYCLE_TRANSITION_INVALID`, `EVENT_AFTER_SEAL`, and
  `PREFLIGHT_ABORT_AFTER_WORK`.

Schema-1 summaries report `legacy-unverifiable`. They retain historical launch
and review event counts as recorded observations, never exact reviewer counts,
and reads never rewrite their source sinks.

This is sink-only integrity. It can prove contradictions and omissions that
leave a partial event pair, but it cannot prove that a caller made every
required instrumentation call. A wholly omitted delegation or validation
leaves no sink evidence to distinguish it from work that never occurred.

## Interruption

`exec` closes its own execution even when the run is interrupted: a wrapper that
receives `SIGINT` or `SIGTERM` records outcome `interrupted`, and a failing
command records `failed` with its exit status. A wrapper killed outright cannot
write anything, so its start has no end; aggregation reports that deterministically
as an `incomplete` execution instead of failing.

A writer killed mid-append leaves a line with no terminator. The next append
closes that line off before writing, so a torn line costs exactly one
`malformed_lines` count and is ignored — it can never fuse with the next event
and destroy both. The sink is never rewritten, so no interruption can lose an
earlier event.

## What is deliberately not recorded

The recorder has a closed set of fields — enumerated roles, phases and kinds,
resolved SHAs, integers, and a supplied validation identifier. There is no field
for free-form text, so none of the following can be stored even by mistake:

- prompts, contracts, briefs, or subagent reports;
- issue bodies, comments, or repository documentation;
- diffs, file contents, or test output — a reviewer delegation records only how
  many bytes were compared, and `exec` records only an exit status and a
  duration;
- environment variables, credentials, or raw untrusted diagnostics;
- **a validation's command line** — neither its arguments nor its program.

A validation is identified only by the `--command-id` its caller supplied. The
command text is never stored, never inspected, and never hashed: a digest of it
would still be a secret-bearing argument list processed for an analytics
purpose, and would name the execution with something nobody can read back. A
deliberately chosen, validated identifier is inspectable, is stable when a
credential is rotated, and is the whole of what the sink knows.

The command's own behaviour is untouched: it receives its exact arguments, and
its stdout, stderr, and exit status pass straight through.

## Bounded closeout summaries

`run-telemetry.sh summary --run "$RUN_HANDLE"` aggregates one run's sink into a
deterministic JSON document: the same sink always produces the same summary.
`render-closeout.sh --run "$RUN_HANDLE" ...` calls it and renders the bounded
rows of the mechanically owned `## Workflow telemetry` section — telemetry run,
schema and integrity; implementation launches; reviewer delegations by kind;
validation executions; and measured elapsed time per phase that recorded events.
Per-launch and per-command events stay in the sink.

The same summary derives seven mechanical aggregates, from the recorded events
alone and with no change to the event schema:

| Row | Derivation |
|---|---|
| Start-to-seal elapsed | `run_sealed.epoch_ms - run_start.epoch_ms` |
| Implementation rounds | distinct `round` over `subagent_launch` with `role=implementation`, `phase=implementation` |
| Independent-review rounds | distinct `round` over `review_delegation` with `kind=full`, `phase=gate` |
| Remediation rounds | distinct `round` over `subagent_launch` with `role=implementation`, `phase=remediation` |
| Validation executions | recorded `validation_start` count |
| Reviewed artifact bytes | sum of valid `review_delegation.input_bytes` |
| Recorded validation duration | sum of valid `validation_end.duration_ms` |

A round is a distinct observed round number, not an event count: Standards,
Spec, and a gate-phase closure sweep sharing one round are one
independent-review round. The `phase=gate` filter admits a gate closure sweep
and excludes the closeout-phase one, readiness, and delta remediation review.
Round counts are counts of observed events, so a wholly omitted instrumentation
call stays undetectable — the same limit the integrity result documents.

Two of the names are deliberately narrow. `Reviewed artifact bytes` is the
deterministic diff or worktree bundle measured once per delegation, not prompt
bytes, model input, or tokens; `Recorded validation duration` covers
instrumented top-level wrappers only.

A seal stamped before its own start describes no interval, and a schema-1 sink
has neither a seal nor an attributable review delegation. Either way the
aggregate renders `unknown` with a bounded warning, never a clamped or
estimated value. Unavailability of one aggregate is not a telemetry-integrity
failure and does not block hand-back.

None of these rows is supplied through the facts file; the renderer refuses
facts that try. Model configuration, blocking findings resolved, and findings
rejected at adjudication remain primary-reported, and a source note below the
table says so. The workflow-provenance runs are unchanged.

## Where this fits

This is the attributable schema owned by
[#9](https://github.com/faviann/skills/issues/9). The run registry in
[`run-registry.md`](./run-registry.md) observes these sealed runs from outside
the repository; that mechanism is not part of this sink or its integrity
result.
