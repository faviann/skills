# Control-window policy and results publication

`scripts/control-window.sh` adapts the generic run registry to one versioned
experiment policy and one append-only GitHub results pull request. It owns the
experiment decision and publication rules. The run telemetry sink remains the
canonical run evidence, and the run registry remains the only local admission
and lifecycle authority.

`work-on` calls this adapter's `register`, `finalize`, and `recover` wrappers.
With no configured policy they preserve the generic registry behavior. With an
active matching policy they make GitHub publication part of the command's
success condition.

## Policy manifest

The manifest is JSON schema **1** with this closed top-level shape:

```json
{
  "schema": 1,
  "control_id": "bounded-token",
  "mode": "demo or production",
  "observer_id": "bounded-token",
  "target": { "repository": "owner/repository", "issue": 123 },
  "population": {
    "repositories": ["owner/repository"],
    "issues": [456]
  },
  "hooks": {
    "match": "never-v1 or repository-issue-set-v1",
    "classify": "registry-lifecycle-v1"
  },
  "results": {
    "repository": "owner/repository",
    "base_branch": "main",
    "branch": "experiment/results-branch",
    "pull_request": {
      "draft": true
    }
  },
  "controller": {
    "scope": "single-xdg-domain",
    "top_level_runs": "sequential",
    "binding_sha256": "64-lowercase-hex-characters"
  },
  "arm": { "id": "bounded-token", "configuration": {} }
}
```

Policy data owns the control and observer identifiers, target issue, population,
matching and classification hooks, results repository/branch/PR, the fixed
single-domain/sequential controller model, and arm configuration. The adapter
supplies the reusable mechanics. Generic
telemetry and registry code contain none of those experiment values.

Only the allowlisted public projection is committed. `arm.configuration`
cannot enter a transition artifact. The
committed projection retains the identifiers, target, population, selected hook
versions, results location, controller declaration and binding digest, and arm
id. The raw controller binding never enters the projection.
The full canonical manifest digest stays only in owner-readable local state, so
a local policy edit cannot silently reuse the prepared public surface.

A production operator provisions one opaque 64-hex binding at
`$XDG_CONFIG_HOME/work-on/controller-binding`, mode `0600`, before preparing the
control, plus that token's digest at
`$XDG_STATE_HOME/work-on/controller-binding.sha256`, also mode `0600`. The
manifest records the same SHA-256 of the token bytes (without its line ending).
The adapter checks both files' ownership, mode, shape, and digest, binding one
configuration root to one state/run-registry root. It never mints either file
from remote evidence or replaces one after loss. The same binding designates
the XDG domain used for the later A3 and B2 controls.

This repository ships two non-operative fixtures:

- `fixtures/control-window/demo-policy.json` is demo-only and matches nothing;
- `fixtures/control-window/b2-like-policy.json` proves the same schema can
  represent a later comparison arm, but defines no actual B2 policy.

No A3-attempt-2 manifest is shipped here.

## Prepare, activate, and close

```sh
control-window.sh validate --policy /absolute/policy.json
control-window.sh prepare --policy /absolute/policy.json
control-window.sh activate --policy /absolute/policy.json
control-window.sh close --policy /absolute/policy.json
control-window.sh close --policy /absolute/policy.json --complete
control-window.sh status --policy /absolute/policy.json
```

`prepare` creates the results branch from the configured base, commits the
bounded policy projection and one `control-prepared` transition, creates or
adopts the draft PR, and verifies its exact branch, base, title, body, draft
state, generated title/body, number, and URL. The PR title and body are generated
only from bounded identifiers, mode, and target, and the body begins
`PREPARED / NON-OBSERVING`.
Preparation stores phase `prepared`; it never makes `applies` match. One
controller domain has one production-policy slot: preparing another production
policy is refused while the configured control is prepared, active, or closing.
Only a remotely reconciled `control-closed` transition releases the slot. Demo
preparation remains descriptor-free.

Every production mutation verifies the controller binding before adopting or
reconstructing phase state. That boundary covers preparation, activation,
matching registration, finalization, recovery, status reconciliation, and
closing. A configured domain with a missing or mismatching binding fails closed;
matching registration fails before #72 can create a row. Loss of mutable phase
state is recoverable from exact remote history while the binding remains, but
loss of the binding is not controller failover.

For a production policy, preparation also configures the adapter at the generic
#72 observer seam and installs one absolute policy descriptor. That is safe in
prepared state because the observer reports not-applicable until activation.
Existing different observer configuration is refused.

`activate` is a separate operation. It accepts only a production policy, proves
the prepared branch/PR and local descriptor still agree, appends and reads back
the exact `control-activated` transition, and only then changes local phase to
`active`. The activation pins the verified prepared PR number, and the
transition id it prints is the opening identity. A demo policy is
mechanically non-activatable: its id must start `demo-`, its branch must start
`demo/`, its match hook must be `never-v1`, and preparation installs no observer
or control descriptor.

