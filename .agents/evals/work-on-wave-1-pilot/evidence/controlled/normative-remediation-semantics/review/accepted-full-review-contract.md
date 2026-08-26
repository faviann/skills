# Accepted full review contract

Standards axis: independently assess the exact supplied candidate and
mechanical comparison against the complete frozen Standards input.

Spec axis: independently assess the exact supplied candidate and mechanical
comparison against the full trusted contract and frozen Validation-surface
manifest.

Closure axis: independently inspect the full contract, production paths,
cumulative or delta subject as assigned, and qualifying evidence under
`github-closeout.md`; produce the required acceptance table and mechanism trace
for cumulative review, or attributable incremental findings for delta review.

Same-mechanism brief for all axes: after reproducing a defect, name its
mechanism and governing criterion, then trace only its immediate neighborhood —
the same boundary's branches, call sites, and input shapes; diagnostics from
the same untrusted source; or states under the same invariant. For a
failure-raising operation, enumerate its occurrences in the same public flow
and attempt the seed-shaped input at each compatible one through its public
entry point, including in-process test entry points. Count a sibling only at a
distinct branch, call site, diagnostic, or governed state; more inputs at the
seed location are reproduction evidence, not siblings. Group the seed with
minimally reproduced siblings, each with its own location, criterion, and
impact; report the seed alone when none reproduce. State the stop boundary and
stop before another criterion, subsystem, external boundary, or speculative
defense. Report reproduced instances only.

Validation evidence policy: apply the exact installed
`references/validation-evidence.md`. Evidence conclusions are not inherited;
each axis makes a fresh judgment from the exact candidate, contract, and raw
evidence. Execute only when existing qualifying evidence cannot settle the
concrete assurance question, using the narrowest adequate check.
