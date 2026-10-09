---
"mattpocock-skills": patch
---

Give `/to-tickets` an **Out of scope** slot for the prohibitions a ticket inherits.

Neither ticket template had a section that accepted a prohibition, so fences carried down from the parent ("no message broker is introduced", "no mutable `latest` tag") landed in Acceptance criteria as items nothing could falsify. Both templates now carry an Out of scope section, and the skill states the rule: a fence asserts some code does not exist, so as a criterion it can only ever be ticked on faith.
