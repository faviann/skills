script_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
telemetry_script="$script_root/run-telemetry.sh"
registry_script="$script_root/run-registry.sh"

setup_registry_fixture() {
  fixture="$(mktemp -d)"
  export XDG_STATE_HOME="$fixture/state"
  export XDG_CONFIG_HOME="$fixture/config"
  export HOME="$fixture/home"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME"
  unset WORK_ON_OBSERVER WORK_ON_REGISTRY_CAPACITY
}

teardown_registry_fixture() { rm -rf "$fixture"; }

new_repo() {
  local path="$1"
  git init -q -b main "$path"
  git -C "$path" config user.name 'Registry Test'
  git -C "$path" config user.email registry@example.invalid
  git -C "$path" remote add origin git@github.com:Example/Telemetry.git
  printf 'fixture\n' >"$path/file.txt"
  git -C "$path" add .
  git -C "$path" commit -qm fixture
}

telemetry() { local workdir="$1"; shift; (cd "$workdir" && "$telemetry_script" "$@"); }
registry_in() { local workdir="$1"; shift; (cd "$workdir" && "$registry_script" "$@"); }
record_of() { "$registry_script" status --run "$1"; }
assert_field() {
  local handle="$1" field="$2" expected="$3" observed
  observed="$(record_of "$handle" | jq -r --arg field "$field" '.[$field] // "null"')"
  [[ "$observed" == "$expected" ]] || {
    printf 'run %s has %s=%s, expected %s\n' "$handle" "$field" "$observed" "$expected" >&2
    return 1
  }
}
