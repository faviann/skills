# Delta review assignment

Independently review the exact candidate delta against the full accepted review
contract.

- Previous Reviewed-anchor identity: commit/tree
  `22e55cd94fe125f10606a4c718acd83ba166431b`.
- Exact current Candidate identity: clean commit/tree
  `9902f9abd6f057e304e8c1cb780d9f0eb2a0ac7a`.
- Mechanically exact direct delta:
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/delta-r3.diff`,
  SHA-256 `d8a26e37b8fbbbccb8df57d6694f2eb742d342d9fd5c158a711dc66dc27b35e9`.
  Verify byte-for-byte from
  `git diff --no-ext-diff --no-color --no-textconv 22e55cd94fe125f10606a4c718acd83ba166431b^{tree} 9902f9abd6f057e304e8c1cb780d9f0eb2a0ac7a^{tree}`.
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
- Qualifying current-candidate raw evidence:
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/remediation-3-committed/`.
  Its provenance names unchanged parsed-config and Compose evidence reused from
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/checkpoint-qualifying/`.

Review scope: begin at the exact correction delta. Inspect unchanged context
only for a concrete contract question, changed-mechanism question, reproduced
finding/seed, or same-mechanism investigation. Do not reconstruct the cumulative
candidate routinely.

Same-mechanism neighborhood: after reproducing a defect, name its mechanism and
criterion, then trace only its immediate same-boundary branches, call sites,
input shapes, diagnostics, or governed states. For a failure-raising operation,
enumerate its occurrences in the same public flow and try the seed-shaped input
at compatible occurrences through public entry points. Count distinct branches,
call sites, diagnostics, or states only; extra inputs at one site are evidence,
not siblings. Stop before another criterion, subsystem, external boundary, or
speculative defense. The manifest never limits inspection.

Do not read prior reports, rationale, findings, adjudications, dispositions,
implementation history, or the ledger. Do not edit, commit, refetch comments,
or mutate GitHub. Inspect raw evidence before execution. If narrow independent
execution is necessary, wrap it in telemetry for run
`20260826T103730Z-9b799001@8de8159fe68e446b8c345d38452d4049`, phase
`remediation`, round `3`, with a safe command id.
