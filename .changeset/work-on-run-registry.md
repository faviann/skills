---
"faviann-skills": patch
---

Give `work-on` runs a bounded, owner-only user-level run registry and an optional observer seam: a run is registered before implementation, finalized automatically on hand-back from its own sealed telemetry summary, and recoverable by the same identity after an interruption, a removed worktree, or a removed clone. A run whose observer obligation is still outstanding blocks the next matching run and prints one idempotent recovery command; runs with no applicable observer behave exactly as before.
