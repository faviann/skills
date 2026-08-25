#!/usr/bin/env node

import fs from "node:fs";
import crypto from "node:crypto";

const VERSION = "3.0.0";
const SELF_DIGEST = crypto.createHash("sha256")
  .update(fs.readFileSync(new URL(import.meta.url)))
  .digest("hex");
const EXPECTED_PROVENANCE = /^work-on:a9ebf0ae3a77 workflow:1b3cf6d962ac tdd:aa54f63292bf review:1dc4289fabb7 \(faviann\/skills@[0-9a-f]{12}\)$/;
const REQUIRED_CELLS = new Set([
  "ordinary-clean-expensive-validation",
  "contract-dense-remediation-opportunity",
  "timing-concurrency-environment-sensitive",
  "collection-valued-validation-surface",
]);
const REQUIRED_SCENARIOS = new Set([
  "validation-surface-omission",
  "normative-remediation-semantics",
]);
const PHASE = new Map([
  ["implementation", 1],
  ["readiness", 2],
  ["post-stabilization", 3],
  ["initial-gate", 4],
  ["remediation", 5],
  ["final-confirmation", 6],
  ["closeout", 7],
]);
const KINDS = new Set([
  "attempt-closeout",
  "controlled-scenario",
  "maintainer-adjudication",
  "pilot-decision",
]);

function fail(message) {
  process.stderr.write(`projection: ${message}\n`);
  process.exit(2);
}

const input = process.argv[2];
if (!input || process.argv.length !== 3) {
  fail("usage: projection.mjs LEDGER.jsonl");
}

const source = fs.readFileSync(input, "utf8");
const entries = source.split(/\n/).filter(Boolean).map((line, index) => {
  try {
    return JSON.parse(line);
  } catch {
    fail(`line ${index + 1} is not JSON`);
  }
});

const ids = new Map();
for (const entry of entries) {
  for (const key of [
    "entry_id", "subject_id", "kind", "recorded_at", "protocol_commit",
    "projection_version", "projection_digest", "workflow_provenance",
    "source_locators",
  ]) {
    if (entry[key] === undefined || entry[key] === null) {
      fail(`${entry.entry_id ?? "unknown entry"} lacks ${key}`);
    }
  }
  if (!KINDS.has(entry.kind)) fail(`${entry.entry_id} has unknown kind`);
  if (entry.projection_version !== VERSION) fail(`${entry.entry_id} has wrong projection version`);
  if (!/^[0-9a-f]{40}$/.test(entry.protocol_commit)) fail(`${entry.entry_id} has malformed protocol commit`);
  if (entry.projection_digest !== SELF_DIGEST) fail(`${entry.entry_id} has wrong projection digest`);
  if (!EXPECTED_PROVENANCE.test(entry.workflow_provenance)) fail(`${entry.entry_id} has non-frozen workflow provenance`);
  if (!Array.isArray(entry.source_locators) || entry.source_locators.length === 0) {
    fail(`${entry.entry_id} lacks source locators`);
  }
  if (ids.has(entry.entry_id)) fail(`duplicate entry_id ${entry.entry_id}`);
  if (entry.supersedes) {
    const prior = ids.get(entry.supersedes);
    if (!prior) fail(`${entry.entry_id} has dangling supersedes`);
    if (prior.subject_id !== entry.subject_id || prior.kind !== entry.kind) {
      fail(`${entry.entry_id} crosses subject or kind while correcting`);
    }
  }
  ids.set(entry.entry_id, entry);
}

const superseded = new Set(entries.flatMap((entry) => entry.supersedes ? [entry.supersedes] : []));
const live = entries.filter((entry) => !superseded.has(entry.entry_id));
const attempts = live.filter((entry) => entry.kind === "attempt-closeout");
const scenarios = live.filter((entry) => entry.kind === "controlled-scenario");
const protocolCommits = new Set(live.map((entry) => entry.protocol_commit));
if (protocolCommits.size > 1) fail("live entries mix protocol commits");

for (const attempt of attempts) {
  for (const key of [
    "repository", "issue", "started", "completed", "cells", "evidence_usable",
    "exact_provenance", "gate1_failures", "gate2_adverse", "validation_surface",
    "validation", "delta", "normative", "natural_exposure", "eligibility",
    "substitution", "run_identities", "base_identity", "candidate_identity",
    "findings", "corrective_batches", "blocker_lineage", "convergence", "cost",
  ]) if (attempt[key] === undefined) fail(`${attempt.entry_id} lacks ${key}`);
  for (const key of ["obligations", "executions", "populations", "reuse_events", "assurance_questions"])
    if (!Array.isArray(attempt.validation[key])) fail(`${attempt.entry_id} validation lacks ${key}`);
}

