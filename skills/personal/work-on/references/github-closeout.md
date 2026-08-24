# Closure gate and GitHub closeout

## Adversarial closure gate

Apply `validation-evidence.md` to reuse qualifying evidence and to decide when
the closure context owes the narrowest Independent execution.

Independently inspect the contract, production paths, diff, and evidence, then
build this table:

| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |
|---|---|---|---|---|

Status values:
- `tested` — evidence that exercises the actual artifact in the actual mode
  and would fail were the behavior absent: a test run, raw output, or an
  inspected screenshot.
- `failing` — direct evidence shows the criterion violated.
- `inferred` — indirect evidence only.
- `unverified` — no evidence.

A criterion reaches `tested` only when such evidence exists for every instance
in its frozen Validation surface.

Hunt for: the wrong artifact/host/path, internal-surface reads posing as
public-surface tests, invented exceptions, fail-open validation, untested
runtime modes, scope drift, tests that stay green when the claimed behavior
is absent, and machinery whose only consumer is its own test — a seam built
to make a conversational constraint mechanically checkable.

Delegate a sweep of the cumulative diff to a fresh subagent given raw
artifacts only — the diff command, issue snapshot, and binding doc paths;
never the ledger or anyone's conclusions. It returns a trace table: every
mechanism a reviewer could name (a state, a run, a handler, a retry) mapped
to the acceptance criterion requiring it. The primary adjudicates uncited
rows: removal — removals re-enter the review loop — unless the ledger
records why removal is worse than keeping it. Put the table and rulings in
the PR body.

Reuse a combined-candidate-gate sweep only while its base, HEAD, trusted
snapshot, and artifacts are unchanged; final regression may complete its
evidence. Otherwise rerun it.

Outcome:
- Every criterion `tested` and no unresolved hard-rule breach → eligible for
  `Closes`.
- Any `failing` row → return to remediation, or `Progresses` plus a blocking
  tracker issue when the fix is out of scope.
- Any `inferred`/`unverified` row → show the table and evidence to the human,
  who may verify the row (their confirmation, quoted in the PR body, makes it
  `tested`) or amend the issue contract (rebuild the table against it). No
  answer → `Progresses` plus a tracker issue.
- A trusted criterion requiring direct evidence at an instance the frozen
  Validation-surface manifest omits → `Closes` is unavailable; take the
  selected workflow's post-delegation manifest hand-back; never append the
  member and re-review in this run. This governs over the `inferred`/
  `unverified` route above: an omitted member is not a row a human can confirm.
- A criterion with no seam to observe it → escalate as a missing validation
  seam (blocking tracker issue), never mark it green. Never manufacture a
  seam for a conversational constraint — markers, protocols, or artifacts
  whose only consumer is the gate itself. Escalate so the human can restate the
  criterion against an observable artifact — the instruction text a runtime
  loads is greppable where the behavior it requests is not — or specify the
  mechanism in the contract. Seams that make mechanical behavior observable
  (injected boundaries, scripted externals) remain ordinary good engineering.

## Reconcile discovered work

Before creating the pull request, classify every unresolved element:

- **Blocking:** required to satisfy the current issue. Create or identify a
  tracker issue, record the blocking relationship, and progress rather than
  close the current issue.
- **Non-blocking:** actionable but outside the current issue contract. Create
  a tracker issue; the current issue may still close.
- **Resolved:** record the decision in the source issue or pull request and,
  when durable, the repository's decision documentation. Do not create an
  open issue.

New unresolved issues start at `needs-triage` unless the active triage workflow
has already established another state. Include:

- origin
- observation
- open question
- why it matters
- relevant constraints
- completion condition

Do not leave actionable unresolved work only in a final report or repository
backlog file.

## Create or update the pull request

Preserve the repository's pull-request template. Free-form summary,
implementation explanation, validation, finding adjudications, and follow-ups
remain ordinary Markdown. Put that content in an untracked narrative file,
excluding the mechanically owned `## Issues`, `## Closure gate`, and
`## Workflow telemetry` sections.

