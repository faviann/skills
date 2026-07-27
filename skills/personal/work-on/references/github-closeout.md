# Closure gate and GitHub closeout

## Adversarial closure gate

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

Hunt for: the wrong artifact/host/path, internal-surface reads posing as
public-surface tests, invented exceptions, fail-open validation, untested
runtime modes, scope drift, tests that stay green when the claimed behavior
is absent, and machinery whose only consumer is its own test — a seam built
to make a conversational constraint mechanically checkable. Rerun the
highest-risk checks yourself.

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

Preserve the repository's pull-request template. Add:

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

Also add `## Finding adjudications` with the ledger's rationale lines and the
sweep's trace table; omit when no blocking findings were adjudicated.

Add this section to every pull request created or updated by `work-on`:

```md
## Workflow telemetry

| Field | Observed value |
|---|---|
| Model configuration | <observed value or unknown> |
| Wall-clock elapsed | <measured seconds or unknown> |
| Implementation rounds | <count or unknown> |
| Independent-review rounds | <count or unknown> |
| Remediation rounds | <count or unknown> |
| Validation executions | <count or unknown> |
| Blocking findings resolved | <count or unknown> |
| Findings rejected at adjudication | <count or unknown> |
| Final workflow outcome | Closes or Progresses |
```

Use observed values only; never estimate. Count each agent-launched top-level
validation command once (not its child processes), including delegate and
reviewer runs; reconcile handoffs or report `unknown`. For sharded suites,
report every shard and the sum. The outcome must match the issue mapping.

Create or update the pull request, then read back its final body — the closing
keywords and telemetry outcome must match the gate outcome — and report its URL.

<!-- Maintainer watch signals, not workflow instructions. Across recent
work-on PRs: (a) adjudication sections dominated by "keeping it"
justifications → the sweep flags junk; tighten what it flags. (b) zero
findings rejected in telemetry while remediation rounds stay high →
adjudication isn't biting; raw findings are likely being forwarded. -->
