# `work-on` review-churn forensic analysis

Date: 2026-08-13

Status: investigative record, not an approved workflow change

Pinned skills revision: [`d5449605bec3fee48d6b0339fb1d765f22c5cf46`](https://github.com/faviann/skills/commit/d5449605bec3fee48d6b0339fb1d765f22c5cf46)

Related issues: [#9](https://github.com/faviann/skills/issues/9), [#62](https://github.com/faviann/skills/issues/62), and [#64](https://github.com/faviann/skills/issues/64)

## Executive finding

Recent `work-on` runs show repeated implementation, independent-review, and remediation rounds, especially on contract-dense tickets. The strongest current hypothesis is not that adversarial review is inherently wasteful. Several late findings were real and important. The suspected inefficiency is the combination of:

> stateless, cumulative, multi-agent, unlimited, post-hoc adversarial review.

Confidence is **high** that the current topology repeats work. Confidence is **moderate** about the causal weight of each suspicious element because the workflow does not yet record launches, tokens, cumulative material reread, or repeated-versus-new findings.

## Research packet

- [Evidence and source provenance](work-on-review-churn-2026-08-13-evidence.md)
- [Ranked diagnosis and causal model](work-on-review-churn-2026-08-13-diagnosis.md)
- [Staged experiment plan, metrics, and guardrails](work-on-review-churn-2026-08-13-plan.md)

Together these files preserve the source artifacts, representative PR telemetry, direct observations, inferences, limitations, suspicious workflow elements, current causal hypothesis, proposed experiments, success metrics, open questions, and non-goals. A fresh session should begin with this index and issue #64 rather than depending on the originating conversation.

## Stage artifacts

- [A3 instrumented control window](work-on-a3-control-window.md) — the pre-registered protocol fixing which runs count, how many are collected, and what would make the control insufficient or invalid. Frozen before the window starts; B1 stays blocked until its results are accepted.
- [A3 attempt 1 forensic closeout](work-on-a3-attempt-1-forensic-closeout.md) — attempt 1 was invalid because its mandatory dual-surface records were not produced; the unavailable overmind telemetry also leaves the exact sample indeterminate.
