---
"mattpocock-skills": patch
---

Make the generated GitHub issue-tracker guidance target a verified repository before every write. It now prefers `origin`, sets it with `gh repo set-default`, and checks it with `gh repo set-default --view`, instead of trusting `gh`'s automatic resolution, which picks the upstream parent in a fork.
