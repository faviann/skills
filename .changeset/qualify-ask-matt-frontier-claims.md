---
"faviann-skills": patch
---

Correct two routing claims in `/ask-matt` about the tickets `/to-tickets` publishes.

- **Blocking edges set the frontier, not who acts.** The router no longer says a ticket can be grabbed as soon as its blockers are done. Edges decide only whether a ticket is startable at all; the role a ticket carries as published decides who may act on it, and that role — agent work by default — is what sends it into `/implement`.
- **The triage on-ramp no longer over-claims.** Instead of asserting every `/to-tickets` output is agent-ready, it says those tickets already carry the role `/to-tickets` assigned them — normally `ready-for-agent` — and still tells you not to triage them.
