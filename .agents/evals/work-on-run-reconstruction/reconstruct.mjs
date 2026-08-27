#!/usr/bin/env node
// Reconstruct one /work-on run's sink-recorded facts from Moraine, GitHub and git.
//
// Evidence tooling for faviann/skills#143 under Map #142. Read-only against all
// three sources: it never writes to a sink, a registry, or a published body.
//
// Every join this performs is a numbered rule with stated assumptions. Nothing
// here is decided by judgement at run time; where a rule is heuristic it says so
// in its own output rather than in prose somewhere else.

import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

const VERSION = "1.0.0";
const SELF_DIGEST = crypto
  .createHash("sha256")
  .update(fs.readFileSync(new URL(import.meta.url)))
  .digest("hex");

// ---------------------------------------------------------------------------
// The sink's own field inventory, from references/run-telemetry.md. The rule is
// answerable to this list: every field here gets a verdict, recovered or not.
// ---------------------------------------------------------------------------
const SINK_FIELDS = [
  "run_start.workflow", "run_start.repository", "run_start.issue",
  "run_start.head", "run_start.run_identity", "run_start.continues_run",
  "subagent_launch.role", "subagent_launch.phase", "subagent_launch.round",
  "subagent_launch.tokens_in", "subagent_launch.tokens_out",
  "review_delegation.role", "review_delegation.kind", "review_delegation.phase",
  "review_delegation.round", "review_delegation.base", "review_delegation.head",
  "review_delegation.head_is_worktree", "review_delegation.input_bytes",
  "validation_start.exec_id", "validation_start.command_id",
  "validation_start.phase", "validation_start.round",
  "validation_end.outcome", "validation_end.exit_status",
  "validation_end.duration_ms",
  "outcome_resolved.outcome",
  "run_sealed",
  "envelope.schema", "envelope.run", "envelope.seq", "envelope.at",
  "envelope.epoch_ms", "envelope.type",
];

const ROLE_VOCABULARY = [
  // [regexp over the authored delegate name or brief, sink role, event type]
  [/\b(impl|implementation|implement)\b/i, "implementation", "subagent_launch"],
  [/\b(readiness|readiness[-_ ]?sweep|preflight)\b/i, "readiness", "review_delegation"],
  [/\b(standards)\b/i, "review-standards", "review_delegation"],
  [/\b(spec|specification)\b/i, "review-spec", "review_delegation"],
  [/\b(closure|closure[-_ ]?sweep|closeout[-_ ]?sweep)\b/i, "closure-sweep", "review_delegation"],
];

const SHA = /\b[0-9a-f]{40}\b/g;

// R3b — the round, where the authored name or brief happens to say it. Nothing
// in either harness records a round; the workflow authors it, and whether it
// survives into the corpus depends entirely on how the primary chose to name
// and brief its delegate. Reported per subject, never assumed.
const ROUND_PATTERNS = [
  /\bround\s*(\d+)\b/i,
  /\b(?:gate|remediation)\s*(\d+)\b/i,
  /\b(?:r|delta|confirm)(\d+)\b/i,
];

function classifyRound(text) {
  if (!text) return null;
  const separated = text.replace(/[^A-Za-z0-9]+/g, " ");
  for (const pattern of ROUND_PATTERNS) {
    const match = pattern.exec(separated);
    if (match) return Number(match[1]);
  }
  return null;
}

function fail(message) {
  process.stderr.write(`reconstruct: ${message}\n`);
  process.exit(2);
}

function run(bin, args, opts = {}) {
  return execFileSync(bin, args, {
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 1024,
    ...opts,
  });
}

function parseArgs(argv) {
  const out = { harness: "auto", windowHours: 96, repoPath: process.cwd() };
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const value = argv[i + 1];
    switch (flag) {
      case "--repo": out.repo = value; i += 1; break;
      case "--pr": out.pr = Number(value); i += 1; break;
      case "--harness": out.harness = value; i += 1; break;
      case "--repo-path": out.repoPath = value; i += 1; break;
      case "--sink": out.sink = value; i += 1; break;
      case "--window-hours": out.windowHours = Number(value); i += 1; break;
      case "--out": out.out = value; i += 1; break;
      default: fail(`unknown argument ${flag}`);
    }
  }
  if (!out.repo || !out.pr) {
    fail("usage: reconstruct.mjs --repo OWNER/NAME --pr N [--harness codex|claude-code] [--repo-path DIR] [--sink FILE] [--out FILE]");
  }
  return out;
}

// ---------------------------------------------------------------------------
// Source adapters. Moraine is the layer-1 retrieval path; gh and git are layer 2.
// ---------------------------------------------------------------------------
let MORAINE_COLUMNS = null;
function moraineColumns() {
  if (MORAINE_COLUMNS) return MORAINE_COLUMNS;
  const schema = JSON.parse(run("moraine", ["schema", "analytics", "--json"]));
  MORAINE_COLUMNS = schema.columns.map((c) => c.name).join(",");
  return MORAINE_COLUMNS;
}

