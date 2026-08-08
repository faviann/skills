Skills are organized into bucket folders under `skills/`:

- `engineering/` — daily code work
- `productivity/` — daily non-code workflow tools
- `misc/` — kept around but rarely used, not promoted
- `personal/` — tied to my own setup, not promoted
- `in-progress/` — beta: public on purpose, feedback wanted, not shipped in the plugin
- `deprecated/` — no longer used

When this checkout has both `origin` and `upstream`, treat `origin` as the
GitHub mutation target unless the user explicitly names another repository.
Before any GitHub mutation, run `gh repo set-default origin`, verify the target
with `gh repo set-default --view`, and pass that verified `owner/repo` via
`-R`. Never rely on unqualified `gh` repository resolution for a mutation.

Prose inherited from `upstream`: edit only what changes what a skill **does**, never
what reads better or matches a neighbour's voice. Preserve the sentence skeleton, patch
the minimum, and word-diff every delta against `upstream` — not `HEAD` — before
committing. If a feature needs an exception to an upstream rule, put the feature in its
own file rather than caveating the rule. `git log -S` a distinctive phrase before
rewriting or deleting a sentence — the fork's own wording is often deliberate too.
Additions are exempt from this paragraph, not from the rest of this file. Why, and the
incidents behind each rule: [.agents/upstream-fidelity.md](./.agents/upstream-fidelity.md).

Every skill in `engineering/` or `productivity/` (the **promoted** buckets) must have a reference in the top-level `README.md` and an entry in `.claude-plugin/plugin.json`'s `skills` array (the Claude Code plugin ships exactly the promoted set). Skills in `misc/`, `personal/`, `in-progress/`, and `deprecated/` must not appear in either.

Install commands are copied verbatim from [.agents/install-block.md](./.agents/install-block.md). The repo is also its own single-plugin Claude Code marketplace: `.claude-plugin/marketplace.json` lists the one `faviann-skills` plugin. When bumping the release version, keep `.claude-plugin/plugin.json`'s `version` in sync with `package.json`'s — `npm run version` does this through `scripts/sync-plugin-version.mjs`, and `npm run check-plugin-version` verifies it without writing. Run `claude plugin validate . --strict` after touching either manifest. Why a Claude plugin but not (yet) a Codex one lives in [.agents/adr/0002-ship-as-a-claude-code-plugin.md](./.agents/adr/0002-ship-as-a-claude-code-plugin.md).

Each skill entry in the top-level `README.md` must link the skill name to its `SKILL.md`.

Each bucket folder has a `README.md` that lists every skill in the bucket with a one-line description, with the skill name linked to its `SKILL.md`. The promoted buckets' `README.md`s and the top-level `README.md` group entries into **User-invoked** and **Model-invoked**; non-promoted bucket `README.md`s (`misc/`, `personal/`, `in-progress/`) use a flat list.

Skills in `engineering/` and `productivity/` also have a human-facing docs page at `docs/<bucket>/<skill-name>.md` (the docs tree mirrors those two bucket folders under `skills/`; the one exception is `docs/agents/`, which holds agent-facing repo configuration rather than published pages). The published URL is `https://aihero.dev/skills-<skill-name>` regardless of bucket — the docs path is repo organisation only. When you add, rename, or change the behaviour of a skill in `engineering/` or `productivity/`, create or re-sync its docs page following [.agents/writing-docs.md](./.agents/writing-docs.md). A finished page follows that file's ordered template: **What it does**, **When to reach for it**, and **Where it fits** are always present; **Common questions** and **It's working if** are included where the evidence and observable signals warrant them. Skills in the non-promoted buckets (`misc/`, `personal/`, `in-progress/`, `deprecated/`) get **no** docs page.

Every `SKILL.md` is either user-invoked (`disable-model-invocation: true` plus `policy.allow_implicit_invocation: false` in `agents/openai.yaml`, reachable only by the human) or model-invoked (model- or user-reachable). See [.agents/invocation.md](./.agents/invocation.md).

[`ask-matt`](./skills/engineering/ask-matt/SKILL.md) is the router that maps every user-reachable skill and how they relate. The same trigger that re-syncs a docs page applies to it: whenever you add, rename, remove, or change how a user-reachable skill fits the flows, re-read `ask-matt`'s `SKILL.md` and update it so the map stays accurate — a new skill it never mentions, or a stale one it still routes to, is a router that lies.

To (re)link every skill into the local harness skill directories (`~/.claude/skills`, `~/.agents/skills`), run `scripts/link-skills.sh`. Each entry is a symlink into this repo, so a `git pull` keeps installed skills current; re-run the script after adding, removing, or renaming a skill.

## Agent skills

### Issue tracker

GitHub Issues on `faviann/skills`, reached via `gh` with an explicit `-R`. See [docs/agents/issue-tracker.md](./docs/agents/issue-tracker.md).

### Triage labels

The five canonical roles, each label string equal to its role name. See [docs/agents/triage-labels.md](./docs/agents/triage-labels.md).

### Domain docs

Single-context — root `CONTEXT.md` plus ADRs in `.agents/adr/`. See [docs/agents/domain.md](./docs/agents/domain.md).

`CONTEXT.md` gets the same trigger as the docs pages and `ask-matt`: whenever a skill introduces a term the glossary defines, renames one, or gives an existing one a second name, re-read `CONTEXT.md` and update it — adding the rejected name to that entry's `_Avoid_` line. A glossary nobody is sent to is a glossary that records the drift it was meant to stop. Where a term is upstream's, skill prose follows upstream's casing; `CONTEXT.md` capitalises its headwords the way a dictionary does, which is a listing convention and not an instruction to prose.

### Risk-shapes evidence

Before changing or removing a production example in `to-tickets`'s risk-shapes reference, preserve its source mapping in [.agents/risk-shapes-provenance.md](./.agents/risk-shapes-provenance.md).

After changing its independent-model rules, discriminators, or worked examples, run the blind regression protocol in [.agents/evals/risk-shapes.md](./.agents/evals/risk-shapes.md) against the live reference.
