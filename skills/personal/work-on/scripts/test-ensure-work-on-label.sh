#!/usr/bin/env bash
set -euo pipefail

# Black-box scenarios for the best-effort `work-on` label. The GitHub boundary
# is a fake `gh` on PATH: it records every invocation verbatim and fails exactly
# where a scenario says it should, so the tests observe the calls the script
# makes rather than the calls it claims to make.

readonly command_under_test="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ensure-work-on-label.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin"
cat >"$fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_CALLS"
stage=other
case "${1:-} ${2:-}" in
  "api --paginate") stage=lookup ;;
  "label create") stage=create ;;
  "pr edit") stage=apply ;;
esac
if [[ ",${GH_FAIL:-}," == *",$stage,"* ]]; then
  printf 'gh: raw diagnostic for %s with token ghp_SHOULD_NOT_LEAK\n' "$stage" >&2
  exit 1
fi
if [[ "$stage" == lookup ]]; then
  cat "$GH_LABELS"
fi
if [[ "$stage" == create ]]; then
  printf '%s\n' "$GH_LABEL_NAME" >>"$GH_LABELS"
fi
exit 0
EOF
chmod +x "$fixture/bin/gh"

export GH_LABEL_NAME=work-on
export PATH="$fixture/bin:$PATH"

run_scenario() {
  local name="$1" labels="$2" fail="$3"
  export GH_CALLS="$fixture/$name.calls"
  export GH_LABELS="$fixture/$name.labels"
  export GH_FAIL="$fail"
  : >"$GH_CALLS"
  printf '%s' "$labels" >"$GH_LABELS"
  set +e
  "$command_under_test" --repository example/skills --pr 42 \
    >"$fixture/$name.out" 2>"$fixture/$name.err"
  scenario_status=$?
  set -e
}

expect_status() {
  local name="$1" expected="$2"
  [[ "$scenario_status" -eq "$expected" ]] || {
    printf 'FAIL[%s]: expected exit %s, got %s\n' "$name" "$expected" \
      "$scenario_status" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  }
}

expect_no_warning() {
  local name="$1"
  [[ ! -s "$fixture/$name.err" ]] || {
    printf 'FAIL[%s]: unexpected diagnostics\n' "$name" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  }
}

expect_warning() {
  local name="$1" stage="$2"
  grep -Fqx \
    "warning: work-on label $stage failed for example/skills#42; closeout remains complete" \
    "$fixture/$name.err" || {
    printf 'FAIL[%s]: expected a bounded %s warning\n' "$name" "$stage" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  }
  # The warning is the whole of what is reported. Raw command output can carry a
  # credential or an unbounded API body and never reaches the operator.
  [[ "$(wc -l <"$fixture/$name.err")" -eq 1 ]] || {
    printf 'FAIL[%s]: warning is not the only diagnostic\n' "$name" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  }
  ! grep -Fq 'ghp_SHOULD_NOT_LEAK' "$fixture/$name.err" || {
    printf 'FAIL[%s]: raw diagnostics reached the warning\n' "$name" >&2
    exit 1
  }
}

expect_call() {
  local name="$1" call="$2"
  grep -Fqx "$call" "$fixture/$name.calls" || {
    printf 'FAIL[%s]: expected call: %s\n' "$name" "$call" >&2
    cat "$fixture/$name.calls" >&2
    exit 1
  }
}

expect_no_call() {
  local name="$1" pattern="$2"
  ! grep -Fq "$pattern" "$fixture/$name.calls" || {
    printf 'FAIL[%s]: unexpected call matching: %s\n' "$name" "$pattern" >&2
    cat "$fixture/$name.calls" >&2
    exit 1
  }
}

readonly create_call='label create work-on --repo example/skills --color 1D76DB --description Pull request created or updated through /work-on'
readonly apply_call='pr edit 42 --repo example/skills --add-label work-on'
readonly lookup_call='api --paginate repos/example/skills/labels --jq .[].name'

# An existing label is used as it stands. Its color and description belong to
# whoever set them, so nothing creates, edits, or forces it.
run_scenario existing $'documentation\nwork-on\nbug\n' ''
expect_status existing 0
expect_no_warning existing
expect_call existing "$lookup_call"
expect_call existing "$apply_call"
expect_no_call existing 'label create'
expect_no_call existing 'label edit'
[[ "$(cat "$fixture/existing.labels")" == $'documentation\nwork-on\nbug' ]] || {
  printf 'FAIL[existing]: the existing label metadata was rewritten\n' >&2
  exit 1
}

