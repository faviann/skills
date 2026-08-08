# Staged calibration

How to publish an immediate frontier when the design is settled but the remainder cannot yet be safely divided, and how to record what remains so a later run can resume it. Assumes the vocabulary in [SKILL.md](SKILL.md) — **tracer bullet**, **vertical slice**, **frontier**, **Parent**. The unresolved-design hand-back named below is the one in step 3 of [SKILL.md](SKILL.md).

This mode is the one exception to *Do NOT close or modify any parent issue* — append the checkpoint to its comment surface, leaving all source-contract content unchanged.

## Entry conditions

Use staged calibration only when all four conditions hold:

1. Product behavior, architecture, authority boundaries, and cross-slice contracts are settled.
2. The immediate frontier satisfies the ordinary ticket rules.
3. The settled remainder cannot yet be divided into safely reviewable tickets.
4. Named production evidence from implementing the immediate frontier will materially inform later ticket boundaries.

If condition 1 fails, use the unresolved-design hand-back above and publish nothing.

On resumption from an active checkpoint, recheck condition 1 before assessing evidence. If it fails, use that hand-back, publish nothing, and leave the checkpoint active. If the user explicitly decides to drop the remainder or remove it from the source contract instead, append a closed `cancelled` checkpoint with `Published Frontier: None`. If design remains settled, assess the named evidence against the sizing assumption. When the evidence is missing or unreadable, ask the user for exact references and stop. Every subsequent staged frontier must satisfy all four conditions before publication.

## Production evidence for staged calibration

**Calibration evidence** comes from the maintained production path and can genuinely inform later ticket boundaries: landed implementation, exercised integration seams, validation or fault injection, independent review and remediation, or operational evidence when operations drive the uncertainty. A throwaway prototype may settle a design question, but it cannot substitute for this evidence because it deliberately omits the maintained integration, validation, error handling, review, and remediation burden being calibrated.

One production wave is the positive case. Its immediate frontier exposed enough variation in integration, fault injection, validation, review, and remediation to shape the later boundaries.

Two nearby cases do not qualify. One still had unresolved-design fog, so it needed a design hand-back rather than partial publication. The other excluded a possible future adapter; evidence about excluded future design would begin a new design effort, not calibrate a settled remainder.

## Resuming from a Parent

When resuming from a Parent with staged-calibration checkpoints, read every checkpoint in tracker order. The last one controls. Take the union of their non-`None` `Published Frontier` references, read those tickets, and never republish work they already represent. If the controlling checkpoint is closed, treat none of its remainder as pending: propose only source-contract work not represented by those tickets, and report completion instead of creating tickets when nothing remains.

## In the quiz

For staged publication, include the reason for staging, the immediate frontier and its blocking edges, the coarse undecomposed remainder, the sizing assumption, and the named evidence location in this same quiz and approval.

## Checkpoints

After approved staged publication, append a checkpoint to its comment surface: a comment or note on a real tracker, or beneath `## Comments` in the local Parent file. Create that local heading when absent without changing the source-contract content above it.

Checkpoints are append-only. The last checkpoint in tracker order controls, so at most one is active at a time; its written date is human metadata. Use exactly these shapes:

```md
## Staged calibration checkpoint — <date>

Checkpoint: active
Published Frontier: <non-empty ticket references>
Undecomposed remainder: <coarse settled remainder>
Sizing assumption: <what production evidence must clarify>
Resume when: <named evidence and where to find it>
```

```md
## Staged calibration checkpoint — <date>

Checkpoint: closed
Disposition: published | cancelled
Published Frontier: <non-empty ticket references when published; None when cancelled>
```

Every active checkpoint and closed `published` checkpoint has a non-empty `Published Frontier`; only closed `cancelled` uses `None`.

Publish the approved frontier first, then append the checkpoint with the real ticket references. When more calibration remains, append an active checkpoint naming the newly published tickets. When the final frontier is published, append a closed `published` checkpoint naming those tickets. If assessment finds that existing tickets already satisfy the remainder, present that finding in the ordinary quiz; after approval, append closed `published` naming them. If the user explicitly decides to drop the remainder or remove it from the source contract, append closed `cancelled` with `None`.

If publication is partial or checkpoint persistence fails, retry the checkpoint with the exact tickets that exist and the remaining work. If checkpoint persistence still fails, stop and report the failure. Do not report success or clear context until the checkpoint is durable.
