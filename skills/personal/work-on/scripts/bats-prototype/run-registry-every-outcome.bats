#!/usr/bin/env bats

load registry-fixture

setup() { setup_registry_fixture; }
teardown() { teardown_registry_fixture; }

@test "registry every-outcome group: Closes finalizes automatically after closeout evidence" {
  repo="$fixture/closes"
  new_repo "$repo"
  handle="$(telemetry "$repo" start --issue 72)"
  registry_in "$repo" register --run "$handle" >/dev/null
  telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
  telemetry "$repo" exec --run "$handle" --command-id registry-tests --phase gate --round 1 -- true
  telemetry "$repo" resolve --run "$handle" --outcome Closes
  telemetry "$repo" exec --run "$handle" --command-id registry-tests --phase closeout --round 1 -- true
  run registry_in "$repo" finalize --run "$handle"
  [[ "$status" -eq 0 && "$output" == "finalized ${handle%@*}" ]]
  assert_field "$handle" finalization finalized
  assert_field "$handle" outcome Closes
  assert_field "$handle" lifecycle sealed
  assert_field "$handle" failure_code null
  [[ "$(telemetry "$repo" summary --run "$handle" | jq -r '.integrity.state')" == valid ]]
}

@test "registry every-outcome group: Progresses finalizes and seals" {
  repo="$fixture/progresses"
  new_repo "$repo"
  handle="$(telemetry "$repo" start --issue 72)"
  registry_in "$repo" register --run "$handle" >/dev/null
  telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
  registry_in "$repo" finalize --run "$handle" --outcome Progresses >/dev/null
  assert_field "$handle" finalization finalized
  assert_field "$handle" outcome Progresses
  assert_field "$handle" lifecycle sealed
}

@test "registry every-outcome group: preflight-aborted finalizes without implementation" {
  repo="$fixture/preflight"
  new_repo "$repo"
  handle="$(telemetry "$repo" start --issue 72)"
  registry_in "$repo" register --run "$handle" >/dev/null
  registry_in "$repo" finalize --run "$handle" --outcome preflight-aborted >/dev/null
  assert_field "$handle" finalization finalized
  assert_field "$handle" outcome preflight-aborted
}

@test "registry every-outcome group: abandoned and failed remain finalizable" {
  for outcome in abandoned failed; do
    repo="$fixture/$outcome"
    new_repo "$repo"
    handle="$(telemetry "$repo" start --issue 72)"
    registry_in "$repo" register --run "$handle" >/dev/null
    telemetry "$repo" launch --run "$handle" --role implementation --phase implementation --round 1
    registry_in "$repo" finalize --run "$handle" --outcome "$outcome" >/dev/null
    assert_field "$handle" finalization finalized
    assert_field "$handle" outcome "$outcome"
  done
}