# A name that merely contains `work-on` is a different label. Only the exact
# repository-local name counts as present.
run_scenario near-miss $'work-on-legacy\nwork-ons\n' ''
expect_status near-miss 0
expect_no_warning near-miss
expect_call near-miss "$create_call"
expect_call near-miss "$apply_call"

# An absent label is created with the fixed bounded metadata, then applied.
run_scenario absent $'documentation\n' ''
expect_status absent 0
expect_no_warning absent
expect_call absent "$create_call"
expect_call absent "$apply_call"
expect_no_call absent 'label edit'

# A concurrent creator wins the race and fails this create. The exact re-read
# finds the label, so the postcondition holds and nothing warns.
export GH_CALLS="$fixture/concurrent.calls"
export GH_LABELS="$fixture/concurrent.labels"
: >"$GH_CALLS"
printf 'documentation\n' >"$GH_LABELS"
cat >"$fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_CALLS"
case "${1:-} ${2:-}" in
  "api --paginate") cat "$GH_LABELS" ;;
  "label create")
    printf 'work-on\n' >>"$GH_LABELS"
    printf 'gh: label already exists (raw ghp_SHOULD_NOT_LEAK)\n' >&2
    exit 1
    ;;
esac
exit 0
EOF
set +e
"$command_under_test" --repository example/skills --pr 42 \
  >"$fixture/concurrent.out" 2>"$fixture/concurrent.err"
scenario_status=$?
set -e
expect_status concurrent 0
expect_no_warning concurrent
expect_call concurrent "$apply_call"
[[ "$(grep -Fxc "$lookup_call" "$fixture/concurrent.calls")" -eq 2 ]] || {
  printf 'FAIL[concurrent]: the exact label was not re-read after the failed create\n' >&2
  cat "$fixture/concurrent.calls" >&2
  exit 1
}

cat >"$fixture/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_CALLS"
stage=other
case "${1:-} ${2:-}" in
  "api --paginate") stage=lookup ;;
  "label create") stage=create ;;
  "pr edit") stage=apply ;;
esac
if [[ ",${GH_FAIL:-}," == *",$stage,"* ]]; then
  printf 'gh: raw diagnostic for %s with token ghp_SHOULD_NOT_LEAK\n' "$stage" >&2
  exit 1
fi
if [[ "$stage" == lookup ]]; then
  cat "$GH_LABELS"
fi
if [[ "$stage" == create ]]; then
  printf '%s\n' "$GH_LABEL_NAME" >>"$GH_LABELS"
fi
exit 0
EOF

# Each stage's failure warns and returns through the nonblocking path: the
# closeout evidence is already published and must not be undone by a label.
run_scenario lookup-failure $'documentation\n' 'lookup'
expect_status lookup-failure 0
expect_warning lookup-failure lookup
expect_no_call lookup-failure 'label create'
expect_no_call lookup-failure 'pr edit'

run_scenario create-failure $'documentation\n' 'create'
expect_status create-failure 0
expect_warning create-failure create
expect_no_call create-failure 'pr edit'

run_scenario apply-failure $'work-on\n' 'apply'
expect_status apply-failure 0
expect_warning apply-failure apply
expect_call apply-failure "$apply_call"

# The repository and pull request are named explicitly; neither is inferred
# from ambient state, so a missing or malformed one is a caller error rather
# than a best-effort failure.
for bad_args in \
  '--repository example/skills' \
  '--pr 42' \
  '--repository not-a-slug --pr 42' \
  '--repository example/skills --pr 0' \
  '--repository example/skills --pr HEAD'; do
  export GH_CALLS="$fixture/usage.calls"
  export GH_LABELS="$fixture/usage.labels"
  export GH_FAIL=''
  : >"$GH_CALLS"
  : >"$GH_LABELS"
  if "$command_under_test" $bad_args >/dev/null 2>"$fixture/usage.err"; then
    printf 'FAIL[usage]: accepted malformed arguments: %s\n' "$bad_args" >&2
    exit 1
  fi
  [[ ! -s "$fixture/usage.calls" ]] || {
    printf 'FAIL[usage]: called GitHub with malformed arguments: %s\n' "$bad_args" >&2
    exit 1
  }
done

printf 'work-on label black-box scenarios passed\n'
