# Forensic conclusion

The run lasted **3h31m34s** from telemetry start to seal (`10:37:30–14:09:04 UTC`).

The best diagnosis is **3. Investigation was hard, but review/evidence machinery materially multiplied the cost.**

The underlying Redis/Traefik behavior was genuinely nondeterministic and required real experimentation. But the final production change is roughly 12 Compose lines, while about **99% of the final added lines are regression/evidence apparatus**. Five delta gates, three semantic cumulative reviews, one invalid review-package launch, 18 recorded validation executions, and repeated adjudication materially extended the run.

Raw sources:

- [Telemetry JSONL](/home/faviann/repos/homelab-iac/.bare/work-on-telemetry/runs/20260826T103730Z-9b799001.jsonl)
- [Adjudication ledger](/home/faviann/repos/homelab-iac/.bare/worktrees/claude-2/work-on-adjudication.log)
- [Evidence tree](/home/faviann/repos/homelab-iac/.bare/work-on-evidence/20260826T103730Z-9b799001)
- [Review packages](/home/faviann/repos/homelab-iac/.bare/work-on-review/20260826T103730Z-9b799001)

## 1. Candidate and review chain

Base: `93f69bc8044172900952ceda6bf5552bfc7968a3`

| Candidate | Material change | Type | Preceding checkpoint / accepted blocker | Following gate |
|---|---|---|---|---|
| **C0** `3f77efac330c6a81dea0eae452b37d2855f50f2b` — `test: capture Portal Redis recreation behavior (#88)` | Added the first disposable Docker reproduction harness, regression population, and contract tests. | Evidence/test only | Implementation checkpoint plus readiness. Corrected diagnostic-only false failure, missing failure observation, and missing recoverable evidence. | Initial three-axis cumulative |
| `22e55cd94fe125f10606a4c718acd83ba166431b` — `test: prove Portal recreation transitions (#88)` | Asserted Redis identity changes, verified pre-input 404, and failed clearly if Docker was unavailable. | Evidence/test only | Initial cumulative blockers: transition modes could no-op; Docker absence skipped the public population. | Delta r2, `C0..22e55cd` |
| `9902f9abd6f057e304e8c1cb780d9f0eb2a0ac7a` — `test: fail on Redis watch closure (#88)` | Removed the conjunction classifier; asserted the diagnostic failure seam independently. | Evidence/test only | Delta r2 blocker: the prior classifier allowed a closed WatchTree observation. | Delta r3, then fresh cumulative r4 |
| `96211292429198cf0d048472011e9d41fa9067c2` — `fix: gate Traefik on Redis readiness (#88)` | Added Redis health and `service_healthy` dependency; upgraded the harness to use tracked static/file/TLS configuration. | Production and evidence | Cumulative r4 blocker: reduced hand-built CLI did not exercise the pinned repository configuration. Exact-config experiments then reproduced persistent route loss. | Delta r4 |
| `c9bdca70591de3dcd7b22c33cd3565b2e3563aeb` — `test: execute Portal Compose readiness gate (#88)` | Added a real Compose clean-start readiness test and stronger startup-state evidence. | Evidence/test only | Delta r4 blocker: the harness manually imposed ordering but never executed the actual Compose dependency. | Delta r5 |
| `aae1728db8ae3a14c2c78fc0fa0453f64c3607e7` — `test: document Portal recreation non-reproduction (#88)` | Reverted the speculative readiness production change and constructed an actual uncorrected Compose replacement experiment. | Mainly evidence; also reverted production | Delta r5 blockers: misleading scenario name and, more importantly, no candidate/control causal discrimination. | No independent gate; intermediate commit inside the final corrective batch. Its committed focused validation failed. |
| `d9bc7e59aede459812880772f7dcb94d002aa403` — `fix: restart Traefik after Redis recreation (#88)` | Added Redis health plus Compose `restart: true`; built candidate/control evidence around `StartedAt`, health ordering, container identity, and restored routes. | Production and evidence | The `aae1728` experiment’s fourth fixed attempt reproduced partial persistent loss, proving readiness-at-first-start was insufficient. | Delta r8, then fresh cumulative r9 |

