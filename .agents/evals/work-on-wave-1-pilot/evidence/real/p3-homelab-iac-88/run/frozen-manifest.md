trusted-snapshot-sha256 775d751fe40d6ecf63f30a2ac46a7ffb101e86e0096956c063c924dbd83f3564
pre-implementation-base 93f69bc8044172900952ceda6bf5552bfc7968a3
manifest-binding-sha256 94e6a03b3b3a17bf8019ceacf9054624887798c204908172cbb374d4d704d1d9
---
# Issue 88 Validation-surface manifest

Trusted contract: issue 88 body plus OWNER comment 5270046313. No untrusted
comment was adopted; omitted count: 0. GitHub reports no parent issue and no
blocking dependency. Issue 68 is contextual rollout evidence, not a parent or
specification source, and its OWNER comments explicitly classify issue 88 as a
separate non-blocking bug.

## Scope

- Investigate the unchanged Portal Traefik v3.6/Redis startup contract from the
  pinned incident commit through a controlled, credential-free recreation.
- The authorized production surfaces are the Portal `traefik3` Compose startup
  and readiness contract and its existing Traefik Redis provider configuration.
- The authorized validation surfaces are a disposable Docker-based recreation
  harness, focused repository contract tests, and concise stack-local evidence
  documentation if the pinned behavior does not reproduce.
- If and only if the experiment mechanically reproduces the missing Redis route,
  implement the smallest startup/recovery correction tied to that mechanism.

Non-scope: image/version changes; Traefik KOP/Redis redesign; unrelated Portal
availability work; treating the historical event as proof; production secrets;
or a speculative startup dependency when the mechanism does not reproduce.

## Frozen criteria, seams, and concrete Validation surfaces

### AC1 — Controlled reproduction or credible non-reproduction

Production path: Portal `traefik3` Compose recreation and Traefik's Redis
provider. Public boundary: a disposable Docker network running the repository's
Traefik v3.6 and Redis service contract, with deterministic provider input and
HTTP probes. Action: recreate the pair repeatedly under the incident-shaped
ordering, retain raw per-attempt observations, and inspect Traefik's provider
diagnostics. Failure observation: an attempt is missing the expected remote
route, emits the closed-WatchTree failure, cannot distinguish Redis-backed from
Docker-provider routing, or does not report a bounded outcome.

Validation surface (explicit finite enumeration):

1. Current repository startup contract, Redis available before Traefik provider
   consumption — one controlled attempt.
2. Current repository startup contract, Redis unavailable/recreated while
   Traefik starts — a fixed three-attempt incident-shaped population.
3. Current repository startup contract, Redis provider input established after
   startup — one controlled recovery observation.

The harness may use parameterization internally, but these five attempts are the
complete direct-evidence population for AC1 in this run.

### AC2 — A fix is tied to a reproduced mechanism

Production path: any changed Compose readiness/dependency/recovery statement.
Boundary: the AC1 disposable harness plus the exact candidate diff. Action: if
AC1 reproduces, vary only the demonstrated causal condition and show the seed
failure before the correction and its absence after the correction; if AC1 does
not reproduce, verify that no production startup/recovery change is introduced.
Failure observation: production behavior changes without a reproduced seed and
causal discrimination, or a correction does not remove the reproduced failure.

Validation surface (deterministic conditional enumeration):

1. When any AC1 member reproduces: that first reproducing member, named by the
   lowest numbered AC1 surface entry and then earliest attempt within it.
2. When no AC1 member reproduces: the complete production diff under
   `stacks/portal/traefik3/`, which must contain no speculative startup/recovery
   change.

### AC3 — Reproduced Redis routes recover without manual Traefik restart

Production path: the smallest correction authorized by AC2. Boundary: the same
reproducing disposable public HTTP route, with the Traefik container identity
captured before and after Redis readiness. Action: when AC1 reproduces, exercise
the corrected incident-shaped transition without restarting Traefik. Failure
observation: the Redis-backed route stays absent, becomes available only after a
Traefik restart, or Traefik's container identity changes.

