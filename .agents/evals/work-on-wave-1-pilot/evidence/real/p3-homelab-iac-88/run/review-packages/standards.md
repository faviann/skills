# Frozen Standards input — issue 88

Comparison base: `93f69bc8044172900952ceda6bf5552bfc7968a3`

Applicable repository standards sources are the exact source-labelled contents below. `pyproject.toml` is tooling configuration, so tooling-enforced matters are excluded under the baseline rule. General README files and `CONTEXT.md` are not code-writing standards for this Python/Portal test change.

===== SOURCE: AGENTS.md @ 93f69bc8044172900952ceda6bf5552bfc7968a3 =====
# Agent Operating Instructions

**Project Type**: Ansible infrastructure-as-code (IaC)  
**Purpose**: Automate Proxmox LXC provisioning, configuration, and service deployments  
**Architecture**: Portable workstation-based (runs from any Linux workstation with network access to Proxmox)

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (faviann/homelab-iac) via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use their default label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root (created lazily by `/domain-modeling`). See `docs/agents/domain.md`.

## Project Philosophy

**Code is a liability, not an asset.** When two approaches exist, recommend the one with less code and fewer objects.

## Non-negotiables
- Never request, paste, or print secrets (API token secret, vault passphrase, private keys). Use placeholders like `<REPLACE_ME>` in docs or examples.
- Run Python and Ansible tools through `uv run --locked <tool>`. If `.venv/` does not exist, run `uv sync --locked`.
- `ansible.cfg` expects the vault passphrase at `~/.ansible/vault-pass`.
- Lifecycle playbooks skip any host whose `inventory_hostname` matches the controller's hostname (`proxmox_skip_self: true` by default). To manage the control node intentionally: `./run.sh -e proxmox_skip_self=false --limit workstation` (`--limit` targets the host, `-e` disables the guard).

## Standard Paths

| Item | Location |
|------|----------|
| SSH key (private) | `~/.ansible/ssh/proxmox_lxc` (home-dir, machine-local, shared across worktrees) |
| SSH key (public) | `~/.ansible/ssh/proxmox_lxc.pub` (home-dir, machine-local, shared across worktrees) |
| Vault password | `~/.ansible/vault-pass` (home-dir, written by chezmoi from Bitwarden) |
| Vaulted secrets | `inventory/group_vars/all/vault.yml` (encrypted) |
| Fact cache | `.ansible/cache/` (project-relative, gitignored, 1h TTL) |
| Venv | `.venv/` (project-relative, gitignored) |
| External roles | `.ansible/roles/` (project-relative, gitignored, auto-installed) |

Secrets are only in encrypted `inventory/group_vars/all/vault.yml` — never commit plaintext credentials. The vault password file is machine-local and should be provisioned outside this repo.

## Inventory Structure

| Type | Groups | Purpose |
|------|--------|---------|
| **Tiers** | `tier_tiny`, `tier_small`, `tier_medium`, `tier_large` | Resource allocation (mutually exclusive) |
| **Capabilities** | `cap_docker`, `cap_gpu`, `cap_wireguard` | Sets feature flags: `docker_enabled`, `gpu_enabled`, etc. |
| **Special** | `proxmox_api`, `lxcs` | API controller + all LXC targets |

**Naming**: LXCs resolve as `{{ inventory_hostname }}.faviann.vms`

**Feature Flags**: Capability groups set boolean flags (`docker_enabled: true`) instead of checking group membership. Roles use `when: docker_enabled | default(false)`, never `'cap_docker' in group_names`.

→ [docs/inventory-structure-guide.md](docs/inventory-structure-guide.md) — read for variable precedence order, worked examples, and adding new hosts.

## Deployment Lifecycle

`site.yml` runs three phases in sequence: **validate** → **provision** (LXC create/update via Proxmox API) → **configure** (in-container: packages, Docker, stacks). Two-tier host config: `proxmox_lxc_provision` handles API-allowed settings; `proxmox_lxc_host_config` handles restricted features (`keyctl=1`, `nesting=1`) via `pct` on the Proxmox host.

