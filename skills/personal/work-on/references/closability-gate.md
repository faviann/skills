# Pre-implementation closability gate

Decide whether the issue can reach `Closes` **before** implementation is
delegated — not after code, review, and remediation have already been spent on
a criterion that was never observable.

Run this once, after the trusted snapshot and the selected workflow have been
read, and before workflow-provenance capture, implementation delegation,
production or test edits, implementation commits, and any pull request.

The gate decides only whether the issue is closable in this run. It changes no
readiness, Standards, Spec, closure, remediation, validation, or closeout
semantics, and adds no tracked artifact, ledger, or telemetry field of its own.
A pass records nothing beyond the run-local Validation-surface manifest it
freezes. An abort resolves the run's existing outcome as
`preflight-aborted`, as the abort steps below require.

## The reasoning the primary produces

For every acceptance criterion, name four things:

- the production path the implementation will affect;
- the actual artifact, mode, host, or public boundary the behavior will be
  observed through;
- the concrete validation action that can run after implementation; and
- the observation that would fail if the criterion were not satisfied.

The production behavior does not have to exist yet. A seam is **available**
when it already exists, or when creating it is explicitly inside this issue's
authorized implementation scope — and, in either case, only when its validation
can be executed during this run.

A seam is **not** available when validation depends on:

- unimplemented work owned by another issue;
- an incomplete blocking prerequisite;
- unavailable hardware, account, device, service, credential, host, or
  environment;
- a future operator action not available in this run;
- an out-of-scope mechanism;
- a gate-only artifact whose sole consumer is the gate; or
- indirect inference where the closure contract requires direct evidence.

## The Validation surface each criterion must materialize

A criterion's **Validation surface** is the complete finite set of concrete
artifact, mode, host, or public-boundary instances whose behavior it requires
direct evidence about for the issue to close. It is not the criterion's input or
state domain — coverage inside a seam may stay parameterized, property-based, or
representative — and it is not the implementation diff. It answers which
instances must carry direct evidence, never where implementation or review may
look; the selected workflow owns that boundary.

Materialize every surface here, in one of two forms:

- an explicit finite enumeration; or
- a deterministic, non-interpretive finite selection rule.

Either form must actually be evaluated during this preflight and produce the
complete concrete list for the trusted snapshot — the one list any later
execution against that same snapshot would also produce. `all relevant
authority` and `whatever implementation touches` fail, because later judgement
can grow their population. A deterministic traversal or tracked-path rule passes
only when executing it here yields that list.

A surface may name an exact artifact this issue authorizes creating, but only
when its identity, location, and criterion role are already determinable from
the trusted contract. An artifact implementation merely turns out to touch never
joins a surface.

Finiteness does not weaken evidence: every member still requires the direct
evidence its criterion demands under conditions 1 and 3.

Together, these surfaces are the run's **Validation-surface manifest**.

## Phase ownership

Enumerate every definitely owed validation command and direct-evidence
obligation from the trusted contract, Validation-surface manifest, repository
baseline, and planned scoped-delegate contract. Resolve each one's owning phase
deterministically from the selected workflow, interpreted alongside the
governing validation authority that establishes what is owed. The selected
workflow alone supplies execution timing; the other sources cannot pull an
obligation earlier merely by listing it.

Keep every resolved obligation and owning phase available for the scoped
delegate contract, including obligations owned by later phases. If the selected
workflow does not deterministically resolve an obligation's phase, condition 4
fails and the unresolved phase aborts Closability. Infer no implementation,
earliest, next-gate, or Closeout default.

Where an enumerated owed obligation is a command the manifest records as the
discharging action for a criterion's Validation surface, what is owed is that
surface's enumerated members' required observations. The command is the default
vehicle that produces them and carries the obligation's owning phase.
Re-executing that exact command is not itself the discharge condition; the
obligation is discharged when every owed member of that surface has qualifying
evidence at the owning phase.

## Conditions

The gate passes only when all six hold.

1. **Every acceptance criterion has a direct validation seam**, available under
   the rules above.
2. **Every blocking prerequisite is complete.** Inspect native GitHub blocking
   relationships, explicit "blocked by" or prerequisite references in the
   trusted snapshot, parent/spec requirements needed to exercise the seams, and
   repository or environment prerequisites named by the selected workflow. A
   prerequisite is not complete because similar behavior exists elsewhere. A
   criterion depending on an open prerequisite blocks implementation.
