---
"faviann-skills": patch
---

Add durable staged calibration to `/to-tickets` for settled work whose later reviewable Ticket boundaries depend on evidence from an initial implementation Frontier.

Calibration records now preserve the deferred remainder, assumptions, checkpoint, linked Frontiers, and append-only decision history across fresh sessions. Resumption reconciles the record with real tracker state before proposing more work, and records can complete, suspend for design, or be deliberately abandoned without changing their Parent or implementation Tickets.
