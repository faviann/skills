#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
fixture="$(mktemp -d)"; trap 'rm -rf "$fixture"' EXIT
skills="$fixture/skills"; mkdir -p "$skills/skills/personal" "$skills/skills/engineering"
cp -R "$source_root/skills/personal/work-on" "$skills/skills/personal/work-on"
cp -R "$source_root/skills/engineering/tdd" "$skills/skills/engineering/tdd"
cp -R "$source_root/skills/engineering/code-review" "$skills/skills/engineering/code-review"
git -C "$skills" init -q -b main; git -C "$skills" config user.name Test; git -C "$skills" config user.email test@example.invalid
git -C "$skills" add .; git -C "$skills" commit -qm fixture; git -C "$skills" remote add origin https://github.com/example/skills.git
scripts="$skills/skills/personal/work-on/scripts"
repo="$fixture/repo"; git init -q -b main "$repo"; git -C "$repo" config user.name Test; git -C "$repo" config user.email test@example.invalid
printf 'base\n' >"$repo/base"; git -C "$repo" add .; git -C "$repo" commit -qm base
printf '%s\n' '- criterion: public seam' >"$fixture/manifest"
printf '%s\n' '{"body":"trusted"}' >"$fixture/snapshot"
workflow="$(cd "$repo" && "$scripts/workflow-provenance.sh" identify-workflow)"
freeze() { (cd "$repo" && "$scripts/manifest-identity.sh" freeze --manifest "$fixture/manifest" --snapshot "$fixture/snapshot" --base HEAD --workflow-identity "$workflow"); }
run1="$(freeze)"
cat >"$fixture/facts.json" <<'JSON'
{"issue_number":150,"outcome":"Closes","acceptance_criteria":["criterion"],"acceptance":[{"criterion":"criterion","production_path":"script","seam":"CLI","evidence":"passed","status":"tested"}]}
JSON
: >"$fixture/narrative"

render_new() {
  (cd "$repo" && "$scripts/render-closeout.sh" --run "$run1" "$1" "$2" --new-pr)
}

(cd "$repo" && "$scripts/render-closeout.sh" --run "$run1" "$fixture/facts.json" "$fixture/narrative" --new-pr) >"$fixture/body1"
grep -Fqx '## Issues' "$fixture/body1"; grep -Fqx '## Closure gate' "$fixture/body1"; grep -Fqx '## Work-on' "$fixture/body1"
! grep -Fq 'Workflow telemetry' "$fixture/body1"
canonical1="$(cd "$repo" && "$scripts/workflow-provenance.sh" read --run "$run1")"
grep -Fqx "Run $run1: $canonical1" "$fixture/body1"

# Consumers treat Run identity as opaque. The manifest binding covers custody
# content, not the encoding of the filename that addresses the trio.
opaque_run='opaque.run_150'
for suffix in .md .trusted-snapshot.json .provenance.json; do
  cp "$repo/.git/work-on-manifest/$run1$suffix" \
    "$repo/.git/work-on-manifest/$opaque_run$suffix"
  chmod 600 "$repo/.git/work-on-manifest/$opaque_run$suffix"
done
(cd "$repo" && "$scripts/render-closeout.sh" --run "$opaque_run" \
  "$fixture/facts.json" "$fixture/narrative" --new-pr) >"$fixture/opaque"
grep -Fqx "Run $opaque_run: $canonical1" "$fixture/opaque"

# Facts may arrive on stdin, and narrative Markdown remains byte-preserved
# behind the renderer-owned boundary for paragraph, list, and code shapes.
(cd "$repo" && "$scripts/render-closeout.sh" --run "$run1" - \
  "$fixture/narrative" --new-pr <"$fixture/facts.json") >"$fixture/stdin"
cmp -s "$fixture/body1" "$fixture/stdin"
cat >"$fixture/paragraph.md" <<'EOF'
Implemented the renderer.

### Validation

The public CLI passed.
EOF
render_new "$fixture/facts.json" "$fixture/paragraph.md" >"$fixture/paragraph-body"
awk '$0=="## Narrative"{x=1} x&&$0=="## Closure gate"{exit} x{print}' \
  "$fixture/paragraph-body" >"$fixture/paragraph-actual"
