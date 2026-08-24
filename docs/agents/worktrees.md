# Git worktrees

Create linked worktrees under `~/repos/skills-worktrees/<branch>/`.

## Skill links stay with the primary checkout

The local harness loads installed skill links from the primary checkout. Editing a skill in a linked worktree does not change the skill that Claude Code or Codex loads. Check a skill's actual behaviour from the primary checkout after the branch lands there.

Run the local installer, `scripts/reconcile-skills.sh`, only from the primary checkout. Installing links to a temporary worktree would leave them dangling when that worktree is removed. The reconciler guards against this mistake and refuses to run from a linked worktree; return to the primary checkout and re-run it there.

The reconciler skips skill names listed in `.agents/skill-link-excludes`. It also removes existing repository links for those names, and the repository links left behind by a removed or renamed skill.

## Fresh worktrees have no dependencies

A fresh worktree has no `node_modules`. `npm run check-plugin-version` works without installing dependencies because `scripts/sync-plugin-version.mjs` imports only Node.js built-ins. Run `npm ci` before `npm run changeset` or `npm run version`, which need the `changeset` binary.
