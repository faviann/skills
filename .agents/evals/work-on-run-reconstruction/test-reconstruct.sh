#!/usr/bin/env bash
set -euo pipefail

# Black-box assertions over the reconstruction rule's joins. The rule itself
# queries Moraine, GitHub and git, which no test suite can hold still; its joins
# are pure, and those are what the recorded result reports rates for. A silent
# regression in one of them invalidates RESULT.md without failing anything else.

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RULE="$ROOT/reconstruct.mjs"

# A throwaway repository, so the SHA-resolving assertion depends on nothing about
# this checkout's history or fetch depth.
readonly REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
printf 'one\n' >"$REPO/f"
git -C "$REPO" add f
git -C "$REPO" commit -q -m base
readonly BASE="$(git -C "$REPO" rev-parse HEAD)"
printf 'two\n' >"$REPO/f"
git -C "$REPO" commit -qam head
readonly HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
readonly HEAD_ABBREV="${HEAD_SHA:0:7}"

node --input-type=module <<NODE
import assert from "node:assert/strict";
import {
  commandsOf, programOf, classifyRole, classifyRound,
  resolveComparedFromBrief, resolveSinkEcho, resolveValidations, VERSION,
} from "$RULE";

const codex = (input) => ({
  harness: "codex", tool_name: "exec", tool_phase: "request",
  payload_json: JSON.stringify({ input }),
});

// One Codex tool call may carry several commands: a Promise.all of two
// exec_command calls is one call and two executions.
assert.equal(
  commandsOf(codex('const a = tools.exec_command({cmd:"one"}); const b = tools.exec_command({cmd:"two"});')).length,
  2,
  "both commands in a batched exec program are extracted",
);

// A template literal is captured and is recognisable as a template.
const templated = commandsOf(codex('tools.exec_command({cmd:\`run --role \${role}\`})'));
assert.equal(templated.length, 1, "a template literal cmd is captured");
assert.ok(templated[0].includes("\\\${role}"), "the template is kept, not resolved");

// An apply_patch program is a file write, not a command. Treating it as one is
// how a text match over the corpus acquires a false-positive rate.
assert.deepEqual(commandsOf(codex('const patch = "*** Begin Patch\\\\n*** Update File: x";')), [],
  "a program with no cmd yields no commands");
assert.ok(programOf(codex('const patch = "*** Begin Patch";')), "it is reported as a program instead");

// The sink echo must not count a quoted mention inside an authored document.
assert.equal(
  resolveSinkEcho([codex('const patch = "*** Begin Patch\\\\n+run-telemetry.sh exec --command-id x";')]).length,
  0,
  "a run-telemetry mention inside a patch payload is not an execution",
);
assert.equal(
  resolveSinkEcho([codex('tools.exec_command({cmd:"t.sh launch --role a && t.sh launch --role b"})')]).length,
  0,
  "a bare script name is not the telemetry recorder",
);
assert.equal(
  resolveSinkEcho([codex('tools.exec_command({cmd:"run-telemetry.sh launch --role a && run-telemetry.sh launch --role b"})')]).length,
  2,
  "both recordings chained in one command line are counted",
);

// Roles are classified across the authored spellings both subjects used, and an
// unmatched delegate falls to the sink's own residual rather than being dropped.
for (const [name, role] of [
  ["implementation_138", "implementation"],
  ["issue96_implementation", "implementation"],
  ["readiness_138", "readiness"],
  ["gate_standards_138", "review-standards"],
  ["issue96_standards_confirm4", "review-standards"],
  ["Round 2 spec review", "review-spec"],
  ["issue96_closure_delta3", "closure-sweep"],
  ["eval_n1", "other"],
]) {
  assert.equal(classifyRole(name).role, role, \`\${name} classifies as \${role}\`);
}

// Rounds are recovered where the author wrote one and declined where they did
// not. Declining is the required behaviour: \`_final\` is round 2, not the last.
assert.equal(classifyRound("issue96_standards_r1"), 1);
assert.equal(classifyRound("issue96_spec_delta2"), 2);
assert.equal(classifyRound("issue96_closure_confirm4"), 4);
assert.equal(classifyRound("Round 3 standards review"), 3);
assert.equal(classifyRound("issue96_standards_final"), null, "an unnumbered name recovers no round");
assert.equal(classifyRound("gate_standards_138"), null, "an issue number is not a round");

// A plaintext brief yields the compared candidate: literal base, and the head as
// the last abbreviated SHA in the commit list.
const brief = [
  "The change under review:",
  "  git diff $BASE...HEAD",
  "Commits:",
  "  $HEAD_ABBREV a change under review",
  "",
].join("\\n");
const compared = resolveComparedFromBrief(brief, "$REPO");
assert.ok(compared, "a plaintext brief resolves a compared candidate");
assert.equal(compared.base, "$BASE");
assert.equal(compared.head, "$HEAD_SHA");
assert.equal(compared.head_is_worktree, false);
assert.equal(resolveComparedFromBrief("no diff here", "$REPO"), null);

// An execution's outcome is unknown unless the recorded output carries a status.
// Reporting it as passed would be the single worst failure this rule could have.
const pair = [
  { ...codex('tools.exec_command({cmd:"npm test"})'), session_id: "s", tool_call_id: "c", event_ts: "t", event_unix_ms: 1000 },
  {
    session_id: "s", tool_call_id: "c", tool_phase: "response", harness: "codex",
    event_ts: "t", event_unix_ms: 4000,
    payload_json: JSON.stringify({ moraine_tool_io: { output_json: "Script completed\\nWall time 3.0 seconds" } }),
  },
];
const executions = resolveValidations(pair);
assert.equal(executions.length, 1);
assert.equal(executions[0].outcome, "unknown", "a Script-completed wrapper is not a pass");
assert.equal(executions[0].duration_ms, 3000);

assert.equal(VERSION, "1.0.0");
console.log("work-on run-reconstruction rule assertions passed");
NODE
