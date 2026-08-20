source_skill_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup_provenance_fixture() {
  fixture="$(mktemp -d)"
  skills_checkout="$fixture/skills-checkout"
  mkdir -p "$skills_checkout/skills/personal" "$skills_checkout/skills/engineering"
  cp -R "$source_skill_root/.." "$skills_checkout/skills/personal/work-on"
  cp -R "$source_skill_root/../../../engineering/tdd" "$skills_checkout/skills/engineering/tdd"
  cp -R "$source_skill_root/../../../engineering/code-review" "$skills_checkout/skills/engineering/code-review"
  git -C "$skills_checkout" init -q -b main
  git -C "$skills_checkout" config user.name 'Provenance Test'
  git -C "$skills_checkout" config user.email provenance@example.invalid
  git -C "$skills_checkout" add .
  git -C "$skills_checkout" commit -qm fixture
  git -C "$skills_checkout" remote add origin https://github.com/example/skills.git
  command_under_test="$skills_checkout/skills/personal/work-on/scripts/workflow-provenance.sh"
  skills_ledger="$skills_checkout/.git/work-on-provenance.json"
}

teardown_provenance_fixture() {
  rm -rf "$fixture"
}

capture_in() { (cd "$1" && "${2:-$command_under_test}" capture); }
verify_in() { (cd "$1" && "${2:-$command_under_test}" verify); }
component_value() { sed -n "s/.*$2:\\([^ ]*\\).*/\\1/p" <<<"$1"; }

make_target_checkout() {
  target_checkout="$fixture/target-checkout"
  git init -q -b main "$target_checkout"
  git -C "$target_checkout" config user.name 'Provenance Test'
  git -C "$target_checkout" config user.email provenance@example.invalid
  mkdir -p "$target_checkout/docs"
  printf '# Target workflow\n' >"$target_checkout/docs/workflow.md"
  git -C "$target_checkout" remote add origin git@github.com:example/target.git
}

assert_success() {
  [[ "$status" -eq 0 ]] || { printf 'expected success, got status %s\nstdout: %s\nstderr: %s\n' "$status" "$output" "${stderr:-}" >&2; return 1; }
}

assert_failure() {
  [[ "$status" -ne 0 ]] || { printf 'expected failure, got status 0\nstdout: %s\nstderr: %s\n' "$output" "${stderr:-}" >&2; return 1; }
}

assert_stderr_contains() {
  [[ "$stderr" == *"$1"* ]] || { printf 'expected stderr to contain: %s\nactual: %s\n' "$1" "$stderr" >&2; return 1; }
}
