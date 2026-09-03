# Bounded re-adjudication of an Ambiguous ruling

Re-adjudicate `R` exactly once when all of the following hold at that gate:

- `R` was classified **Ambiguous**; Contract-backed and Defensive rulings are
  ineligible;
- `D` produced the current remediation candidate;
- an accepted blocker at that gate is attributable to the mechanism introduced
  for `D`, traced the same way any blocking finding is traced to a criterion;
- the frozen criterion bytes are unchanged; and
- that criterion's Validation-surface membership is unchanged.

An accepted blocker at the same gate that does not trace to `D`'s mechanism
takes ordinary remediation. Anything requiring changed criterion text, an
obligation those bytes do not already carry, or changed Validation-surface
membership takes the existing trusted-maintainer or immutable-manifest hand-back
route instead and is never re-adjudicated here.

Before ordinary remediation continues, launch one fresh blind reader. Reuse the
isolation pattern of `references/normative-remediation.md` without invoking or
extending that mechanism. The reader is non-reviewing: never reuse it as a
review-axis agent in this chain. Supply only the exact frozen criterion text,
the bounded raw governing context needed to interpret it, and the raw
triggering observation and its boundary. Withhold the prior ruling, any
previously rejected alternative, the adjudication ledger, prior reviewer
conclusions and dispositions, and the current implementation except a bounded
raw fact needed to understand the triggering boundary. Ask it to derive the
governing consequence at the observed boundary and, where several materially
defensible readings exist, to enumerate them with the concrete obligation each
creates; it must not prefer a reading because that reading is cheaper and must
not propose an implementation. The reader derives meaning only; the primary
retains adjudication authority. One fresh invocation may handle several
eligible criterion units from the same gate independently.

Then adjudicate:

- **Uphold** — the prior interpretation stands. Continue ordinary remediation
  and do not re-adjudicate `R` again in this run. The limit is one
  re-adjudication per Ambiguous ruling, not one per run.
- **Supersede** — the reproduced observation and its evidence remain valid, but
  the primary replaces its earlier interpretation with another materially
  defensible reading of the same unchanged bytes. Remove mechanism no criterion
  requires rather than hardening it, keep any blocker portion that still applies
  to surviving candidate content, and freshly adjudicate under
  `references/validation-evidence.md` whether existing raw validation evidence
  proves the newly adjudicated obligation: reuse evidence only where it directly
  proves that obligation, rerun where sufficiency requires it, and carry no
  earlier `tested` disposition across the reversal. The correction then takes
  the ordinary correction → delta gate → fresh blind cumulative confirmation
  path.

Re-adjudication changes no frozen review-chain governing input, and the ledger
stays out of every reviewer package. State in ordinary working reasoning which
ruling was re-adjudicated, what the reader returned, whether the ruling was
upheld or superseded, and the resulting evidence-sufficiency decision.
