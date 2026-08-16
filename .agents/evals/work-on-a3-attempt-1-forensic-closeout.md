# `work-on` A3 attempt 1 forensic closeout

Date: 2026-08-16

Verdict: **INVALID**

This artifact adjudicates the first A3 control-window attempt. It preserves the
difference between what surviving evidence proves, what pull-request bodies
corroborate, and what is unavailable. It does not populate the original
protocol's Results section or certify an exact counted sample.

## Scope and authority

The authoritative sources are:

- the current `faviann/skills` `main` branch at the protocol merge commit;
- issue #64's revised ordered roadmap, resolution-verification amendment, and
  A3 pre-registration comment;
- issue #9 and its A1/C1 ownership comment;
- issue #62's mechanism-neighborhood contract;
- the research packet merged through PR #65;
- merged PRs #66, #67, and #68; and
- [the frozen A3 protocol](work-on-a3-control-window.md).

The revised roadmap and its resolution-verification amendment supersede
conflicting older wording in issue #64's body. A1 belongs to #9, A3 consumes its
telemetry, and B1 remains downstream of a valid, separately accepted A3
control.

## Protocol identity

| Field | Reproduced value |
|---|---|
| Protocol merge commit | `9bc1a6172c704c9b7f2ce6f849789d5152bfd7ff` |
| Commit timestamp in UTC run-id form | `20260814T193632Z` |
| Opening rule | Run id strictly greater than the opening timestamp |
| Frozen-region SHA-256 | `468d2321e15273de61a160e0f1e251635f6f92bd1e74736300d0bd8f92a14557` |
| Expected frozen-region SHA-256 | `468d2321e15273de61a160e0f1e251635f6f92bd1e74736300d0bd8f92a14557` |

The digest was recomputed from the marker lines and every byte between them.
The original protocol artifact is unchanged by this closeout.

## Evidence preservation

The surviving sinks were copied outside all Git worktrees to the owner-only
directory
`/home/faviann/.local/share/work-on-a3-attempt-1-preservation/`. Directories
are mode `0700`; copied sinks, the manifest, and the local report are mode
`0600`.

The `SHA256SUMS` manifest contains one entry for every source sink and one for
its preserved copy. Its SHA-256 is:

`b9f14a84f1e8ef718cd3a0b3f77b60196eb1eaae6835a6c96229ce3521d55724`

All 18 entries passed `sha256sum -c`; each of the nine copies is byte-identical
to its source. Raw JSONL remains private and untracked.

## Preserved sink inventory

| Repository | Run id | Sink SHA-256 |
|---|---|---|
| `faviann/homelab-iac` | `20260814T200522Z-5860eb43` | `3439929f5aa3d425f17afbfb7cd2846a7ae678b4bc96e01740dea3270e04d66c` |
| `faviann/homelab-iac` | `20260814T201131Z-501c84ce` | `191ce3eabfc78fab998ad960e53e592be2ef1995d85b1ce23d3b344a800f5378` |
| `faviann/homelab-iac` | `20260814T201142Z-ae348f0e` | `304e1ac233f1804db52a16789a755f98606d48d339ca036a03298a2a586d06d4` |
| `faviann/homelab-iac` | `20260814T201335Z-ebdea38d` | `56c85dda24a9901ca2ed6ae3262f23454ca58344d4a20f5ee4ba6f3c41b5772d` |
| `faviann/homelab-iac` | `20260814T211832Z-305e545f` | `b18214ec921e0bab6572d740194a5342c63764585f98b97de5a41a1f03746bdc` |
| `faviann/homelab-iac` | `20260814T224810Z-86ba9b4a` | `7bbf7a67bd10b6a38da88f835d420d2169bf1ace8556220cb28f1df2aa23bcc2` |
| `faviann/homelab-iac` | `20260814T235816Z-f5fad826` | `d611167984450f225b352be0c382089e470909bbff7637c69b9d36371e82edce` |
| `faviann/homelab-iac` | `20260815T004338Z-9f193154` | `9f60db6e71c5bcaeb7173afb34afc03d21c0589041d79607d7d408d135b66e9a` |
| `faviann/dotfiles` | `20260816T132643Z-370ae380` | `0619d7b3f743a6fa74dfff3bffeefe23647ed17e98b75e5f91608b8d8ced55c3` |

