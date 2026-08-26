trusted-snapshot-sha256 20353d2e76c5acae7a4c8b869ca6f96aa8b865afb0103d6191e058e5db8e94f9
pre-implementation-base a2cc08210864064b6890ff9c1facd8ae369d3430
manifest-binding-sha256 15b2b9f5dd3c2c3a0baf89a5210bbbe176fe97b916488fc128f8f1dab6711ea0
---
# Validation-surface manifest — faviann/dotfiles#73

Trusted snapshot: `20260826T021754Z-b4665c2d.trusted-snapshot.json` (ready issue #73, referenced parent/spec #65, zero trusted comments, zero omitted untrusted comments).

## Frozen acceptance criteria and direct-evidence surfaces

1. **The rendered workstation configuration contains a user service that executes the supported foreground herdr server entrypoint directly.**
   - Production path: `home/workstation.nix`.
   - Validation surface (explicit finite enumeration): `homeConfigurations.workstation.config.systemd.user.services.herdr` for the repository's sole `x86_64-linux` workstation configuration.
   - Direct action: render that public Home Manager configuration boundary and execute the exact focused behavioral case that checks the service and foreground command.
   - Failing observation: the `herdr` service is absent or `Service.ExecStart` is not the absolute supported `herdr server` entrypoint.

2. **The service uses the simple service type, an absolute executable reference, a deterministic working directory, and an explicit process PATH suitable for pane and agent processes.**
   - Production path: `home/workstation.nix`.
   - Validation surface: the same single rendered `systemd.user.services.herdr` instance.
   - Direct action: execute the focused rendered-service contract case over `Type`, `ExecStart`, `WorkingDirectory`, and `Environment`.
   - Failing observation: any required field is absent, indirect, relative, nondeterministic, or the PATH omits the workstation's user/profile and ordinary system command locations.

3. **The service restarts on failure with a bounded retry delay.**
   - Production path: `home/workstation.nix`.
   - Validation surface: the same single rendered `systemd.user.services.herdr` instance.
   - Direct action: execute the focused rendered-service restart-policy case.
   - Failing observation: `Restart` is not `on-failure`, or `RestartSec` is absent/non-positive/unbounded for this configuration contract.

4. **Normal termination is left to herdr's graceful signal handling; no daemon flag, PID file, notification type, or mandatory custom stop command is introduced.**
   - Production path: `home/workstation.nix`.
   - Validation surface: the same single rendered `systemd.user.services.herdr` instance.
   - Direct action: execute the focused rendered-service graceful-termination case over the complete service value.
   - Failing observation: the command has a daemon/PID-file mode, the unit uses a notification type, or defines `ExecStop`/another mandatory custom stop mechanism.

5. **The unit is not enabled in a user target and is not started by applying this ticket.**
   - Production path: `home/workstation.nix`.
   - Validation surface: (a) the single rendered `systemd.user.services.herdr` instance and (b) the single workstation Home Manager activation configuration that installs it.
   - Direct action: execute the focused disabled-staging case, observing the rendered unit's lack of target activation and the absence of any herdr start activation hook.
   - Failing observation: an `Install.WantedBy`/equivalent target enablement exists or activation contains a herdr start action.

6. **Applying the change leaves the existing detached herdr server and active panes untouched.**
   - Production path: `home/workstation.nix`.
   - Validation surface: the same single rendered service plus workstation activation configuration; these are the complete repository-owned apply boundary for this ticket at base `a2cc08210864064b6890ff9c1facd8ae369d3430`.
   - Direct action: execute the focused staging-safety case over the rendered activation/service contract, proving there is no activation, stop, migration, daemon-management, or pane-management action.
   - Failing observation: any repository-owned activation/service action starts, stops, signals, migrates, or otherwise takes ownership of the detached server or its panes.

7. **Rendered behavioral coverage proves both the final unit semantics and its deliberately disabled staging state.**
   - Production paths: `tests/workstation-herdr.bash` (authorized exact new suite) and the `workstationRenderedConfiguration` fixture in `flake.nix`.
   - Validation surface: the one new `workstation-herdr.bash` suite exercised both against live `nix eval` and through the repository's rendered-configuration fixture in `nix flake check`.
   - Direct action: run the exact focused suite, then the sole full closeout command.
   - Failing observation: the suite omits either the full required unit semantics or disabled staging state, cannot exercise live render, or fails under the flake fixture.

8. **The workstation operating documentation explains that activation is deferred to the cutover ticket because server shutdown ends pane processes.**
   - Production path and Validation surface: the single `README.md` “Workstation herdr” operating-contract section.
   - Direct action: inspect the final source artifact and execute the focused documentation-contract case.
   - Failing observation: it does not state both deferred activation/cutover and that server shutdown ends pane processes.

9. **The focused dotfiles suite and nix flake check pass.**
   - Production/validation surface (explicit finite enumeration): `bash scripts/run-tests --suite workstation-herdr.bash`, `nix run .#shellcheck`, and `nix flake check`, all from `/home/faviann/repos/dotfiles/main` against the exact candidate.
   - Direct action: execute the focused suite and shell analysis at the checkpoint/gate ownership below, and `nix flake check` at Closeout.
   - Failing observation: any command exits nonzero.

## Definitely owed obligations and phase ownership

- **Implementation:** red/green execution of one exact new `workstation-herdr.bash` case per vertical slice; any narrow repeated exact cases genuinely needed for development; the bounded coherence pass with focused tests unchanged and green.
- **Primary checkpoint / pre-gate:** complete `bash scripts/run-tests --suite workstation-herdr.bash`; `nix run .#shellcheck` because the change adds Bash behavioral coverage; inspect the exact current Candidate and qualifying raw outputs.
- **Initial/final gate:** Standards, Spec, and closure independently judge the exact stabilized candidate and the complete direct-evidence population; no broader regression command is moved here.
- **Closeout:** `nix flake check` as the sole full closeout command and `git diff --check`; reuse only qualifying evidence whose Candidate and Validation identity remains exact.

## Closability result

All nine criteria have executable direct seams, the only explicit blocker is closed, no criterion is knowingly limited to inferred/unverified evidence, required commands are available, the issue and parent contract are consistent, and every direct-evidence population is materialized above. The gate passes.
