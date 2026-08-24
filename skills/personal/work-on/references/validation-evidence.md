# Validation evidence reuse

Apply this policy whenever an implementation, readiness, Standards, Spec, or
closure context produces or adjudicates validation evidence. The frozen
Validation-surface manifest remains the complete population of direct evidence
the accepted candidate owes; this policy decides whether qualifying evidence
for a listed member must be executed again.

## Qualifying evidence

Candidate identity names the exact repository and all candidate-controlled
content under assessment. Include the base only when the validation depends on
the base or diff. Validation identity names the exact command, arguments,
working directory, and other check-defining inputs. Reusable-evidence identity
combines that Candidate identity and Validation identity with every relevant
environment, toolchain, external-input, and artifact identity whose change
could affect the result.

Reusable validation evidence supplies recoverable source provenance, execution
status, and inspectable raw output or a result artifact. A prior participant's
pass conclusion is not evidence. Every reviewer still makes a fresh Independent
judgment from the candidate, contract, and raw evidence without inheriting
prior conclusions, adjudications, or dispositions. Validity depends on identity
and provenance, not producer role.

Wave 1 uses a conservative exact-candidate rule. A committed HEAD qualifies
when the required worktree state is proven clean. Evidence from an uncommitted
state qualifies only when its content identity was deterministically captured
and proven identical to the reviewed candidate.

Evidence remains valid only for the candidate and inputs it exercised. Changes
to code, tests, fixtures, configuration, dependency locks, validation
definitions, relevant generated artifacts, external inputs, environment, or
toolchain state invalidate the evidence they can affect. When irrelevance is not
mechanically clear, obtain fresh evidence from the affected validation.

## Required execution

Assurance sufficiency alone determines whether another execution is required.
When qualifying evidence for the exact current Candidate identity and Validation
identity settles the concrete assurance question, another execution is not
required. When it does not, execute the narrowest check that settles it.

Independent execution is required when existing evidence cannot settle a
concrete assurance question involving timing, concurrency, nondeterminism,
environment- or host-sensitive behavior, uncertain identity or provenance,
incomplete, stale, contradictory, or otherwise suspect evidence,
or a finding that needs discriminating reproduction. A documented contract or
hard rule triggers re-execution only when it requires re-execution or its
assurance question cannot otherwise be resolved. Where the assurance question
itself requires an Independent context, implementation-context execution does
not satisfy it: at least one fresh Independent review context performs the
qualifying execution. Otherwise producer role does not determine validity.

Escalate in this order:

1. inspect the existing raw evidence;
2. use static or source inspection where sufficient;
3. run the cheapest adequate targeted discriminating check; and
4. use broader execution only when the narrower check cannot answer the
   assurance question.

Timing and concurrency require the smallest reproduction that establishes the
property, not an automatic full-suite rerun. "For confidence", "to be safe",
or independently repeating an already adequate green result do not justify
another execution. One qualifying Independent execution may answer several
named assurance questions and is never required once per reviewer or stage. A
workflow-stage transition is never itself a reason to execute again.

## Repetition guardrail

Only after sufficiency is established: do not repeat materially costly
deterministic validation already covered by qualifying evidence that settles the
current assurance question. Materially costly means repeating the validation
would meaningfully add workflow latency or consume a scarce resource. Judge that
qualitatively; never consult or build a duration threshold, timing history,
telemetry-based classification, cost database, or persistent resource metadata.

This is an efficiency directive, not an assurance invariant. Violating it wastes
resources; it does not by itself make the candidate or review unsound, and it is
never a reason to skip an execution sufficiency requires. Trivially cheap checks
stay at reviewer discretion. Do not move or pre-produce validation merely to
create reusable evidence.

## Validity across stages

A later workflow stage does not by itself make deterministic evidence stale.
Qualifying evidence may satisfy later stages and final closeout while its
complete Reusable-evidence identity remains unchanged. The final blind
confirmation still independently assesses the exact clean accepted candidate
and the sufficiency of its complete direct evidence; behavior- or
evidence-changing remediation invalidates that confirmation.

Failing, stale, contradictory, incomplete, identity-invalid, or otherwise
inadequate evidence remains blocking and never reaches the repetition
guardrail. Adjudicate what failed and the evidence's bearing on the contract
before another execution; a rerun-until-green chain without adjudication cannot
erase a failure. A documented hard-rule violation remains blocking, but does
not by itself require another execution.

## Safe evidence

Evidence records never persist credential or secret values and never override
privacy, redaction, retention, or access-control constraints. Record command
structure and declared environment inputs without their sensitive values; use
an opaque safe identifier or hash when a command, argument, artifact, input, or
environment detail is sensitive. A safe provenance locator may point to
access-controlled source evidence instead of copying it. Redact or avoid
retaining secret-bearing output under the governing constraints. Unsafe or
unrecoverable evidence is non-reusable: obtain safe qualifying evidence rather
than weakening those constraints.

## Reviewer record

Keep reuse and rerun reasoning in the ordinary reviewer report. For reused
evidence, record the Reusable-evidence identity, safe provenance locator, and
fresh Independent sufficiency judgment for the named criterion or assurance
question. For an execution claimed as necessary for Independent assurance, also
name the assurance question, why existing evidence and static inspection were
insufficient, and why the execution was the narrowest adequate check. A
discretionary cheap check owes no justification record.

Do not copy raw evidence into the Run telemetry sink or create another evidence
subsystem. Raw harness transcripts and access-controlled result artifacts
remain source evidence; the reviewer report carries safe provenance and
reasoning only.