### Reviewed anchors and corrective batches

Observed review bases/anchors were:

`C0 3f77ef` → `22e55c` → `9902f9` → `962112` → `d9bc7e`

`c9bdca` was reviewed but was not retained as the base for the final delta. The later experiment invalidated its proposed mechanism, so the final package compared the complete replacement batch from `962112..d9bc7e`.

Corrective batches were:

1. C0 → `22e55c`
2. `22e55c` → `9902f9`
3. `9902f9` → `962112`
4. `962112` → `c9bdca`
5. `962112` → `d9bc7e`, internally including `aae1728`

Fresh semantic cumulative confirmations occurred at:

- C0, after readiness;
- `9902f9`, after clean delta r3;
- `d9bc7e`, after clean delta r8.

Telemetry reports **12 full reviews** because it counts four launches of Standards/Spec/Closure:

- one initial launch with an invalid exact-diff package, stopped before semantic review;
- the corrected initial cumulative review;
- cumulative r4;
- cumulative r9.

Thus `4 × 3 = 12`, but only **three were substantive cumulative reviews**.

It reports **15 delta reviews** because there were five delta gates, each with three axes:

`5 × 3 = 15`.

## 2. Accepted blocker census

Categories: **A** production correctness, **B** harness/reproduction, **C** provenance/direct evidence, **D** repository/testing contract.

The first two were discovered during the implementation checkpoint immediately preceding readiness; I classify them under readiness-stage discovery while retaining that substage.

| # | Stage / axis | Criterion or hard rule | Finding | Correction | Primary cause | Secondary | Category |
|---|---|---|---|---|---|---|---|
| 1 | Readiness, checkpoint/Closure | AC1 incident oracle | Closed WatchTree plus all routes 200 was incorrectly treated as the persistent incident. | C0 | `contract-or-surface` | oracle semantics | B |
| 2 | Readiness, checkpoint/Closure | AC1 bounded observation | Harness raised before writing final route, log, identity, and provenance evidence. | C0 | `contract-or-surface` | failure-path evidence | B, C |
| 3 | Readiness / evidence | Validation-evidence policy | Supplied locator contained telemetry status but no inspectable JUnit/Compose result artifacts. | C0 qualifying rerun | `contract-or-surface` | provenance | C |
| 4 | Initial cumulative / Closure | AC1 controlled transitions | `REDIS_RECREATED` could be a no-op and `INPUT_AFTER_START` could seed early while tests passed. | `22e55c` | `pre-existing-missed` | transition oracle | B |
| 5 | Initial cumulative / Closure | AC1 public Docker seam | Docker absence skipped the whole AC1 population green. | `22e55c` | `pre-existing-missed` | fail-open environment | B, D |
| 6 | Delta r2 / Spec+Closure | Frozen AC1 direct-evidence semantics | The joint/conjunction classifier allowed a closed WatchTree diagnostic. | `9902f9` | `remediation-introduced` | authority reinterpretation | B, D |
| 7 | Final cumulative r4 / Spec | AC1 credible pinned-config reproduction | Reduced CLI omitted tracked static/file/TLS inputs that could affect provider timing. | `962112` | `pre-existing-missed` | `cumulative-only`, proof fidelity | B, D |
| 8 | Delta r4 / Spec+Closure | AC2 production-seam proof | Harness asserted Redis-before-Traefik manually but never executed real Compose `service_healthy`. | `c9bdca` | `remediation-introduced` | production/proof mismatch | A, B, C, D |
| 9 | Delta r5 / Standards | Evidence names must match exercised state | “during provider start” was claimed although Traefik remained stopped during replacement. | `aae1728` batch | `remediation-worsened` | misleading provenance | B, C |
| 10 | Delta r5 / Spec+Closure | AC1–AC2 causal discrimination | Candidate and pre-fix raw transitions were materially identical; the clean Compose test neither replaced Redis nor probed the reproduced routes. | `d9bc7e` | `remediation-worsened` | control/counterfactual gap | A, B, C |

