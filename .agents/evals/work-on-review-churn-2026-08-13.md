# `work-on` review-churn forensic analysis

Date: 2026-08-13

Status: investigative record, not an approved workflow change

Pinned skills revision: [`d5449605bec3fee48d6b0339fb1d765f22c5cf46`](https://github.com/faviann/skills/commit/d5449605bec3fee48d6b0339fb1d765f22c5cf46)

Related issues: [#9](https://github.com/faviann/skills/issues/9), [#62](https://github.com/faviann/skills/issues/62), and [#64](https://github.com/faviann/skills/issues/64).

## Executive finding

Recent `work-on` runs show repeated implementation, independent-review, and remediation rounds, especially on contract-dense tickets. The strongest current hypothesis is not that adversarial review is inherently wasteful. Several late findings were real and important. The suspected inefficiency is the combination of **stateless, cumulative, multi-agent, unlimited, post-hoc adversarial review**.

This note preserves the source-backed analysis, limitations, suspected causes, proposed experiments, metrics, and guardrails so a fresh session can resume without relying on the originating conversation.