cat >"$fixture/paragraph-expected" <<'EOF'
## Narrative

Implemented the renderer.

### Validation

The public CLI passed.

EOF
cmp -s "$fixture/paragraph-expected" "$fixture/paragraph-actual"
cat >"$fixture/list-code.md" <<'EOF'
- renderer passed
- validator passed

```text
literal output
```
EOF
render_new "$fixture/facts.json" "$fixture/list-code.md" >"$fixture/list-code-body"
awk '$0=="## Narrative"{x=1} x&&$0=="## Closure gate"{exit} x{print}' \
  "$fixture/list-code-body" >"$fixture/list-code-actual"
{ printf '## Narrative\n\n'; cat "$fixture/list-code.md"; printf '\n'; } \
  >"$fixture/list-code-expected"
cmp -s "$fixture/list-code-expected" "$fixture/list-code-actual"

# Markdown table delimiters in facts stay readable without changing column shape.
jq '.acceptance_criteria[0]="Input | output" | .acceptance[0].criterion="Input | output"' \
  "$fixture/facts.json" >"$fixture/pipe.json"
render_new "$fixture/pipe.json" "$fixture/narrative" >"$fixture/pipe-body"
grep -Fqx '| Input &#124; output | script | CLI | passed | tested |' "$fixture/pipe-body"

reject_render() {
  if render_new "$1" "$fixture/narrative" >"$fixture/rejected.out" 2>/dev/null; then
    echo "malformed renderer input was accepted: $2" >&2; exit 1
  fi
  [[ ! -s "$fixture/rejected.out" ]]
}
printf '{not json\n' >"$fixture/malformed.json"; reject_render "$fixture/malformed.json" malformed-json
printf '[]\n' >"$fixture/non-object.json"; reject_render "$fixture/non-object.json" non-object
for mutation in \
  'del(.issue_number)' \
  '.issue_number="150"' \
  'del(.outcome)' \
  'del(.acceptance_criteria)' \
  '.acceptance_criteria[0]=""' \
  '.acceptance_criteria += [.acceptance_criteria[0]]' \
  'del(.acceptance)' \
  '.acceptance[0].status="instructional"' \
  '.acceptance[0].status="inferred"' \
  'del(.acceptance[0].evidence)' \
  '.acceptance_criteria += ["missing row"]' \
  '.acceptance += [{"criterion":"extra","production_path":"p","seam":"s","evidence":"e","status":"tested"}]' \
  '.acceptance += [.acceptance[0]]'; do
  jq "$mutation" "$fixture/facts.json" >"$fixture/mutated.json"
  reject_render "$fixture/mutated.json" "$mutation"
done

# Exactly one render mode and complete frozen custody are mandatory.
if (cd "$repo" && "$scripts/render-closeout.sh" --run "$run1" \
    "$fixture/facts.json" "$fixture/narrative") >/dev/null 2>&1; then
  echo 'renderer accepted no render mode' >&2; exit 1
fi
if (cd "$repo" && "$scripts/render-closeout.sh" --run opaque-partial \
    "$fixture/facts.json" "$fixture/narrative" --new-pr) >/dev/null 2>&1; then
  echo 'renderer accepted incomplete custody' >&2; exit 1
fi

# A renderer candidate rejected by its shipped validator is never emitted.
cp -R "$skills" "$fixture/drifted-skills"
drifted="$fixture/drifted-skills/skills/personal/work-on/scripts"
cat >"$drifted/validate-closeout-body.sh" <<'EOF'
#!/usr/bin/env bash
printf 'closeout body invalid: scripted validator drift\n' >&2
exit 1
EOF
chmod +x "$drifted/validate-closeout-body.sh"
if (cd "$repo" && "$drifted/render-closeout.sh" --run "$run1" \
    "$fixture/facts.json" "$fixture/narrative" --new-pr) \
    >"$fixture/drift.out" 2>"$fixture/drift.err"; then
  echo 'renderer emitted a validator-rejected candidate' >&2; exit 1
fi
[[ ! -s "$fixture/drift.out" ]]
grep -Fq 'scripted validator drift' "$fixture/drift.err"