3. **No criterion is knowingly limited to `inferred` or `unverified`.** Abort
   when the primary already knows a criterion can produce only indirect
   evidence, source-level inference for a runtime claim, shared-predicate
   reasoning without exercising the required transition, a mocked internal path
   where the contract requires a public boundary, a human assumption with no
   available verifier, or no evidence at all. Proceed when the planned
   validation would directly produce `tested` evidence after implementation.
4. **The required workflow and validation commands are executable, and every
   definitely owed obligation has a resolved owning phase.** Abort when a
   command needs a dependency or authority that cannot be established within
   this scope, or when the selected workflow cannot deterministically resolve
   its phase. Ordinary setup explicitly included in the run is available. A
   transient command failure during later validation is not a preflight
   failure: this asks whether the path is available and executable, not whether
   the unimplemented candidate already passes.
5. **The trusted contract is internally consistent.** Abort on a criterion
   requiring behavior the issue places out of scope, two trusted requirements
   demanding incompatible outcomes, a criterion requiring a mechanism the issue
   prohibits, incompatible issue-body and trusted-maintainer amendments, a
   closing condition that cannot coexist with a named prerequisite, or
   ambiguity material enough that the implementation delegate would have to
   choose the contract. Adjudicate ordinary wording against the trusted
   sources; never invent a requirement or choose between genuinely
   incompatible trusted ones.
6. **Every criterion's Validation surface is finite and materialized here.**
   Abort when a criterion's direct-evidence population can be settled only by
   later judgement — an interpretive rule, an open-ended traversal, or a
   population the implementation delegate would have to discover. A criterion
   whose surface the trusted contract does not make decidable — evaluated
   against the trusted snapshot and the pre-implementation base — takes this
   abort; it is never rescued by reading the criterion more narrowly than the
   trusted contract states it.

## Manual and human seams

A manual seam counts only when the trusted contract explicitly allows that form
of verification, the required human, device, or environment is actually
available during this run, the exact observation is defined in advance, and the
result can be recorded as direct evidence.

An AFK run may not assume a human will become available later. A future request
for human confirmation at closeout is not a pre-implementation seam.

## Size is not a condition

Do not reject an issue here on file count, diff size, acceptance-criterion
count, state count, token estimate, complexity score, or any
repository-independent size threshold. Review-budget fit remains a triage and
calibration concern. A large or contract-dense issue whose every criterion has
direct, available validation passes.

## Freeze and custody

The manifest freezes when the complete gate passes — after the trusted snapshot
and the selected workflow have been read, and before workflow-provenance capture
and implementation delegation. Identify it with the trusted snapshot and the
pre-implementation base it was materialized from. The selected workflow remains
an invalidation input below; Workflow provenance owns its instruction-version
identity rather than duplicating it in the manifest.

Before applying the gate, retain the exact selected-workflow identity in the
primary's working context; the path below is relative to the skill root:

```bash
selected_workflow_identity="$(scripts/workflow-provenance.sh identify-workflow)"
```

This shell value is not manifest identity or another durable record. It is the
comparison input for the post-freeze capture. Losing it before capture
invalidates the not-yet-delegated manifest and takes complete recomputation;
identifying the workflow again cannot authorize a manifest already derived.

Before applying the gate, retain the exact source-labelled trusted snapshot it
will read. Preserve each trusted source's attribution and body in that one
snapshot; it is the run's contract, not a serialization a later context must
recreate. Record the committed base before the gate as
`pre_implementation_base="$(git rev-parse HEAD)"`.

Keep that snapshot and the manifest in two untracked run-local files in the
target repository's Git common directory:

```text
$(git rev-parse --path-format=absolute --git-common-dir)/work-on-manifest/
  <run-id>.trusted-snapshot.json
  <run-id>.md
```

using the bare run id from `$RUN_HANDLE`, before its `@`. Both survive a branch
switch and every supported continuation or resume of the run, and never reach a
published artifact. They are run-local semantic contract state: not telemetry,
not Workflow provenance, not Run registry state, and never tracked repository
artifacts. Provenance fingerprints the instructions this run read; it carries
neither object.

Create the directory and both files for their owner only — `0700` and `0600`.
Create each in the shell first, guarded so re-running this step never truncates
what a resume still needs:

```bash
manifest_dir="$(git rev-parse --path-format=absolute --git-common-dir)/work-on-manifest"
run_id="${RUN_HANDLE%%@*}"
trusted_snapshot_file="$manifest_dir/$run_id.trusted-snapshot.json"
manifest_file="$manifest_dir/$run_id.md"
[[ -d "$manifest_dir" ]] || (umask 077 && mkdir -p "$manifest_dir")
chmod 700 "$manifest_dir"
[[ -e "$trusted_snapshot_file" ]] || (umask 077 && : >"$trusted_snapshot_file")
[[ -e "$manifest_file" ]] || (umask 077 && : >"$manifest_file")
chmod 600 "$trusted_snapshot_file"
chmod 600 "$manifest_file"
```

The guards protect frozen state a resume still needs from a repeated creation
step; a rebuild before delegation still overwrites both paths' contents
outright, as invalidation requires. Create each file in the shell before writing
it, then reapply `0600`: the umask closes the creation-to-chmod window only for
shell-created files, while an editor may replace an inode at its default mode.
Write the exact source-labelled snapshot before applying the gate, and write the
materialized manifest when the complete gate passes. Then, from the target
repository, run this skill's identity helper; the path below is relative to the
skill root:

```bash
scripts/manifest-identity.sh freeze \
  --manifest "$manifest_file" \
  --snapshot "$trusted_snapshot_file" \
  --base "$pre_implementation_base" \
  --workflow-identity "$selected_workflow_identity"
```

The command requires both frozen files to be owner-only, prepends the full base
SHA, the snapshot's SHA-256 digest, and one binding digest over both identities
plus the manifest body, and atomically replaces the manifest at `0600`.
Immediately before replacement, it removes the
target worktree's previous Workflow provenance ledger, so only a capture after
this freeze can authorize reuse. It also seals the retained workflow identity
in Workflow provenance's owner-only sidecar, not in the manifest; a later
identity cannot be substituted for it during capture. The binding makes
malformed identity fields, a changed manifest body, or a missing, replaced, or
changed snapshot fail verification. Retain both files for the run's supported
continuation/resume lifetime. A run's record of a workstation's work is not
group- or world-readable.

After the freeze, return to the procedure with the retained identity. The later
capture in `SKILL.md` step 7 compares the current selected workflow with that
retained identity before it writes the provenance ledger. A mismatch invalidates
the manifest and takes complete recomputation before delegation; a later
identity obtained from the changed workflow cannot authorize the old manifest.

The selected workflow supplies the manifest to the implementation delegate and
to the readiness, Standards, Spec, and closure contexts, and keeps it available
to the primary for adjudication. It is contract input, not a prior review
conclusion: reviewers stay independent about whether the evidence satisfies a
criterion, and may report that the manifest conflicts with the trusted contract.

## Invalidation before delegation

Any change to an input the manifest was derived from invalidates it — the
trusted contract or snapshot, the selected workflow, or an enumeration rule or
its inputs.

While no implementation delegate has launched and no implementation work has
begun, discard the manifest, rebuild the affected trusted preflight state, and
rerun the complete gate over it. Rerunning it is not a second gate: the run
passes one complete gate, over whichever trusted preflight state it finally
delegates from. Never patch one entry in place: re-materialize every criterion's
surface, including those whose own inputs did not move. If no valid replacement
can be established, abort as below.

After implementation is delegated the manifest is immutable for this run, and
the selected workflow owns what happens when a trusted criterion turns out to
require an omitted member.

## Pass

Keep the compact criterion-to-seam reasoning in the primary's working context,
write the frozen manifest, capture workflow provenance, and continue the
selected workflow unchanged. A pass records nothing else; the run's outcome
remains the closure gate's to resolve.

## Abort

Launch no implementation delegate, make no implementation edit, and create no
implementation commit or pull request. Then:

1. finalize the run this hand-back ends, with
   `scripts/run-registry.sh finalize --run "$RUN_HANDLE" --outcome preflight-aborted`,
   which resolves that outcome in the sink this run already opened, seals it,
   and discharges the run's registered lifecycle in one step;
2. name the exact criterion, prerequisite, command, unmaterializable validation
   surface, or contract conflict that failed;
3. explain why direct `tested` evidence is unavailable;
4. name the one narrow route out — return to triage; split or amend the issue;
   complete a blocking prerequisite; obtain the explicitly required
   human/manual environment; create or identify a blocking tracker issue; or
   request a trusted-maintainer contract correction; and
5. stop.

Do not convert the failure into a speculative implementation plan, weaken the
criterion to continue, or manufacture a seam.

An aborted preflight is a hand-back, not a candidate closeout: it is never
`Closes`, never `Progresses`, and renders no closeout body. Follow the existing
GitHub-mutation authority and tracker conventions when a blocking issue or
triage change is genuinely required.