Causal antecedents for remediation-origin findings:

- **#6** came from `22e55c`, implementing the initial cumulative directive to “explicitly classify the joint historical incident outcome.”
- **#8** came from `962112`, whose corrected harness parsed or manually represented the new readiness dependency without executing that Compose behavior.
- **#9 and #10** were worsened by `c9bdca`: it added stopped-state evidence and a real clean-start Compose seam, but retained a concurrency-implying name and proved only clean startup—not replacement recovery.

## 3. Why five delta gates?

| Delta | Accepted blocker? | Following cumulative | Did cumulative find something delta missed? | Classification |
|---|---:|---|---:|---|
| C0→`22e55c` r2 | Yes, #6 | None; remediation continued | — | Delta worked |
| `22e55c`→`9902f9` r3 | No | Cumulative r4 found #7 | Yes | Legitimately cumulative-only relative to this delta; however, the same harness-fidelity issue had also been missed by the earlier initial cumulative review |
| `9902f9`→`962112` r4 | Yes, #8 | None | — | Delta worked |
| `962112`→`c9bdca` r5 | Yes, #9 and #10 | None | — | Delta worked |
| `962112`→`d9bc7e` r8 | No | Cumulative r9 clean | No | Final cumulative reread produced confirmation, not a new defect |

Quantitatively:

- Delta gates found **4 of 10 blockers**.
- Cumulative reviews found **3 of 10**.
- Checkpoint/readiness found **3 of 10**.
- Only one cumulative-after-clean-delta found a blocker: #7.
- There was **no repeated pattern of delta-scope defects escaping delta review and then being caught cumulatively**.

For #105, the result is mainly **B with some A**:

- **B:** Delta review reduced full rereading, but every clean delta still required a fresh three-axis cumulative pass. The final `d9bc7e` cumulative review reread unchanged material and found no distinct defect; its value was independent confirmation.
- **A:** Much of the remaining sequence came from genuine experimental learning.
- **C:** Little evidence. There was no recurring true delta-miss pattern.
- **D:** Only in the broad sense that one cumulative-only defect had been missed by the earlier full review.

Serial remediation remained—five delta gates—but the old “fresh cumulative after every blocker” pathology did not fully return.

## 4. Rejected-finding churn

The ledger contains exactly **19 `REJECT` adjudication entries**. These are already partly collapsed across axes, so 19 is not equivalent to 19 independent mechanisms.

At mechanism-family granularity there were approximately **seven unique rejected concerns**:

1. Diagnostic-only WatchTree should fail by itself.
2. Abstraction/duplication/style demands in the large harness.
3. AC6 closeout validation was missing during candidate review.
4. Protected routes needed live Authentik behavior.
5. `MISSING_PROVIDER_INPUT` was scope creep.
6. Raw attempt artifacts were absent.
7. The final control should isolate restart separately from readiness.

The remaining **12 entries were repeats or variants**, principally:

- AC6 closeout timing: **7 total entries**, one concern plus six re-raises.
- Diagnostic-only WatchTree semantics: **2 rejected entries**, later revisited under changed authority analysis.
- Repeated-switch/duplication/dispatcher/helper abstraction concerns: **6 entries** across evolving versions of the same large proof mechanism.

Several ledger lines also combine duplicate reports from Spec and Closure within one gate, including WatchTree semantics, AC6 timing, and `MISSING_PROVIDER_INPUT`.

Purely advisory/style/refactor concerns included repeated switches, duplicated code, `_start_redis`, dispatcher structure, and the final 861-line harness duplication concern.

Concerns that required nontrivial investigation before rejection were:

- WatchTree semantics;
- whether live protected-auth behavior was required;
- whether raw artifacts actually existed;
- whether the control’s removal of both readiness and restart defeated discrimination.

The seven AC6 re-raises were mostly cheap for the primary to reject because the rationale was sticky, but they still consumed reviewer reading and report space. Closure-agent sessions across the run totalled about **35 agent-minutes**; it is not possible to isolate how many of those minutes were AC6 re-adjudication, so attributing the whole amount would be misleading.