Run lifecycle operations through `./run.sh`. It serializes lifecycle mutation with one machine-local lock shared by every worktree on the workstation; it does not coordinate runs from different control nodes.

Roles live in `playbooks/roles/{base,infrastructure,provisioning,config}/`.

## Docker Stacks

Stacks live in `stacks/<hostname>/<stack-name>/compose.yaml`. Auto-discovered and started with `docker compose up -d` — no registration needed.

→ [stacks/README.md](stacks/README.md) — read for stack contract, Traefik routing, secrets, and full conventions.

## Command Reference

| Command | Purpose |
|---------|---------|
| `./validate.sh` | Complete non-live verification — lint, full lifecycle regressions, and full pytest suite |
| `./run.sh` | Full lifecycle — deploy/update all LXCs |
| `./run.sh -e proxmox_skip_self=false --limit workstation` | Intentionally include the control node when running from `workstation` |
| `./run.sh --limit <host>` | Target one host |
| `./run.sh --limit <host> -e stack_filter=<stack>` | Deploy one stack on a host (skips all others) |
| `./run.sh --check` | Dry run |
| `uv run --locked ansible-playbook bootstrap.yml` | Recreate bootstrap artifacts after clean install |
| `uv run --locked python tests/regression/run_lxc_lifecycle_regressions.py` | Fast lifecycle feedback (~1.5 min) — semantic lifecycle facade matrix + targeted planning barrier, controlled observations only. Run while iterating on LXC lifecycle changes |
| `uv run --locked python tests/regression/run_lxc_lifecycle_regressions.py --only <launcher.py>` | Target one registered lifecycle launcher in the same credential-free fixture environment. Repeat `--only` to run several launchers in the supplied order |
| `uv run --locked python tests/regression/run_lxc_lifecycle_regressions.py --full --fail-fast` | Remediation pass — finish the concurrent fast launchers, then stop scheduling after the first observed failure |
| `uv run --locked python tests/regression/run_lxc_lifecycle_regressions.py --full` | Full lifecycle regression set (~6 min) — fast path plus host-config idempotence, real role-composition wiring, fleet preflight, and contract seams. Prefer `./validate.sh` for handoff verification |
| `uv run --locked ansible-lint` | Targeted repo-wide lint feedback (production profile). Prefer `./validate.sh` for handoff verification |
| `./setup.sh` | Fresh workstation setup — extend here for new workstation config (editor, tooling, env) |
| `ssh -l root -i ~/.ansible/ssh/proxmox_lxc <host>` | Direct SSH into an LXC |

**Timing**: `uv run --locked ansible-playbook` runs against live hosts typically take 5–10 minutes. Do not assume a hang — wait for completion before acting on the result.

For lifecycle-regression remediation, use repeatable `--only <launcher.py>` for the shortest targeted loop and add `--fail-fast` when later selected launchers cannot provide useful evidence after a failure. `--only` accepts the registered filenames reported by the runner's actionable error. Before handoff, always run the unchanged aggregate completion command with `--full` and without `--fail-fast` so every launcher reports a result.

Run `./validate.sh` for complete deterministic handoff verification. It does not load live inventory or acquire the lifecycle lock. Route every operation that contacts managed hosts, including `--check`, through `./run.sh`.

**Long-running output discipline**: For live deploys or other noisy commands, avoid streaming full output into chat context. Prefer redirecting to a temp log and polling only high-signal excerpts:
```bash
./run.sh --limit <host> > /tmp/<task>.log 2>&1
tail -40 /tmp/<task>.log
rg "failed=|unreachable=|FAILED|changed=|<relevant-resource>" /tmp/<task>.log
```
Only read the full log when the summarized output is insufficient to diagnose a failure. Never print secrets from logs or vault output.

Debug: `./run.sh -vvv` for verbose output, `uv run --locked ansible-inventory -i inventory/hosts.yml --host <name> --yaml` for merged vars, `uv run --locked ansible -i inventory/hosts.yml lxcs -m ping` for connectivity, delete `.ansible/cache/` for stale facts.

