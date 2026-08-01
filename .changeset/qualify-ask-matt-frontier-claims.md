---
"faviann-skills": patch
---

Correct two routing claims in `/ask-matt` about the tickets `/to-tickets` publishes.

- **Published `/to-tickets` output stays agent-ready.** Every ticket it publishes is `ready-for-agent`; blocking edges decide when `/implement` can start each one. Unresolved design questions return to grilling, prototyping, or Wayfinder instead of becoming an alternative output role.
- **The triage on-ramp stays direct.** Tickets from `/to-tickets` are already agent-ready and classified, so the router still tells you not to triage them.