## 5. Proof apparatus versus production mechanism

Final diff:

- 4 files
- `+1208/-1`
- approximately 12 changed Compose lines
- 1,196 added test/harness lines

Approximately **99% of added lines were proof apparatus**, not production configuration.

Approximate blocker distribution, allowing overlap:

- Harness/reproduction correctness: #1, #4, #5, #6, #7, #9 — **6**
- Direct evidence/provenance: #2, #3, with substantial overlap in #8–#10
- Production causal correctness: #8 and #10 — **2**
- Ordinary production-code review: no separate final Compose defect was accepted after `d9bc7e`

The seven commits break down as:

- Production-bearing: `962112`, `d9bc7e`
- Production revert plus experiment: `aae1728`
- Primarily proof/test evolution: C0, `22e55c`, `9902f9`, `c9bdca`, and most of `aae1728`

**No: the final production mechanism probably would not inherently have required seven committed candidates.** Most transitions were proof-instrument evolution. Without the evidence/review machinery, the mechanism likely would have occupied one or two production commits—although discovering which mechanism was correct still required the replacement experiment.

## 6. Validation chronology

“Invalidated” below means invalidated as qualification for the eventual final candidate, not that the historical observation became false.

| # | Seam / candidate | Phase | Duration | Result | Purpose and later status |
|---|---|---|---:|---|---|
| e001 | Focused, pre-C0 worktree | Checkpoint r1 | 46.9s | Fail | Initial candidate/harness failure: diagnostic-only recovery was misclassified. Corrected; not reusable green evidence. |
| e002 | Focused, corrected pre-C0 | Checkpoint r2 | 59.9s | Pass | Verified checkpoint corrections. Superseded because readiness required retained raw/JUnit evidence. |
| e003 | Compose config, pre-C0 | Checkpoint r2 | 0.35s | Pass | Render check. Superseded by later changes. |
| e004 | Focused, C0-equivalent | Checkpoint r2 | 56.6s | Pass | Readiness-requested rerun with JUnit/raw evidence. Qualifying C0 evidence. |
| e005 | Compose config, C0-equivalent | Checkpoint r2 | 0.32s | Pass | Qualifying C0 render. |
| e006 | Focused, `22e55c` | Remediation r2 | 87.1s | Pass | Proved corrected transition assertions. Later code changes superseded it. |
| e007 | Focused, `9902f9` | Remediation r3 | 92.0s | Pass | Proved independent diagnostic oracle. Later superseded. |
| e008 | Focused, `962112` | Remediation r4 | 94.2s | Pass | Exact-config/readiness candidate. Later shown causally insufficient. |
| e009 | Compose config, `962112` | Remediation r4 | 0.22s | Pass | Rendered readiness dependency. Later superseded. |
| e010 | Focused, `c9bdca` | Remediation r5 | 110.4s | Pass | Proved clean Compose startup, but not replacement recovery. Superseded. |
| e011 | Compose config, `c9bdca` | Remediation r5 | 0.32s | Pass | Render check. Superseded. |
| e012 | Focused, `aae1728` | Remediation r7 | 171.4s | Fail | Actual candidate failure: attempt 04 reproduced Immich 404 after replacement. Crucial negative/causal evidence, but not a qualifying final result. |
| e013 | Focused, `d9bc7e` | Remediation r8 | 181.4s | Pass | Final candidate/control causal proof. Qualifying reusable evidence. |
| e014 | Compose config, `d9bc7e` | Remediation r8 | 0.28s | Pass | Final render. Qualifying. |
| e015 | Closure diff check, `d9bc7e` | Remediation r8 | 0.05s | Pass | Independent closure reviewer check. |
| e016 | Compose version, `d9bc7e` | Closeout | 0.24s | Pass | Recorded Compose 5.5.0 identity for restart-sensitive evidence. |
| e017 | `./validate.sh`, `d9bc7e` | Closeout | **28m11s** | Pass | Mandatory full handoff gate. Qualifying final evidence. |
| e018 | Final `git diff --check`, `d9bc7e` | Closeout | 0.11s | Pass | Mandatory final whitespace check. |

