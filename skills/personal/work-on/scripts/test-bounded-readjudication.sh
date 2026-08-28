#!/usr/bin/env bash
set -euo pipefail

# Bounded re-adjudication is one inline workflow contract with an authority
# clarification in SKILL.md. Exercise the seams a wrong implementation would
# break: eligibility, attribution, the blind package, the one-shot property,
# the supersede routing, the immutability fence, and the static surface.
#
# Assertions bind obligations, not sentences. Two rules keep both halves of
# that honest: alternate over the function words a rewrite legitimately
# changes (must not/may not/never, keep no/introduce no, one/a single), and
# never let a gap span a negation or a sentence boundary that could invert the
# obligation. Prefer [^.] over . wherever a sentence boundary is load-bearing.

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
    fail "$3 (missing in ${1#"$skill_dir/"}: $2)"
  fi
}

lacks() {
  if grep -Eqi -- "$2" "$(flatten "$1")"; then
    fail "$3 (unexpected in ${1#"$skill_dir/"}: $2)"
  fi
}

extract_section() {
  local source="$1" heading="$2" output="$3"
  awk -v heading="$heading" '
    $0 == heading { inside = 1 }
    inside && $0 != heading && /^#{1,3} / { exit }
    inside { print }
  ' "$source" >"$output"
}

heading="$(grep -m1 '^### Bounded re-adjudication' "$WORKFLOW" || true)"
section="$fixture_dir/readjudication-section.md"
[[ -n "$heading" ]] && extract_section "$WORKFLOW" "$heading" "$section"
[[ "$heading" == *Ambiguous* ]] ||
  fail 'the section heading names the Ambiguous ruling it governs'
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
has "$section" 're-adjudicate `R` (exactly once|once and only once|only once)' \
  'a qualifying trigger produces exactly one re-adjudication'
has "$section" 'classified \*\*Ambiguous\*\*' 'only an Ambiguous ruling qualifies'
has "$section" \
  '(Contract-backed and Defensive|Defensive and Contract-backed) rulings? (are|is) ineligible' \
  'Contract-backed and Defensive rulings are ineligible'
lacks "$section" '(Contract-backed|Defensive)[^.]{0,40}(are|is) eligible' \
  'no ineligible classification is admitted as eligible'
has "$section" '`D` produced the current remediation candidate' \
  'the triggering directive produced the current remediation candidate'
has "$section" 'accepted blocker.*attributable to the mechanism introduced\s+for `D`' \
  'the trigger requires a blocker attributable to the Ambiguous directive'
has "$section" '(immediately following delta gate|delta gate that immediately follows)' \
  'the trigger window is the immediately following delta gate'
has "$section" 'does not trace to `D`.s mechanism (takes|proceeds through) ordinary remediation' \
  'an unattributable blocker at the same gate does not trigger the mechanism'
echo 'ok - eligibility is limited to Ambiguous rulings whose own mechanism reproduced a blocker'

## The association is transient working state, not a lineage system.
has "$section" 'run-local note[^.]*`D` descends from `R`' \
  'the association records only that the directive descends from the ruling'
for forbidden in 'lineage store' 'registry' 'lifecycle' 'event protocol' \
  'telemetry' 'persistent correlation state'; do
  has "$section" "(keep|introduce|add) no[^.]*$forbidden" \
    "the association introduces no $forbidden"
done
has "$section" '(drop|discard) it once that gate is adjudicated' \
  'the association is bounded to the immediate delta window'
echo 'ok - the directive-to-ruling association is transient run-local state'

## The reader is fresh, blind, non-reviewing, and derives meaning only.
has "$section" 'launch (one|a single) fresh blind reader' \
  'one fresh blind reader performs the reading'
has "$section" 'isolation pattern of `references/normative-remediation.md` without invoking or extending' \
  'the reader reuses the isolation pattern without importing that mechanism'
for supplied in \
  'exact frozen criterion text' \
  'bounded raw governing context' \
  'raw triggering observation and its boundary'; do
  has "$section" "(supply|give it) only[^.]*$supplied" \
    "the closed reader package supplies $supplied and nothing else"
done
has "$section" 'reader is non-reviewing' 'the reader is non-reviewing'
has "$section" 'never reuse it as a review-axis agent' \
  'the reader never becomes a review axis in this chain'
for withheld in \
  'prior ruling' \
  'previously rejected alternative' \
  'adjudication ledger' \
  'prior reviewer conclusions and dispositions' \
  'current implementation except a bounded raw fact'; do
  has "$section" "(withhold|never give the reader)[^.]*$withheld" \
    "the reader is blind to the $withheld"
