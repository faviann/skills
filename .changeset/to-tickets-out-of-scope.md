---
"mattpocock-skills": patch
---

Give `/to-tickets` an **Out of scope** slot for the prohibitions a ticket inherits.

Both ticket templates had four sections — Parent, What to build, Acceptance criteria, Blocked by — and none of them accepted a prohibition. So when a decomposition carried a fence down from the parent ("no message broker is introduced", "no mutable `latest` tag"), the only section that took a normative statement was Acceptance criteria, and fences landed there as criteria nothing could falsify. Both templates now carry an Out of scope section, and the skill states the rule directly: a fence asserts some code does not exist, so no input could make it fail, and as a criterion it can only ever be ticked on faith.
