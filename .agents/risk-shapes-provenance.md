# Risk-shapes provenance

The production examples in `skills/engineering/to-tickets/RISK-SHAPES.md` are
deliberately generic at runtime. This record preserves the source artifacts that
ground them. Consult it before changing or removing an example.

## Production evidence for staged calibration

- The qualifying production wave began with Overmind issue
  [#78](https://github.com/faviann/overmind/issues/78), which published the
  immediate frontier in issues
  [#130](https://github.com/faviann/overmind/issues/130),
  [#131](https://github.com/faviann/overmind/issues/131),
  [#132](https://github.com/faviann/overmind/issues/132), and
  [#133](https://github.com/faviann/overmind/issues/133). Its production evidence
  shaped the later boundaries in issues
  [#144](https://github.com/faviann/overmind/issues/144) through
  [#156](https://github.com/faviann/overmind/issues/156).
- The unresolved-design counterexample is Overmind issue
  [#86](https://github.com/faviann/overmind/issues/86).
- The excluded-future-design counterexample is Overmind issue
  [#73](https://github.com/faviann/overmind/issues/73).

## Oversized shapes

- *Discover stable child rollout streams* — Overmind PR
  [#160](https://github.com/faviann/overmind/pull/160).
- *Advance oversized captures with explicit omissions* — Overmind PR
  [#168](https://github.com/faviann/overmind/pull/168).
- *Omit binary capture bytes before persistence* — Overmind PR
  [#174](https://github.com/faviann/overmind/pull/174).
- *Report fidelity loss separately from capture safety failure* — Overmind PR
  [#176](https://github.com/faviann/overmind/pull/176).

## Eval case abstractions

Cases in `.agents/evals/risk-shapes.md` are written in neutral domains. Three abstract a
real slice and borrow its verdict; the rest are constructed. Consult this before changing
those three, because their keys rest on the production outcome rather than on argument.

- Case 7 — *Omit binary capture bytes before persistence*, Overmind issue
  [#153](https://github.com/faviann/overmind/issues/153) and PR
  [#174](https://github.com/faviann/overmind/pull/174). Should have been split.
- Case 8 — the terminality counterexample, Overmind issue
  [#154](https://github.com/faviann/overmind/issues/154) and PR
  [#175](https://github.com/faviann/overmind/pull/175). Correctly stayed one ticket.
- Case 10 — *Import one Codex exchange through the capture spine*, Overmind issue
  [#74](https://github.com/faviann/overmind/issues/74) and PR
  [#121](https://github.com/faviann/overmind/pull/121). Should have been split; shipped as
  one ticket across 28 files. The eval's **Reality check** section ran issue #74's
  unabstracted text against the live reference three times before the case was written.
  Case 10 keeps that slice's authorization and deduplication models and deliberately drops
  its persistence lifecycle, so that the case fails when an authorization model is not
  counted. The eval explains why.

## Counterexample

The terminality-determination example originated in Overmind issue
[#154](https://github.com/faviann/overmind/issues/154) and was implemented by PR
[#175](https://github.com/faviann/overmind/pull/175).

## Ownership collision

Overmind issues [#147](https://github.com/faviann/overmind/issues/147) and
[#148](https://github.com/faviann/overmind/issues/148) both claimed
`context_compacted` normalization. Their independent implementations landed in
PRs [#162](https://github.com/faviann/overmind/pull/162) and
[#163](https://github.com/faviann/overmind/pull/163).
