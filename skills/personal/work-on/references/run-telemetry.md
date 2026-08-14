# Run-scoped telemetry

`scripts/run-telemetry.sh` records what one `work-on` run actually did, so the
workflow can be measured before its review semantics change. It records the
current workflow; it does not change it. Every stage still runs in the same
order, with the same authority, for the same reasons.

## The sink

One run is one append-only JSON-lines file:

```text
$(git rev-parse --absolute-git-dir)/work-on-telemetry/
  current-run              # the active run id
  runs/<run-id>.jsonl      # that run's events, one JSON object per line
```

It sits in the target repository's git-dir beside the provenance ledger and the
adjudication log, so it is untracked by construction, survives a branch switch,
and never reaches a published artifact. A run id is `<UTC timestamp>-<8 hex>`;
starting a run mints a new id and a new file, so two runs never share events.

Every line carries `schema`, `run`, `seq`, `at`, `epoch_ms`, and `type`. The
current schema version is **1**; the rendered pull-request body names it.

## Recording a run

Run these from the target repository. Each one appends and exits; nothing is
buffered, so an abandoned run leaves exactly what it had recorded.

| When | Command |
|---|---|
| Once, when the run begins | `run-telemetry.sh start` |
| Every top-level subagent launch | `run-telemetry.sh launch --role R --phase P --round N [--tokens-in N --tokens-out N]` |
| Every review handed to a subagent | `run-telemetry.sh review --kind K --phase P --round N --base REF (--head REF \| --worktree)` |
| Every top-level validation command | `run-telemetry.sh exec --phase P --round N -- <command>` |
| Once, after the pull request is created or updated | `run-telemetry.sh finish --outcome (Closes\|Progresses\|aborted)` |

- `--role` is one of `implementation`, `readiness`, `review-standards`,
  `review-spec`, `closure-sweep`, `other`.
- `--phase` is one of `orient`, `implementation`, `checkpoint`, `gate`,
  `remediation`, `closeout`.
- `--kind` is one of `readiness`, `full`, `delta`. `delta` exists in the schema
  so the recorder does not need changing later; the current workflow never
  emits it.
- `review` resolves both refs to full SHAs itself and measures the compared
  diff's byte count itself. Use `--worktree` for a sweep that reads uncommitted
  work, which measures the working tree against `--base`.
- `exec` runs the command, passes its stdout, stderr, and exit status straight
  through, and records the execution around it. Wrap the top-level command, not
  its child processes.

Token counts are optional. A runtime that does not expose them records launches
without `--tokens-in`/`--tokens-out`; the summary then reports token coverage as
`none` or `partial` and nothing fails. Never estimate a token count.

## Interruption

`exec` closes its own execution even when the run is interrupted: a wrapper that
receives `SIGINT` or `SIGTERM` records outcome `interrupted`, and a failing
command records `failed` with its exit status. A wrapper killed outright cannot
write anything, so its start has no end; aggregation reports that deterministically
as an `incomplete` execution instead of failing. A line the recorder did not
write is counted as `malformed_lines` and ignored. The sink is never rewritten,
so no interruption can lose an earlier event.

## What is deliberately not recorded

The recorder has a closed set of fields — enumerated roles, phases and kinds,
resolved SHAs, integers, and a redacted command identity. There is no field for
free-form text, so none of the following can be stored even by mistake:

- prompts, contracts, briefs, or subagent reports;
- issue bodies, comments, or repository documentation;
- diffs, file contents, or test output — a review records only how many bytes
  were compared, and `exec` records only an exit status and a duration;
- environment variables, credentials, or raw untrusted diagnostics.

Command arguments are the one place a secret could arrive, so `exec` redacts a
token whose name, flag, or value shape looks like a credential before storing
it. Keep secrets in the environment rather than on the command line anyway.

## Bounded closeout summaries

`run-telemetry.sh summary` aggregates one run's sink into a deterministic JSON
document: the same sink always produces the same summary. `render-closeout.sh`
calls it and renders five bounded rows into the mechanically owned
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
