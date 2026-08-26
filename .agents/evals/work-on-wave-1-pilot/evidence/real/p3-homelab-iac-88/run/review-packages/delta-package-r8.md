# Delta review assignment

Independently review the exact candidate delta against the full accepted review
contract.

- Previous Reviewed-anchor identity: commit/tree
  `96211292429198cf0d048472011e9d41fa9067c2`.
- Exact current Candidate identity: clean commit/tree
  `d9bc7e59aede459812880772f7dcb94d002aa403`.
- Mechanically exact direct delta:
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/delta-r8.diff`,
  SHA-256 `780e6efd52e1b5a5d3c653c239ff7f4ca414e6ba2d99af9ac09d1ae59ceca1ae`.
  Verify byte-for-byte from
  `git diff --no-ext-diff --no-color --no-textconv 96211292429198cf0d048472011e9d41fa9067c2^{tree} d9bc7e59aede459812880772f7dcb94d002aa403^{tree}`.
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
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/remediation-8-committed/`.
  It contains raw JUnit output for all 15 focused tests; the complete five-member
  population; per-arm effective Compose configurations, update/recreation and
  cleanup logs, Traefik logs, observations, owner-only overrides; a placeholder
  effective stack render; and exact-candidate provenance. Attempts 02–04 use
  the tracked stack-wide Compose update path. The candidate changes Redis
  identity, waits for PONG, automatically advances the Traefik process StartedAt
  while preserving its container identity, and returns the Docker plus three
  Redis routes as 200. Attempt 04 also retains an evidence-only uncorrected
  control whose Traefik process does not restart, emits WatchTree, and leaves
  Jellyfin/Immich at 404.
- Approved raw reproduced seed under the unchanged pre-fix production contract:
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/remediation-7-committed/04-redis-recreated-during-start-3/`.
  It records distinct Redis identities, unchanged Traefik identity, WatchTree,
  Docker/Bazarr/Jellyfin 200, and Immich 404 after the 30-second bound.

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
`remediation`, round `8`, with a safe command id.
