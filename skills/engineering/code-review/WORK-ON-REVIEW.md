# Work-on review packages

Apply this adapter when `work-on` supplies a frozen cumulative- or delta-review
package. The caller's review state machine owns the package contract. This
adapter carries it across the `code-review` seam without replacing frozen inputs
with this skill's ordinary discovery.

## Package verification

The package replaces `SKILL.md` steps 1 through 3 and the generic input bullets
in step 4. Verify that every identity required by the caller resolves and that
executing each supplied mechanical diff reproduces the supplied artifact. The
package's exact Candidate identity and frozen sources are authoritative: never
resolve an independent `HEAD`, build or pass a commit list, discover or refetch
a spec, or discover live standards. A missing field, identity mismatch, or
non-reproducible diff fails before either sub-agent starts.

## Prompt composition

Construct each prompt from exactly two inputs:

```text
<exact caller-supplied frozen review package, verbatim>
<corresponding Standards or Spec axis brief from SKILL.md, verbatim>
```

Add no convenience summary or other context. For both cumulative and delta
packages, send the same exact package to Standards and Spec. A cumulative review
begins at its full cumulative subject. A delta review begins at its correction
delta and follows the package's bounded unchanged-context and same-mechanism
rules. After both axes return, continue at `SKILL.md` step 5.
