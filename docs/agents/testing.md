# Shell tests

Run every shell test suite from the repository root with:

```bash
npm test
```

The npm command delegates to `scripts/run-shell-tests.sh`, so the runner can also be invoked directly. It finds every tracked file named `test-*.sh`, runs all of them, reports each result, and exits nonzero when any suite fails. Adding a tracked suite with that name automatically adds it to the command and CI.

## Suite membership

There is one shell-test set. It includes the repository-level reconciliation suite, `select-issue`'s GitHub digest suite, and every `work-on` suite. Groups would make callers choose a subset and restore the list-maintenance problem this command removes; add them only if measured runtime makes the full set impractical.

## Pull-request policy

The `Shell tests` workflow runs the full set on every pull request, without path filters. Most changes are prose, but skill behavior often spans instructions and scripts, and the current few-minute runtime is cheap enough to keep the trigger simple and complete.

A failing suite fails the `Shell tests` job: it is not advisory and must be green before merge. Repository merge rules should require that check; the workflow deliberately has no `continue-on-error` escape hatch.