for (const scenario of scenarios) {
  for (const key of ["scenario", "arms", "passed", "gate1_failures"])
    if (scenario[key] === undefined) fail(`${scenario.entry_id} lacks ${key}`);
}

const completed = attempts.filter((attempt) => attempt.started && attempt.completed);
const repositories = [...new Set(completed.map((attempt) => attempt.repository))].sort();
const cells = [...new Set(completed.flatMap((attempt) => attempt.cells))].sort();
const missingCells = [...REQUIRED_CELLS].filter((cell) => !cells.includes(cell));
const scenarioByName = new Map(scenarios.map((scenario) => [scenario.scenario, scenario]));
const missingScenarios = [...REQUIRED_SCENARIOS].filter((name) => !scenarioByName.has(name));
const failedScenarios = scenarios.filter((scenario) => REQUIRED_SCENARIOS.has(scenario.scenario) && !scenario.passed);

const gate1 = [
  ...attempts.flatMap((attempt) => attempt.gate1_failures ?? []),
  ...scenarios.flatMap((scenario) => scenario.gate1_failures ?? []),
];
const gate2No = attempts.flatMap((attempt) => attempt.gate2_adverse ?? [])
  .filter((item) => item.conclusive_no === true);

const collectionRuns = completed.filter((attempt) =>
  attempt.cells.includes("collection-valued-validation-surface"));
const finiteFailed = collectionRuns.some((attempt) => {
  const value = attempt.validation_surface;
  return !value.complete_before_delegation || !value.frozen ||
    !value.all_members_directly_evidenced || value.post_delegation_amendment ||
    !value.review_and_neighborhood_unrestricted;
}) || scenarioByName.get("validation-surface-omission")?.passed === false;
const finiteSuccess = collectionRuns.length > 0 && !finiteFailed &&
  scenarioByName.get("validation-surface-omission")?.passed === true;

function rank(phase, subject) {
  if (!PHASE.has(phase)) fail(`${subject} has unknown phase ${phase}`);
  return PHASE.get(phase);
}

const validations = completed.map((attempt) => ({ attempt, value: attempt.validation }));
const validationReuseCount = validations.reduce((sum, { value }) => sum +
  value.reuse_events.filter((event) => event.qualifying && event.duration_seconds >= 60).length, 0);
const validationViolations = [];
for (const { attempt, value } of validations) {
  const executions = new Map(value.executions.map((execution) => [execution.execution_id, execution]));
  for (const execution of value.executions) {
    rank(execution.phase, execution.execution_id);
    if (execution.duplicate_class === "unjustified-workflow" && execution.workflow_attributable) {
      validationViolations.push({ attempt: attempt.subject_id, code: "unjustified-workflow-duplicate", execution: execution.execution_id });
    }
    if (execution.additional && execution.duration_seconds >= 60 && !execution.assurance_reason) {
      validationViolations.push({ attempt: attempt.subject_id, code: "unjustified-additional-expensive-execution", execution: execution.execution_id });
    }
  }
  for (const obligation of value.obligations) {
    const owner = rank(obligation.owning_phase, obligation.obligation_id);
    if (!obligation.resolved_before_delegation) {
      validationViolations.push({ attempt: attempt.subject_id, code: "unresolved-owning-phase", obligation: obligation.obligation_id });
    }
    if (obligation.owed && !obligation.discharged) {
      validationViolations.push({ attempt: attempt.subject_id, code: "dropped-later-obligation", obligation: obligation.obligation_id });
    }
    for (const executionId of obligation.execution_ids ?? []) {
      const execution = executions.get(executionId);
      if (!execution) fail(`${attempt.entry_id} obligation references missing execution ${executionId}`);
      if (rank(execution.phase, executionId) < owner && execution.timing_cause !== "narrow-development-case") {
        validationViolations.push({ attempt: attempt.subject_id, code: "earlier-than-owning-phase", obligation: obligation.obligation_id, execution: executionId, timing_cause: execution.timing_cause });
      }
    }
  }
  for (const population of value.populations) {
    if (population.complete_at_phase !== null &&
      rank(population.complete_at_phase, population.population_id) < rank(population.owning_phase, population.population_id)) {
      validationViolations.push({ attempt: attempt.subject_id, code: "premature-complete-population", population: population.population_id });
    }
    const invalidated = new Set(population.invalidated_member_ids ?? []);
    const independentlyRequired = new Set(population.independently_required_member_ids ?? []);
    for (const member of population.rerun_member_ids ?? []) {
      if (!invalidated.has(member) && !independentlyRequired.has(member)) {
        validationViolations.push({ attempt: attempt.subject_id, code: "unchanged-member-coarse-rerun", population: population.population_id, member });
      }
    }
  }
  for (const question of value.assurance_questions) {
    if (question.independent_execution_required && !question.executed) {
      validationViolations.push({ attempt: attempt.subject_id, code: "warranted-independent-execution-omitted", question: question.question_id });
    }
  }
}
const validationFailed = validationViolations.length > 0;
const validationSuccess = validationReuseCount > 0 && !validationFailed;

