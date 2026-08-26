# Cumulative review assignment

Independently review the exact cumulative candidate against the full accepted
review contract.

- Comparison-base identity: commit/tree
  `93f69bc8044172900952ceda6bf5552bfc7968a3`.
- Exact current Candidate identity: clean commit/tree
  `3f77efac330c6a81dea0eae452b37d2855f50f2b`.
- Mechanically exact cumulative diff:
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/cumulative.diff`,
  SHA-256 `c379bef86d6c3619cc4bddbaa53be1f33a846bbd6108bfd0f91db7925235e29f`.
  Verify it reproduces byte-for-byte from
  `git diff --no-ext-diff --no-color --no-textconv 93f69bc8044172900952ceda6bf5552bfc7968a3^{tree} 3f77efac330c6a81dea0eae452b37d2855f50f2b^{tree}`.
- Full trusted contract: exact frozen snapshot
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.trusted-snapshot.json`.
  GitHub reports no parent contract source. Do not refetch issue comments or
  discover a replacement spec.
- Binding Standards input: exact frozen combined input
  `/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001/standards.md`,
  SHA-256 `5501bc1b61c74487020657237c4aab600fe177dc92e543d9e1ba977447303a71`.
  It contains source-labelled exact contents and the complete Fowler baseline.
  Do not discover live standards or reconstruct the baseline.
- Validation-surface manifest: exact immutable file
  `/home/faviann/repos/homelab-iac/.bare/work-on-manifest/20260826T103730Z-9b799001.md`.
  It bounds direct-evidence population, not authorized review or defect
  reporting.
- Validation-evidence policy: exact file
  `/home/faviann/repos/skills/skills/personal/work-on/references/validation-evidence.md`.
  Read and apply it completely.
- Qualifying raw validation evidence:
  `/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001/checkpoint-qualifying/`.
  It contains JUnit output, the five frozen attempt observations/logs, the
  missing-input observation/log, placeholder-only effective Compose output,
  command/candidate provenance, and the committed-identity proof. Make a fresh
  independent sufficiency judgment; inherit no conclusion.

Review scope and same-mechanism neighborhood: after reproducing a defect, name
its mechanism and governing criterion, then trace only its immediate
neighborhood — the same boundary's branches, call sites, and input shapes;
diagnostics from the same untrusted source; or states under the same invariant.
For a failure-raising operation, enumerate its occurrences in the same public
flow and attempt the seed-shaped input at each compatible one through its public
entry point, including in-process test entry points. Count a sibling only at a
distinct branch, call site, diagnostic, or governed state; more inputs at the
seed location are reproduction evidence, not siblings. Group the seed with
minimally reproduced siblings, each with its own location, criterion, and
impact; report the seed alone when none reproduce. State the stop boundary and
stop before another criterion, subsystem, external boundary, or speculative
defense. Report reproduced instances only; primary adjudicates and repairs. The
manifest never limits inspection or defect reporting.

Do not read or receive prior reviewer conclusions, implementation history,
adjudications, dispositions, or the adjudication ledger. Do not edit, commit,
refetch issue comments, or mutate GitHub. Existing raw evidence should be
inspected before any execution. Execute only the narrowest discriminating check
when independent assurance cannot be settled otherwise; if one is necessary,
wrap it with the run telemetry command for run
`20260826T103730Z-9b799001@8de8159fe68e446b8c345d38452d4049`, phase `gate`,
round `1`, and a safe lowercase command id.
