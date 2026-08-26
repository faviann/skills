trusted-snapshot-sha256 258b2daa616659a52287164f04d58c71a4027ec4e2de3989400e72829ac2e5b1
pre-implementation-base dea1579185416cfa0bd4198bb2b904bae67d96ba
manifest-binding-sha256 0d1edf486ac8c951da69faa014494640c4815eea8cfb1b0f500cb861d1d0770d
---
# Validation-surface manifest

Run: `20260826T002100Z-0196225d`

## AC1 — denied diagnostic names the requested project without changing access

- Production path: `bin/check-access` denial branch.
- Surface (explicit finite enumeration): public CLI invocation with owner
  `alpha` and requested project `beta`.
- Validation action: execute the repository suite `bash test.sh`, whose denial
  assertion invokes that exact public boundary.
- Failing observation: the denial succeeds, or its exact diagnostic omits the
  requested project.

## AC2 — ownership proposition is clearer and remains owner-only

- Production path: the ownership proposition in `POLICY.md`.
- Surface (explicit finite enumeration): the single ownership proposition in
  `POLICY.md` at the pre-implementation base.
- Validation action: `bash test.sh` asserts the exact governing proposition and
  exercises owned and cross-project access through the public CLI.
- Failing observation: the proposition no longer limits reports to owned
  projects, owned access fails, or cross-project access succeeds.

## AC3 — staging-retention proposition preserves records, scope, and window

- Production path: the staging-retention proposition in `POLICY.md`.
- Surface (explicit finite enumeration): the single staging-retention
  proposition in `POLICY.md` at the pre-implementation base.
- Validation action: `bash test.sh` asserts the exact clarified governing
  proposition.
- Failing observation: the proposition changes which records or active staging
  scope it governs, or which scope-assigned retention window applies.

## AC4 — deterministic suite directly proves both access cases and diagnostic

- Production path: `test.sh` assertions and `bin/check-access` public CLI.
- Surface (explicit finite enumeration): `alpha`/`alpha` owned invocation and
  `alpha`/`beta` cross-project invocation in `bash test.sh`.
- Validation action: execute `bash test.sh`.
- Failing observation: owned access is not `allowed`, cross-project access does
  not fail, or the denial diagnostic is not the expected project-naming text.

## Obligations and owning phases

- Implementation: red-green focused execution of `bash test.sh` at the agreed
  public CLI and policy-file seams; perform the bounded coherence pass with the
  focused test unchanged and green.
- Primary checkpoint / initial-gate preparation: after the first commit and a
  clean worktree, execute `bash test.sh` to populate every manifest member with
  direct evidence for the exact committed Candidate identity.
- Initial and later review gates: independently judge the exact candidate,
  frozen contract, manifest, and qualifying raw evidence; execute only the
  narrowest discriminating check when existing evidence is insufficient.
- Closeout: reuse qualifying exact-candidate `bash test.sh` evidence when still
  sufficient; otherwise execute it, then execute `git diff --check`.

All four criteria have available direct seams; there are no blocking
prerequisites; no criterion is knowingly limited to inferred or unverified
evidence; all commands are executable; the trusted contract is consistent; and
every surface above is finite and materialized.