const deltaExposures = completed.filter((attempt) => (attempt.delta.accepted_corrections ?? 0) > 0);
const deltaFailed = deltaExposures.some((attempt) => {
  const value = attempt.delta;
  return !value.all_fresh_delta_axes || value.routine_cumulative_reread ||
    !value.mechanism_neighborhood_reachable || !value.valid_final_blind_confirmation;
});
const deltaSuccess = deltaExposures.length > 0 && !deltaFailed;

const normativeExposures = completed.filter((attempt) =>
  (attempt.normative.qualifying_batches ?? 0) > 0);
const normativeAssuranceFailure = normativeExposures.some((attempt) =>
  attempt.normative.blindness_breach || attempt.normative.review_package_contamination ||
  attempt.normative.substituted_for_review_axis);
const normativeExperimentalFailure = normativeExposures.some((attempt) => {
  const value = attempt.normative;
  return (value.qualification_misses ?? 0) > 0 ||
    (value.semantic_challenge_failures ?? 0) > 0 ||
    value.disproportionate_cost_or_false_positive;
}) || scenarioByName.get("normative-remediation-semantics")?.passed === false;
const normativeSuccess = normativeExposures.length > 0 &&
  scenarioByName.get("normative-remediation-semantics")?.passed === true &&
  !normativeAssuranceFailure && !normativeExperimentalFailure;

if (normativeAssuranceFailure) gate1.push({ code: "normative-assurance-integrity" });

const cleanRuns = completed.filter((attempt) =>
  attempt.cells.includes("ordinary-clean-expensive-validation") &&
  (attempt.delta.accepted_corrections ?? 0) === 0);
const commitments = cleanRuns.map((attempt) => attempt.behavioral_commitment).filter(Boolean);
const commitmentNo = commitments.some((value) => value.answer === "NO");
const commitmentYes = commitments.some((value) => value.answer === "YES");

const evidenceGap = completed.some((attempt) => !attempt.evidence_usable || !attempt.exact_provenance);
const pendingExposure = completed.some((attempt) =>
  (attempt.natural_exposure ?? []).some((exposure) => exposure.required && !exposure.observed));
const adverse = gate1.length > 0 || gate2No.length > 0 || commitmentNo ||
  finiteFailed || validationFailed || deltaFailed;
const missing = completed.length < 3 || completed.length > 4 || repositories.length < 2 ||
  missingCells.length > 0 || missingScenarios.length > 0 || evidenceGap || pendingExposure ||
  !finiteSuccess || !validationSuccess || !deltaSuccess || !normativeSuccess ||
  !commitmentYes || normativeExperimentalFailure;

const result = adverse ? "DO NOT RESUME" : missing ? "INCONCLUSIVE" : "PASS";
const output = {
  projection_version: VERSION,
  ledger_sha256: crypto.createHash("sha256").update(source).digest("hex"),
  result,
  population: {
    completed_runs: completed.length,
    repositories,
    cells,
    missing_cells: missingCells,
  },
  controlled_scenarios: {
    observed: scenarios.map((scenario) => ({ scenario: scenario.scenario, passed: scenario.passed })),
    missing: missingScenarios,
    failed: failedScenarios.map((scenario) => scenario.scenario),
  },
  assurance: { gate1_failures: gate1, gate2_conclusive_no: gate2No },
  mechanisms: {
    finite_validation_surface: finiteFailed ? "FAILED" : finiteSuccess ? "SUCCESS" : "INCONCLUSIVE",
    validation_reuse_and_phase_ownership: validationFailed ? "FAILED" : validationSuccess ? "SUCCESS" : "INCONCLUSIVE",
    delta_review: deltaFailed ? "FAILED" : deltaSuccess ? "SUCCESS" : "INCONCLUSIVE",
    normative_remediation: normativeAssuranceFailure ? "FAILED_ASSURANCE" :
      normativeExperimentalFailure ? "FAILED_EXPERIMENTAL" : normativeSuccess ? "SUCCESS" : "INCONCLUSIVE",
    convergence: "OBSERVATIONAL_ONLY",
  },
  clean_run_commitment: commitmentNo ? "NO" : commitmentYes ? "YES" : "MISSING",
  unresolved: {
    evidence_or_provenance: evidenceGap,
    required_natural_exposure: pendingExposure,
  },
  validation_violations: validationViolations,
};
process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