The local `faviann/overmind` clone is readable, but its telemetry directory is
unavailable. This closeout does not claim that the directory never existed or
that no overmind run occurred. The missing directory prevents a complete
population enumeration and therefore prevents certification of the exact
counted sample.

## Deterministic summaries

The frozen schema-1 summarizer was run twice against every preserved source
sink after reproducing its digest. Each pair of outputs was byte-identical. In
the compact columns below, launch roles are `impl/readiness/standards/spec/closure`;
review kinds are `readiness/full/delta`; validations are
`passed/failed/interrupted/incomplete`; and phases retain their full names.

| Repository | Run | Schema | Started / finished | Outcome | Recorded launches by role | Recorded reviews by kind; bytes | Recorded validations; duration ms | Recorded `phase_elapsed_ms` | Tokens | Malformed / after finish | Remediation | Summary SHA-256 |
|---|---|---:|---|---|---|---|---|---|---|---|---|---|
| homelab-iac | `20260814T200522Z-5860eb43` | 1 | `2026-08-14T20:05:22Z` / `null` | `null` | 0: `0/0/0/0/0` | 0: `0/0/0`; 0 | 0: `0/0/0/0`; 0 | `{}` | `0/0`, none | `0/0` | no | `d5811d8a4e15e01eb609ffd137bbad3020ec0f20c946a9005591b461bb901def` |
| homelab-iac | `20260814T201131Z-501c84ce` | 1 | `2026-08-14T20:11:31Z` / `2026-08-14T22:14:15Z` | Closes | 14: `4/1/3/3/3` | 4: `1/3/0`; 19,368 | 10: `10/0/0/0`; 859,110 | `orient=33681, implementation=0, checkpoint=170062, gate=3863982, remediation=4411077, closeout=829132` | `0/0`, none | `0/0` | yes | `eeaac1244d88ed26993e263b3f350f493b6bba7137662a9e3a0575fd05669b50` |
| homelab-iac | `20260814T201142Z-ae348f0e` | 1 | `2026-08-14T20:11:42Z` / `2026-08-14T20:58:25Z` | aborted | 0: `0/0/0/0/0` | 0: `0/0/0`; 0 | 0: `0/0/0/0`; 0 | `{}` | `0/0`, none | `0/0` | no | `dcf08952dbccc2f304404e03e705f1d1e0ce2bd7eb39d0fd0d6e76174bfe8ad0` |
| homelab-iac | `20260814T201335Z-ebdea38d` | 1 | `2026-08-14T20:13:35Z` / `2026-08-14T20:58:16Z` | aborted | 7: `3/1/1/1/1` | 4: `1/3/0`; 71,805 | 2: `2/0/0/0`; 141,843 | `implementation=0, checkpoint=91742, gate=747, remediation=891316` | `0/0`, none | `0/0` | yes | `f11f9d8becadccd714e762ae44601ce6cd1164714d571ee591e1232a08c2d873` |
| homelab-iac | `20260814T211832Z-305e545f` | 1 | `2026-08-14T21:18:32Z` / `2026-08-14T22:52:25Z` | Closes | 12: `3/0/3/3/3` | 9: `0/9/0`; 308,625 | 8: `7/1/0/0`; 1,618,519 | `checkpoint=74313, gate=2567982, remediation=3499022, closeout=1309520` | `0/0`, none | `0/0` | yes | `f9c727edbb1b37fa28626786a1b6bbf18dde1333a4f834b7f718e9d72e812231` |
| homelab-iac | `20260814T224810Z-86ba9b4a` | 1 | `2026-08-14T22:48:10Z` / `2026-08-14T23:35:27Z` | Closes | 9: `2/1/2/2/2` | 7: `1/6/0`; 22,373 | 10: `10/0/0/0`; 827,187 | `implementation=0, checkpoint=100538, gate=793774, remediation=356467, closeout=523971` | `0/0`, none | `0/0` | yes | `616498be01d938c7dcac3998ab05640a55d4520a82d7582c5e3646d880b92958` |
| homelab-iac | `20260814T235816Z-f5fad826` | 1 | `2026-08-14T23:58:16Z` / `2026-08-15T00:20:18Z` | Closes | 5: `1/1/1/1/1` | 4: `1/3/0`; 4,144 | 4: `4/0/0/0`; 619,693 | `implementation=0, checkpoint=8171, gate=454, closeout=518183` | `0/0`, none | `0/0` | no | `ae5b41a84b42bf395c60b32c2c92471cf03b915d1add09035a72dbce8786d789` |
| homelab-iac | `20260815T004338Z-9f193154` | 1 | `2026-08-15T00:43:38Z` / `2026-08-15T01:21:25Z` | Closes | 9: `2/1/2/2/2` | 7: `1/6/0`; 54,256 | 10: `10/0/0/0`; 748,132 | `orient=21236, implementation=0, checkpoint=42054, gate=522988, remediation=201753, closeout=551558` | `0/0`, none | `0/0` | yes | `5feac97cdff9979790ee583e25e2b719f90f5cf98af795cc5616befb6af6cc69` |
| dotfiles | `20260816T132643Z-370ae380` | 1 | `2026-08-16T13:26:43Z` / `2026-08-16T14:18:03Z` | Closes | 11: `4/1/2/2/2` | 3: `1/2/0`; 34,074 | 5: `5/0/0/0`; 246,197 | `implementation=0, checkpoint=894437, gate=991999, remediation=1892378, closeout=67017` | `0/0`, none | `0/0` | yes | `0da36aa4f7c070e3206fa25a0a1e729c3dd179fc46e50bd958862d07220bd956` |

