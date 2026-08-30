#!/usr/bin/env bash
set -euo pipefail

# Bounded re-adjudication is one inline workflow contract with an authority
# clarification in SKILL.md. Exercise the seams a wrong implementation would
# break: eligibility, attribution, the blind package, the one-shot property,
# the supersede routing, the immutability fence, and the static surface.
#
# Assertions bind obligations, not sentences. Alternate over function words a
# rewrite legitimately changes, keep load-bearing gaps inside sentence
# boundaries, and put required polarity in each obligation-specific pattern.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"

SKILL="$skill_dir/SKILL.md"
WORKFLOW="$skill_dir/references/default-workflow.md"

failures=0
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

flatten() {
  local source="$1"
  local flat="$fixture_dir/$(printf '%s' "${source#"$skill_dir/"}" | tr '/' '_')"
  [[ -f "$flat" ]] || awk '
    /^[[:space:]]*$/ { print paragraph; paragraph = ""; next }
    { paragraph = (paragraph == "" ? $0 : paragraph " " $0) }
    END { print paragraph }
  ' "$source" | tr -s ' ' >"$flat"
  printf '%s' "$flat"
}

has() {
  if ! grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3"
  fi
}

lacks() {
  if grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3"
  fi
}

heading="$(grep -m1 '^### Bounded re-adjudication' "$WORKFLOW" || true)"
section="$fixture_dir/readjudication-section.md"
if [[ -n "$heading" ]]; then
  awk -v heading="$heading" '
    $0 == heading { inside = 1 }
    inside && $0 != heading && /^#{1,3} / { exit }
    inside { print }
  ' "$WORKFLOW" >"$section"
fi
if [[ ! -s "$section" ]]; then
  fail 'the default workflow carries the bounded re-adjudication section inline'
  printf '\n%s bounded-re-adjudication assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

## The mechanism lives beside adjudication, and only Ambiguous rulings qualify.
awk '/^## / { inside = ($0 ~ /^## 5\./) }
  inside && /^### Bounded re-adjudication/ { found = 1 }
  END { exit !found }' "$WORKFLOW" ||
  fail 'bounded re-adjudication sits inside the adjudicate-and-remediate step'
all_conditions='((all|every one) of the following (hold|holds)|all (of )?(these|the) conditions (are )?(satisfied|met))'
has "$section" \
  "(re-adjudicate \`R\` (exactly once|once,? and only once|only once)[^.]*(when|only if|if) $all_conditions|(when|only if|if) $all_conditions[^.]*re-adjudicate \`R\` (exactly once|once,? and only once|only once))" \
  'a qualifying trigger produces exactly one re-adjudication only when every condition holds'
lacks "$section" \
  '(there is (no|not any) (obligation|requirement)[^.]{0,32}|nothing[^.]{0,64}requires[^.]{0,48})re-adjudicate `R`' \
  'the positive trigger is not retained inside an explicit denial of its obligation'
lacks "$section" \
  "(do not|never) re-adjudicate \`R\` (exactly once|once,? and only once|only once)[^.]*(when|only if|if) $all_conditions" \
  'the trigger is not inverted into a prohibition'
has "$section" \
  '(`R` was classified \*\*Ambiguous\*\*|classification of `R` (was|is) \*\*Ambiguous\*\*)' \
  'only an Ambiguous ruling qualifies'
lacks "$section" '`R` was not classified \*\*Ambiguous\*\*' \
  'the Ambiguous classification is not explicitly inverted'
has "$section" \
  '(Contract-backed and Defensive|Defensive and Contract-backed) rulings? (are|is) (ineligible|never eligible)' \
  'Contract-backed and Defensive rulings are ineligible'
lacks "$section" \
  '((not true|not the case|false) that[^.]*Contract-backed and Defensive rulings? (are|is) ineligible|Contract-backed and Defensive rulings? (are|is) not ineligible)' \
  'Contract-backed and Defensive ineligibility is not directly negated'
lacks "$section" \
  '(Contract-backed and Defensive|Defensive and Contract-backed) rulings? (are|is) ineligible[^.]*(but|yet|however)[^.]*(treat|consider|regard)[^.]*eligible' \
  'ineligible rulings are not later treated as eligible in the same sentence'
lacks "$section" \
  '((Contract-backed and Defensive|Defensive and Contract-backed) rulings? (are|is) ineligible[^.]*(unless|except when|only if)|(unless|except when|only if)[^.]*(Contract-backed and Defensive|Defensive and Contract-backed) rulings? (are|is) ineligible)' \
  'Contract-backed and Defensive ineligibility has no exception'
lacks "$section" '(Contract-backed|Defensive)( ruling)?s?[^.]{0,40}((is|are|becomes?) (also |likewise )?eligible|(also |likewise )?qualifies|reclassified as)' \
  'no ineligible classification is admitted as eligible or reclassified'
has "$section" '(`D` produced the current remediation candidate|current remediation candidate was produced by `D`)' \
  'the triggering directive produced the current remediation candidate'
has "$section" 'accepted blocker at that gate (is attributable to|traces to) the mechanism introduced for `D`' \
  'the trigger requires a blocker attributable to the Ambiguous directive'
has "$section" '(immediately following delta gate|delta gate that immediately follows)' \
  'the run-local note is scoped to the immediately following delta gate'
has "$section" 'does not trace to `D`.s mechanism (takes|proceeds through|is handled by) ordinary remediation' \
  'an unattributable blocker at the same gate does not trigger the mechanism'
echo 'ok - eligibility is limited to Ambiguous rulings whose own mechanism reproduced a blocker'

## The association is transient working state, not a lineage system.
has "$section" 'carry a run-local note[^.]*`D` descends from `R`' \
  'the association records only that the directive descends from the ruling'
for forbidden in 'lineage store' 'registry' 'lifecycle' 'event protocol' \
  'telemetry' 'persistent correlation state'; do
  has "$section" "(keep|introduce|add) no[^.;]*$forbidden" \
    "the association introduces no $forbidden"
done
lacks "$section" '(keep|introduce|add) no[^.]*but (keep|introduce|add|retain)' \
  'the machinery prohibition is not reversed mid-sentence'
lacks "$section" \
  '((keep|introduce|add) no[^.]*(unless|except when|only if)|(unless|except when|only if)[^.;,]*,[[:space:]]*([^[:space:].;,]+[[:space:]]+){0,4}(keep|introduce|add) no)' \
  'the absolute machinery prohibition has no exception'
has "$section" '(drop|discard) it once that gate is adjudicated' \
  'the association is bounded to the immediate delta window'
echo 'ok - the directive-to-ruling association is transient run-local state'

## The reader is fresh, blind, non-reviewing, and derives meaning only.
has "$section" '(launch|use) (one|a single) fresh blind reader' \
  'one fresh blind reader performs the reading'
lacks "$section" '(do not|never) (launch|use) (one|a single) fresh blind reader' \
  'launching the fresh blind reader is not directly negated'
has "$section" 'isolation pattern of `references/normative-remediation.md`' \
  'the reader reuses the normative-remediation isolation pattern'
has "$section" \
  '(without (invoking[^.]{0,20}extending|extending[^.]{0,20}invoking) that mechanism|that mechanism (is|must be|may be) neither invoked nor extended|((do|does|must|may|shall|should|can|will)( not|n.t)|never) (invoke[^.]{0,20}extend|extend[^.]{0,20}invoke) that mechanism)' \
  'the reader does not invoke or extend normative remediation'
for supplied in \
  'exact frozen criterion text' \
  'bounded raw governing context' \
  'raw triggering observation and its boundary'; do
  has "$section" "(supply|give it|provide) only[^.]*$supplied" \
    "the closed reader package supplies $supplied and nothing else"
done
lacks "$section" '(supply|give it|provide) only[^.;]*(prior ruling|adjudication ledger|previously rejected alternative)' \
  'no withheld item appears in the closed supply clause'
lacks "$section" '(withhold|never give|keep back)[^.]*but (supply|give|provide)' \
  'the withholding clause is not reversed mid-sentence'
has "$section" 'non-reviewing[^.]*(never|not) (reuse it as|be reused as) a review-axis agent' \
  'the reader is non-reviewing and never becomes a review axis in this chain'
for withheld in \
  'prior ruling' \
  'previously rejected alternative' \
  'adjudication ledger' \
  'prior reviewer conclusions and dispositions' \
  'current implementation except a bounded raw fact'; do
  has "$section" "(withhold|never give the reader|keep back from it)[^.]*$withheld" \
    "the reader is blind to the $withheld"
done
has "$section" '(enumerate|list) (them|every|each|all)[^.]{0,40}\bwith the concrete obligation' \
  'the reader enumerates every materially defensible reading and its obligation'
has "$section" '(must not|must never|may not) prefer a reading[^.]*cheaper' \
  'the reader may not prefer a reading for being cheaper'
has "$section" '(must not|must never|may not) propose an implementation' \
  'the reader proposes no implementation'
has "$section" '(reader|it) derives meaning only' 'the reader derives meaning only'
has "$section" '(primary retains adjudication authority|adjudication authority stays with the primary)' \
  'the primary retains adjudication authority'
has "$section" '(one|a single) fresh invocation may handle several eligible criterion units' \
  'several eligible units from one gate share a single fresh invocation'
echo 'ok - the fresh blind reader derives governing meaning from a bounded blind package'

## Uphold is one-shot; supersede removes mechanism and resets evidence.
has "$section" 'uphold[^.]*prior interpretation stands' \
  'upholding leaves the prior ruling in force'
has "$section" 'continue ordinary remediation and (do not|never) re-adjudicate `R` again in this run' \
  'an upheld ruling returns to ordinary remediation and cannot trigger again'
has "$section" 'one re-adjudication per Ambiguous ruling, (not|rather than) one per run' \
  'the one-shot limit is per ruling rather than a global per-run cap'
has "$section" '(remove mechanism no criterion requires[^.]{0,30}rather than hardening|rather than hardening it[^.]{0,20}remove mechanism no criterion requires)' \
  'superseding removes mechanism instead of hardening it'
lacks "$section" '(do not|never) remove mechanism no criterion requires[^.]*rather than hardening' \
  'Supersede removal is not directly negated'
lacks "$section" \
  '(remove mechanism no criterion requires[^.]*rather than hardening[^.]*(unless|except when|only if)|(unless|except when|only if)[^.]*remove mechanism no criterion requires[^.]*rather than hardening)' \
  'Supersede removal rather than hardening has no exception'
has "$section" '(keep|retain) any blocker portion that still applies to surviving candidate content' \
  'the surviving portion of the blocker is retained'
has "$section" '(freshly adjudicate|adjudicate afresh) under `references/validation-evidence.md`' \
  'evidence sufficiency is freshly adjudicated after a superseding reading'
has "$section" '(rerun|re-execute) (it )?where sufficiency requires' \
  'evidence is re-executed where the fresh adjudication requires it'
has "$section" 'reuse evidence only where it directly proves that obligation' \
  'evidence is reused only where it proves the newly adjudicated obligation'
has "$section" '(carry|inherit) no earlier `tested` disposition across the reversal' \
  'no prior tested disposition is silently inherited'
has "$section" 'correction[^.]{0,20}delta gate[^.]{0,30}fresh blind cumulative confirmation' \
  'the supersede route re-enters the existing correction and confirmation path'
echo 'ok - uphold is one-shot and supersede removes mechanism through the existing path'

## The immutability fence and reviewer blindness are preserved.
has "$section" "(frozen criterion bytes|criterion's frozen bytes) are unchanged" \
  're-adjudication requires identical frozen criterion bytes'
has "$section" "Validation-surface membership is unchanged" \
  're-adjudication requires unchanged Validation-surface membership'
has "$section" \
  'changed criterion text[^.]*obligation those bytes do not already carry[^.]*changed Validation-surface membership takes the existing trusted-maintainer or immutable-manifest hand-back' \
  'changed bytes or membership take the existing hand-back routes'
has "$section" 'hand-back[^.]*(is|are) never re-adjudicated here' \
  'a change outside the fence is never re-adjudicated by this mechanism'
has "$section" 'changes no frozen review-chain governing input' \
  're-adjudication changes no frozen review-chain governing input'
has "$section" 'ledger (stays out of|is withheld from) every reviewer package' \
  'the adjudication ledger remains hidden from reviewers'
has "$SKILL" \
  'materially defensible reading of an exact unchanged frozen criterion[^.]*membership is unchanged, is adjudication rather than a requirements change' \
  'SKILL.md grants the bounded right to reconsider without a requirements change'
echo 'ok - the immutability fence, reviewer blindness, and authority grant hold'

## Observability uses ordinary primary reasoning rather than a new protocol.
reporting_block="$fixture_dir/reporting-block.md"
awk -v RS='' '
  {
    lower = tolower($0)
    if (lower ~ /ordinary working reasoning/ &&
        lower ~ /(^|[^[:alnum:]_])(state|report)([^[:alnum:]_]|$)/) {
      print
      if ((getline adjacent) > 0 && adjacent ~ /^- /) {
        print ""
        print adjacent
      }
      exit
    }
  }
' "$section" >"$reporting_block"
if [[ ! -s "$reporting_block" ]]; then
  fail 'the section has an ordinary-working-reasoning reporting block'
fi
reporting_exemption='(not required to (be )?(state|report|stated|reported)|need not be (stated|reported)|(do not|never) (state|report))'
for reported in 'which ruling was re-adjudicated' 'the reader returned' \
  'upheld or superseded' 'evidence-sufficiency decision'; do
  has "$reporting_block" "$reported" "the reporting block names $reported"
  lacks "$reporting_block" \
    "($reported[^.]*$reporting_exemption|$reporting_exemption[^.]*$reported)" \
    "the reporting block gives $reported no explicit exemption"
done
echo 'ok - observability is ordinary primary reasoning'

## No new document, no expansion of normative remediation, no new naming.
mapfile -t references < <(cd "$skill_dir/references" &&
  find . -name '*.md' | sed 's|^\./||' | sort)
for reference in "${references[@]}"; do
  [[ "$skill_dir/references/$reference" == "$WORKFLOW" ]] && continue
  lacks "$skill_dir/references/$reference" \
    're-adjudicat|Ambiguous ruling|`D` descends from `R`' \
    "the mechanism does not expand or move into $reference"
done
lacks "$section" 'semantic challenge' \
  'the mechanism is not named with the normative-remediation term'
lacks "$SKILL" 'Ambiguous ruling[^.]*semantic challenge|semantic challenge[^.]*Ambiguous ruling' \
  'SKILL.md never names this mechanism a semantic challenge'
lacks "$section" 'telemetry schema|run registry|durable event protocol|new lifecycle' \
  'no telemetry, registry, or lifecycle machinery is introduced'
echo 'ok - the static surface gains no document, term, or lifecycle machinery'

if (( failures > 0 )); then
  printf '\n%s bounded-re-adjudication assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll bounded re-adjudication contract assertions held.\n'