Recorded validation runtime: **43m13s**.

Top consumers:

1. `./validate.sh`: **28m11s**, 65% of recorded validation time
2. Final focused candidate/control test: **3m01s**
3. Failed `aae1728` reproduction: **2m51s**
4. `c9bdca` focused test: **1m50s**

Conclusions:

- `./validate.sh` ran **exactly once**, at Closeout.
- No full expensive validation was run prematurely under the #129 failure mode.
- Both failures were actual candidate/harness failures, not ceremonial RED executions.
- e012 became a valuable discriminator, but it was still a real failed candidate execution.
- e002/e004 were duplicate focused runs, justified by readiness’s demand for retained JUnit/raw evidence.
- e015/e018 duplicated the diff check, but for distinct owners/phases: closure review and mandatory final closeout.

The evidence tree contains roughly **50 run directories** and nine retained JUnit files, so the 18 telemetry executions materially undercount development experiments.

## 7. Agent and wall-time accounting

Moraine found **30 matching sessions** in this repository and time window:

- one root;
- one implementation delegate;
- one readiness reviewer;
- 27 Standards/Spec/Closure reviewers.

That exactly matches root plus the telemetry’s **29 subagent launches**. No additional semantic reader or hidden evaluator session was found.

| Role | Sessions | Session-span aggregate | Input tokens | Cache-read tokens | Output tokens |
|---|---:|---:|---:|---:|---:|
| Primary | 1 | 3h33m44s | 48.57M | 47.91M | 106.6K |
| Implementation | 1 | 2h41m24s | 39.97M | 39.42M | 136.2K |
| Readiness | 1 | 3m56s | 0.73M | 0.66M | 9.2K |
| Standards | 9 | 20m38s aggregate | 4.78M | 4.22M | 44.8K |
| Spec | 9 | 24m59s aggregate | 5.98M | 5.32M | 55.4K |
| Closure | 9 | 34m58s aggregate | 8.88M | 8.06M | 76.8K |

Total Moraine capture-derived usage:

- Input: **108.90M**
- Cache read: **105.60M**
- Output: **428.9K**

These are session event sums, not necessarily billable-token accounting. Session spans also include waiting and follow-up gaps.

Chronology:

- Root: `10:37–14:10`
- Implementation: `10:42–13:24`
- Readiness: `11:01–11:05`
- Invalid initial full launch: about `11:11`
- Corrected initial cumulative: `11:13–11:19`
- Delta r2: `11:33–11:37`
- Delta r3: `11:43–11:47`
- Cumulative r4: `11:48–11:52`
- Delta r4: `12:16–12:20`
- Delta r5: `12:31–12:38`
- Delta r8: `13:29–13:33`
- Cumulative r9: `13:35–13:40`
- Full closeout validation: `13:40–14:08`

Review/readiness wall windows total approximately **41 minutes**, while parallel reviewer session spans total roughly **84 agent-minutes**.

The top three wall-time centers were:

1. Harness/experiment/causal-discrimination work, spanning roughly `10:42–13:24`
2. Nine three-axis review sets plus readiness, about 41 serialized wall minutes
3. Final `./validate.sh`, 28m11s

## 8. Production-discovery turning point

`962112` solved a plausible but narrower problem: it prevented Traefik’s **first start** until Redis became healthy.

The decisive delta-r5 finding was that this did not distinguish the actual failure:

- The raw pre-fix and candidate route experiments both created Traefik stopped.
- Both replaced Redis and waited for readiness.
- Both then started Traefik.
- The “candidate” harness mostly parsed the newly added dependency.
- The real Compose seam proved only a clean health-gated start.
- It neither replaced Redis nor probed the reproduced routes.

So candidate success could have been nondeterministic non-recurrence rather than an effect of the production change.

That checkpoint forced the actual uncorrected replacement experiment in `aae1728`. Three early fixed attempts recovered automatically, provisionally suggesting non-reproduction. But committed attempt 04 then produced:

