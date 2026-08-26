trusted-snapshot-sha256 5125992bac2f3b6e3843fe200cdc6a1b2b1c674a08bae04ed92199407ff47f68
pre-implementation-base fe3765b39681bd8705276345abad47d5b7c4a305
manifest-binding-sha256 f447a530b37b998eca92c4e221e1f5981429ae79e0d7d965a5bd8b58c57da60e
---
# Validation-surface manifest — issue 96

Trusted snapshot: `20260826T151118Z-34bc65dd.trusted-snapshot.json` (owner-authored issue body; zero untrusted comments omitted)

Pre-implementation base: `fe3765b39681bd8705276345abad47d5b7c4a305`

## Frozen acceptance criteria and direct-evidence surfaces

### AC1 — one managed npm component inventory

Criterion: `MANAGED_NPM_ENGINE_COMPONENTS` is the single source for runtime-engine checks, install-phase npm package installation, and `check_toolchain`'s managed-package version, stable-version, and component comparisons.

Production path: `dot_local/bin/executable_update-agent-tools` inventory consumers in `check_runtime_engines`, `check_toolchain`, and the install phase.

Public boundary and validation action: execute the updater through the behavioral harness and inspect its boundary-owned npm command log and user-visible component/version output. The observation fails if an inventory member is omitted, duplicated, renamed inconsistently, or bypassed by one consumer.

Validation surface (explicit finite enumeration from the pre-implementation inventory; each member is owed direct evidence in install and version-check modes):

1. `Codex CLI (standalone)|@openai/codex`
2. `Claude Code CLI|@anthropic-ai/claude-code`
3. `Pi agent CLI|@earendil-works/pi-coding-agent`
4. `OpenCode CLI|opencode-ai`
5. `Oh My Pi CLI|@oh-my-pi/pi-coding-agent`
6. `codex-acp adapter|@agentclientprotocol/codex-acp`
7. `claude-agent-acp adapter|@agentclientprotocol/claude-agent-acp`
8. `pi-acp adapter|pi-acp`

### AC2 — drift-closing behavioral coverage

Criterion: a behavioral test asserts that every entry in the managed inventory is installed and version-checked, so removal from the inventory cannot remain invisible.

Production path: the inventory-driven install and `check_toolchain` flows; validation artifact: `tests/update-agent-tools-check.bash` through `scripts/run-tests`.

Public boundary and validation action: execute the exact new case `test_managed_npm_inventory_drives_install_and_version_checks`; it compares the updater's observable npm install/query command log with the inventory-derived eight-member expectation and fails when either consumer drifts.

Validation surface: the same explicit eight component/package members enumerated under AC1, each in both install and version-check observations, plus exact registration of `test_managed_npm_inventory_drives_install_and_version_checks` in `tests/update-agent-tools-check.bash`'s `test_cases` array and `tests/contracts/suite-dispatch.bash`.

### AC3 — one managed-package registry round trip

Criterion: each managed package is queried once with `npm view <package>@latest version engines --json`, replacing separate version and engine requests and preserving current version/engine behavior.

Production path: managed-package discovery in `check_toolchain` and engine consumption in `check_runtime_engines`.

Public boundary and validation action: execute the updater's check path through the behavioral harness; inspect the boundary-owned npm query log for exactly one combined query for each surface member and exercise existing version-result, absent/malformed engine, unreadable-engine, and runtime-floor outcomes. The observation fails on a second managed-package lookup, the old command shape, or changed behavior.

Validation surface (explicit finite enumeration of combined queries):

1. `npm view @openai/codex@latest version engines --json`
2. `npm view @anthropic-ai/claude-code@latest version engines --json`
3. `npm view @earendil-works/pi-coding-agent@latest version engines --json`
4. `npm view opencode-ai@latest version engines --json`
5. `npm view @oh-my-pi/pi-coding-agent@latest version engines --json`
6. `npm view @agentclientprotocol/codex-acp@latest version engines --json`
7. `npm view @agentclientprotocol/claude-agent-acp@latest version engines --json`
8. `npm view pi-acp@latest version engines --json`

The existing nested Codex dependency-range and compatible-version queries are outside this eight-package combined-query surface and remain behaviorally unchanged.

## Owed commands and phase ownership

- Implementation: red-green execution of `bash scripts/run-tests --case test_managed_npm_inventory_drives_install_and_version_checks`, followed by the affected exact cases needed to preserve query parsing, registry failure, runtime-floor, absent-engine, and unreadable-engine behavior.
- Primary checkpoint before the initial gate: `bash scripts/run-tests --suite update-agent-tools-check.bash` supplies the complete direct-evidence population for AC1–AC3 against the stabilized committed candidate; `nix run .#shellcheck` supplies the repository-required focused shell analysis.
- Closeout: `git diff --check`, then the sole full closeout command `nix flake check`; do not run a redundant standalone full behavioral pass immediately beforehand.

All commands are executable in the current repository and environment. GitHub reports no blocking dependencies. No criterion depends on inferred or unavailable evidence, and the trusted contract is internally consistent.
