---
"faviann-skills": patch
---

Correct two routing claims in `/ask-matt` about the tickets `/to-tickets` publishes.

- **Blocking edges decide when a ticket is startable, not who acts.** The router no longer says a ticket can be grabbed as soon as its blockers are done. Its triage role decides who may start it, and `/implement` now picks up startable tickets carrying the `ready-for-agent` role rather than every startable ticket.
- **The triage on-ramp no longer over-claims.** Instead of asserting every `/to-tickets` output is agent-ready, it says those tickets already carry the triage role assigned at publication — normally `ready-for-agent` — and still tells you not to triage them.