Validation surface (explicit conditional enumeration):

1. The single AC2-selected reproducing member. The population is empty when the
   bounded AC1 experiment records non-reproduction, because the trusted
   criterion is explicitly conditional on reproducibility.

### AC4 — Existing routing and certificate contracts remain valid

Production path: Portal Traefik Compose and static/dynamic configuration.
Boundaries: disposable HTTP probes plus parsed repository Compose/config
contracts. Actions: prove each named route/provider category remains present and
valid, parse the effective Compose model with placeholders, and verify the ACME
resolver/storage and protected middleware declarations. Failure observation:
the named route does not resolve through its provider, protected/public behavior
changes, effective Compose is invalid, or the certificate contract is removed
or malformed.

Validation surface (explicit representative enumeration fixed by the trusted
snapshot's named observations and route categories):

1. Docker-provider local route: `portal-entry` category.
2. Redis-backed protected route: `bazarr` category.
3. Redis-backed public route: `jellyfin` category.
4. Redis-backed public route: `immich` category.
5. Certificate contract: `cloudflare` resolver, TLS domain declaration,
   `/var/traefik/certs/cloudflare-acme.json` mount/storage, and the repository
   `x-managed-files` mode `0600` declaration as one coupled artifact instance.
6. Protected routing contract: `protected-edge-auth@file` chain and its existing
   forward-auth address as one coupled artifact instance.

The route names are representative instances because the trusted issue itself
describes representative route probes; they do not imply every route in the
repository is a direct-evidence member.

### AC5 — Credential-free regression coverage for reproducible behavior

Production path: any mechanically reproduced branch and its correction.
Boundary: the locked automated test entry point added for AC1–AC3. Action: if
AC1 reproduces, execute the regression from a credential-free environment and
show it fails against the uncorrected mechanism and passes against the exact
candidate. Failure observation: reproduced behavior lacks an automated test,
the test needs a credential/live host, or it does not discriminate the defect.

Validation surface (explicit conditional enumeration):

1. The single AC2-selected reproducing member through the committed automated
   regression entry point. The population is empty when AC1 records bounded
   non-reproduction.

### AC6 — Locked focused and repository closeout checks pass

Production path: the entire candidate. Boundaries: locked focused pytest,
effective Compose parsing, the repository's deterministic validation entry
point, and Git whitespace validation. Failure observation: any command exits
nonzero or the focused output does not include the affected contracts.

Validation surface (explicit enumeration):

1. Focused recreation/regression test module created or selected for AC1–AC5.
2. `tests/unit/test_portal_externalservice_config.py` plus any focused Portal
   Traefik Compose/config contract module created by the implementation.
3. Effective `stacks/portal/traefik3/compose.yaml` model with credential
   placeholders and no live inventory or secret reads.
4. Unchanged repository closeout entry point `./validate.sh`.
5. Final candidate `git diff --check`.

## Required commands and phase ownership

- Implementation: locked narrow red/green pytest invocations for the new or
  affected recreation and Portal contract tests. The delegate may run only the
  AC1 cases needed to develop each slice; later complete population remains
  owed.
- Primary checkpoint / pre-gate stabilization: locked focused pytest over the
  complete five-attempt AC1 population and all affected Portal contract tests;
  credential-placeholder `docker compose config --quiet` for the `traefik3`
  stack; rerun only invalidated members after corrections.
- Checkpoint: one independent raw-worktree readiness sweep after focused checks
  are green and before the first commit.
- Initial and remediation gates: independent Standards, Spec, and closure review
  delegations under the review state machine; no full regression is pulled into
  remediation.
- Closeout: `./validate.sh` unless qualifying evidence for the exact final
  Candidate and Validation identity already settles it; then `git diff --check`.

All commands run from the repository root. Python, pytest, and Ansible commands
must run through `uv run --locked`; live-host operations are neither required nor
authorized by this manifest. Docker-based evidence must use only disposable,
uniquely named resources and credential placeholders and must clean them up.
