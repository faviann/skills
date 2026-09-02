---
"faviann-skills": patch
---

Prune accidental authority out of the deterministic checks that guard agent-facing documents.

`writing-for-agents` now carries the rule in its pruning section: a check takes its
authority from the governing contract, so it may enforce exact wording, headings or
order where the contract intentionally makes that representation authoritative, and
otherwise has to pass any alternative representation that still satisfies the contract.
A check that rejects a compliant rewrite has turned today's draft into a **shadow
contract** — and the contract, not the ease of passing, decides which case a given
assertion is in.

The repository's own testing notes make that pass the last step before a check guarding
agent-facing instructions is done.