function moraine(filters) {
  const args = [
    "export", "events", "--format", "jsonl", "--all", "--include-sensitive",
    "--columns", moraineColumns(), ...filters,
  ];
  const text = run("moraine", args, { stdio: ["ignore", "pipe", "ignore"] });
  return text.split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

function gh(args) {
  return JSON.parse(run("gh", args));
}

function git(repoPath, args) {
  try {
    return run("git", ["-C", repoPath, ...args]);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Harness adapters. Everything provider-specific is confined to these two, so
// the rules below read the same shape whichever harness produced the run.
// ---------------------------------------------------------------------------
function sessionMeta(row) {
  if (row.event_kind !== "session_meta") return null;
  try {
    return JSON.parse(row.payload_json);
  } catch {
    return null;
  }
}

// Every top-level shell command a row requested, with the caveat that one Codex
// `exec` tool call may carry several commands: its input is a JS program, and a
// `Promise.all` of two `exec_command` calls is one tool call and two executions.
function commandsOf(row) {
  if (row.tool_phase !== "request") return [];
  let payload;
  try {
    payload = JSON.parse(row.payload_json);
  } catch {
    return [];
  }
  if (row.harness === "claude-code") {
    const command = payload?.input?.command;
    return typeof command === "string" ? [command] : [];
  }
  if (row.tool_name !== "exec") return [];
  const input = typeof payload.input === "string" ? payload.input : "";
  const found = [];
  // Two literal forms. A Codex `exec` input is a JavaScript program, so `cmd`
  // may be a double-quoted string or a template literal — and a template literal
  // may interpolate, in which case the corpus holds the program and never the
  // command line it ran. Those are captured and marked, not silently treated as
  // commands.
  const quoted = /"?cmd"?\s*:\s*"((?:[^"\\]|\\.)*)"/g;
  let match;
  while ((match = quoted.exec(input)) !== null) {
    try {
      found.push(JSON.parse(`"${match[1]}"`));
    } catch {
      found.push(match[1]);
    }
  }
  const templated = /"?cmd"?\s*:\s*`((?:[^`\\]|\\.)*)`/g;
  while ((match = templated.exec(input)) !== null) {
    found.push(match[1]);
  }
  // A Codex `exec` input with no `cmd` is not a shell command at all — an
  // `apply_patch` program is a file write. Returning its text as a command is
  // how a pattern match over "command lines" acquires a false-positive rate:
  // a review package that quotes `run-telemetry.sh exec` in its prose would be
  // counted as an execution. On subject 2 that was 5 of 61.
  return found;
}

// The non-shell tool programs, kept separate. These are where the workflow's own
// authored artifacts appear in the corpus.
function programOf(row) {
  if (row.tool_phase !== "request" || row.harness === "claude-code") return null;
  if (row.tool_name !== "exec") return null;
  try {
    const input = JSON.parse(row.payload_json).input;
    return typeof input === "string" && !/"?cmd"?\s*:/.test(input) ? input : null;
  } catch {
    return null;
  }
}

function outputOf(row) {
  try {
    const payload = JSON.parse(row.payload_json);
    return payload?.moraine_tool_io?.output_json ?? "";
  } catch {
    return "";
  }
}

// ---------------------------------------------------------------------------
// R1 — a pull request resolves to its primary session.
//
// Anchor: the primary is the only agent authorised to mutate GitHub, so the
// session that ran `gh pr create ... --head <headRefName>` for this PR is the
// primary. This anchor is authored by the workflow's authority invariant, not by
// the sink, so it survives the sink's deletion.
//
// Assumptions:
//  a. the PR was opened from the run, by `gh` in a recorded tool call;
//  b. the branch name is on the create command line (`--head`, or a preceding
//     `git push -u origin <branch>` in the same command);
//  c. for a harness with session ancestry, the primary is that session's root.
// Corroborator (Codex only): a session_meta whose git.repository_url is this
// repository and whose git.branch is the PR's head branch.
// ---------------------------------------------------------------------------
function resolvePrimary(ctx) {
  const { pr, repo, windowHours } = ctx;
  const created = new Date(pr.createdAt);
  const since = new Date(created.getTime() - windowHours * 3600 * 1000).toISOString();
  const until = new Date(created.getTime() + 3600 * 1000).toISOString();
  const name = repo.split("/")[1];

  const rows = moraine(["--since", since, "--until", until, "--tool-name", "exec"])
    .concat(moraine(["--since", since, "--until", until, "--tool-name", "Bash"]));

  const anchors = [];
  for (const row of rows) {
    for (const command of commandsOf(row)) {
      if (!command.includes("gh pr create")) continue;
      const headNamed = command.includes(`--head ${pr.headRefName}`)
        || command.includes(`--head '${pr.headRefName}'`)
        || command.includes(`--head "${pr.headRefName}"`)
        || command.includes(`origin ${pr.headRefName}`);
      const repoNamed = command.includes(repo) || command.includes(name)
        || !command.includes("--repo");
      if (headNamed && repoNamed) {
        anchors.push({ session_id: row.session_id, harness: row.harness, at: row.event_ts, command });
      }
    }
  }

  const metas = moraine(["--since", since, "--until", until, "--event-kind", "session_meta"])
    .map((row) => ({ row, meta: sessionMeta(row) }))
    .filter((entry) => entry.meta);
  const metaBySession = new Map(metas.map((entry) => [entry.row.session_id, entry.meta]));

  const roots = new Set();
  for (const anchor of anchors) {
    let id = anchor.session_id;
    const seen = new Set();
    while (metaBySession.get(id)?.parent_thread_id && !seen.has(id)) {
      seen.add(id);
      id = metaBySession.get(id).parent_thread_id;
    }
    roots.add(id);
  }

  const corroborating = metas
    .filter((entry) => (entry.meta.git?.repository_url ?? "").includes(repo)
      && entry.meta.git?.branch === pr.headRefName)
    .map((entry) => entry.meta.parent_thread_id ?? entry.row.session_id);

  const primary = [...roots][0] ?? null;
  return {
    rule: "R1",
    deterministic: false,
    primary_session_id: primary,
    harness: anchors[0]?.harness ?? metaBySession.get(primary)?.originator ?? "unknown",
    anchors: anchors.map((a) => ({ session_id: a.session_id, at: a.at })),
    candidate_roots: [...roots],
    corroborating_branch_roots: [...new Set(corroborating)],
    assumptions: [
      "the primary opened the PR itself, from a recorded tool call",
      "the PR head branch appears on that command line",
      "session ancestry lifts the anchor to the run's root session",
    ],
    breaks_when: [
      "the PR is opened from the GitHub web UI, by a script outside the harness, or in a later session",
      "one session opens several PRs (observed: a Claude Code session that opened three)",
      "a branch name is reused across runs inside the query window",
    ],
    window: { since, until },
  };
}

// ---------------------------------------------------------------------------
// R2 — a primary session resolves to its delegate sessions.
//
// Codex: an exact two-key join, not timestamp proximity. `spawn_agent` returns
// the authored `task_name`, and the child's `session_meta` carries both
// `agent_path` (`/root/<task_name>`) and `parent_thread_id`. Matching on the
// pair is deterministic for any run whose task names are distinct.
//
// Claude Code: the delegate has no session of its own. Its events are in the
// parent session with `is_substream` set and an `agent_run_id` Moraine
// projects. The launch-to-substream join is by stream order: the first event
// bearing an unseen `agent_run_id` after an `Agent` request belongs to it.
// ---------------------------------------------------------------------------
function resolveDelegatesCodex(primaryId, primaryRows, since, until) {
  const spawns = [];
  for (const row of primaryRows) {
    if (row.tool_phase !== "request") continue;
    if (row.tool_name !== "spawn_agent" && row.tool_name !== "followup_task") continue;
    let args = {};
    try {
      args = JSON.parse(JSON.parse(row.payload_json).arguments ?? "{}");
    } catch { /* an unparseable launch is reported as unmatched, never guessed */ }
    spawns.push({
      at: row.event_ts,
      epoch_ms: row.event_unix_ms,
      tool: row.tool_name,
      task_name: args.task_name ?? (args.target ?? "").replace(/^\/root\//, ""),
      brief_is_ciphertext: typeof args.message === "string" && /^gAAAAA/.test(args.message),
    });
  }

  const metas = moraine(["--since", since, "--until", until, "--event-kind", "session_meta"])
    .map((row) => ({ session_id: row.session_id, meta: sessionMeta(row) }))
    .filter((entry) => entry.meta?.parent_thread_id === primaryId);

  const delegates = metas.map((entry) => ({
    session_id: entry.session_id,
    name: (entry.meta.agent_path ?? "").replace(/^\/root\//, ""),
    started_at: entry.meta.timestamp ?? null,
    branch: entry.meta.git?.branch ?? null,
    commit: entry.meta.git?.commit_hash ?? null,
    cli_version: entry.meta.cli_version ?? null,
    nickname: entry.meta.agent_nickname ?? null,
  }));

  const byName = new Map(delegates.map((d) => [d.name, d]));
  const launches = spawns.map((s) => ({
    ...s,
    session_id: byName.get(s.task_name)?.session_id ?? null,
    joined_by: byName.has(s.task_name) ? "task_name+parent_thread_id" : "unjoined",
  }));

  return {
    rule: "R2",
    deterministic: true,
    join: "spawn_agent.task_name == session_meta.agent_path AND session_meta.parent_thread_id == primary",
    delegates,
    launches,
    unjoined: launches.filter((l) => !l.session_id).length,
    duplicate_task_names: delegates.length - new Set(delegates.map((d) => d.name)).size,
    assumptions: [
      "task names are distinct within one parent session",
      "a continuation (followup_task) targets a delegate already joined by name, and is not a new session",
    ],
    breaks_when: [
      "the primary reuses one task name for two delegates",
      "a delegate is spawned at depth > 1 (this rule joins one level; ancestry is transitive but roles are not)",
    ],
  };
}

function resolveDelegatesClaude(primaryRows) {
  const ordered = [...primaryRows].sort((a, b) => a.event_order - b.event_order);
  const launches = [];
  const seen = new Set();
  let pending = null;
  for (const row of ordered) {
    if (!row.is_substream && row.tool_name === "Agent" && row.tool_phase === "request") {
      let input = {};
      try {
        input = JSON.parse(row.payload_json).input ?? {};
      } catch { /* reported unmatched below */ }
      pending = {
        at: row.event_ts,
        epoch_ms: row.event_unix_ms,
        tool_call_id: row.tool_call_id,
        description: input.description ?? null,
        brief: typeof input.prompt === "string" ? input.prompt : null,
        brief_is_ciphertext: false,
        agent_run_id: null,
        joined_by: "unjoined",
      };
      launches.push(pending);
      continue;
    }
    if (row.is_substream && row.agent_run_id && !seen.has(row.agent_run_id)) {
      seen.add(row.agent_run_id);
      if (pending && !pending.agent_run_id) {
        pending.agent_run_id = row.agent_run_id;
        pending.joined_by = "stream-order after Agent request";
      }
    }
  }
  return {
    rule: "R2",
    deterministic: false,
    join: "first unseen agent_run_id in event_order after an Agent request",
    delegates: [...seen].map((id) => ({ agent_run_id: id })),
    launches,
    unjoined: launches.filter((l) => !l.agent_run_id).length,
    assumptions: [
      "delegate substream events are ordered after the launch that produced them",
      "one Agent request produces exactly one agent_run_id",
    ],
    breaks_when: [
      "several Agent tools are called in one assistant message and their substreams interleave",
      "Moraine's agent_run_id projection is absent for a harness version",
    ],
  };
}

// ---------------------------------------------------------------------------
// R3 — a delegate resolves to a role.
//
// The name is authored by the primary, not by the harness, and the workflow does
// not fix its spelling: `gate_standards_138`, `issue96_standards_r1` and
// `issue96_standards_confirm4` are all the Standards reviewer. Classification is
// lexical over that name, plus the plaintext brief where the harness has one.
// This is a heuristic. Every unmatched delegate is reported, never guessed.
// ---------------------------------------------------------------------------
function classifyRole(text) {
  if (!text) return { role: null, event: null, matched: null };
  // Authored names join their words with underscores and hyphens, which are word
  // characters, so the vocabulary is matched against a separated form.
  const separated = text.replace(/[^A-Za-z0-9]+/g, " ");
  for (const [pattern, role, event] of ROLE_VOCABULARY) {
    if (pattern.test(separated)) return { role, event, matched: String(pattern) };
  }
  // The sink's own launch enum has a residual category, `other`, so an
  // unmatched delegate is classified there rather than dropped. It is a residual
  // and is reported as one: nothing about the delegate's purpose was recovered.
  return { role: "other", event: "subagent_launch", matched: "residual" };
}

// ---------------------------------------------------------------------------
// R4 — a review delegation resolves to a compared candidate.
//
// The brief is opaque on Codex, so the compared identity is read from what the
// reviewer *did*: the first `git diff` in the delegate's own tool calls naming
// SHAs. Two SHAs is a committed comparison (base, head); one SHA together with
// `git ls-files --others` is the worktree bundle a readiness sweep reads.
// `input_bytes` is then recomputed from git by the sink's own definition rather
// than recovered, so it is a git fact, not a corpus fact.
// ---------------------------------------------------------------------------
// R4b — where the brief is plaintext, the compared candidate is in the brief.
// A Claude Code reviewer is told `git diff <base>...HEAD` and handed a commit
// list, so the base is literal and the head is the last abbreviated SHA in that
// list, resolved through git. Codex has no equivalent: its brief is ciphertext,
// which is why R4 reads the reviewer's own diff instead.
function resolveComparedFromBrief(brief, repoPath) {
  if (!brief) return null;
  const diff = /git diff\s+([0-9a-f]{7,40})\s*(?:\.\.\.?|\s)\s*([0-9a-f]{7,40}|HEAD)/.exec(brief);
  if (!diff) return null;
  const base = diff[1];
  let head = diff[2];
  if (head === "HEAD") {
    const list = /Commits?(?: list)?:\s*\n([\s\S]{0,2000}?)(?:\n\s*\n|$)/.exec(brief);
    const shas = list ? [...list[1].matchAll(/^\s*([0-9a-f]{7,40})\s/gm)].map((m) => m[1]) : [];
    if (shas.length === 0) return null;
    head = shas[shas.length - 1];
  }
  const resolve = (ref) => (git(repoPath, ["rev-parse", `${ref}^{commit}`]) ?? "").trim() || null;
  const baseSha = resolve(base);
  const headSha = resolve(head);
  if (!baseSha || !headSha) return null;
  return {
    base: baseSha, head: headSha, head_is_worktree: false,
    evidence: diff[0], method: "plaintext brief: stated base and commit list",
  };
}

function resolveComparedCandidate(rows, repoPath) {
  for (const row of rows) {
    for (const command of commandsOf(row)) {
      if (!/\bgit\s+diff\b/.test(command)) continue;
      const shas = [...new Set(command.match(SHA) ?? [])];
      if (shas.length === 0) continue;
      if (shas.length >= 2) {
        return {
          base: shas[0], head: shas[1], head_is_worktree: false,
          evidence: command.slice(0, 200), method: "reviewer's own git diff",
        };
      }
      return {
        base: shas[0], head: shas[0], head_is_worktree: true,
        evidence: command.slice(0, 200),
        method: "reviewer's own git diff against a single base (worktree sweep)",
      };
    }
  }
  return null;
}

function measureBundle(repoPath, base, head, isWorktree) {
  if (!base) return null;
  if (isWorktree) return null; // the worktree is gone; the bundle is unmeasurable after the fact
  // Byte-identical to the sink's own `diff_git`: the presentation configuration
  // that would otherwise vary the count is pinned the same way.
  const diff = git(repoPath, [
    "-c", "core.quotePath=false", "-c", "diff.noprefix=false",
    "-c", "diff.mnemonicPrefix=false", "--no-pager", "diff", "--no-ext-diff",
    "--no-color", "--no-textconv", `${base}...${head}`,
  ]);
  return diff === null ? null : Buffer.byteLength(diff, "utf8");
}

// ---------------------------------------------------------------------------
// R5 — a validation execution resolves to a command identity, a duration and an
// outcome.
//
// Identity is the literal command line, which the corpus holds in full and the
// sink deliberately does not hold at all. Duration is the request-to-result
// interval, except where the harness yielded on a long command: Codex returns a
// `session_id` and the agent polls it, so the interval must be followed to the
// last poll. Outcome is only as good as what the agent's own script printed:
// Codex's `exec` is a JS sandbox, and a script that emits `r.output` discards
// the exit code the harness had.
// ---------------------------------------------------------------------------
function resolveValidations(rows) {
  const requests = new Map();
  const executions = [];
  const ordered = [...rows].sort((a, b) => a.event_unix_ms - b.event_unix_ms);

  for (const row of ordered) {
    if (row.tool_phase === "request") {
      requests.set(row.tool_call_id, row);
      continue;
    }
    const request = requests.get(row.tool_call_id);
    if (!request) continue;
    const commands = commandsOf(request);
    if (commands.length === 0) continue;
    const output = outputOf(row);
    const yielded = /"session_id"\s*:\s*(\d+)/.exec(output);
    const exit = /"exit_code"\s*:\s*(-?\d+)/.exec(output);
    const wall = /Wall time ([0-9.]+) seconds/.exec(output);
    for (const command of commands) {
      executions.push({
        session_id: row.session_id,
        // A template literal that interpolates records the program, not the
        // command. The identity here is a template, and what actually ran is
        // recoverable only by evaluating the program.
        identity_is_template: command.includes("${"),
        tool_call_id: row.tool_call_id,
        command,
        started_at: request.event_ts,
        started_ms: request.event_unix_ms,
        ended_ms: row.event_unix_ms,
        duration_ms: row.event_unix_ms - request.event_unix_ms,
        duration_is_partial: Boolean(yielded),
        yield_handle: yielded ? Number(yielded[1]) : null,
        wall_time_seconds: wall ? Number(wall[1]) : null,
        exit_status: exit ? Number(exit[1]) : null,
        outcome: exit ? (Number(exit[1]) === 0 ? "passed" : "failed") : "unknown",
        commands_in_this_tool_call: commands.length,
      });
    }
  }

  // Follow a yielded execution to its last poll, so its duration is the command's
  // and not the yield window's.
  for (const execution of executions) {
    if (!execution.yield_handle) continue;
    let last = execution;
    for (const row of ordered) {
      if (row.event_unix_ms <= execution.ended_ms) continue;
      const text = row.tool_phase === "request"
        ? commandsOf(row).join(" ") + JSON.stringify(row.payload_json)
        : outputOf(row);
      if (text.includes(String(execution.yield_handle))) last = { ended_ms: row.event_unix_ms };
    }
    execution.duration_ms = last.ended_ms - execution.started_ms;
    execution.duration_is_partial = false;
    execution.duration_followed_polls = true;
  }

  return executions;
}

// ---------------------------------------------------------------------------
// R0 — sink echo. The primary invoked `run-telemetry.sh` through the harness, so
// the corpus holds those command lines verbatim, and the whole sink can be
// replayed from them. This is reported and never counted as recovery: it is
// circular. These command lines exist only because the sink exists, so they
// vanish the moment the sink is deleted, which is the decision they would be
// used to justify.
// ---------------------------------------------------------------------------
function resolveSinkEcho(rows) {
  const echoes = [];
  for (const row of rows) {
    for (const command of commandsOf(row)) {
      // One command line may chain or batch several invocations, so every match
      // counts: `&&`, `;` and a Promise.all all put two recordings in one call.
      const matches = command.matchAll(/run-telemetry\.sh\s+(start|launch|review-delegation|exec|resolve|seal)\b/g);
      for (const match of matches) {
        echoes.push({ verb: match[1], at: row.event_ts, command: command.slice(0, 400) });
      }
    }
  }
  return echoes;
}

// ---------------------------------------------------------------------------
// R8 — authored review packages.
//
// Where the workflow writes a review assignment to disk, the corpus captures the
// patch that wrote it, and that text names the review's kind and round in the
// primary's own words. This is not harness metadata: it is a workflow-authored
// marker that happens to be observable because writing it was a tool call. It is
// the concrete precedent for the transcript-marker option #142 leaves open, and
// it is present on one subject and absent on the other.
// ---------------------------------------------------------------------------
function resolveAuthoredReviewPackages(rows) {
  const packages = [];
  for (const row of rows) {
    const program = programOf(row);
    if (!program) continue;
    const path = /work-on-review\/[^\s"]*?\.((?:cumulative|delta)-r\d+)\.md/.exec(program);
    const heading = /#\s+((?:Delta|Cumulative) review assignment[^\\"\n]*)/.exec(program);
    if (!path && !heading) continue;
    packages.push({
      at: row.event_ts,
      package: path ? path[1] : null,
      kind: path ? path[1].split("-")[0] : null,
      round: path ? Number(path[1].replace(/^.*-r/, "")) : null,
      heading: heading ? heading[1].trim() : null,
    });
  }
  return packages;
}

// ---------------------------------------------------------------------------
// R6 — the run's outcome. GitHub holds it: the published body's closing keyword
// and the issue's state are the authored outcome, which is what the sink's
// `outcome_resolved` records a copy of.
// ---------------------------------------------------------------------------
function resolveOutcome(pr, repo) {
  const closes = /\b(Closes|Fixes|Resolves)\s+#(\d+)/i.exec(pr.body ?? "");
  const progresses = /\bProgresses\b/i.test(pr.body ?? "");
  let issue = null;
  if (closes) {
    try {
      issue = gh(["issue", "view", closes[2], "-R", repo, "--json", "number,state,closedAt,title"]);
    } catch { /* an unreadable issue leaves the outcome at what the body says */ }
  }
  return {
    rule: "R6",
    outcome: closes ? "Closes" : (progresses ? "Progresses" : "unknown"),
    issue,
    resolved_at_bound_by: pr.createdAt,
    assumptions: ["the published body carries the authored outcome verbatim"],
    breaks_when: [
      "a run that aborted before publishing leaves no GitHub artifact at all, so preflight-aborted, abandoned and failed are indistinguishable from a run that never started",
    ],
  };
}

// ---------------------------------------------------------------------------
// Per-field verdicts.
// ---------------------------------------------------------------------------
const RECOVERED = "recovered-exactly";
const ASSUMED = "recovered-with-assumption";
const ARTIFACT = "recovered-from-git-or-github";
const NOT_RECOVERABLE = "not-recoverable";

function verdicts(reconstruction) {
  const harness = reconstruction.harness;
  const briefsOpaque = harness === "codex";
  const v = (field, verdict, note) => ({ field, verdict, note });
  return [
    v("run_start.workflow", ARTIFACT, "the run is a /work-on run because its published body carries the workflow's mechanical sections; constant, not measured"),
    v("run_start.repository", ARTIFACT, "the PR's own repository"),
    v("run_start.issue", ARTIFACT, "the closing keyword in the published body, corroborated by the primary's own `gh issue view N`"),
    v("run_start.head", ARTIFACT, "the PR's merge base; on Codex also the primary session_meta git.commit_hash at session start"),
    v("run_start.run_identity", NOT_RECOVERABLE, "minted by the sink and by nothing else. The primary session id is a recoverable substitute identity, but it is a different key: it is not what closability-gate.md's frozen snapshot and manifest are keyed on, and it does not exist before the session's first event"),
    v("run_start.continues_run", NOT_RECOVERABLE, "a handle-to-handle link between two sink files; no corpus, git or GitHub fact carries it"),
    v("subagent_launch.role", ASSUMED, briefsOpaque
      ? "the authored delegate name (session_meta.agent_path) classified lexically; the brief is ciphertext"
      : "the plaintext Agent brief and description"),
    v("subagent_launch.phase", ASSUMED, "inferred from position in the run's ordered structure (before the first review = implementation; between gate and closeout = remediation), not stated anywhere in the corpus"),
    v("subagent_launch.round", ASSUMED, "inferred by counting review cycles; the authored round number is not in the corpus unless the delegate name carries it, and the names observed carry it inconsistently"),
    v("subagent_launch.tokens_in", RECOVERED, "Moraine holds per-event token counts for every delegate; strictly better than the sink, which recorded none on any subject. The accounting must be stated: on Claude Code almost all input arrives as cache reads, so `input_tokens` alone understates a delegate by three orders of magnitude"),
    v("subagent_launch.tokens_out", RECOVERED, "as above"),
    v("review_delegation.role", ASSUMED, "as subagent_launch.role"),
    v("review_delegation.kind", ASSUMED, "readiness/full/delta is inferable from the compared candidate shape: a worktree sweep is readiness, a two-SHA comparison whose base is the run base is full, and one whose base is a prior candidate is delta"),
    v("review_delegation.phase", ASSUMED, "as subagent_launch.phase"),
    v("review_delegation.round", ASSUMED, "as subagent_launch.round"),
    v("review_delegation.base", RECOVERED, "the reviewer's own `git diff` names it; recovered from what the reviewer did, not from its brief"),
    v("review_delegation.head", RECOVERED, "as base, when the comparison is against a commit"),
    v("review_delegation.head_is_worktree", ASSUMED, "a single-SHA diff plus `git ls-files --others` is a worktree bundle"),
    v("review_delegation.input_bytes", ARTIFACT, "recomputable from git by the sink's own definition for a committed comparison. For a worktree sweep it is NOT recoverable: the uncommitted bytes are gone once the worktree moves on"),
    v("validation_start.exec_id", NOT_RECOVERABLE, "a sink-local sequence number; nothing outside the sink allocates it"),
    v("validation_start.command_id", ASSUMED, "the caller-supplied name is a sink field, and the corpus usually holds the full command line the name stood for — more precisely than the name did. But a Codex `exec` input is a JavaScript program, and a `cmd` written as an interpolating template literal records the template and never the command line that ran. Recovering those needs the program evaluated, which this rule does not do; it marks them"),
    v("validation_start.phase", ASSUMED, "as subagent_launch.phase"),
    v("validation_start.round", ASSUMED, "as subagent_launch.round"),
    v("validation_end.outcome", harness === "codex" ? NOT_RECOVERABLE : ASSUMED, harness === "codex"
      ? "Codex's exec tool is a JS sandbox and the recorded output is whatever the agent's script chose to emit. A script that emits `r.output` discards the exit code, and the harness's own wrapper text says `Script completed` for a failed command. Exit status is present only when the command yielded and the poll surfaced `exit_code`"
      : "the Bash tool result carries an error flag; a non-zero exit is visible but the status itself is not always"),
    v("validation_end.exit_status", NOT_RECOVERABLE, "see validation_end.outcome"),
    v("validation_end.duration_ms", ASSUMED, "request-to-result interval, corrected by following the yield handle to the last poll. It measures the harness round trip, not the wrapper's own clock, and differs from the sink's by the wrapper's start-up"),
    v("outcome_resolved.outcome", ARTIFACT, "the published body's closing keyword and the issue state. Closes and Progresses are recoverable; preflight-aborted, abandoned and failed publish nothing and are not"),
    v("run_sealed", NOT_RECOVERABLE, "a sink lifecycle transition with no event in the world. It marks the end of recording, and there is no recording to end"),
    v("envelope.schema", NOT_RECOVERABLE, "describes the sink, not the run"),
    v("envelope.run", NOT_RECOVERABLE, "see run_start.run_identity"),
    v("envelope.seq", NOT_RECOVERABLE, "a sink-local ordering allocated under the sink's lock"),
    v("envelope.at", RECOVERED, "every reconstructed event carries the corpus timestamp of the act it reconstructs"),
    v("envelope.epoch_ms", RECOVERED, "as envelope.at"),
    v("envelope.type", RECOVERED, "the reconstructed event's own kind"),
  ];
}

// ---------------------------------------------------------------------------
// The joins are exported so a test suite can hold them to the behaviour this
// rule's result reports. Everything below the guard runs only when the file is
// invoked directly.
// ---------------------------------------------------------------------------
export {
  commandsOf, programOf, classifyRole, classifyRound,
  resolveComparedFromBrief, resolveSinkEcho, resolveValidations,
  VERSION, SELF_DIGEST,
};

// ---------------------------------------------------------------------------
// Main.
// ---------------------------------------------------------------------------
if (process.argv[1] && fileURLToPath(import.meta.url) === fs.realpathSync(process.argv[1])) {
  const opts = parseArgs(process.argv.slice(2));
  const pr = gh([
    "pr", "view", String(opts.pr), "-R", opts.repo, "--json",
    "number,headRefName,baseRefName,createdAt,mergedAt,body,commits,url,state",
  ]);

  const r1 = resolvePrimary({ pr, repo: opts.repo, windowHours: opts.windowHours });
  if (!r1.primary_session_id) fail(`no primary session resolved for ${opts.repo}#${opts.pr}`);

  const primaryRows = moraine(["--session-id", r1.primary_session_id]);
  const harness = opts.harness === "auto" ? (primaryRows[0]?.harness ?? "unknown") : opts.harness;
  r1.harness = harness;

  const created = new Date(pr.createdAt);
  const since = new Date(created.getTime() - opts.windowHours * 3600 * 1000).toISOString();
  const until = new Date(created.getTime() + 3600 * 1000).toISOString();

  const r2 = harness === "codex"
    ? resolveDelegatesCodex(r1.primary_session_id, primaryRows, since, until)
    : resolveDelegatesClaude(primaryRows);

  // R3 + R4 per delegate.
  const delegateRows = new Map();
  if (harness === "codex") {
    for (const delegate of r2.delegates) {
      delegateRows.set(delegate.session_id, moraine(["--session-id", delegate.session_id]));
    }
  } else {
    for (const row of primaryRows) {
      if (!row.is_substream || !row.agent_run_id) continue;
      if (!delegateRows.has(row.agent_run_id)) delegateRows.set(row.agent_run_id, []);
      delegateRows.get(row.agent_run_id).push(row);
    }
  }

  const classified = [];
  for (const launch of r2.launches) {
    const key = harness === "codex" ? launch.session_id : launch.agent_run_id;
    const rows = key ? (delegateRows.get(key) ?? []) : [];
    const nameText = harness === "codex"
      ? launch.task_name
      : [launch.description, (launch.brief ?? "").slice(0, 400)].join(" ");
    const role = classifyRole(nameText);
    // The brief is preferred where it is readable, because it states what the
    // reviewer was told to compare; the reviewer's own diff is the fallback and
    // the only path on a harness whose brief is ciphertext.
    const compared = role.event === "review_delegation"
      ? (resolveComparedFromBrief(launch.brief, opts.repoPath)
        ?? resolveComparedCandidate(rows, opts.repoPath))
      : null;
    // The two harnesses account input differently: on Claude Code almost all of it
    // arrives as cache reads, so a bare `input_tokens` sum would report a delegate
    // that consumed 22.8M tokens as having consumed 940. `tokens_in` is therefore
    // defined here as everything that entered the model, with the uncached part
    // reported beside it rather than folded away.
    const sum = (field) => rows.reduce((total, row) => total + (row[field] || 0), 0);
    const tokensIn = sum("input_tokens") + sum("cache_read_tokens") + sum("cache_write_tokens");
    const tokensOut = sum("output_tokens");
    classified.push({
      key,
      at: launch.at,
      authored_name: harness === "codex" ? launch.task_name : launch.description,
      brief_is_ciphertext: launch.brief_is_ciphertext,
      role: role.role,
      role_matched_on: role.matched,
      round_hint: classifyRound(harness === "codex"
        ? launch.task_name
        : [launch.description, (launch.brief ?? "").slice(0, 400)].join(" ")),
      reconstructed_event: role.event ?? "unclassified",
      compared,
      input_bytes: compared && !compared.head_is_worktree
        ? measureBundle(opts.repoPath, compared.base, compared.head, false)
        : null,
      tokens_in: tokensIn,
      tokens_out: tokensOut,
      tokens_in_uncached: sum("input_tokens"),
      tokens_in_cache_read: sum("cache_read_tokens"),
      tokens_in_cache_write: sum("cache_write_tokens"),
      events_seen: rows.length,
    });
  }

  // R5 over every session in the run.
  const allRows = [...primaryRows];
  for (const rows of delegateRows.values()) allRows.push(...rows);
  const validations = resolveValidations(allRows);
  const echo = resolveSinkEcho(allRows);
  const authoredPackages = resolveAuthoredReviewPackages(allRows);
  const r6 = resolveOutcome(pr, opts.repo);

  // Comparison against the sink, when one is supplied. The sink is evidence
  // authority 4 — a corroborating transitional summary, never the population.
  let comparison = null;
  if (opts.sink) {
    const events = fs.readFileSync(opts.sink, "utf8").split("\n").filter(Boolean)
      .map((line) => JSON.parse(line));
    const count = (type) => events.filter((e) => e.type === type).length;
    const sinkReviews = events.filter((e) => e.type === "review_delegation");
    const reconstructedReviews = classified.filter((c) => c.reconstructed_event === "review_delegation");
    const sinkPairs = new Set(sinkReviews.map((e) => `${e.base}..${e.head}`));
    const ourPairs = new Set(reconstructedReviews.filter((c) => c.compared)
      .map((c) => `${c.compared.base}..${c.compared.head}`));
    comparison = {
      sink_run: events[0]?.run ?? null,
      counts: {
        subagent_launch: { sink: count("subagent_launch"), reconstructed: classified.filter((c) => c.reconstructed_event === "subagent_launch").length },
        review_delegation: { sink: sinkReviews.length, reconstructed: reconstructedReviews.length },
        validation_start: { sink: count("validation_start"), reconstructed_wrapped: echo.filter((e) => e.verb === "exec").length,
          reconstructed_primary_only: validations.filter((x) => x.session_id === r1.primary_session_id).length,
          reconstructed_all_sessions: validations.length },
      },
      compared_candidate_pairs: {
        sink: [...sinkPairs],
        reconstructed: [...ourPairs],
        sink_only: [...sinkPairs].filter((p) => !ourPairs.has(p)),
        reconstructed_only: [...ourPairs].filter((p) => !sinkPairs.has(p)),
      },
      input_bytes: sinkReviews.map((e) => {
        const ours = reconstructedReviews.find((c) => c.compared
          && c.compared.base === e.base && c.compared.head === e.head);
        return {
          base: e.base, head: e.head, worktree: e.head_is_worktree,
          sink: e.input_bytes,
          recomputed: ours?.input_bytes ?? null,
          agrees: ours?.input_bytes === e.input_bytes,
        };
      }),
      outcome: { sink: events.find((e) => e.type === "outcome_resolved")?.outcome ?? null, reconstructed: r6.outcome },
      round: (() => {
        // Aligned in time order, which is safe here only because both sequences
        // are one run's review delegations in the order they happened.
        const ours = reconstructedReviews;
        const theirs = sinkReviews;
        const pairs = ours.slice(0, theirs.length).map((c, i) => ({
          authored_name: c.authored_name,
          sink_round: theirs[i].round,
          reconstructed_round: c.round_hint,
          agrees: c.round_hint === theirs[i].round,
        }));
        return {
          compared: pairs.length,
          recovered: pairs.filter((p) => p.reconstructed_round !== null).length,
          agreeing: pairs.filter((p) => p.agrees).length,
          pairs,
        };
      })(),
    };
  }

  const document = {
    rule_version: VERSION,
    rule_digest: SELF_DIGEST,
    produced_at: new Date().toISOString(),
    subject: { repository: opts.repo, pull_request: pr.number, url: pr.url, harness },
    source_locators: [
      `moraine:session:${r1.primary_session_id}`,
      ...r2.delegates.map((d) => `moraine:session:${d.session_id ?? d.agent_run_id}`),
      `github:${opts.repo}#${pr.number}`,
      `git:${opts.repoPath}`,
      ...(opts.sink ? [`sink:${opts.sink}`] : []),
    ],
    rules: { R1: r1, R2: r2, R6: r6 },
    authored_review_packages: {
      note: "Workflow-authored review assignments, observable because writing them was a tool call. Recovers the kind and round no join recovers — where the workflow writes them at all.",
      count: authoredPackages.length,
      packages: authoredPackages,
    },
    delegates: classified,
    validations,
    command_identity: {
      executions: validations.length,
      templated: validations.filter((x) => x.identity_is_template).length,
      note: "A templated identity is a program, not a command line. It is counted here so the identity axis is not reported as cleaner than it is.",
    },
    sink_echo: {
      note: "Circular, and incomplete: these are exec programs, not invocations. A loop over three reviewer roles is one program and three recordings, so the echo undercounts wherever the primary batched.",
      count: echo.length,
      by_verb: echo.reduce((acc, e) => ({ ...acc, [e.verb]: (acc[e.verb] ?? 0) + 1 }), {}),
      events: echo,
    },
    verdicts: verdicts({ harness }),
    comparison,
    covered_fields: SINK_FIELDS.length,
  };

  const rendered = `${JSON.stringify(document, null, 2)}\n`;
  if (opts.out) fs.writeFileSync(opts.out, rendered);
  else process.stdout.write(rendered);

  const notRecoverable = document.verdicts.filter((v) => v.verdict === NOT_RECOVERABLE);
  process.stderr.write(
    `reconstruct ${VERSION} ${opts.repo}#${opts.pr} (${harness}): `
    + `primary=${r1.primary_session_id} delegates=${r2.delegates.length} `
    + `validations=${validations.length} not-recoverable=${notRecoverable.length}/${document.verdicts.length}\n`
  );
}
