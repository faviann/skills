# Delta review assignment — issue 96, remediation gate 2

Independently review the exact candidate delta against the full accepted review contract.

- Previous Reviewed-anchor identity: `faviann/dotfiles`, `2850ebc9efc103ef35978c08f440f94ee878c553^{tree}`.
- Exact current Candidate identity: clean committed `faviann/dotfiles`, `7688473133d5b1812a5c5d30bec9652feda582ea^{tree}`.
- Exact delta: `git diff --no-ext-diff --no-textconv 2850ebc9efc103ef35978c08f440f94ee878c553^{tree} 7688473133d5b1812a5c5d30bec9652feda582ea^{tree}`. Reproduce directly; do not resolve live HEAD.
- Full trusted contract and manifest: complete exact frozen files `/home/faviann/repos/dotfiles/.bare/work-on-manifest/20260826T151118Z-34bc65dd.trusted-snapshot.json` and `/home/faviann/repos/dotfiles/.bare/work-on-manifest/20260826T151118Z-34bc65dd.md`. Do not refetch/rediscover.
- Binding Standards: complete exact `/home/faviann/repos/dotfiles/.bare/work-on-review/20260826T151118Z-34bc65dd.standards.md`. Do not rediscover.
- Validation-surface manifest is the exact bound manifest above; it bounds evidence, not review.
- Raw exact-candidate evidence, cwd `/home/faviann/repos/dotfiles/main`:
  1. Telemetry `issue96-invalid-version-phase-red`: exact affected case failed against the pre-correction candidate with the readable-engine/invalid-version fixture, reproducing an early `engine metadata unavailable` failure. Reproduction evidence only.
  2. Telemetry `issue96-invalid-version-phase-green`: exact affected case exit 0, raw stdout `PASS: update-agent-tools --check`, no stderr, with the current behavior restored/corrected.
  3. Additional exact preservation cases for unreadable engines, absent engines, inventory behavior, and post-install registry failure exited 0 as individually recorded implementation validations.
  4. Telemetry `update-agent-tools-suite`: `bash scripts/run-tests --suite update-agent-tools-check.bash`, exit 0, raw stdout `PASS: update-agent-tools --check`, no stderr, exact clean candidate before/after.
  5. Telemetry `shellcheck`: `nix run .#shellcheck`, exit 0, raw stdout names/builds `/nix/store/mn8sygfy5akw4g7in9dxx9milgmq60ay-dotfiles-shellcheck.drv`, no stderr, exact clean candidate before/after.
- Validation evidence policy: evaluate exact identity/provenance/status/raw output; a prior conclusion is not evidence. Reuse adequate evidence; independently execute only for a concrete unresolved question with the narrowest command and record why. Do not repeat costly settled checks or run `nix flake check`, universal dispatch, or `git diff --check`.
- Telemetry wrapper if necessary: `/home/faviann/repos/skills/skills/personal/work-on/scripts/run-telemetry.sh exec --run '20260826T151118Z-34bc65dd@25f9182e37ee4b6fab5fce74b68d653a' --command-id <safe-axis-id> --phase remediation --round 2 -- <command>`.
- Scope: begin at exact correction delta. Inspect unchanged context only for a concrete contract/mechanism/reproduction question or same-mechanism neighborhood. After reproducing a defect trace immediate same-boundary branches/call sites/input shapes and same-source diagnostics; state stop boundary; stop before another criterion/subsystem/external boundary/speculative defense. Report reproduced instances only.
- Blindness: no prior finding/report, remediation rationale, directive, adjudication, disposition, ledger, or convenience summary. Exact frozen inputs, delta, and raw evidence are the whole package.