done
has "$section" '(enumerate|list) (them|every|each|all)[^.]{0,60}concrete obligation' \
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
has "$section" 'uphold.*prior interpretation stands' 'upholding leaves the prior ruling in force'
has "$section" 'continue ordinary remediation and do not re-adjudicate `R` again in this run' \
  'an upheld ruling returns to ordinary remediation and cannot trigger again'
has "$section" 'one re-adjudication per Ambiguous ruling, (not|rather than) one per run' \
  'the one-shot limit is per ruling rather than a global per-run cap'
has "$section" '(remove mechanism no criterion requires.{0,30}rather than hardening|rather than hardening it.{0,20}remove mechanism no criterion requires)' \
  'superseding removes mechanism instead of hardening it'
has "$section" 'keep any blocker portion that still applies to surviving candidate content' \
  'the surviving portion of the blocker is retained'
has "$section" '(freshly adjudicate|adjudicate afresh) under `references/validation-evidence.md`' \
  'evidence sufficiency is freshly adjudicated after a superseding reading'
has "$section" '(rerun|re-execute) (it )?where sufficiency requires' \
  'evidence is re-executed where the fresh adjudication requires it'
has "$section" 'reuse evidence only where it directly proves that obligation' \
  'evidence is reused only where it proves the newly adjudicated obligation'
has "$section" '(carry|inherit) no earlier `tested` disposition across the reversal' \
  'no prior tested disposition is silently inherited'
has "$section" 'correction.{0,20}delta gate.{0,30}fresh blind cumulative confirmation' \
  'the supersede route re-enters the existing correction and confirmation path'
echo 'ok - uphold is one-shot and supersede removes mechanism through the existing path'

## The immutability fence and reviewer blindness are preserved.
has "$section" '(frozen criterion bytes|criterion.s frozen bytes) are unchanged' \
  're-adjudication requires identical frozen criterion bytes'
has "$section" "Validation-surface membership is unchanged" \
  're-adjudication requires unchanged Validation-surface membership'
has "$section" \
  'changed criterion text.*obligation those bytes do not already carry.*changed Validation-surface membership.*trusted-maintainer or immutable-manifest hand-back' \
  'changed bytes or membership take the existing hand-back routes'
has "$section" 'changes no frozen review-chain governing input' \
  're-adjudication changes no frozen review-chain governing input'
has "$section" 'ledger (stays out of|is withheld from) every reviewer package' \
  'the adjudication ledger remains hidden from reviewers'
has "$SKILL" \
  'materially defensible reading of an exact unchanged frozen criterion.*Validation-surface membership is unchanged.*adjudication rather than a requirements change' \
  'SKILL.md grants the bounded right to reconsider without a requirements change'
echo 'ok - the immutability fence, reviewer blindness, and authority grant hold'

## Observability uses ordinary primary reasoning rather than a new protocol.
for reported in 'which ruling was re-adjudicated' 'the reader returned' \
  'upheld or superseded' 'evidence-sufficiency decision'; do
  has "$section" "(state|report) in ordinary working reasoning[^.]*$reported" \
    "the reporting obligation itself names $reported"
done
echo 'ok - observability is ordinary primary reasoning'

## No new document, no expansion of normative remediation, no new naming.
mapfile -t references < <(cd "$skill_dir/references" &&
  find . -name '*.md' -printf '%P\n' | sort)
expected='closability-gate.md default-workflow.md github-closeout.md normative-remediation.md review-state-machine.md validation-evidence.md'
if [[ "${references[*]}" != "$expected" ]]; then
  fail "no new reference document is introduced (found: ${references[*]})"
fi
while IFS= read -r reference; do
  [[ "$reference" == "$WORKFLOW" ]] && continue
  lacks "$reference" 're-adjudicat|Ambiguous ruling' \
    "the mechanism does not expand or move into ${reference##*/}"
done < <(find "$skill_dir/references" -name '*.md')
lacks "$section" 'semantic challenge' \
  'the mechanism is not named with the normative-remediation term'
lacks "$SKILL" 'semantic challenge' \
  'SKILL.md never names the mechanism a semantic challenge'
lacks "$section" 'telemetry schema|run registry|durable event protocol|new lifecycle' \
  'no telemetry, registry, or lifecycle machinery is introduced'
echo 'ok - the static surface gains no document, term, or lifecycle machinery'

if (( failures > 0 )); then
  printf '\n%s bounded-re-adjudication assertion(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll bounded re-adjudication contract assertions held.\n'
