# Cumulative review assignment

Independently review the exact cumulative candidate against the full accepted
review contract.

- Comparison-base identity: commit/tree
  `93f69bc8044172900952ceda6bf5552bfc7968a3`.
- Exact current Candidate identity: clean commit/tree
  `9902f9abd6f057e304e8c1cb780d9f0eb2a0ac7a`.
- Mechanically exact cumulative diff:
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/cumulative-final.diff`,
  SHA-256 `1e2fe112f85a2615f7a7366f90133bff4d84767eef9879cfe4c2abde7c330f4c`.
  Verify byte-for-byte from
  `git diff --no-ext-diff --no-color --no-textconv 93f69bc8044172900952ceda6bf5552bfc7968a3^{tree} 9902f9abd6f057e304e8c1cb780d9f0eb2a0ac7a^{tree}`.
- Full trusted contract: exact frozen snapshot
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.trusted-snapshot.json`.
  Do not refetch comments or discover another spec.
- Binding Standards input: exact frozen combined input
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/standards.md`,
  SHA-256 `5501bc1b61c74487020657237c4aab600fe177dc92e543d9e1ba977447303a71`.
  Do not discover live standards or reconstruct the Fowler baseline.
- Validation-surface manifest: exact immutable file
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.md`.
- Validation-evidence policy: exact file
  `/home/faviann/repos/skills/skills/personal/work-on/references/validation-evidence.md`.
- Qualifying exact-candidate Docker evidence:
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/remediation-3-committed/`.
  Its provenance names unchanged parsed-config and placeholder Compose evidence
  reused from
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/checkpoint-qualifying/`.
  The missing-provider-input observation is ephemeral under pytest's temporary
  directory; its retained JUnit result proves that case and no package claims a
  raw artifact for it.

Same-mechanism neighborhood: after reproducing a defect, name its mechanism and
governing criterion, then trace only immediate same-boundary branches, call
sites, input shapes, diagnostics, or governed states. For a failure-raising
operation, enumerate occurrences in the same public flow and attempt the
seed-shaped input at compatible occurrences through public entry points. Count
distinct branches, call sites, diagnostics, or states only; more inputs at one
site are reproduction evidence. Stop before another criterion, subsystem,
external boundary, or speculative defense. Report reproduced instances only;
the primary adjudicates. The manifest never limits inspection.

Do not read prior reports, implementation history, findings, rationale,
adjudications, dispositions, or the ledger. Do not edit, commit, refetch
comments, or mutate GitHub. Inspect evidence before execution. If narrow
independent execution is necessary, wrap it in telemetry for run
`20260826T103730Z-9b799001@8de8159fe68e446b8c345d38452d4049`, phase `gate`,
round `4`, with a safe command id.
