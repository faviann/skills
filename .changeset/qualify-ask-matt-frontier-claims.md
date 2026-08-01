---
"faviann-skills": patch
---

Correct two routing claims in `/ask-matt` about the tickets `/to-tickets` publishes.

- **Blocking edges set the frontier, not who acts.** The router no longer says a ticket can be grabbed as soon as its blockers are done. Edges decide only when a ticket is startable; the role it carries as published decides who may act on it, and `/implement` now picks up the frontier tickets published as agent work rather than every frontier ticket.
- **The triage on-ramp no longer over-claims.** Instead of asserting every `/to-tickets` output is agent-ready, it says those tickets already carry the role `/to-tickets` assigned them — normally `ready-for-agent` — and still tells you not to triage them.
