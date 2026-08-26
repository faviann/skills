# Delta review assignment

Independently review the exact candidate delta against the full accepted review
contract.

- Previous Reviewed-anchor identity: commit/tree
  `96211292429198cf0d048472011e9d41fa9067c2`.
- Exact current Candidate identity: clean commit/tree
  `c9bdca70591de3dcd7b22c33cd3565b2e3563aeb`.
- Mechanically exact direct delta:
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/delta-r5.diff`,
  SHA-256 `73a3b06d48d51890ddf7ed573e7555e6a984d8d5a798f2595747135ca4d6e9c0`.
  Verify byte-for-byte from
  `git diff --no-ext-diff --no-color --no-textconv 96211292429198cf0d048472011e9d41fa9067c2^{tree} c9bdca70591de3dcd7b22c33cd3565b2e3563aeb^{tree}`.
- Full trusted contract: exact frozen snapshot
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.trusted-snapshot.json`.
  Do not refetch comments or discover another spec.
- Binding Standards input: exact frozen combined input
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/standards.md`,
  SHA-256 `5501bc1b61c74487020657237c4aab600fe177dc92e543d9e1ba977447303a71`.
- Validation-surface manifest: exact immutable file
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.md`.
- Validation-evidence policy: exact file
  `/home/faviann/repos/skills/skills/personal/work-on/references/validation-evidence.md`.
- Qualifying exact-candidate evidence:
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/remediation-5-committed/`.
  It contains raw JUnit output for all 16 focused tests; five raw route-attempt
  observations and logs; the effective Compose render; a real tracked-Compose
  startup observation, state, logs and cleanup log; and exact-candidate
  provenance. The recreation attempts record Traefik stopped before each Redis
  replacement, a changed Redis identity, unchanged Traefik identity, and all
  representative routes returning 200.

Review scope: begin at the exact correction delta. Inspect unchanged context
only for a concrete contract or changed-mechanism question, a reproduced seed,
or same-mechanism neighborhood investigation. Do not routinely reconstruct the
cumulative candidate.

Same-mechanism neighborhood: after reproducing a defect, name its mechanism and
criterion, then trace immediate same-boundary branches, call sites, input shapes,
diagnostics, or governed states. For failure-raising operations, enumerate same-
flow occurrences and try seed-shaped input through compatible public entry
points. Count distinct branches/call sites/diagnostics/states only. Stop before
another criterion, subsystem, external boundary, or speculative defense. The
manifest never limits inspection.

Do not read prior reports, implementation history, rationale, findings,
adjudications, dispositions, or the ledger. Do not edit, commit, refetch
comments, or mutate GitHub. Inspect evidence before execution. If narrow
independent execution is necessary, wrap it in telemetry for run
`20260826T103730Z-9b799001@8de8159fe68e446b8c345d38452d4049`, phase
`remediation`, round `5`, with a safe command id.
