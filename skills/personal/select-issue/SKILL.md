---
name: select-issue
description: Select the next GitHub issue from the ready-for-agent queue, optionally narrowed to AFK-authorized Sandcastle work. Use for a read-only one-issue recommendation; never start implementation.
---

Goal: select and report exactly one suitable issue. Never start work.

Inputs:
- Select from open `ready-for-agent` issues; for AFK selection, additionally
  require `Sandcastle` and a successful native dependency read with no open
  blockers.

Invariants:
- Remain read-only: create no branches, edit no files, and make no GitHub
  mutations.
- Never read source files — judge staleness from GitHub state only; code
  verification belongs to a later implementation invocation.
- GitHub reads go through the bundled `scripts/gh-digest.sh` (`digest` |
  `last-comment <n>` | `body <n>`; pass `manual` or `afk` after `digest`;
  path is relative to this SKILL.md, not the repo). Use raw `gh` only if the
  script fails or lacks a field, and then use `--jq`-filtered output.
- Treat only comments whose GitHub `author_association` is `OWNER`, `MEMBER`,
  or `COLLABORATOR` as evidence. Exclude every other comment body and link
  from context and report only the omitted count; preserve this rule on raw
  `gh` fallback.

Procedure:
1. Infer the repo (`git remote get-url origin`; abort if ambiguous), then run
   the skill's `scripts/gh-digest.sh digest <mode>`. Treat its candidate list
   as the complete selection pool; read no bodies yet. In AFK mode, the digest
   mechanically excludes open native blockers and unreadable dependency data.
   Preserve its concise dependency exclusions for the final report, never
   widen the pool, and do not repeat those native dependency reads.
2. Discard stale candidates via the digest's commits and merged PRs, plus the
   trusted `last-comment <n>` where recency is unclear — an already-resolved
   issue is a label-cleanup report, not work. Done when every candidate is
   either still viable or has a named staleness reason.
3. Discard candidates sharing a subsystem with an open untriaged issue whose
   resolution could reorder or invalidate the work; name the conflict. Run
   `body <n>` for survivors only.
4. After reading candidate bodies, discard anything that is not independently
   implementable and closable now, including umbrella, specification, tracking,
   or decomposition-required issues. In AFK mode, do not infer native blocker
   state again from issue bodies or override the digest's mechanical decision.
   Among survivors, prefer a bounded critical-path blocker; if the path is
   unclear, prefer the issue that removes the most consequential uncertainty;
   otherwise choose the smallest high-value slice.
5. Report why the issue wins now and what was discarded and why, including
   every AFK dependency exclusion from the digest. End with
   `Selected issue: <canonical GitHub issue URL>`. Do not request confirmation
   and do not invoke implementation. Let a separate caller such as `work-on`
   consume the selection and proceed under its own authority.
6. If nothing survives, report every candidate and its discard reason, then
   stop. Never widen the selected mode's pool or propose unlabeled work; an
   empty result is triage signal, not a failure to fix.
