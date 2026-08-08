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
