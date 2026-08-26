The branch now names the requested project in denied diagnostics, keeps the
owner/project authorization decision unchanged, and clarifies the ownership
proposition without widening entitlement. The complete deterministic suite
directly checks owned access, cross-project denial, the diagnostic, and the
clarified ownership authority.

The staging-retention clarification could not be completed safely. The bounded
normative checkpoint found that the repository has no definitions establishing
record/scope membership, the assignment source for the retention window, or
the mandatory force of the proposed shorthand. The unsafe draft was removed
before commit, leaving the governing proposition unchanged.

Commits:

- `8369896` — name denied project in access diagnostic.
- `4146125` — clarify owner-only report access and assert the governing text.

Validation:

- `bash test.sh` — pass for exact final candidate
  `4146125269f0ea351912ab8606825a809b48628e`.
- `git diff --check` — pass for the complete base-to-candidate diff.
- Final Standards — no findings.
- Final Spec/closure — AC1, AC2, and AC4 pass; AC3 remains failing.

## Follow-ups

- #5 — define the finite staging-retention terms and assignment/precedence
  rules needed to complete AC3. Issue #2 is natively blocked by #5.

## Finding adjudications

- Readiness AC2/AC3 omissions and absent policy assertions were retained for
  the authorized initial-candidate control and then accepted at the cumulative
  gate as contract-backed corrective work.
- Readiness's dirty-candidate concern was rejected because the selected workflow
  places raw-artifact readiness before the first commit.
- The initial cumulative ownership and staging findings were accepted as two
  qualifying units in one corrective batch.
- The entitlement-widening draft was rejected after independent semantic
  interpretation and revised before any corrective commit.
- The staging shorthand remained unresolved after finite context was found
  unavailable; it was restored before commit and routed to #5/`Progresses`.
- The delta Spec re-raise of unchanged AC3 was rejected only as
  delta-attributable because AC3 was identical at both delta endpoints; the
  underlying blocker remained accepted and controls the outcome.

| Mechanism | Governing criterion | Ruling |
|---|---|---|
| Owner/project equality and both CLI branches | AC1, AC2, AC4 | Required and directly tested |
| Project-derived denial diagnostic | AC1, AC4 | Required and directly tested |
| Clarified owner-only policy proposition | AC2 | Required; semantic meaning preserved |
| Exact ownership proposition assertion | AC2 | Required direct policy-artifact seam |
| Original staging-retention proposition | AC3 | Semantics retained, but clarification missing |
| Clarified staging-retention assertion | AC3 | Missing because no safe clarified proposition exists |
