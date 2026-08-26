trusted-snapshot-sha256 473888d724dc8921ad1aac1e5188837dcc34b94a4ccb7165056334969ffa6e93
pre-implementation-base dea1579185416cfa0bd4198bb2b904bae67d96ba
manifest-binding-sha256 3fd8866d3dd454aa013b6e62e9cbc874e2203a2afcb14d7142c5a1f70b472f94
---
# Validation-surface manifest

## Frozen concrete population

1. `fixtures/members/alpha.txt`
2. `fixtures/members/beta.txt`

## Criterion obligations

- Criterion 1: directly inspect the frozen concrete population through the public reporting command and verify the finite member mapping.
- Criterion 2: directly execute `bin/report-members` and compare its complete ordered stdout to the expected `name=value` lines for the frozen concrete population.
- Criterion 3: exercise each frozen member independently through the public command with black-box assertions that fail when its line is absent or incorrect.
- Criterion 4: execute `bash test.sh` as the repository baseline.

## Validation seams and owning phases

- Implementation: focused black-box execution of `bin/report-members` for vertical red-green slices at the public command seam.
- Primary checkpoint / initial-gate path: complete direct-evidence execution for the frozen concrete population after the candidate is committed and stable.
- Closeout: `bash test.sh` complete deterministic regression and `git diff --check`.
