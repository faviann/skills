# Cumulative review assignment — issue 96, final fresh confirmation

Independently review the exact cumulative candidate against the full accepted review contract.

- Comparison base: `faviann/dotfiles`, `fe3765b39681bd8705276345abad47d5b7c4a305^{tree}`.
- Exact current Candidate: clean committed `faviann/dotfiles`, `7688473133d5b1812a5c5d30bec9652feda582ea^{tree}`.
- Exact cumulative diff: `git diff --no-ext-diff --no-textconv fe3765b39681bd8705276345abad47d5b7c4a305^{tree} 7688473133d5b1812a5c5d30bec9652feda582ea^{tree}`. Reproduce directly; do not resolve live HEAD.
- Full trusted contract/manifest: read complete exact `/home/faviann/repos/dotfiles/.bare/work-on-manifest/20260826T151118Z-34bc65dd.trusted-snapshot.json` and `/home/faviann/repos/dotfiles/.bare/work-on-manifest/20260826T151118Z-34bc65dd.md`. Do not refetch/rediscover.
- Binding Standards: read complete exact `/home/faviann/repos/dotfiles/.bare/work-on-review/20260826T151118Z-34bc65dd.standards.md`. Do not rediscover.
- Validation surface is the exact bound manifest; it bounds direct evidence, not review.
- Raw exact-candidate evidence, cwd `/home/faviann/repos/dotfiles/main`:
  1. Telemetry exact inventory case green: `bash scripts/run-tests --case test_managed_npm_inventory_drives_install_and_version_checks`, exit 0, raw stdout `PASS: update-agent-tools --check`, no stderr; mutation reproduction separately failed when the managed stable-version consumer was bypassed.
  2. Telemetry invalid-version phase green: exact affected case exit 0, raw stdout `PASS: update-agent-tools --check`, no stderr; pre-correction reproduction separately showed the early wrong phase/diagnosis.
  3. Telemetry `update-agent-tools-suite`: `bash scripts/run-tests --suite update-agent-tools-check.bash`, exit 0, raw stdout `PASS: update-agent-tools --check`, no stderr, exact clean candidate before/after. It covers all frozen eight-member query/install/output surfaces and preservation cases.
  4. Telemetry `shellcheck`: `nix run .#shellcheck`, exit 0, raw stdout names/builds `/nix/store/mn8sygfy5akw4g7in9dxx9milgmq60ay-dotfiles-shellcheck.drv`, no stderr, exact clean candidate before/after.
  5. Telemetry `universal-suite-dispatch`, exact current Candidate: `bash tests/contracts/suite-dispatch.bash`, exit 1. Raw output is solely a `diff -u` for later ordered suite `workstation-update.bash`, adding actual cases `test_failed_workstation_configuration_without_marker_is_retried` and `test_failed_workstation_configuration_is_retried_before_completion`, then `FAIL: workstation-update.bash --list did not expose its complete case set`. Inspect the exact ordered contract and independently determine its bearing; inherit no disposition.
- Validation-evidence policy: judge exact Candidate/Validation/environment identity, provenance, status, raw output. A failure is never erased by rerun; independently adjudicate bearing. Reuse adequate evidence, execute only the narrowest command for a concrete unresolved question, and do not repeat costly settled checks. Do not run `nix flake check` or `git diff --check` before Closeout.
- Necessary validation telemetry: `/home/faviann/repos/skills/skills/personal/work-on/scripts/run-telemetry.sh exec --run '20260826T151118Z-34bc65dd@25f9182e37ee4b6fab5fce74b68d653a' --command-id <safe-axis-id> --phase gate --round 3 -- <command>`.
- Full cumulative/same-mechanism scope: inspect complete subject. After reproducing a defect trace only immediate same-boundary branches/call sites/input shapes, same-source diagnostics, or states under same invariant; count distinct siblings; state stop boundary; stop before another criterion/subsystem/external boundary/speculative defense. Report reproduced instances only.
- Blindness: do not consult prior reviewer conclusions/findings, remediation rationale, adjudication, dispositions, or ledger. Exact frozen inputs, cumulative artifacts, and raw evidence are the whole package.
