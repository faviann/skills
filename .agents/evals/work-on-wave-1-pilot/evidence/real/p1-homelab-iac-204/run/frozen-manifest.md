trusted-snapshot-sha256 1e1722fbe01eeb9bd401d00d53a330bc6b88f56be077dd5be9a840e46e57b152
pre-implementation-base 93f69bc8044172900952ceda6bf5552bfc7968a3
manifest-binding-sha256 0770c8e986ac0968e8e49ef4066ac49d5e96dd1cc97a43afcbeef6948524ff3f
---
# Validation-surface manifest — issue 204

Selected workflow: `/home/faviann/repos/skills/skills/personal/work-on/references/default-workflow.md`

Pre-implementation base: `93f69bc8044172900952ceda6bf5552bfc7968a3`

Trusted snapshot: `20260826T010651Z-ab241455.trusted-snapshot.json`

## Frozen acceptance surfaces

1. **A fixture inventory and fixture passphrase live inside the test tree.**
   - Production path: `tests/fixtures/ansible/inventory.yml` and `tests/fixtures/ansible/vault-pass`.
   - Direct seam: tracked-file inspection from the repository root.
   - Failing observation: either exact file is absent, outside `tests/`, or not readable as the fixture artifact expected by `validate.sh`.
   - Validation surface: the two exact paths above.

2. **The fixture inventory carries no host addresses and no SSH settings.**
   - Production path: `tests/fixtures/ansible/inventory.yml`.
   - Direct seam: parse the exact YAML artifact and inspect its concrete host definitions.
   - Failing observation: any of the three frozen hosts (`auth`, `portal`, `workstation`) has a host address, SSH connection setting, or SSH credential setting.
   - Validation surface: the `auth`, `portal`, and `workstation` host entries in that exact file.

3. **`./validate.sh` exports both once for its whole run, and everything beneath inherits them.**
   - Production paths: `validate.sh` and `tests/regression/run_lxc_lifecycle_regressions.py`.
   - Direct seam: execute the real `validate.sh` with the existing stubbed-`uv` public command test and observe the environment of all three top-level child command slots; invoke the registered lifecycle runner through its public `main` entry with a launcher callback and observe the inherited values at that boundary.
   - Failing observation: `ANSIBLE_INVENTORY` or `ANSIBLE_VAULT_PASSWORD_FILE` is missing, differs from the two frozen fixture paths, differs between any top-level child, or is replaced before a registered launcher is invoked.
   - Validation surface: the `ansible-lint`, full lifecycle-runner, and `pytest` child command slots of `validate.sh`, plus one registered-launcher callback invocation through `run_lxc_lifecycle_regressions.main`.

4. **`./validate.sh` completes on a machine with no vault passphrase file present.**
   - Production path: `validate.sh` and the complete validation suite it launches.
   - Direct seam: run the exact real `./validate.sh` command with `HOME` set to a fresh empty directory containing no `.ansible/vault-pass`.
   - Failing observation: the command loads the machine-local vault path or exits nonzero.
   - Validation surface: one complete no-argument `./validate.sh` run from the repository root under that empty-home mode.

5. **A shared test helper exists that constructs the locked playbook invocation and asserts the fixture environment is in effect.**
   - Production path: `tests/regression/ansible_test_helper.py`.
   - Direct seam: import the helper and call its public playbook-command constructor with the exact fixture environment.
   - Failing observation: it does not return the locked `uv run --locked ansible-playbook` argv prefix or does not reject a missing/mismatched fixture environment.
   - Validation surface: the helper constructor's default fixture-inheriting mode.

6. **When the assertion fails, the message names `./validate.sh tests` as the supported path.**
   - Production path: `tests/regression/ansible_test_helper.py`.
   - Direct seam: call the helper with each required fixture variable absent or mismatched and inspect the raised diagnostic.
   - Failing observation: any failure diagnostic omits the exact text `./validate.sh tests`.
   - Validation surface: absent and mismatched states for `ANSIBLE_INVENTORY` and `ANSIBLE_VAULT_PASSWORD_FILE` at the helper constructor boundary.

7. **The helper accepts an explicit declaration for tests that supply their own inventory.**
   - Production path: `tests/regression/ansible_test_helper.py`.
   - Direct seam: call the same helper constructor with its explicit own-inventory declaration while the shared inventory variable is absent, retaining the vault-fixture guard.
   - Failing observation: the declared mode is unavailable, silently inferred, or still requires the shared inventory path.
   - Validation surface: the helper constructor's single explicit own-inventory mode.

8. **An ADR records enforcing the non-live boundary in the validation command, its rejected alternatives, and its recorded boundaries.**
   - Production path: `docs/adr/0008-enforce-non-live-validation-boundary.md`.
   - Direct seam: inspect the exact tracked ADR artifact against the trusted issue and parent decision text.
   - Failing observation: the decision is missing, does not place enforcement at `validate.sh`, omits the rejected per-fixture and offline alternatives, or omits the no-managed-host/no-vault-secret/no-machine-specific-credential and public-network boundaries.
   - Validation surface: the complete exact ADR file above.

9. **`./validate.sh` passes.**
   - Production path: the complete committed candidate.
   - Direct seam: execute the exact real no-argument `./validate.sh` from the repository root.
   - Failing observation: nonzero exit status.
   - Validation surface: one complete no-argument `./validate.sh` run for the exact final candidate; the empty-home execution for criterion 4 may supply the same qualifying raw execution when identities match.

## Owed validation and phase ownership

- **Implementation:** red-green focused checks for `tests/regression/test_validate_command.py`, `tests/unit/test_lxc_lifecycle_regression_runner.py`, and the helper's focused test module; narrow YAML/static inspection for the fixture inventory; keep raw output as candidate-bound evidence.
- **Primary checkpoint / initial-gate path:** rerun only invalidated focused checks after readiness corrections and populate direct evidence for every frozen member not already settled by qualifying exact-candidate evidence.
- **Gate:** fresh Standards, Spec, and cumulative closure judgments consume the complete frozen surface and qualifying raw evidence; they do not execute a full regression merely because the gate began.
- **Remediation:** only focused checks and frozen members invalidated by an accepted corrective batch; no full regression.
- **Closeout:** run the complete no-argument `./validate.sh` under a fresh empty `HOME` with no machine-local vault passphrase, satisfying criteria 4 and 9 when green; run `git diff --check`. Reuse that exact qualifying full-run evidence rather than executing `./validate.sh` twice.

The repository-required full handoff command is owned by Closeout. It is not an implementation-completion prerequisite and must not be pre-produced for reuse.