# Closeout consumes custody after an authorized live self-change and with the
# telemetry and registry implementations absent.
printf '\nself change\n' >>"$skills/skills/personal/work-on/SKILL.md"
rm "$scripts/run-telemetry.sh" "$scripts/run-registry.sh"
mv "$skills/skills/personal/work-on/references/default-workflow.md" \
  "$fixture/removed-default-workflow.md"
(cd "$repo" && "$scripts/render-closeout.sh" --run "$run1" "$fixture/facts.json" "$fixture/narrative" --previous-body "$fixture/body1") >"$fixture/same"
cmp -s "$fixture/body1" "$fixture/same"

# Restore governing bytes only to mint a distinct second run.
git -C "$skills" restore skills/personal/work-on/SKILL.md skills/personal/work-on/references/default-workflow.md skills/personal/work-on/scripts/run-telemetry.sh skills/personal/work-on/scripts/run-registry.sh
run2="$(freeze)"
(cd "$repo" && "$scripts/render-closeout.sh" --run "$run2" "$fixture/facts.json" "$fixture/narrative" --previous-body "$fixture/body1") >"$fixture/body2"
mapfile -t run_lines < <(awk '$0=="## Work-on"{x=1;next}x&&/^Run /{print}' "$fixture/body2")
[[ "${#run_lines[@]}" -eq 2 && "${run_lines[0]}" == "Run $run1: $canonical1" && "${run_lines[1]}" == "Run $run2: "* ]]

sed "s|^Run $run1: .*|Run $run1: work-on:000000000000 workflow:000000000000 tdd:000000000000 review:000000000000 (unknown@0000000)|" "$fixture/body1" >"$fixture/contradictory"
if (cd "$repo" && "$scripts/render-closeout.sh" --run "$run1" "$fixture/facts.json" "$fixture/narrative" --previous-body "$fixture/contradictory") >/dev/null 2>"$fixture/err"; then
  echo 'contradictory same-identity provenance was accepted' >&2; exit 1
fi
grep -Fq 'already has contradictory provenance' "$fixture/err"

cat >"$fixture/legacy" <<EOF
## Issues

old text

## Closure gate

This is a counterfeit narrative closure gate.

## Work-on

This is old free-form narrative, not mechanical run history.

## Closure gate

old closure content

## Workflow telemetry

Run 1: $canonical1
Run 2: work-on:111111111111 workflow:222222222222 tdd:333333333333 review:444444444444 (unknown@abcdef1)
EOF
(cd "$repo" && "$scripts/render-closeout.sh" --run "$run2" "$fixture/facts.json" "$fixture/narrative" --previous-body "$fixture/legacy") >"$fixture/migrated"
grep -Fqx "Legacy run: $canonical1" "$fixture/migrated"
grep -Fqx 'Legacy run: work-on:111111111111 workflow:222222222222 tdd:333333333333 review:444444444444 (unknown@abcdef1)' "$fixture/migrated"
! grep -Fq '## Workflow telemetry' "$fixture/migrated"
! grep -Fq 'This is old free-form narrative' "$fixture/migrated"
! grep -Fq 'This is a counterfeit narrative closure gate' "$fixture/migrated"

render_rejected() {
  if (cd "$repo" && "$scripts/render-closeout.sh" --run "$run2" "$1" \
      "$fixture/narrative" --new-pr) >/dev/null 2>&1; then
    echo "removed facts field was accepted: $2" >&2
    exit 1
  fi
}
for shape in '{}' '[]' 'null' '"reported"' '0'; do
  jq --argjson shape "$shape" '.telemetry=$shape' "$fixture/facts.json" \
    >"$fixture/telemetry.json"
  render_rejected "$fixture/telemetry.json" "telemetry=$shape"
done
for field in repository provenance workflow_provenance runs phases; do
  jq --arg field "$field" '. + {($field): "removed"}' "$fixture/facts.json" \
    >"$fixture/removed-field.json"
  render_rejected "$fixture/removed-field.json" "$field"
done

flat="$(tr '\n' ' ' <"$skills/skills/personal/work-on/references/github-closeout.md")"
[[ "$flat" == *'Put only the four authored facts'* && "$flat" == *'never verifies live instruction files'* && "$flat" == *'Finished old pull requests are otherwise left alone'* ]]
echo 'render-closeout black-box scenarios passed'
