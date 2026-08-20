# Issue #60: Bats-core prototype evidence

Date: 2026-08-20
Base: `97afe50aa16a5aa5eedbeb287c3a6cda48f6ab82`
Subject: [`#60 Evaluate Bats-core for shell-script tests`](https://github.com/faviann/skills/issues/60)

## Scope and seams

This is evidence only. It does not adopt Bats, add a dependency, add a runner or
CI job, change production behavior, or decide the follow-up adopt/reject issue.
The prototype uses only the agreed black-box seams: script arguments, stdout,
stderr, exit status, and repository/filesystem state left by
`workflow-provenance.sh` and `run-registry.sh`.

The prototype covers the complete current `test-workflow-provenance.sh` behavior
in 11 named tests. Registry coverage is deliberately bounded to the coherent
**every outcome finalizes** group from `test-run-registry.sh`: Closes,
Progresses, preflight-aborted, and the abandoned/failed pair. Fixture commits,
dirty files, remotes, symlinks, ledgers, and registry records remain explicit in
the test bodies or small fixture files; there is no repository-specific fixture
DSL.

## Prototype result and independent selection

Pinned version: Bats 1.13.0. The Bats project publishes an npm installation
route and identifies npm as an any-OS option in its
[official installation guide](https://bats-core.readthedocs.io/en/stable/installation.html).
The pinned release is recorded in the project's
[official releases](https://github.com/bats-core/bats-core/releases/tag/v1.13.0).

Together:

```text
$ npx --yes bats@1.13.0 skills/personal/work-on/scripts/bats-prototype/workflow-provenance.bats skills/personal/work-on/scripts/bats-prototype/run-registry-every-outcome.bats
1..15
ok 1 capture fingerprints only declared bytes and preserves a frozen canonical value
ok 2 verify rejects changed declared instructions without deleting the frozen ledger
ok 3 verify rejects a missing ledger without printing a canonical value
ok 4 target workflow identity is dirty before commit and clean after commit
ok 5 capture rejects a symlinked declared workflow even when its target is readable
ok 6 unrecognized and hostile skills origins capture with an unknown pointer
ok 7 capture fails when git is unavailable
ok 8 capture rejects a non-Git skills checkout and removes a reachable stale ledger
ok 9 capture rejects a missing declared instruction and leaves no ledger
ok 10 capture rejects directory, broken-symlink, and unreadable target workflows
ok 11 a failed recapture removes the previous run ledger
ok 12 registry every-outcome group: Closes finalizes automatically after closeout evidence
ok 13 registry every-outcome group: Progresses finalizes and seals
ok 14 registry every-outcome group: preflight-aborted finalizes without implementation
ok 15 registry every-outcome group: abandoned and failed remain finalizable
```

One scenario selected and run alone by its descriptive name:

```text
$ npx --yes bats@1.13.0 --filter '^registry every-outcome group: Progresses finalizes and seals$' skills/personal/work-on/scripts/bats-prototype/run-registry-every-outcome.bats
1..1
ok 1 registry every-outcome group: Progresses finalizes and seals
```

Bats documents `--filter` as its name-regex selector in the tool's help, and
1.13.0 also includes negative filtering in its
[first-party changelog](https://github.com/bats-core/bats-core/blob/v1.13.0/docs/CHANGELOG.md#1130---2025-11-07).

## Fault-injection sensitivity

Each test was run alone while the production script it covers contained a
deliberate one-line break. Every test failed. Mutations were applied one at a
time and restored immediately. The broad provenance mutation changed the
declared `work-on` input from `SKILL.md` to `SKILL.missing`; four negative-path
tests that correctly survived that break received a more direct one-line
mutation. The registry mutation changed the one-line `run_outcomes` declaration
to an empty array.

| Named prototype scenario | One-line production break | Isolated result |
| --- | --- | --- |
| capture fingerprints only declared bytes and preserves a frozen canonical value | missing declared `work-on` input | `not ok 1`; unreadable declared input |
| verify rejects changed declared instructions without deleting the frozen ledger | missing declared `work-on` input | `not ok 1`; setup capture failed |
| verify rejects a missing ledger without printing a canonical value | missing declared `work-on` input | `not ok 1`; setup capture failed |
| target workflow identity is dirty before commit and clean after commit | missing declared `work-on` input | `not ok 1`; setup capture failed |
| capture rejects a symlinked declared workflow even when its target is readable | removed the `! -L` regular-file guard | `not ok 1`; expected failure, got status 0 |
| unrecognized and hostile skills origins capture with an unknown pointer | missing declared `work-on` input | `not ok 1`; capture failed |
| capture fails when git is unavailable | checked for `bash` instead of `git` | `not ok 1`; expected `capture requires git`, got the later Git-backed-target diagnostic |
| capture rejects a non-Git skills checkout and removes a reachable stale ledger | missing declared `work-on` input | `not ok 1`; prerequisite capture failed |
| capture rejects a missing declared instruction and leaves no ledger | replaced the declared `mocking.md` input with an existing input | `not ok 1`; expected failure, got status 0 |
| capture rejects directory, broken-symlink, and unreadable target workflows | selected only ordinary non-symlink workflow files | `not ok 1`; expected failure, got status 0 |
| a failed recapture removes the previous run ledger | missing declared `work-on` input | `not ok 1`; initial capture failed |
| registry every-outcome group: Closes finalizes automatically after closeout evidence | empty `run_outcomes` | `not ok 1`; finalization refused |
| registry every-outcome group: Progresses finalizes and seals | empty `run_outcomes` | `not ok 1`; `outcome must be one of:` |
| registry every-outcome group: preflight-aborted finalizes without implementation | empty `run_outcomes` | `not ok 1`; `outcome must be one of:` |
| registry every-outcome group: abandoned and failed remain finalizable | empty `run_outcomes` | `not ok 1`; `outcome must be one of:` |

Representative direct output from the broad provenance mutation:

```text
1..1
not ok 1 capture fingerprints only declared bytes and preserves a frozen canonical value
# expected success, got status 1
# workflow provenance: declared instruction input is unreadable: /tmp/<fixture>/skills-checkout/skills/personal/work-on/SKILL.missing
```

The provenance prototype also uses Bats 1.13.0's `run --separate-stderr` at
every compatible public `capture` or `verify` failure call. Each call asserts
that stdout is empty and checks the exact or required diagnostic on stderr,
matching the original suite's separate `.out`/`.err` contract. Redirecting the
production `fail()` helper to stdout with a transient one-line change made the
focused verify test red:

```text
1..1
not ok 1 verify rejects changed declared instructions without deleting the frozen ledger
# (in test file skills/personal/work-on/scripts/bats-prototype/workflow-provenance.bats, line 63)
#   `[[ -z "$output" ]]' failed
```

Restoring that one line returned all 11 provenance cases to green. The
production file's restored SHA-256 remained the value below.

After restoration, SHA-256 values were identical to their pre-mutation values:

```text
294ad32e787c3b8ba48e3c85495109a186448d9ee43144faf8ad4872eead99f6  workflow-provenance.sh
b5ce5258edbbc0619bebfa0466ff4ba8c1df9ec8cca234ec2308137b630bb1d0  run-registry.sh
```

## Failure diagnostics

A deliberate assertion failure in a copy of the current framework-free
registry suite asked for `finalization=pending` after the Closes flow had
produced `finalization=finalized`. Its complete output was (the run identifiers
are fixture data from that execution):

```text
run registry scenarios
  closes-finalizes-automatically
20260820T035731Z-c4935780-a001
FAIL[closes-finalizes-automatically]: run 20260820T035731Z-c4935780@4a48994810754d4980225ae1a115cd15 has finalization=finalized, expected pending
```

The Bats prototype copy made the same deliberate assertion in the same Closes
flow: the `finalization` field was observed as `finalized` but expected as
`pending`. Its complete output, including Bats' test name, helper and test
locations, failed command, command output, and helper diagnostic, was:

```text
1..1
not ok 1 registry every-outcome group: Closes finalizes automatically after closeout evidence
# (from function `assert_field' in file skills/personal/work-on/scripts/bats-prototype/registry-fixture.bash, line 35,
#  in test file skills/personal/work-on/scripts/bats-prototype/run-registry-every-outcome-diagnostic-copy.bats, line 19)
#   `assert_field "$handle" finalization pending' failed
# 20260820T035734Z-2570145e-a001
# run 20260820T035734Z-2570145e@c94195eefe364cb3a14fdf1e52a901e5 has finalization=finalized, expected pending
```

The useful difference is not better domain prose—both came from the same small
helper style—but automatic test name, source location, failed command, and
one-test selection around that prose.

## Line counts

Counts are physical lines, not averages. For the monolithic provenance
baseline, lines 1–37 and the reused invalid-workflow helper at 255–265 are
classified as shared helper (48); all other lines are individual scenario
material (254). For the bounded registry baseline, the universally executed
harness/helper region before the selected group is lines 1–271; the group's
individual scenario region is 298–350. Lines 272–297 and later, out-of-scope
registry scenarios are excluded. In the Bats files, the complete file-level
region before the first `@test`—including the shebang, `load`, minimum-version
declaration where present, `setup`, `teardown`, and intervening blank lines—is
shared helper material rather than individual-test material.

| Subject | Before: shared fixture/helper | Before: individual tests | After: shared fixture/helper | After: individual tests |
| --- | ---: | ---: | ---: | ---: |
| Provenance, complete suite | 48 | 254 | 56 (48 fixture + 8 Bats file-level) | 195 |
| Registry, “every outcome finalizes” only | 271 | 53 | 44 (37 fixture + 7 Bats file-level) | 52 |

The sums independently match physical line counts: provenance is 302 before
(`wc -l test-workflow-provenance.sh`) and 251 after (`48 + 203` from the two
prototype files); the bounded registry selection is 324 before (`271 + 53`)
and 96 after (`37 + 59` from the two prototype files). For provenance, Bats
reduces individual-test material by 59 lines and the complete compared material
by 51 while shared material grows by 8. For this registry slice, individual
tests shrink by 1 line and complete compared material shrinks by 228; the
extracted helper is much smaller because unrelated observer, collision,
locking, and retention fixtures do not load. This does not predict the helper
size of a full registry conversion.

## Exact install and run commands

No package manifest was changed. These local commands were executed:

```bash
local_prefix=/dev/shm/issue-60-bats-local
mkdir -p "$local_prefix"
npm install --prefix "$local_prefix" --no-save --ignore-scripts bats@1.13.0
"$local_prefix/node_modules/.bin/bats" skills/personal/work-on/scripts/bats-prototype/workflow-provenance.bats skills/personal/work-on/scripts/bats-prototype/run-registry-every-outcome.bats
```

Output began `added 1 package` and the run ended with all 15 `ok` results shown
above.

These CI-shaped commands were also executed locally with
`ISSUE60_RUNNER_TEMP=/dev/shm`; a future GitHub Actions step could bind that
task-specific variable to `${{ runner.temp }}` without changing the commands:

```bash
npm install --prefix "${ISSUE60_RUNNER_TEMP}/issue-60-bats-ci-exact" --no-save --ignore-scripts bats@1.13.0
"${ISSUE60_RUNNER_TEMP}/issue-60-bats-ci-exact/node_modules/.bin/bats" skills/personal/work-on/scripts/bats-prototype/workflow-provenance.bats skills/personal/work-on/scripts/bats-prototype/run-registry-every-outcome.bats
```

Output was `added 1 package` followed by `1..15` and 15 `ok` results. This
documents a command; it does not add a CI job or runner.

## Dependency and portability

- Bats adds one versioned npm package and needs Bash. The official installation
  guide also documents distro packages, Homebrew, source installation, and an
  official Docker image, so npm is not the only distribution route.
- The npm route needs Node/npm and either network access or a populated package
  cache. Pinning `1.13.0` makes the evaluated behavior repeatable, but it also
  creates an explicit update obligation. Bats 1.13.0 reset output variables
  between successive `run` invocations, a detail relevant to relying on its
  capture semantics; see the
  [official 1.13.0 release notes](https://github.com/bats-core/bats-core/releases/tag/v1.13.0).
- Bats itself does not make these subjects portable. The production/test seams
  still require repository tools such as Git, jq, `sha256sum`, and—for the
  registry—`flock`; some full registry fixtures also use Linux `/proc`. The
  bounded prototype deliberately preserves rather than hides those facts.
- The official Docker image is described as minimal and may lack tools a suite
  requires, according to the
  [official installation guide](https://bats-core.readthedocs.io/en/stable/installation.html#running-bats-in-docker).
  It therefore is not a drop-in runner for these scripts without an image layer.

## Existing-suite regression result

All ten existing `skills/personal/work-on/scripts/test-*.sh` files remained
present and passed in one sequential run:

```text
existing_suite_count=10
...
PASS test-afk-skill-loading.sh
PASS test-codex-observation.sh
PASS test-ensure-work-on-label.sh
PASS test-render-closeout.sh
PASS test-run-registry.sh
PASS test-run-telemetry-schema3.sh
PASS test-run-telemetry.sh
PASS test-select-issue-codex.sh
PASS test-validate-closeout-body.sh
PASS test-workflow-provenance.sh
existing_suite_failures=0
```

A diff against the base SHA for both production subjects and every existing
`test-*.sh` path was empty.

## What the evidence does and does not support

The evidence supports these statements:

- Bats 1.13.0 can express the complete provenance suite and the bounded registry
  group without changing production code or crossing the agreed public seams.
- The resulting 15 cases are descriptively named, independently selectable,
  green against current production, and sensitive to deliberate faults,
  including provenance stderr being misdirected to stdout.
- Bats supplies consistent naming, location, failed-command context, and
  filtering while allowing fixture state to remain legible Bash.
- The provenance individual-test material is shorter; the bounded registry
  individual-test material is one line shorter, while its extracted helper is
  dramatically smaller than the monolithic harness it currently loads behind.

The evidence does **not** support these stronger claims:

- It does not show that converting the other nine framework-free files—or the
  rest of the 1,500-line registry suite—would have the same line-count or
  maintenance result.
- It does not measure reviewer time, authoring time, flake rate, CI duration,
  package-security burden, or long-term upgrade cost.
- It does not establish cross-platform success; these executions were on the
  current Linux environment.
- It does not justify deleting, shortening, or replacing any current suite, and
  it is not an adoption decision.

Recommendation for the required follow-up decision: treat Bats as technically
viable but treat whole-repository adoption as unproven. The adopt/reject issue
should link [issue #60](https://github.com/faviann/skills/issues/60), this report,
and explicitly decide whether the provenance readability/selection gain is
worth a runtime dependency before considering any broader conversion.
