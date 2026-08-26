# Post-stop corroborating observation: `faviann/dotfiles#96`

## Status and scope

This is **not** a selected pilot attempt, substitute, alternate, or P4 result.
The frozen pilot had already reached its authoritative `DO NOT RESUME` result
after P1. This record preserves and independently adjudicates a later execution
only as post-stop corroborating repair evidence. It does not enter the selected
population, satisfy the collection cell, alter the frozen projection, average
against P1, or reopen the result.

- Repository/issue: `faviann/dotfiles#96`
- Pull request: `faviann/dotfiles#104`
- Telemetry run: `20260826T151118Z-34bc65dd`
- Base: `fe3765b39681bd8705276345abad47d5b7c4a305`
- Final candidate: `19923be1488bf3560e10160305b4e7b66ef0c3b6`
- Outcome observed by that run: `Closes`
- Workflow provenance: `work-on:a9ebf0ae3a77 workflow:1b3cf6d962ac tdd:aa54f63292bf review:1dc4289fabb7 (faviann/skills@a4c450839650)`
- Frozen pilot protocol/projection used only as the adjudication contract:
  `266fc77d505b774eb235d4c7c9d11be5d109f127` /
  `e6f0782f02a66f025fc17013abe71e016c902f4c25c5dde0860261db87a2307b`

## Independent adjudication

### 1. Evidence-phase ownership: corroborated failure

The manifest resolves the complete eight-member install/version-query
population to the primary checkpoint before the initial gate, after the
candidate and validation instrument stabilize. Implementation is limited to
red-green development cases and affected preservation cases.

Implementation nevertheless executed the complete eight-member population.
Telemetry execution `e002` ran the new inventory case green, and later
Implementation executions repeatedly ran that same complete population while
developing query accounting. The complete population was therefore produced
before its workflow-owned post-stabilization phase. The later checkpoint then
ran it again as `e029` and as part of the affected suite in `e030`.

Classification: **revision-3 named falsifier — premature complete evidence
population**. The fact that a narrow development case was legitimately useful
does not permit that case to materialize all eight members before the population
owner. This corroborates that the merged phase-ownership contract was not
reliably enforced in execution.

### 2. Review progression: R2/R3 were contract-required confirmations

The exact chain was:

1. initial cumulative R1 at `a0214ff242aa88dfc8179e8fd4a404e3e65459b6`;
2. delta R1, `a0214ff..2850ebc`;
3. cumulative R2 at `2850ebc9efc103ef35978c08f440f94ee878c553`;
4. delta R2, `2850ebc..7688473`;
5. cumulative R3 at `7688473133d5b1812a5c5d30bec9652feda582ea`;
6. delta R3, `7688473..19923be`; and
7. final blind cumulative R4 at
   `19923be1488bf3560e10160305b4e7b66ef0c3b6`.

R2 and R3 are **not** prohibited routine cumulative rereading. Each preceding
delta gate was clean, so the merged review state machine required a fresh blind
cumulative confirmation for the exact candidate. R2 independently exposed the
preserved failure-phase defect that caused the next correction; R3 independently
exposed the query-uniqueness evidence gap that caused the next correction. R4
was the final clean confirmation after delta R3. None was inserted between
corrective candidates without the contract's clean-delta transition.

This sequence may still be costly observationally, but it is the shipped delta-
review topology operating as written. It is not evidence that the implementation
violated that topology and creates no delta-review repair question by itself.

### 3. Exact-identity reruns: corroborated coarse-rerun failure

The suite-level label alone is not the basis for this classification. The exact
candidate deltas, targeted executions, and affected evidence identities show
unchanged members were executed again:

| Candidate transition | Actually invalidated evidence | Prior qualifying evidence at the same stabilized candidate | Coarse execution |
| --- | --- | --- | --- |
| `a0214ff..2850ebc` | One inventory-test subcase was added to detect bypass of the Claude stable-version consumer; production and the other suite cases were unchanged. | Targeted `e033` ran the changed case green, including all eight inventory members. | `e034` immediately reran the whole affected suite, including the already-green eight members and unchanged cases. |
| `2850ebc..7688473` | The shared metadata loader and one invalid-version fixture changed, affecting the eight metadata members and named engine/version preservation paths. | Targeted `e039`–`e043` discharged the changed invalid-version, unreadable/absent-engine, inventory, and post-install registry identities. | `e045` reran the whole suite, including those already-discharged identities and unaffected cases. |
| `7688473..0f50132`, then `0f50132..19923be` | The first change added the eight-member total-query oracle; the second changed only that oracle's `grep` count implementation after ShellCheck. Production was unchanged. | `e048` discharged the query oracle before `e049`; `e051` discharged the ShellCheck correction before `e052`. | `e049` and `e052` each reran the whole suite, including unchanged members/cases. |

At the initial checkpoint, targeted population execution `e029` was also
followed by suite execution `e030` against the same candidate. Thus there are
multiple direct same-candidate examples, independent of any dispute about what
an earlier candidate change could affect.

Classification: **revision-3 named falsifier — unchanged-member/coarse rerun**.
The affected suite is one convenient command, but its member/case evidence
identities were finer-grained and the run had already produced qualifying
targeted evidence for the changed identities. No timing, nondeterminism,
environment sensitivity, suspect provenance, or distinct assurance question is
recorded to require the unchanged repetitions.

## Minimum implicated repair questions

1. **Manifest completeness:** What minimum pre-delegation check makes a trusted-
   contract-required direct observation impossible to omit from a frozen
   Validation-surface manifest, as happened to P1's resolver boundary?
2. **Phase-ownership enforcement:** What minimum enforcement makes the resolved
   workflow owner control execution when a development case would also produce
   an entire later-owned population?
3. **Identity-granular reuse:** What minimum execution-planning boundary carries
   exact invalidation and qualifying-reuse decisions through a convenient suite
   command, so a narrow correction cannot force unchanged member/case evidence
   to rerun?

These are repair questions only. This handoff does not choose or implement a
solution and does not reopen the compliant R2/R3 cumulative-review transitions.

## Preserved evidence

- `harness/`: raw primary, implementation, readiness/reviewer, and preservation
  transcripts selected by the run identity.
- `run/telemetry.jsonl`: sealed schema-2 telemetry.
- `run/frozen-manifest.md` and `run/trusted-snapshot.json`: frozen authority.
- `run/review-packages/`: exact R1–R4 cumulative and R1–R3 delta packages plus
  frozen Standards input.
- `run/adjudication.log`: repository adjudication history containing the #96
  rulings.
- `run/registry.json`: sealed run registry record.
- Repository commits and `faviann/dotfiles#104`: candidate and tracker artifacts.
