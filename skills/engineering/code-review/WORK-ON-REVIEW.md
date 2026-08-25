# Pinned review inputs

Apply this adapter when a caller supplies the complete review subject and
governing inputs. The caller owns their selection, scope, identity, and custody;
this adapter transports them into Standards and Spec judgment.

The pinned invocation contains:

- the exact comparison Candidate identity;
- the exact current Candidate identity;
- the exact frozen spec and full contract, including any governing manifest;
- the exact frozen Standards input;
- qualifying raw validation evidence; and
- caller-supplied review-scope instructions.

The pinned inputs replace `SKILL.md` steps 1 through 3 and the generic input
bullets in step 4. Verify that both Candidate identities resolve and that the
supplied mechanical comparison reproduces directly from those exact endpoints.
The supplied identities and frozen sources are authoritative: never resolve an
independent `HEAD`, build or pass a commit list, discover or refetch a spec, or
discover live standards. A missing input, identity mismatch, or non-reproducible
comparison fails before either sub-agent starts.

## Prompt composition

Construct each prompt from exactly two inputs:

```text
<exact caller-supplied pinned review inputs, verbatim>
<corresponding Standards or Spec axis brief from SKILL.md, verbatim>
```

Add no convenience summary or other context. Send the same exact pinned inputs
to Standards and Spec, and apply the caller-supplied scope without modifying
either axis brief. After both axes return, continue at `SKILL.md` step 5.

For Standards, the complete frozen Standards input supplies both the
source-labelled exact content of every applicable repository standards source
and the complete Fowler smell baseline from `SKILL.md`. Preserve the baseline's
repo-overrides and judgement-call semantics and its tooling-enforcement
exclusion. Pass that input verbatim; step 3 does not rediscover any part of it.
