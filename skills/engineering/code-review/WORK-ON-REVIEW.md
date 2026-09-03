# Pinned review inputs

Apply this adapter when a caller supplies the complete review subject and
governing inputs. The caller owns their selection, scope, identity, and custody;
this adapter transports them into Standards and Spec judgment.

The pinned invocation contains:

- the Review-index path and its exact identity;
- the exact pinned comparison and current Candidate identities;
- the verified reads and changed-path operation that reach the frozen universe,
  and the starting components for each axis.

The pinned inputs replace `SKILL.md` steps 1 through 3 and the generic input
bullets in step 4. Verify the dispatched Review index and its identity before
either sub-agent starts, and take every frozen component, changed path, and
comparison through the caller's pinned operations. The dispatched identities and
frozen components are authoritative: never resolve an independent `HEAD`, build
or pass a commit list, discover or refetch a spec, or discover live standards. A
missing input, identity mismatch, or unverifiable component fails before either
sub-agent starts, and no similarly named live source substitutes for it.

## Prompt composition

Construct each prompt from exactly two inputs:

```text
<exact caller-supplied pinned review inputs, verbatim>
<corresponding Standards or Spec axis brief from SKILL.md, verbatim>
```

Add no convenience summary or other context. Standards and Spec receive the
identical common dispatch — the Review-index path and identity, the pinned
comparison and Candidate identities, and the verified-read and changed-path
operations — and modify neither axis brief. What differs is only where each axis
starts. After both axes return, continue at `SKILL.md` step 5.

Both axes begin by reading the authenticated review assignment, which carries
the caller's review scope, and the complete changed-path inventory. Beyond that
each reads only its own starting component: Standards the complete frozen
Standards input, Spec the frozen contract. Neither ingests the other's starting
component up front; either reads any further frozen component through the common
dispatch when a concrete review question requires it.

The Standards input supplies both the source-labelled exact content of every
applicable repository standards source and the complete Fowler smell baseline
from `SKILL.md`. Preserve the baseline's repo-overrides and judgement-call
semantics and its tooling-enforcement exclusion. Read that component verbatim;
step 3 does not rediscover any part of it.

Each axis returns its report under the caller's completion contract: bound to
the exact Review-index identity, and `COMPLETE` or `INCOMPLETE`. Report Standards
and Spec judgment; the caller owns what those two values mean for its gate.
