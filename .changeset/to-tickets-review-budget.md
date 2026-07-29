---
"faviann-skills": patch
---

Size a `/to-tickets` slice by its review budget as well as its context budget.

`<vertical-slice-rules>` sized a slice only as "fits in a single fresh context window" — a capacity limit on the agent building the ticket, with nothing said about the human reviewing it. Tickets that fit context comfortably still landed as pull requests too large to review in one sitting, and had to be split by hand after the fact. Slices are now bounded by two constraints that both have to hold: one fresh context window, and one reviewable pull request. The docs page names both budgets and why they differ.
