# `work-on` review-churn evidence

Date: 2026-08-13

Pinned skills revision: [`d5449605bec3fee48d6b0339fb1d765f22c5cf46`](https://github.com/faviann/skills/commit/d5449605bec3fee48d6b0339fb1d765f22c5cf46)

Related issues: [#9](https://github.com/faviann/skills/issues/9), [#62](https://github.com/faviann/skills/issues/62), and [#64](https://github.com/faviann/skills/issues/64)

## Sources and method

The forensic review inspected the pinned versions of:

- [`work-on/SKILL.md`](https://github.com/faviann/skills/blob/d5449605bec3fee48d6b0339fb1d765f22c5cf46/skills/personal/work-on/SKILL.md)
- [`default-workflow.md`](https://github.com/faviann/skills/blob/d5449605bec3fee48d6b0339fb1d765f22c5cf46/skills/personal/work-on/references/default-workflow.md)
- [`github-closeout.md`](https://github.com/faviann/skills/blob/d5449605bec3fee48d6b0339fb1d765f22c5cf46/skills/personal/work-on/references/github-closeout.md)
- [`code-review/SKILL.md`](https://github.com/faviann/skills/blob/d5449605bec3fee48d6b0339fb1d765f22c5cf46/skills/engineering/code-review/SKILL.md)
- [`tdd/SKILL.md`](https://github.com/faviann/skills/blob/d5449605bec3fee48d6b0339fb1d765f22c5cf46/skills/engineering/tdd/SKILL.md)

No repository-local `docs/workflow.md` was found on `main` in `overmind`, `homelab-iac`, or `dotfiles` at review time, so the documented default workflow governed the sampled runs.

The pull requests below were selected to expose a range of behavior, not to estimate a population average. Evidence comes from final PR bodies and their mechanically recorded workflow telemetry. Unknown fields remain unknown.

## Representative runs

| Pull request | Outcome | Implementation | Review | Remediation | Blockers resolved | Rejected | Elapsed |
|---|---|---:|---:|---:|---:|---:|---:|
| [`homelab-iac#141`](https://github.com/faviann/homelab-iac/pull/141) | merged / `Closes` | 1 | 1 | 0 | 0 | 0 | 1,438 s |
| [`homelab-iac#140`](https://github.com/faviann/homelab-iac/pull/140) | merged / `Closes` | 3 | 4 | 2 | 2 | 3 | 3,630 s |
| [`dotfiles#76`](https://github.com/faviann/dotfiles/pull/76) | merged / `Closes` | 3 | 3 | 3 | 8 | 2 | 3,058 s |
| [`overmind#175`](https://github.com/faviann/overmind/pull/175) | merged / `Closes` | 8 | 6 | 7 | unknown | 4 | 02:14:07 |
| [`overmind#201`](https://github.com/faviann/overmind/pull/201) | merged / `Closes` | 8 | unknown | unknown | 17 | 2 | 13,704 s |
| [`overmind#202`](https://github.com/faviann/overmind/pull/202) | closed unmerged / `Progresses` | 8 | 8 | 7 | 17 | 4 | 10,313 s |

The table does not itself prove waste. `homelab-iac#141`, for example, has a one-line tracked diff but also performed a real ownership migration and live runtime validation. The material pattern is the repeated review/remediation topology on larger runs and the inability of current telemetry to separate review cost from implementation, testing, image builds, environmental failures, and live operations.

## Hidden review fan-out

The default workflow requires fresh agents for delegated implementation, the pre-commit readiness sweep, the Standards axis, the Spec axis, and the adversarial closure sweep. After each remediation, a fresh implementation delegate is followed by another combined candidate gate containing three reviewers.

Under that documented topology, `overmind#202`'s eight implementation and eight candidate-gate rounds plausibly imply at least 33 fresh subagent launches outside the primary: 8 implementation delegates, 1 readiness reviewer, and 8 candidate gates × 3 reviewers.

This is a topology-derived lower bound, not observed telemetry. The run may have launched more agents, and the nominal review-round count does not expose this fan-out.

## Contract-density examples

[`overmind#182`](https://github.com/faviann/overmind/issues/182) has five acceptance bullets but combines eleven hook surfaces, explicit installation and upgrade, loopback isolation, multiple fail-open states, coalescing, and scheduler authority.

[`overmind#186`](https://github.com/faviann/overmind/issues/186) combines instruction creation, delivery, acknowledgement, replay, restart behavior, pause/resume policy, durable queue behavior, credential revocation, and a broad remote-management prohibition.

Both were clear enough to implement, but clarity is not the same as fitting one review budget. Contract density and validation state space appear to be major co-factors in the expensive runs.

## Closability failure example

[`overmind#202`](https://github.com/faviann/overmind/pull/202) ended as `Progresses` after eight implementation rounds and seventeen resolved blockers because the revoked-credential criterion remained `inferred`. Its known-valid revocation transition belonged to open prerequisite [`overmind#181`](https://github.com/faviann/overmind/issues/181). The missing prerequisite or validation seam was knowable before implementation.

## Counterevidence and limitations

- Several sampled PRs contain real contract-backed findings that materially improved correctness and operational safety.
- The sample is deliberately selected, not random.
- Telemetry is incomplete and self-reported by the workflow.
- Elapsed time includes work other than review.
- Lower remediation counts can be gamed by suppressing, reclassifying, or deferring findings.
- A candidate workflow must compare escaped defects and final hard findings, not only rounds or tokens.