## Role Design Principles

- One role = one concern; use `meta/main.yml` for dependencies
- Use feature flags (`docker_enabled`) not group checks (`'cap_docker' in group_names`)
- Avoid hardcoded values; inject via vars. Ensure idempotency; use `assert` to fail fast

## Related Documentation

→ [docs/inventory-structure-guide.md](docs/inventory-structure-guide.md) — read when adding hosts or debugging variable precedence.
→ [stacks/README.md](stacks/README.md) — read when creating or modifying Docker stacks.
→ [setup.sh](setup.sh) — read when addressing workstation tooling, editor config, or environment setup for contributors.
→ [docs/workstation-persistent-state.md](docs/workstation-persistent-state.md) — read before any workstation deploy that enables persistent home mounts.
===== END SOURCE: AGENTS.md =====

===== SOURCE: CLAUDE.md @ 93f69bc8044172900952ceda6bf5552bfc7968a3 =====
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Commit Conventions

Never add `Co-Authored-By` trailers to commits in this repository.

## Explanation Style

Favor plain-cause explanations: name the behavior, say when it works, say when it breaks, then state the safer rule.
===== END SOURCE: CLAUDE.md =====

===== SOURCE: stacks/README.md @ 93f69bc8044172900952ceda6bf5552bfc7968a3 =====
# Per-Host Docker Compose Stacks

This directory defines repo-managed Docker Compose stacks, grouped by `inventory_hostname`. The role deploys `stacks/<host>/` to `/conf/docker/stacks/` inside the target container and starts every discovered `compose.yml` / `compose.yaml`.

## Portability Model

Stack portability is explicit. A stack being under `stacks/<host>/<stack>/` does not mean every input belongs inside the stack folder.

| Tier | Meaning | Examples | Change Style |
| --- | --- | --- | --- |
| Portable app stack | Normal application stack that can carry its Compose files, non-secret `.env.j2`, repo-only `README.md`, and non-secret `stack.yaml` beside the stack. | `stacks/servarr/notifiarr`, `stacks/servarr/kapowarr` | Small stack-local changes are allowed after stack sync deploy exclusions are in place. |
| Host-bound app stack | App stack whose runtime depends on host-local storage, GPU, VPN, external networks, or ownership mechanics. It can still have stack-local docs/metadata, but host mechanics stay in inventory. | `stacks/jellyfin/jellyfin`, `stacks/seedbox/bittorrent` | Keep host dependencies documented in stack metadata; keep deployment mechanics in host vars. |
| Foundational controlled migration | Cross-host or platform stack that other stacks depend on, or that has scripts with hardcoded repo paths. | `stacks/auth/auth`, `stacks/portal/traefik3`, `stacks/portal/dockhand`, `stacks/public/romm` OIDC coupling | Treat as a controlled migration with a dedicated plan. Do not use these as the first metadata/portability pilot. |

Foundational stacks are intentionally less portable. Authentik/OIDC has cross-host coupling, `scripts/authentik_blueprint_sync.py` depends on the current auth stack paths, and `portal_instance` controls portal discovery, Traefik KOP behavior, Hawser inclusion, and Dockhand seeding.

Accepted normalization exceptions are indexed in [ADR-006](../docs/decisions/adr-006-stack-normalization-exceptions.md). Stack-local details live in each stack README.

This directory is only for repo-managed stacks that Ansible deploys and reconciles.

## Stack Contract

```text
stacks/
  <inventory_hostname>/
    <stack_name>/
      compose.yaml
      compose.override.yaml   # optional: vendor-preserving overrides
      .env | .env.j2
      appdata/
```

### Ownership Rules

Stack-owned files:

- `compose.yaml`, `compose.yml`, and optional `compose.override.yaml`
- `.env.j2` when values are rendered from inventory/vault variables
- committed app config under `appdata/`
- stack-local `README.md` and files under `docs/`
- non-secret `stack.yaml` metadata
- Compose extension blocks such as `x-prereq-dirs` and `x-managed-files`

Host/inventory-owned settings:

- `default_domain`
- `lxc_docker_env_stack_vars`
- `proxmox_lxc_overrides`
- `lxc_hwaddr`
- tier and capability group membership
- LXC CPU, RAM, disk, mount, and resource settings
- `lxc_docker_env_external_networks`
- `lxc_docker_env_host_directories`
- `lxc_docker_env_path_ownership_overrides`
- vault-backed secret bindings in `inventory/host_vars/*.yml`
- `portal_instance`, `traefik_kop_enabled`, Hawser, and Dockhand host orchestration

Do not dynamically include stack-local variable files into Ansible host scope. Stack metadata is non-secret role data; templates still render from normal Ansible inventory, group, host, and vault variables plus the injected `stack_name`.

- Host folder must match `inventory_hostname`.
- Stack folder name becomes the Compose project name. During `.j2` rendering, the role also injects `stack_name`.
- `.j2` files are rendered with inventory, host, group, vault variables, `stack_name`, and the current stack `stack_vars` task-scoped render data, then deployed without the `.j2` suffix.
- Other files are copied verbatim.
- Stack-local `README.md`, `docs/**`, `stack.yaml`, `stack.yml`, and `metadata.*` files are repo-only and are excluded from deployment.
- Do not use stack-local metadata for secrets or runtime variable injection.
- Compose-relative persistent data should live under `./appdata/...`.
- All bind-mount target directories must exist before first deploy. If they do not, Docker creates them as root on first start, causing permission errors for non-root container processes. Declare dirs that need pre-creation in an `x-prereq-dirs` block in the repo-managed compose definition for the stack; the Ansible role creates each missing directory on the LXC with Docker user ownership and mode `0755`. This is create-if-absent behavior: once a declared directory exists, `x-prereq-dirs` does not change its mode, owner, or group. Use `compose.yaml` by default. If the stack intentionally preserves an upstream vendor `compose.yaml`, place `x-prereq-dirs` in `compose.override.yaml` instead. This applies to empty `./appdata/` dirs, `/ephemeral/<stack>/` paths, and new `/data/` subpaths.
- Files that must exist before container start with a specific mode can be declared in `x-managed-files`. Relative `./` paths are resolved from the deployed stack directory. Repository-synced files are rendered or copied directly with the declaration's mode; other declared files are created empty when absent without truncating existing content. This is intended for generated state files such as Traefik ACME storage that must exist with restricted permissions.
- Dirs that contain committed files do not need an `x-prereq-dirs` entry; Ansible creates them automatically when deploying the files.
- Do not use `.gitkeep`.
- If both `.env` and `.env.j2` exist for the same output path, the templated output wins.
- Hosts with no folder here are valid; they just get no repo-managed stacks.

| Path Type | Purpose | Example | Notes |
| --- | --- | --- | --- |
| `./appdata/...` | Persistent container config or state | `./appdata/jellyfin/config` | Use `x-prereq-dirs` only when the dir is otherwise empty |
| `/ephemeral/...` | Regenerable data on fast local storage | `/ephemeral/romm/resources` | Declare in `x-prereq-dirs` if the stack needs it created |
| `/data/...` | Shared external pool | `/data/media` | Only declare new subpaths in `x-prereq-dirs`; leave pre-existing paths alone |

## Stack Metadata

Portable and host-bound app stacks may include `stack.yaml` for non-secret metadata:

```yaml
schema_version: 1
kind: stack
name: notifiarr
description: Notification and automation companion
portability:
  tier: portable-app
  owner: stack
runtime:
  template_inputs:
    - docker_uid
    - docker_gid
    - default_domain
    - stack_name
  host_requirements:
    external_networks:
      - shared
    host_directories: []
    ownership_overrides: []
exposure:
  traefik: protected
  homepage_instances:
    - admin
updates:
  mode: images
  track: stable
  services:
    database:
      track: "16"
```

Rules:

- `stack.yaml` is not copied to `/conf/docker/stacks`.
- During deployment, stack sync parses `stack.yaml` only as
  `lxc_stack_sync_manifest_plan.stack_metadata`; repository policy validation
  independently reads it to validate and normalize the stack update policy.