For every non-empty narrative, the renderer adds a mechanically owned
`## Narrative` boundary before copying the narrative Markdown verbatim, apart
from normalizing terminal blank lines. The narrative may begin with any
Markdown block; do not add or require a heading merely to satisfy the
validator.

Put the closeout facts in an untracked JSON file with this shape:

```json
{
  "repository": "owner/repository",
  "issue_number": 123,
  "outcome": "Closes",
  "acceptance_criteria": [
    "The acceptance criterion"
  ],
  "acceptance": [
    {
      "criterion": "The acceptance criterion",
      "production_path": "`path/to/artifact`",
      "seam": "The exact public artifact, mode, or seam",
      "evidence": "The observed evidence",
      "status": "tested"
    }
  ],
  "telemetry": {
    "model_configuration": "observed value or unknown",
    "blocking_findings_resolved": 0,
    "findings_rejected_at_adjudication": 0,
    "final_workflow_outcome": "Closes"
  }
}
```

The primary supplies `acceptance_criteria` from the authoritative issue
snapshot. It must be a non-empty array of unique, non-empty strings, and the
`acceptance` rows must match that set exactly once: no missing, extra, or
duplicate criteria. This mechanically checks completeness against the
primary-supplied contract data; it does not establish that the supplied
criteria are truthful.

Render the complete human-readable pull-request body:

```sh
~/.agents/skills/work-on/scripts/render-closeout.sh \
  --run "$RUN_HANDLE" <untracked-facts.json> <untracked-narrative.md> --new-pr \
  > <untracked-pr-body.md>
```

For an existing pull request, first save its live body, then render with
`--previous-body <old-body.md>` in place of `--new-pr`. Exactly one mode is
required. The renderer accepts `-` instead of the facts path to read facts from
stdin. It fails before writing any body when the run's frozen provenance cannot
be verified, the run has no telemetry sink, schema-2 integrity is not valid,
repository/issue/outcome identity differs, the facts are malformed, the
authoritative criteria and
closure rows do not match exactly once, a required acceptance row or telemetry
value is absent, a status is outside
`tested`/`failing`/`inferred`/`unverified`, a `Closes` row is not `tested`, the
two outcome fields contradict each other, or the shipped read-back validator
rejects the rendered candidate. Inspect the rendered Markdown as the actual PR
body; manual `work-on` does not depend on the AFK watcher or on a human reading
JSON.

Every render appends exactly one run from the frozen provenance of the current
run, even when it equals the prior run. In `--previous-body` mode the prior runs
come only from the saved live pull-request body and survive as an exact prefix.
Facts never supply provenance or prior runs.

The renderer generates this issue mapping:

```md
## Issues

Closes #<issue>
Progresses #<issue>

## Follow-ups

- #<issue> - <short description>
```

Rules:

- `Closes` — only when the gate resolved to it; means the pull request fully
  satisfies the issue contract.
- `Progresses` — every other case; means it contributes without completing
  the contract.
- The input issue appears in exactly one of those groups.
- Include related issues only when the change materially addresses them.
- Issue category and labels do not change these semantics.
- Omit `Follow-ups` when empty.

Retain the gate's one result as `OUTCOME` (`Closes` or `Progresses`) and use it
for both outcome fields in the facts file and the telemetry resolution below.

Include `## Finding adjudications` in the narrative with the ledger's rationale
lines and the sweep's trace table; omit it when no blocking findings were
adjudicated.

Three observations are primary-reported through the facts file — model
configuration, blocking findings resolved, and findings rejected at
adjudication. Every other row is derived from the run's telemetry sink:

```md
## Workflow telemetry

| Field | Observed value |
|---|---|
| Model configuration | <observed value or unknown> |
| Start-to-seal elapsed | <milliseconds> ms, or unknown |
| Implementation rounds | <count> |
| Independent-review rounds | <count> |
| Remediation implementation launches | <count> |
| Validation executions | <count> |
| Blocking findings resolved | <count or unknown> |
| Findings rejected at adjudication | <count or unknown> |
| Final workflow outcome | Closes or Progresses |
| Telemetry run | <bare run id> (schema <version>, integrity <state>) |
| Subagent launches | <total and by-role breakdown> |
| Reviews recorded | <total and readiness/full/delta breakdown> |
| Reviewed artifact bytes | <bytes> bytes, or unknown |
| Validation executions recorded | <total and outcome breakdown> |
| Recorded validation duration | <milliseconds> ms, or unknown |
| Measured phase elapsed | <per-phase seconds, or unknown> |
| Workflow provenance | <N> run or runs |
```

Use observed values only; never estimate. The outcome must match the issue
mapping. A mechanical count of zero is a plain `0`, not a flag.

The renderer aggregates every sink-derived row itself, appends the mechanically
owned source note naming which rows are primary-reported, and rejects facts
whose `telemetry` object holds anything beyond the four fields shown above —
under any name, not a fixed list of forbidden ones; see
`references/run-telemetry.md`. The
table describes the latest run alone, so a later run may legitimately report
smaller counts than the previous body did. Individual launches, reviews,
and validation executions stay in the sink. Record the run's outcome with
`scripts/run-telemetry.sh resolve --run "$RUN_HANDLE" --outcome "$OUTCOME"` as
soon as the gate resolves it. Record legitimate closeout evidence, then run
`scripts/run-registry.sh finalize --run "$RUN_HANDLE"` before rendering: it
seals the run and discharges its registered lifecycle from the sink's own
sealed summary, and refuses to report success unless that summary is valid. A
run the registry deliberately left unregistered is sealed the same way and
reported as `unregistered`.
Schema-2
rendering fails unless integrity is `valid`, repository/issue/outcome identity
matches the facts, and the run has exactly one compatible resolution and seal.
Rendering never repairs the sink.

Create or update the pull request, then read back its final body and validate
the exact content returned by GitHub:

```sh
gh pr view <pr-number> --json body --jq .body \
  | ~/.agents/skills/work-on/scripts/validate-closeout-body.sh <issue-number> -
```

For an updated pull request, also pass `--previous <old-body.md>` so validation
proves that its prior provenance runs were preserved as an exact prefix. Only
the current table format is accepted. A pull request whose body was written
under the earlier format is not migrated: revalidating it refuses and blocks
hand-back on that pull request. Those pull requests are finished; leave the
historical body in place.

Once the body has been read back and validated, make the observation findable:

```sh
~/.agents/skills/work-on/scripts/ensure-work-on-label.sh \
  --repository <owner/repository> --pr <pr-number>
```

It applies the repository-local `work-on` label, creating it with fixed bounded
metadata when absent and leaving an existing label's color and description
alone. The label is a discovery aid, not evidence authority: a lookup, creation,
or application failure prints one bounded warning and hand-back continues. Name
the repository and pull request explicitly; neither is inferred.

The canonical issue mapping, acceptance rows and statuses, and telemetry
outcome must survive read-back. Generic validation accepts canonical `Closes`
and `Progresses` bodies for manual closeout. Unattended AFK closeout invokes
the same validator with `--require-closes` and refuses `Progresses` before the
guarded merge or required checks. Report the pull-request URL. Keep the facts,
narrative, rendered body, and any other closeout scratch untracked.

<!-- Maintainer watch signals, not workflow instructions. Across recent
work-on PRs: (a) adjudication sections dominated by "keeping it"
justifications → the sweep flags junk; tighten what it flags. (b) zero
findings rejected in telemetry while independent-review rounds stay high →
inspect whether adjudication is filtering findings or raw findings are being
forwarded; repeated full gates can also expose real new defects. -->
