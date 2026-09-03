# Accepted-blocker correction self-check

An accepted-blocker correction is any accepted-blocker-driven correction routed
to the retained implementation delegate, including readiness and post-gate
corrections. Readiness corrections receive this self-check without becoming
Corrective batches or acquiring normative-remediation qualification.

For every accepted-blocker correction round, extend the implementation owner's
ordinary return to the following shape, whether the existing mechanism
continues the retained context or uses its fresh-delegate fallback:

```text
Changed:
Evidence:
Rechecked:
Unverified:
Risks:
```

The initial implementation and bounded coherence pass keep the unchanged return
above. `Rechecked:` is only a labelled correction-return channel: keep focused
validation results in `Evidence:`, uncertainty in `Unverified:` and `Risks:`,
and the checks below in `Rechecked:`.

Applicability has two discovery times. Before dispatch, the primary derives
and dispatches minimum obligations already knowable from the accepted blocker
using only information it owns. After implementing, the retained delegate
accounts for additional applicability created by its chosen mechanism;
`not applicable — <one-line reason>` is a valid delegate declaration. The
primary preserves it for working traceability without adjudicating its technical
conclusion.

Apply these checks:

1. **Correction-specific repository standards — every correction.** The
   delegate reads repository standards directly and reports either named
   correction-specific governing sources plus the outcome, or that no
   correction-specific governing repository source was identified. Bare
   `standards: checked`-style boilerplate is insufficient. This check does not
   receive the reviewers' frozen Standards input or replace the Standards axis.
2. **Adversarial negative or population-boundary check — when applicable.**
   Apply only when correctness depends on absence, rejection, a forbidden case,
   exhaustive enumeration, or population closure. Try at least one appropriate
   plausible false candidate, contradiction, omitted member, or forbidden case
   and report the result. Do not extend this to every falsifiable universal
   claim.
3. **Claimed behavior versus observed validation surface — when focused
   validation is offered as proof.** In `Rechecked:`, name the claim and actual
   observed surface, then state whether that surface can or cannot establish the
   claim. A helper or private seam establishes broader public or contract
   behavior only when the governing contract makes that seam authoritative.
   Repository testing guidance may strengthen this rule. Keep the validation
   execution and result in `Evidence:`.

The retained implementation delegate owns the checks. The primary enforces that
required information is present and applicability is accounted for, without
technically adjudicating the conclusions; existing reviewers remain the
independent backstop.

- Missing or incomplete required information returns through the existing
  implementation-owner mechanism for completion.
- An explicitly unresolved required check blocks commit. First revise or reshape
  the correction, narrow its claim, replace its mechanism, or try another way to
  satisfy the blocker.
- Once every required check is established, this self-check no longer blocks
  commit.

Only when no advancing correction can be produced, use the existing closeout
rules directly: reach ordinary `Progresses` with a safe, independently useful
narrowed candidate through the existing gates, or `failed` when none exists.
This route does not pass through `references/normative-remediation.md`.

Complete this self-check in the working tree before commit; the last commit
remains the mechanically identified candidate. For a qualifying post-gate
Corrective batch, complete this self-check before applying the existing
`references/normative-remediation.md` checkpoint to the actual correction; both
must be complete before commit, and that reference retains ownership of its
contract.

Keep `Rechecked:` rationale, applicability declarations, conclusions, and
correction reasoning in primary-side working state, excluded from cumulative
and delta reviewer packages. Qualifying raw validation evidence may still flow
through `references/validation-evidence.md` into the package slots enumerated in
`references/review-state-machine.md`.