- `stack.yaml` must not contain secrets, vault references, API tokens, passwords, private keys, or credentials.
- Neither use loads `stack.yaml` into Ansible variable scope: it does not define
  Ansible variables or override host vars.
- Host requirements listed in metadata are documentation until a future explicit aggregation design exists.

### Image Update Policy

An image-tracked stack declares `updates.mode: images`. Its optional stack-level `track` is the default image update track. `updates.services.<compose-service>.track` supplies an exception or complete per-service coverage when there is no shared default. Service keys always name services from effective Compose after the supported `compose.override.yaml` or `compose.override.yml` has been applied. Every effective image-bearing service must have an intentional effective image update track; a service without an image cannot be selected.

An update procedure is stack-wide and assisted only:

```yaml
updates:
  mode: images
  track: stable
  procedure:
    mode: assisted
    runbook: docs/upgrade.md
```

The runbook path is relative to the stack directory and must resolve to a repository file. Per-service assistance and permanent service exclusions are unsupported. A missing `stack.yaml`, missing `updates`, unknown service, missing image update track, or secret-shaped metadata is a strict validation failure.

### Vendor Update Policy

A vendor-tracked stack preserves an official upstream Compose file byte for byte
as `compose.yaml`, with its local behavior isolated in the optional
`compose.override.yaml` layer:

```yaml
updates:
  mode: vendor
  track: stable
  upstream:
    repository: https://github.com/goauthentik/authentik
    compose_path: docker-compose.yml
  services:
    independently-released-helper:
      track: stable
```

`updates.upstream.repository` must be one canonical
`https://github.com/<owner>/<repository>` URL,
`updates.upstream.compose_path` must stay relative to that repository, and
`updates.track` selects the maintained vendor line. The validator resolves that track to a commit and
requires the configured path at that commit to exactly match `compose.yaml`.
Unlisted services move with the vendor baseline; only independently tracked
images belong in `updates.services`. Vendor bases named `compose.yml`, local
overrides named `compose.override.yml`, direct edits to the vendor base, and
layouts requiring assisted restructuring fail strict validation. Such a stack
should use image mode until its upstream base and local override can follow the
vendor contract.

Validate exactly one repo-managed stack without changing repository or deployed state:

```bash
uv run --locked python -B -m stack_update_policy validate \
  --repository-root . stacks/<host>/<stack>
```

The command writes schema-versioned JSON to standard output, diagnostics to standard error, and exits nonzero for an invalid contract. Its normalized result is the shared validation model for later planning and Create Stack integration. It exposes the effective image-bearing services and image tracks, vendor authority and resolved baseline when applicable, vendor track, assisted procedure, explicit low-confidence policy, and foundational controlled-migration status. Consumers should not reparse raw metadata or infer service risk from image names.

### Repository Input Snapshot API

`build_repository_snapshot` is the canonical read-only Python API for creating a repository input snapshot for caller-selected repo-managed stacks:

```python
from pathlib import Path

from stack_update_policy import build_repository_snapshot

build = build_repository_snapshot(
    Path.cwd(),
    ["stacks/servarr/notifiarr"],
)
```

The API infers the GitHub `owner/repository` identity only from `origin`, reads GitHub for the current default branch and its commit, and rejects the snapshot unless local `HEAD` is exactly that commit. It does not require a clean worktree. For each selected stack it fingerprints the checked-in `stack.yaml`, checked-in supported Compose base and override names, and any repository-local assisted runbook named by the checked-in policy. Locally added or deleted supported Compose names are also relevant. A changed relevant input marks only that stack incomplete; unrelated changes do not affect completeness or fingerprints.

The result is immutable and exposes `as_dict()` for stable schema-versioned consumption. It does not select stacks, validate policy, inspect containers or deployments, invoke Renovate, write GitHub state, or modify the repository. Tests replace only the GitHub read boundary; Git and filesystem behavior use real temporary repositories.

Run the credential-free snapshot contract tests with the locked environment:

```bash
uv run --locked pytest -q tests/unit/test_stack_update_policy_snapshot.py
```

### Image Update Planning Selection

`build_stack_selection` creates the read-only, versioned scope used before image
discovery. Its default scope is the union of checked-in repo-managed stacks and
stack identities retained by open image update proposals. A removed or renamed
stack therefore remains selectable while its open proposal needs resolution.
Closed proposals are loaded only for selected current stacks; a closed proposal
alone does not add its identity to the default scope.

Host and stack filters are exact and repeatable. Repeated values within one
dimension are ORed, while host and stack dimensions are ANDed. Globs and regular
expressions are unsupported, and a filter that matches neither a current stack
nor an open marked proposal fails before image discovery. A proposal-only match
is valid.

Proposal identity comes only from the supported versioned hidden marker, which
records the canonical `stacks/<host>/<stack>` identity and proposal fingerprint.
Titles and labels are presentation, not identity. Duplicate open proposals make
that stack incomplete. A malformed, duplicated, or unsupported marker makes
repository-wide proposal discovery untrustworthy and stops selection without
repairing or guessing identity. Selection performs GitHub reads only and never
inspects deployed containers.

A checked-in stack without `stack.yaml` or without an `updates` section is
reported as `policy-not-configured`. Broad planning can report and skip that
legacy stack without changing an existing proposal; strict single-stack
validation continues to reject the missing policy.

Run the credential-free contract tests with the locked environment:

```bash
uv run --locked pytest -q tests/unit/test_stack_update_policy_selection.py
```

## Build a Stack

1. Create `stacks/<host>/<stack>/compose.yaml`.
2. Add `.env` or `.env.j2` if the stack needs environment variables.
3. For bind-mount target dirs that need pre-creation, add an `x-prereq-dirs` block to the repo-managed compose definition for the stack. Use `compose.yaml` by default. If you are intentionally preserving a vendor upstream base compose, put it in `compose.override.yaml` instead. Dirs that already contain committed config files need no entry.
4. Add Traefik and Homepage labels only to the user-facing service.
5. Deploy with:

```bash
./run.sh --limit <host>
```

To iterate on a single stack without reconciling the others:

```bash
./run.sh --limit <host> -e stack_filter=<stack>
```

No registration step is required; the role discovers everything under `stacks/<host>/` automatically.

## Traefik

Some Docker hosts act as label sources for Traefik on `portal`: `traefik-kop` copies their Docker labels into portal's Redis. Stacks on the reverse-proxy host use Traefik directly.

### Discovery Contract

- `traefik.enable=true` means the service should be routed.
- No Traefik labels means the service stays internal.
- Put labels on the user-facing container, not sidecars or databases.
- `traefik.domain=<domain>` only overrides the host's `default_domain`.
- Use an explicit `traefik.http.routers.<name>.rule=Host(...)` only when you need a non-default hostname.

Default hostname:

```text
Host(`<compose-project>.<default_domain>`)
```

### Defaults You Should Not Restate

- `websecure` is the default entrypoint.
- TLS is automatic on `websecure`.

So you normally should not add `entrypoints=websecure` or `tls=true`.

### Common Patterns

| Situation | Labels |
| --- | --- |
| Standard routed service | `traefik.enable=true` |
| Protected routed service | above + `traefik.http.routers.<router>.middlewares=protected-edge-auth@file` |
| Different domain than host default | above + `traefik.domain=<domain>` |
| Custom hostname | above + `traefik.http.routers.<name>.rule=Host(...)` |
| Ambiguous service port | above + `traefik.http.services.<name>.loadbalancer.server.port=<port>` |

Public services should omit the auth middleware label. Protected tiers add it explicitly.

Port labels name the port Traefik can reach. For label-exported routes, such as routes copied by `traefik-kop` from a Docker host that is not running the reverse proxy, Traefik reaches the service through the published host port. If the service publishes `host_port:container_port` and those ports differ, set `traefik.http.services.<name>.loadbalancer.server.port` to the host port.

Example:

```yaml
services:
  myapp:
    ports:
      - 8990:8989
    labels:
      traefik.enable: true
      traefik.http.services.myapp.loadbalancer.server.port: 8990
```

### Usually Leave Unlabeled

- internal databases and caches
- workers/background jobs
- internal helper APIs
- VPN support containers

### Shared Docker Network

Use one external `shared` network when multiple stacks on the same LXC need stable Docker-network access to each other. This is host-local cross-stack plumbing; it is not a cross-LXC network.

```yaml
services:
  myapp:
    networks:
      - shared

networks:
  shared:
    external: true
```

Also declare the external network in host vars:

```yaml
lxc_docker_env_external_networks:
  - shared
```

Older stacks used inconsistent legacy names for this pattern. Use `shared` so
host-local shared networks are named consistently across LXCs.

Do not add `shared` only because a stack has Traefik labels or because `traefik-kop` exports those labels. Label-exported routes need a reachable published port; `shared` is only for same-LXC stack-to-stack traffic.

### Domains

Set `default_domain` per host in `inventory/host_vars/<host>.yml`. The docker-agents `.env.j2` passes it to traefik-kop as `DOMAIN`.

| Host | `default_domain` | Example |
| --- | --- | --- |
| `portal` | `faviann.com` | `media.faviann.com` |
| `seedbox` | `admin.faviann.com` | `bittorrent.admin.faviann.com` |
| `jellyfin` | `public.faviann.com` | `jellyfin.public.faviann.com` |

When adding a new tier subdomain, also add its wildcard SAN in `stacks/portal/traefik3/appdata/traefik3/config/traefik.yaml` or TLS will fail.

## Secrets and `.env`

→ [docs/stacks-secrets.md](../docs/stacks-secrets.md) — read when adding secrets or environment variables to a stack.

## Homepage Labels

→ [docs/stacks-homepage.md](../docs/stacks-homepage.md) — read when adding or changing Homepage visibility for a service.

## Authentik

→ [docs/stacks-authentik.md](../docs/stacks-authentik.md) — read when creating or modifying Authentik providers, applications, or auth bypass rules.

## RomM

→ [stacks/public/romm/README.md](public/romm/README.md) — read for RomM native OIDC behavior and Authentik coupling notes.

## Docker Agents

→ [docs/stacks-docker-agents.md](../docs/stacks-docker-agents.md) — read when debugging the managed docker-agents stack or changing agent configuration.

## Networking

→ [docs/stacks-networking.md](../docs/stacks-networking.md) — read when a stack needs external networks, VPN tunneling, or non-default network configuration.

## Minimal Example

```text
stacks/jellyfin/jellyfin/
├── compose.yaml
└── .env.j2
```

```yaml
x-prereq-dirs:
  - ./appdata/jellyfin

services:
  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    restart: unless-stopped
    container_name: jellyfin
    volumes:
      - ./appdata/jellyfin:/config
      - /data/media:/data/media:ro
    labels:
      traefik.enable: true
      homepage.group: Media
      homepage.name: Jellyfin
      homepage.href: https://${HOMEPAGE_FQDN}
      homepage.description: Media streaming server
      homepage.icon: jellyfin
```

```jinja2
PUID={{ docker_uid }}
PGID={{ docker_gid }}
TZ=America/Montreal
HOMEPAGE_FQDN={{ stack_name }}.{{ default_domain }}
```

## Review Checklist

1. Exposure intent is explicit.
2. Only user-facing services carry Traefik labels.
3. Homepage labels match the intended access tier.
4. All bind-mount target dirs that need pre-creation are declared in `x-prereq-dirs` in the repo-managed compose definition for the stack. `compose.yaml` is the default location; vendor-preserving stacks may use `compose.override.yaml`. No `.gitkeep` files.
5. Any new subdomain tier also updates Traefik SANs.
6. Secrets live in vault-backed `.env.j2`, not static `.env`.
7. Stateful databases should not use floating `latest` tags; pin them and give them a realistic `stop_grace_period`.
8. Portability tier is clear: portable app, host-bound app, or foundational controlled migration.
9. Host-level deployment mechanics remain in inventory/host vars, not stack metadata.
10. Stack-local docs and `stack.yaml` contain no plaintext secrets or secret-shaped values.
11. Foundational stacks (`auth`, `portal`, Authentik/OIDC-coupled public apps) are changed only through dedicated migration plans.