The dotfiles run started and finished after the latest possible boundary
established by the five surviving finished candidates, so it is out of the
window. The other
dispositions cannot be certified without the unavailable overmind population.

## Observed telemetry-integrity limitations

The tables are deterministic aggregates of surviving recorded events. They do
not prove that every delegation or review was instrumented and are not
certified total resource measurements.

- `20260814T201131Z-501c84ce` records ten review-role launches but four review
  events. `20260816T132643Z-370ae380` records seven review-role launches but
  three review events. Both event types depended on agent-side instrumentation
  without harness corroboration, so neither stream is authoritative; this
  document reports exactly what each contains.
- For `20260814T211832Z-305e545f`, the frozen workflow required a fresh
  readiness sweep, but this run records neither a readiness launch nor a
  readiness review. Surviving evidence cannot establish whether the sweep
  occurred but was unrecorded, or was skipped.
- `20260814T201335Z-ebdea38d` records implementation, review, validation, and
  remediation before resolving to `aborted`. That conflicts with A2's
  documented use of `aborted` as a pre-implementation hand-back, but schema 1
  cannot represent or recover the actual late non-success reason.
- Repository attribution comes from each preserved sink's location. Exact
  Telemetry run rows in PR bodies corroborate issue and PR attribution for the
  successful candidates. The two aborted runs have no mechanically recoverable
  issue or PR identity.

Consequently, launches, reviews, reviewed bytes, validations, and phase timings
are recorded-event observations, not certified complete resource totals. These
limitations affect resource analysis only. They do not weaken the decisive
**INVALID** verdict, which follows independently from the complete absence of
mandatory publication records.

## Provisional reconstruction from surviving evidence

The surviving finished `Closes`/`Progresses` candidates sort as follows by
`(finished_at, run id)`. Exact run-id rows in the PR bodies map each run to its
issue and PR:

| Provisional position | Run | Repository issue | PR | Finished (UTC) | Outcome | Mechanical remediation phase |
|---:|---|---|---:|---|---|---|
| 1 | `20260814T201131Z-501c84ce` | homelab-iac #144 | #150 | `2026-08-14T22:14:15Z` | Closes | yes |
| 2 | `20260814T211832Z-305e545f` | homelab-iac #133 | #151 | `2026-08-14T22:52:25Z` | Closes | yes |
| 3 | `20260814T224810Z-86ba9b4a` | homelab-iac #149 | #152 | `2026-08-14T23:35:27Z` | Closes | yes |
| 4 | `20260814T235816Z-f5fad826` | homelab-iac #148 | #153 | `2026-08-15T00:20:18Z` | Closes | no |
| 5 | `20260815T004338Z-9f193154` | homelab-iac #147 | #154 | `2026-08-15T01:21:25Z` | Closes | yes |