- closed WatchTree;
- changed Redis identity;
- unchanged Traefik identity;
- Docker/Bazarr/Jellyfin 200;
- Immich still 404 after 30 seconds.

That proved startup readiness alone was insufficient. The final mechanism therefore used Compose’s Redis dependency with `restart: true`, causing an automatic in-place Traefik process restart after Redis recreation/readiness. Candidate evidence showed `StartedAt` advanced and all routes recovered; the pre-fix control left routes missing.

Could the causal question have been asked earlier? **Conceptually, yes.** The original issue required the fix to be tied to the reproduced mechanism, so a pre-fix/candidate counterfactual should have been demanded when the readiness fix was first proposed.

Could it have been answered convincingly earlier? **Probably not before the exact-config and real-Compose harness existed.** The pinned configuration, observable replacement choreography, identities, route probes, and nondeterministic fourth-attempt reproduction were necessary experimental learning.

This was therefore a mixture:

- a workflow sequencing miss: readiness was committed before causal discrimination;
- genuine experimental necessity: the relevant race became observable only after substantial harness work and repeated fixed-population trials.

## 9. Bottom-line attribution

A necessarily approximate, mutually exclusive allocation of the 211.6-minute run is:

| Cost center | Approximate share | Approximate wall time |
|---|---:|---:|
| A. Environment/race reproduction | 18% | 38m |
| B. Actual production design | 7% | 15m |
| C. Recorded validation runtime | **20%** | **43m** |
| D. Evidence/harness construction | 24% | 51m |
| E. Baseline review fan-out | 10% | 21m |
| F. Repeated review-chain transitions | 9% | 19m |
| G. Rejected/re-raised adjudication | 4% | 8m |
| H. Packaging/orchestration/other | 8% | 17m |

Only validation time is directly measured. The other allocations are constrained estimates because implementation, experimentation, review, and command runtime overlapped.

The dominant mechanism was:

> A nondeterministic infrastructure race required a large disposable causal-proof system; the three-axis delta/cumulative topology then repeatedly reviewed that rapidly evolving proof system.

That supports diagnosis **3**, not diagnosis 4. Serial remediation existed, but #105 did prevent a fresh cumulative reread after every blocking delta. The remaining topology still multiplied cost through five delta gates, a mandatory final cumulative confirmation, and one invalid full-review launch.

## Strongest evidence

1. The final diff is approximately **99% proof/test lines**, and five of seven committed candidates were proof-dominant.
2. Raw evidence shows about **50 experiment directories**, 18 telemetry validations totaling 43m13s, and a crucial failure only on fixed attempt 04.
3. Moraine shows root plus **29 actual subagents**, about 41 review wall minutes and 84 parallel reviewer agent-minutes; the final cumulative reread found no new blocker.

## Biggest remaining uncertainties

1. Moraine’s token sums and first-to-last session spans include caching and idle/follow-up gaps; they are not exact active-effort or billing measurements.
2. Many development experiments were not represented in the 18 validation events, so their exact durations cannot be reconstructed.
3. Because the race was nondeterministic, it is unknowable whether an earlier causal Compose harness would have reproduced immediately or still required the readiness detour and multiple attempts.

## What the #107 pilot controller should know

- Classify the production-discovery mechanism primarily as **`nondeterministic-environmental`**, with substantial **`contract-or-surface`** proof cost.
- Preserve the individual `remediation-introduced` and `remediation-worsened` labels for blockers #6, #8, #9, and #10; do not label every adjacent discovery remediation-caused.
- Treat the first three-axis “full review” as a packaging failure, not a semantic cumulative review.
- Do not use the telemetry’s 18 validations as the total experiment count; the raw evidence tree shows materially more work.
- #105 partly worked: it prevented cumulative review after each blocked delta, but the delta→cumulative pair and three-axis fan-out still imposed substantial cost.
- This P3 run is poor evidence for a simple fixed review-floor estimate. It is strong evidence about proof-heavy nondeterministic work and topology amplification.
