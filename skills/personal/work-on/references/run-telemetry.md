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

Every line carries `schema`, `run`, `seq`, `at`, `epoch_ms`, and `type`. The
current schema version is **1**; the rendered pull-request body names it.

Several subagents and validation wrappers may record at the same time, so
sequence numbers, execution ids, the single final outcome, and the append itself
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
| Once, when the run begins | `RUN_HANDLE="$(run-telemetry.sh start)"` |
| Every top-level subagent launch | `run-telemetry.sh launch --run "$RUN_HANDLE" --role R --phase P --round N [--tokens-in N --tokens-out N]` |
| Every review handed to a subagent | `run-telemetry.sh review --run "$RUN_HANDLE" --kind K --phase P --round N --base REF (--head REF \| --worktree)` |
| Every top-level validation command | `run-telemetry.sh exec --run "$RUN_HANDLE" --command-id ID --phase P --round N -- <command>` |
| Once, when the run's outcome resolves | `run-telemetry.sh finish --run "$RUN_HANDLE" --outcome (Closes\|Progresses\|aborted)` |

Keep the printed handle for this operation. Every recording, summary, render,
and closeout command requires it; none consults a mutable current-run selection.
A malformed handle, a handle bound to another repository, or one whose sink is
missing from this repository's common directory is refused. A plain schema-1 id
remains accepted only for read-only summary and renderer access to forensic
sinks in the common directory or the current linked worktree's legacy location.

- `--role` is one of `implementation`, `readiness`, `review-standards`,
  `review-spec`, `closure-sweep`, `other`.
- `--phase` is one of `orient`, `implementation`, `checkpoint`, `gate`,
  `remediation`, `closeout`.
- `--kind` is one of `readiness`, `full`, `delta`. `delta` exists in the schema
  so the recorder does not need changing later; the current workflow never
  emits it.
- `review` resolves both refs to full SHAs itself and measures the reviewed
  artifact's byte count itself. Use `--worktree` for a sweep that reads
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
- `finish` is recorded once, when the run's outcome resolves: at the closure
  gate before the body is rendered, or as `aborted` when the pre-implementation
  closability gate hands the issue back. See
  [The run's outcome](#the-runs-outcome).

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

## The run's outcome

A run resolves its outcome exactly once. `finish` refuses a second call, so a
run cannot hold two answers, and the summary of a finished run is **final**: the
aggregation window closes at `run_finish`. The same finished run therefore
summarizes identically however often the body is re-rendered, and every
validation counted in a published body ran before the gate that closed the run.
Anything recorded after `finish` is reported separately as `events_after_finish`
and is not folded into counts an already-published body reported.

Rendering a closeout requires a finished run. `render-closeout.sh` refuses a
body when the run never finished, when it recorded more than one final outcome,
or when the recorded outcome differs from either the issue mapping's outcome or
the observed `Final workflow outcome` field.

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
- diffs, file contents, or test output — a review records only how many bytes
  were compared, and `exec` records only an exit status and a duration;
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
`render-closeout.sh --run "$RUN_HANDLE" ...` calls it and renders five bounded rows
into the mechanically owned
`## Workflow telemetry` section — telemetry run and schema, launches with a
by-role breakdown, reviews by kind, validation executions with outcomes, and
measured elapsed time per phase that recorded events. Per-launch and
per-command events stay in the sink.

Those rows are never supplied through the facts file; the renderer refuses facts
that try. The existing observed-value rows and the workflow-provenance runs are
unchanged.

## Why this lands first

This is the mechanical foundation of
[#9](https://github.com/faviann/skills/issues/9), consumed by
[#64](https://github.com/faviann/skills/issues/64)'s review-topology work. It
exists to establish an attributable control period: runs measured under today's
implementation, readiness, review, remediation, and closeout semantics, before
any of those semantics change. A change measured against no control cannot be
shown to have helped.
