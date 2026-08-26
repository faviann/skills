# Delta review assignment

Independently review the exact candidate delta against the full accepted review
contract.

- Previous Reviewed-anchor identity: commit/tree
  `3f77efac330c6a81dea0eae452b37d2855f50f2b`.
- Exact current Candidate identity: clean commit/tree
  `22e55cd94fe125f10606a4c718acd83ba166431b`.
- Mechanically exact direct delta:
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/delta-r2.diff`,
  SHA-256 `2e6dd2dd598edc7f1f9c7ddc7a3736ad7ea02df5fac4bfb819ef8fbeae8278c0`.
  Verify it reproduces byte-for-byte from
  `git diff --no-ext-diff --no-color --no-textconv 3f77efac330c6a81dea0eae452b37d2855f50f2b^{tree} 22e55cd94fe125f10606a4c718acd83ba166431b^{tree}`.
- Full trusted contract: exact frozen snapshot
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.trusted-snapshot.json`.
  Do not refetch comments or discover a replacement spec.
- Binding Standards input: exact frozen combined input
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/standards.md`,
  SHA-256 `5501bc1b61c74487020657237c4aab600fe177dc92e543d9e1ba977447303a71`.
  Do not discover live standards or reconstruct the Fowler baseline.
- Validation-surface manifest: exact immutable file
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.md`.
- Validation-evidence policy: exact file
  `/home/faviann/repos/skills/skills/personal/work-on/references/validation-evidence.md`.
- Qualifying current-candidate raw evidence:
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/remediation-2-committed/`.
  Its provenance names unchanged members reused from
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/checkpoint-qualifying/`.
  The missing-provider-input observation is intentionally ephemeral under
  pytest's temporary directory; its JUnit test result is retained, and neither
  locator claims that raw observation is present.

Review scope: Begin at the exact correction delta. Inspect unchanged context
only for a recorded concrete contract question, changed-mechanism question,
reproduced finding or seed, or the same-mechanism neighborhood investigation
below. Do not routinely reconstruct, repackage, or reread the full cumulative
candidate.

Same-mechanism neighborhood: after reproducing a defect, name its mechanism and
governing criterion, then trace only its immediate neighborhood — the same
boundary's branches, call sites, and input shapes; diagnostics from the same
untrusted source; or states under the same invariant. For a failure-raising
operation, enumerate its occurrences in the same public flow and attempt the
seed-shaped input at each compatible one through its public entry point,
including in-process test entry points. Count a sibling only at a distinct
branch, call site, diagnostic, or governed state; more inputs at the seed
location are reproduction evidence, not siblings. Group the seed with minimally
reproduced siblings, each with its own location, criterion, and impact. State
the stop boundary and stop before another criterion, subsystem, external
boundary, or speculative defense. The manifest never limits inspection.

Do not read prior reports, remediation rationale, findings, adjudications,
dispositions, implementation history, or the adjudication ledger. Do not edit,
commit, refetch comments, or mutate GitHub. Inspect existing raw evidence before
execution. If a narrow independent check is necessary, wrap it with run
telemetry for run
`20260826T103730Z-9b799001@8de8159fe68e446b8c345d38452d4049`, phase
`remediation`, round `2`, and a safe lowercase command id.