The append-only remote history is authoritative for control phase; local state
is its owner-readable projection. `prepare`, `activate`, `status`, matching
`applies`, registration, and closing reconcile that history before trusting a
local phase. A process lost after a successful activation or closing write is
therefore recovered from the one existing transition. Missing or stale local
state cannot hide an opened or closing control.

Closing is likewise two transitions. `control-closing` requires no outstanding
registry obligations and makes public registration refuse new matching work;
`control-closed` can follow only that exact predecessor. The observer continues
to identify the control for #72 recovery of an obligation registered before the
barrier.

## Registration and finalization

The wrapper uses #72 in this order:

1. the adapter reconciles the remote control while holding the control admission
   lock shared by public registration and closing;
2. `run-registry.sh register --run HANDLE` acquires the matching local admission;
3. `run-registry.sh status --run HANDLE` supplies the bounded registered row;
4. the adapter publishes and reads back `run-registered`; and
5. only then does `control-window.sh register` return success to `work-on`.

A publication failure leaves #72's row pending, so implementation does not
begin and the existing next-run guard blocks another matching run. Retrying the
same wrapper reuses the same registry row and deterministic transition.

At hand-back, #72 calls the adapter's observer form:

```sh
control-window.sh finalize --record /absolute/registry-record \
  --transition GENERIC_FINALIZATION_ID
```

The adapter validates the bounded record, publishes `run-finalized` or
`run-failed` from its lifecycle/outcome/hash projection, and returns success
only after exact read-back. A publication failure is `OBSERVER_FAILED`, distinct
from the run's workflow outcome; #72 preserves the registry row and raw sink and
keeps the next-run guard engaged. `control-window.sh recover` drives the same
generic run identity. Missing repository/sink evidence becomes one bounded
`run-unreproducible` transition rather than disappearing.
If #72 later reconciles a previously finalized row to `unreproducible` because
its canonical repository or sink disappeared, the adapter preserves the
historical terminal record and appends one `run-evidence-lost` successor naming
that terminal transition. Repeated recovery adopts the same successor.

## Append-only publication

Every transition is one new JSON file and one ordinary fast-forward commit:

```text
control-window/<control-id>/transitions/<transition-id>.json
```

The transition id is the SHA-256 of its canonical allowlisted content without
the id field. A retry adopts an existing file only when path, identity, and
bytes match exactly. A successful remote push followed by a lost client
response is therefore recoverable without another logical transition.

Every fetch pins ancestry to the preparation merge-base, so a normal advance of
the configured base branch is harmless while a rewritten results branch is not.
It validates the last verified head, linear history, add-only commits, closed
paths and serializers, content and idempotency identities, and compatible state
predecessors. Any mismatch fails closed. The publisher has no
amend, rebase, squash, force-push, reorder, or automatic history-repair path.

Top-level matching runs are sequential in the designated controller domain.
#72's next-run guard and registry are the sole admission authority; parallel
subagents inside the admitted run are unchanged. The remote replay invariant
also rejects any history containing two unresolved `run-registered`
transitions, but that is corruption/evidence validation rather than a lease or
cross-domain admission protocol.

Public registration and closing additionally hold one local control admission
lock across the #72 admission/pending check and exact remote publication.
Closing therefore cannot pass its empty-obligation check while a matching
registration in that controller domain is between generic admission and durable
publication. Remote closing is reconciled before a later registration may call
#72.

## Privacy boundary

Publication serializers construct new JSON objects from a closed allowlist.
They cannot copy caller fields. GitHub receives bounded identifiers, repository
and issue attribution, enumerated lifecycle/outcome/integrity values, and
summary/transition hashes only. It never receives the sink or worktree path,
raw JSONL, prompts, diffs or source content, commands, output, credentials, raw
diagnostics, reviewer prose, or the raw controller binding. Only the binding's
SHA-256 digest appears in `policy.json`. Per-run issue comments are not used.
Every evidence commit also forces the fixed author and committer identity
`Control Window Publisher <control-window@invalid.local>` and a generated
bounded message. Ambient Git identity/configuration and `CONTROL_WINDOW_GIT_*`
values cannot enter published commit metadata; history validation rejects a
different identity or message.

## Where this fits

The telemetry schema and run registry are generic mechanisms owned by #9. This
policy adapter is the #64 experiment layer added by #73. GitHub is append-only
evidence and reconciliation authority, not a distributed lease service. A later
policy may select the B2 arm without changing these mechanics. Population,
sample size,
eligibility, attrition, stopping, success, and observation-boundary decisions
for A3 attempt 2 remain for a separate documentation-only pre-registration.