## Notes

- The role discovers both `compose.yml` and `compose.yaml`.
- A host with no folder here is not an error.
===== END SOURCE: stacks/README.md =====

===== SOURCE: stacks/portal/traefik3/README.md @ 93f69bc8044172900952ceda6bf5552bfc7968a3 =====
# Traefik3 Stack

This stack is the domain-edge reverse proxy on the `portal` Docker host. It is
infrastructure, not a normal routed application stack.

## Normalization Boundary

This stack intentionally does not follow every ordinary app-stack default.

Preserve:

- Do not remove either `443/tcp` or `443/udp`; same-number TCP and UDP bindings
  are not a port conflict.
- Keep Docker provider socket access behind the stack-local
  `traefik-docker-socket-proxy`; Traefik should not mount the host Docker socket
  directly.
- Do not treat Redis, certificate storage, or `x-managed-files` as
  exception-only behavior. They are normal features for this domain-edge reverse
  proxy pattern.
- Do not read or print files under `stacks/portal/traefik3/secrets/`.
- Do not document `.env` values.
- Do not normalize this stack as if it were a normal routed application.

Do not use this stack as a template for normal application stacks.

## Ownership

Stack-owned:

- `compose.yaml`
- `.env.j2`
- Traefik dynamic and static config under `appdata/`
- ACME storage declarations through `x-managed-files`

Host-owned:

- `shared` external network declaration
- portal vault-backed variable bindings in `inventory/host_vars/portal.yml`
- domain-edge exposure and certificate DNS credentials

## Deploy

```bash
./run.sh --limit portal -e stack_filter=traefik3
```
===== END SOURCE: stacks/portal/traefik3/README.md =====

===== FOWLER BASELINE: exact code-review/SKILL.md lines 40-60 =====
Anything in the repo that documents how code should be written, such as `CODING_STANDARDS.md` or `CONTRIBUTING.md`.

On top of whatever the repo documents, the Standards axis always carries the **smell baseline** below — a fixed set of Fowler code smells (_Refactoring_, ch.3) that applies even when a repo documents nothing. Two rules bind it:

- **The repo overrides.** A documented repo standard always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible Feature Envy"), never a hard violation — and, like any standard here, skip anything tooling already enforces.

Each smell reads *what it is* → *how to fix*; match it against the diff:

- **Mysterious Name** — a function, variable, or type whose name doesn't reveal what it does or holds. → rename it; if no honest name comes, the design's murky.
- **Duplicated Code** — the same logic shape appears in more than one hunk or file in the change. → extract the shared shape, call it from both.
- **Feature Envy** — a method that reaches into another object's data more than its own. → move the method onto the data it envies.
- **Data Clumps** — the same few fields or params keep travelling together (a type wanting to be born). → bundle them into one type, pass that.
- **Primitive Obsession** — a primitive or string standing in for a domain concept that deserves its own type. → give the concept its own small type.
- **Repeated Switches** — the same `switch`/`if`-cascade on the same type recurs across the change. → replace with polymorphism, or one map both sites share.
- **Shotgun Surgery** — one logical change forces scattered edits across many files in the diff. → gather what changes together into one module.
- **Divergent Change** — one file or module is edited for several unrelated reasons. → split so each module changes for one reason.
- **Speculative Generality** — abstraction, parameters, or hooks added for needs the spec doesn't have. → delete it; inline back until a real need shows.
- **Message Chains** — long `a.b().c().d()` navigation the caller shouldn't depend on. → hide the walk behind one method on the first object.
- **Middle Man** — a class or function that mostly just delegates onward. → cut it, call the real target direct.
- **Refused Bequest** — a subclass or implementer that ignores or overrides most of what it inherits. → drop the inheritance, use composition.
===== END FOWLER BASELINE =====

