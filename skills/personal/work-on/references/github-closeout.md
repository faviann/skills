# Closure gate and GitHub closeout

## Adversarial closure gate

Apply `validation-evidence.md` to reuse qualifying evidence and to decide when
the closure context owes the narrowest Independent execution.

When the selected workflow delegates a closure axis, use a fresh subagent given
raw artifacts only. Neither kind receives the ledger or anyone's conclusions.

### Cumulative closure

An initial or final cumulative closure axis receives the selected workflow's
identical neutral cumulative-review package. Independently inspect the full
contract, production paths, cumulative subject, and evidence, then build this
complete table:

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

It returns a trace table: every mechanism a reviewer could name (a state, a run,
a handler, a retry) mapped to the acceptance criterion requiring it. The primary
adjudicates uncited rows: removal — removals re-enter the review loop — unless
the ledger records why removal is worse than keeping it. Put the table and
rulings in the PR body. The final cumulative axis is the complete closure-table
backstop after remediation.

### Delta closure

The delta closure axis receives the selected workflow's identical neutral pinned
review package and its incremental closure brief. Begin at the exact correction
and judge only its effects on contract coverage, production paths, validation
seams, Validation-surface members, evidence identity or sufficiency, scope, and
unrequired machinery. Follow the package's concrete unchanged-context and #62
rules when those effects require it.

Return the closure findings and affected criterion/mechanism rows attributable
to that scope. This delta closure is incremental: it does not reconstruct the
complete cumulative closure table or trace every unchanged mechanism. The
primary retains the provisional cumulative table without exposing it to the
delta reviewer; final cumulative review supplies the complete closure table as
the backstop.

## Closeout confirmation

Closeout consumes exactly one applicable clean cumulative confirmation: either
the clean initial cumulative gate while its candidate and governing inputs stay
unchanged, or the post-remediation fresh blind cumulative confirmation. Do not
delegate a second identical closure sweep merely because Closeout begins. Reuse
the confirmation only while its base, exact Candidate identity, trusted
snapshot, binding standards, accepted full review contract,
Validation-surface manifest, and reviewed artifacts are unchanged. New
qualifying raw evidence for that exact candidate may complete the provisional
table without invalidating confirmation. A candidate-content or governing-input
change returns to the selected workflow's review state machine.

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
remain ordinary Markdown. Put them in an untracked narrative file, excluding
the mechanically owned `## Issues`, `## Closure gate`, and `## Work-on`
sections. `## Follow-ups` and `## Finding adjudications` are ordinary narrative
Markdown, not required sections.

For every non-empty narrative, the renderer adds a mechanically owned
`## Narrative` boundary before copying the narrative Markdown verbatim, apart
from normalizing terminal blank lines.

Put only the four authored facts in an untracked JSON file:

```json
{
  "issue_number": 123,
  "outcome": "Closes",
  "acceptance_criteria": ["The acceptance criterion"],
  "acceptance": [{
    "criterion": "The acceptance criterion",
    "production_path": "`path/to/artifact`",
    "seam": "The exact public artifact, mode, or seam",
    "evidence": "The observed evidence",
    "status": "tested"
  }]
}
```

The primary supplies `acceptance_criteria` from the authoritative issue
snapshot. It must be a non-empty array of unique, non-empty strings, and the
`acceptance` rows must match that set exactly once. The renderer refuses any
`telemetry` key, any facts-supplied provenance or run history, and any other
top-level field. Provenance comes only from Run custody.

Render the complete human-readable body with the Run identity minted by
contract freeze:

```sh
~/.agents/skills/work-on/scripts/render-closeout.sh \
  --run "$RUN_IDENTITY" <untracked-facts.json> <untracked-narrative.md> --new-pr \
  > <untracked-pr-body.md>
```

For an existing pull request, first save its live body, then use
`--previous-body <old-body.md>` instead of `--new-pr`. The renderer reads the
captured provenance from that Run identity's complete custody; it never verifies
live instruction files. Thus an authorized change to governing instructions in
the same uninterrupted invocation does not invalidate closeout.

The mechanically owned sections are, in order:

```md
## Issues

Closes #123

## Closure gate

| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |
|---|---|---|---|---|
| The acceptance criterion | `path/to/artifact` | public seam | observed evidence | tested |

## Work-on

Run 20260827T182139Z-3f9ac1b2a4d6e8f0: work-on:a1b2c3d4e5f6* workflow:0f1e2d3c4b5a tdd:9a8b7c6d5e4f review:112233445566 (faviann/skills@0a1b2c3d4e5f)
```

`Closes` means the pull request fully satisfies the issue contract and requires
every closure row to be `tested`; `Progresses` is every other safe partial
outcome. The input issue appears exactly once.

Each run that renders the body contributes one line joining its opaque Run
identity to its exact captured canonical provenance. The identity syntax
accepted by consumers is `[A-Za-z0-9._-]{8,64}`. It records render order only:
no predecessor/successor relation, continuation, lifecycle, or completeness
claim. The `(owner/repo@sha)` pointer belongs to provenance, not to Run identity.
A published identity may outlive its custody; it is an opaque correlation token
into git, GitHub, and the harness corpus, never a lookup key into a live store.

The list is append-only by Run identity. Re-rendering the same identity requires
its whole line to match and appends nothing. A new identity appends exactly one
line. Contradictory provenance for an existing identity fails, and all earlier
lines survive byte-for-byte in order. When an old-format body is actually
re-rendered, only canonical provenance from its `Run N:` lines is carried
forward, in order, as `Legacy run: <canonical provenance>` ahead of the current
line. No identity is invented and no telemetry value migrates. Finished old
pull requests are otherwise left alone and never revalidated.

Create or update the pull request, then read back and validate the exact body:

```sh
gh pr view <pr-number> --json body --jq .body \
  | ~/.agents/skills/work-on/scripts/validate-closeout-body.sh <issue-number> -
```

For an update, also pass `--previous <old-body.md>`. The validator checks only:
the three required headings exactly once and in order; the single issue-mapping
line; `--require-closes`; the closure table shape, status vocabulary, and
`Closes` ⇒ every row `tested`; Work-on line shape and Run-identity uniqueness;
the previous provenance prefix with at most one appended Run line; and CRLF
normalization of its scratch copy. It inspects no other historical content and
does not recursively validate the previous body.

Once the body has been read back and validated, apply the repository-local
`work-on` label with `scripts/ensure-work-on-label.sh`. Its failure warns and
does not block hand-back. Generic validation accepts canonical `Closes` and
`Progresses`; unattended AFK closeout passes `--require-closes` and refuses
`Progresses`. Report the pull-request URL and keep all scratch files untracked.