This ordering is **provisional, not certified**. An unavailable overmind sink
could sort before or among these runs and change the exact counted sample. The
table proves only the order of the surviving finished candidates. Within that
provisional order, runs 1, 2, 3, and 5 mechanically contain a `remediation` key
in `phase_elapsed_ms`; PR-body remediation-round values are not used for that
determination.

## PR-body corroboration and frozen surfaces

PRs homelab-iac #150 through #154 contain the exact Telemetry run rows shown
above, schema 1, and `Closes` mappings for issues #144, #133, #149, #148, and
#147 respectively. Dotfiles PR #89 contains the exact row for
`20260816T132643Z-370ae380` and closes issue #81. These bodies corroborate the
sink mappings; they do not replace the sinks or establish remediation.

Every mapped body carries the same repository-independent provenance:
`work-on:6a0c6e912785`, `tdd:aa54f63292bf`, and
`review:1aebe11f115e`, without a dirty suffix, plus the default workflow digest
`87087d1136ae`. Each names `faviann/skills@ceb5c6b14002`.

The four runtime-script digests reproduced both from the current committed
files and from that recorded skills revision:

| Script | Frozen digest |
|---|---|
| `run-telemetry.sh` | `63142a42ec65e069` |
| `render-closeout.sh` | `166d163837f139ea` |
| `validate-closeout-body.sh` | `d6d62761f2dd959b` |
| `workflow-provenance.sh` | `294ad32e787c3b8b` |

The surviving mapped runs therefore reproduce the frozen instruction and
runtime identities. This does not cure the missing record surfaces.

## Dual-surface and chain audit

Mechanical GitHub and git inspection found:

| Frozen obligation | Surviving result |
|---|---|
| `A3-RECORD` or `A3-CORRECTION` comments on issue #64 | none |
| Remote `agent/work-on-a3-results` branch | absent |
| Results PR from that branch | absent |
| Append-only record commits | none; the required branch does not exist |
| Matching comment/commit pairs | none |
| Record-chain continuity from the frozen digest | unavailable; no first record exists |
| Required export before the next listed-repository run | no timely export survives for any run; at least one export obligation necessarily arose |

Surviving telemetry proves that five finished candidates began after the
opening boundary. Their existence guarantees that at least one finished run
created a mandatory export obligation: if unavailable overmind candidates
displaced every surviving candidate, those earlier candidates created the
obligation instead. Every in-window class from `preflight-aborted` through
`counted` required a record commit followed by a matching issue comment before
the next listed-repository run began. No record exists on either surface.
Creating the branch, comments, or commits now could not satisfy the original
deadlines and would fabricate timeliness, so this closeout records the failure
without retroactive repair.

## Verdict

**INVALID — mandatory dual-surface records were not produced at their frozen
deadlines. The exact counted sample is additionally indeterminate because the
overmind telemetry population is unavailable.**

The invalidation does not depend on certifying the five-run sample. Surviving
telemetry contains five finished post-opening candidates. Either at least one
belongs to the exact in-window sample, or unavailable overmind candidates
finished earlier and displaced it; either case necessarily creates at least one
mandatory export obligation. No required record survives on either surface.
Under §9, a missing, late, deleted, or unreproducible record invalidates the
attempt rather than removing the run from the sequence.

The reconstructed surviving telemetry remains useful as forensic and
non-control evidence. It cannot be called the accepted Phase A control. B1
remains blocked. The next roadmap action is a separately pre-registered
replacement A3 control followed by a separate results adjudication and
acceptance step.

## Lessons for a replacement protocol

- Between-run evidence capture cannot depend on a silent manual obligation.
- Capture failure must become immediately visible before another eligible run
  begins.
- Completeness must remain auditable across every listed repository and its
  active worktree git directories.
- The replacement protocol's design and implementation belong to separate
  work; this closeout contains neither.
