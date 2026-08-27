#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/validate-closeout-body.sh"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
prov1='work-on:111111111111 workflow:222222222222 tdd:333333333333 review:444444444444 (unknown@abcdef1)'
prov2='work-on:aaaaaaaaaaaa* workflow:bbbbbbbbbbbb tdd:cccccccccccc review:dddddddddddd (owner/repo@123456789abc)'
body() {
  local outcome="$1" status="$2" entries="$3"
  printf '## Issues\n\n%s #150\n\n## Closure gate\n\n| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |\n|---|---|---|---|---|\n| criterion | script | CLI | passed | %s |\n\n## Work-on\n\n%b\n' "$outcome" "$status" "$entries"
}
body Closes tested "Run opaque_run-1: $prov1" >"$fixture/good"
"$script" 150 "$fixture/good"
sed 's/$/\r/' "$fixture/good" >"$fixture/crlf"; "$script" 150 "$fixture/crlf"
sed 's/$/\r/' "$fixture/good" | "$script" 150 -

reject() { if "$script" "$@" >/dev/null 2>&1; then echo "validator accepted invalid fixture: $*" >&2; exit 1; fi; }
body Progresses tested "Run opaque_run-1: $prov1" >"$fixture/progress"; "$script" 150 "$fixture/progress"; reject --require-closes 150 "$fixture/progress"
sed 's/Closes #150/Closes #151/' "$fixture/good" >"$fixture/wrong-issue"; reject 150 "$fixture/wrong-issue"
sed 's/| tested |/| guessed |/' "$fixture/good" >"$fixture/status"; reject 150 "$fixture/status"
body Closes inferred "Run opaque_run-1: $prov1" >"$fixture/not-tested"; reject 150 "$fixture/not-tested"
sed '/## Work-on/i ## Closure gate\n' "$fixture/good" >"$fixture/duplicate-heading"; reject 150 "$fixture/duplicate-heading"
cat >"$fixture/out-of-order" <<EOF
## Closure gate

| Acceptance criterion | Production path | Exact artifact/mode/seam | Evidence | Status |
|---|---|---|---|---|
| criterion | script | CLI | passed | tested |

## Issues

Closes #150

## Work-on

Run opaque_run-1: $prov1
EOF
reject 150 "$fixture/out-of-order"
sed 's/| criterion | script | CLI | passed | tested |/| criterion | script | CLI | tested |/' \
  "$fixture/good" >"$fixture/malformed-table"
reject 150 "$fixture/malformed-table"
body Closes tested "Run short: $prov1" >"$fixture/bad-id"; reject 150 "$fixture/bad-id"
body Closes tested "Run opaque_run-1: $prov1\nRun opaque_run-1: $prov1" >"$fixture/duplicate-id"; reject 150 "$fixture/duplicate-id"

# Every unchanged heading, issue-mapping, closure-table, and provenance-shape
# branch from the base suite remains discriminating.
for heading in '## Issues' '## Closure gate' '## Work-on'; do
  grep -Fvx "$heading" "$fixture/good" >"$fixture/missing-heading"
  reject 150 "$fixture/missing-heading"
  { cat "$fixture/good"; printf '\n%s\n' "$heading"; } >"$fixture/duplicate-any-heading"
  reject 150 "$fixture/duplicate-any-heading"
done
sed '/Closes #150/a Progresses #150' "$fixture/good" >"$fixture/two-issues"; reject 150 "$fixture/two-issues"
sed 's/Closes #150/Close #150/' "$fixture/good" >"$fixture/bad-outcome"; reject 150 "$fixture/bad-outcome"
sed 's/Closes #150/Closes  #150/' "$fixture/good" >"$fixture/bad-spacing"; reject 150 "$fixture/bad-spacing"
sed 's/| Acceptance criterion | Production path | Exact artifact\/mode\/seam | Evidence | Status |/| wrong | header |/' "$fixture/good" >"$fixture/bad-header"; reject 150 "$fixture/bad-header"
sed 's/|---|---|---|---|---|/|---|---|/' "$fixture/good" >"$fixture/bad-separator"; reject 150 "$fixture/bad-separator"
grep -Fv '| criterion | script | CLI | passed | tested |' "$fixture/good" >"$fixture/no-rows"; reject 150 "$fixture/no-rows"
empty_rows=(
  '|  | script | CLI | passed | tested |'
  '| criterion |  | CLI | passed | tested |'
  '| criterion | script |  | passed | tested |'
  '| criterion | script | CLI |  | tested |'
  '| criterion | script | CLI | passed |  |'
)
for empty_row in "${empty_rows[@]}"; do
  sed "s/| criterion | script | CLI | passed | tested |/$empty_row/" \
    "$fixture/good" >"$fixture/empty-column"
  reject 150 "$fixture/empty-column"
done
for status in tested failing inferred unverified; do
  body Progresses "$status" "Run opaque_run-1: $prov1" >"$fixture/status-$status"
  "$script" 150 "$fixture/status-$status"
done
body Closes tested "Legacy run: $prov1" >"$fixture/legacy-only"; "$script" 150 "$fixture/legacy-only"
for malformed in \
  'Run opaque_run-1: work-on:short workflow:222222222222 tdd:333333333333 review:444444444444 (unknown@abcdef1)' \
  'Run opaque_run-1: work-on:111111111111 workflow:222222222222 tdd:333333333333 review:444444444444 (bad pointer@abcdef1)' \
  'Legacy run: not canonical'; do
  body Closes tested "$malformed" >"$fixture/malformed-provenance"
  reject 150 "$fixture/malformed-provenance"
done
if "$script" --unknown 150 "$fixture/good" >/dev/null 2>&1; then echo 'unknown validator option accepted' >&2; exit 1; fi
if "$script" zero "$fixture/good" >/dev/null 2>&1; then echo 'invalid issue number accepted' >&2; exit 1; fi

body Closes tested "Run opaque_run-1: $prov1\nRun opaque_run-2: $prov2" >"$fixture/appended"
"$script" --previous "$fixture/good" 150 "$fixture/appended"
"$script" --previous "$fixture/good" 150 "$fixture/good"
body Closes tested "" >"$fixture/dropped"; reject --previous "$fixture/good" 150 "$fixture/dropped"
body Closes tested "Run opaque_run-1: $prov2" >"$fixture/rewritten"; reject --previous "$fixture/good" 150 "$fixture/rewritten"
body Closes tested "Run opaque_run-2: $prov2\nRun opaque_run-1: $prov1" >"$fixture/reordered"; reject --previous "$fixture/good" 150 "$fixture/reordered"
body Closes tested "Run opaque_run-1: $prov1\nRun opaque_run-2: $prov2\nRun opaque_run-3: $prov1" >"$fixture/two-appended"; reject --previous "$fixture/good" 150 "$fixture/two-appended"

# The old body is not recursively judged. Only its ordered Run N provenance is
# transformed into the required Legacy prefix.
cat >"$fixture/old" <<EOF
historically invalid current headings

## Closure gate

This is a counterfeit narrative closure gate.

## Work-on

This is old free-form narrative, not mechanical run history.

## Closure gate

historical closure content

## Workflow telemetry
Run 1: $prov1
EOF
body Closes tested "Legacy run: $prov1\nRun opaque_run-2: $prov2" >"$fixture/from-old"
"$script" --previous "$fixture/old" 150 "$fixture/from-old"

echo 'validate-closeout-body black-box scenarios passed'
