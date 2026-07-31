---
"faviann-skills": patch
---

Name the triage-label mapping's left column for what it means, not for the repo that ships it.

The seed template `/setup-matt-pocock-skills` writes headed its left column `Label in faviann/skills`, inherited from upstream's `Label in mattpocock/skills` via the fork rebrand. That identifies a vocabulary by naming the repo that distributes it, which reads oddly anywhere and collapses when the skill is run against the distribution repo itself — both columns then denote the same tracker, and the table maps nothing. The columns are now `Canonical role` and `Label in this repo`, which is what they have always meant and stays true wherever the file lands. The separator and body rows are re-padded to the new widths (cosmetic; the old padding was sized for the pre-rebrand header).

The template's example of a skill naming a role also referred to a `ready-for-afk` role that no longer exists, as did the **Triage role** entry in `CONTEXT.md`. Both now say `ready-for-agent`, matching the table and the wording `/to-tickets` and `/triage` actually use.
