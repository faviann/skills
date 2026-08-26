Delta review assignment: independently review the exact candidate delta against
the full accepted review contract.
- Previous Reviewed-anchor identity: clean commit/tree endpoint
  `836989632875cc3020a579b2415601f6f4a29208`.
- Exact current Candidate identity: clean commit/tree endpoint
  `4146125269f0ea351912ab8606825a809b48628e`.
- Mechanically exact delta: the two-endpoint command
  `git diff 836989632875cc3020a579b2415601f6f4a29208^{tree} 4146125269f0ea351912ab8606825a809b48628e^{tree}` produces exactly:

```diff
diff --git a/POLICY.md b/POLICY.md
index d0fa805..fedb335 100644
--- a/POLICY.md
+++ b/POLICY.md
@@ -1,6 +1,6 @@
 # Access and retention policy
 
-Operators may read reports only for projects they own.
+Operators may read reports only when they own the project.
 
 Records within an active staging scope must use the retention window assigned
 by that scope.
diff --git a/test.sh b/test.sh
index 7004446..5ea6a26 100755
--- a/test.sh
+++ b/test.sh
@@ -9,4 +9,5 @@ if "$root/bin/check-access" alpha beta >"$root/.denied.out" 2>&1; then
 fi
 grep -qx 'denied: beta' "$root/.denied.out"
 rm -f "$root/.denied.out"
+grep -Fqx 'Operators may read reports only when they own the project.' "$root/POLICY.md"
 echo "fixture tests: pass"
```

- Full trusted contract: exact source-labelled content at
  `.git/work-on-manifest/20260826T002100Z-0196225d.trusted-snapshot.json`, SHA-256
  `258b2daa616659a52287164f04d58c71a4027ec4e2de3989400e72829ac2e5b1`.
- Binding Standards input: exact source-labelled content at
  `.git/work-on-review/20260826T002100Z-0196225d/frozen-standards.md`, SHA-256
  `0ffa2e85d0f8fa8ce5c9fc4338ae660a555978fd75f61840370c7d3cda96af4c`.
- Validation-surface manifest: exact frozen content at
  `.git/work-on-manifest/20260826T002100Z-0196225d.md`, SHA-256
  `200cf45f3bbf2d4b2ca2effa71ee1c3a8ba76756fe4a5c1a79e73c96f7f7967e`.
- Accepted full review contract: exact content at
  `.git/work-on-review/20260826T002100Z-0196225d/accepted-full-review-contract.md`,
  SHA-256
  `5761880135cc6ea43ac94c5809f138aa93a9c23db82f3e2bd5a14f025455c723`.
- Qualifying raw validation evidence: exact clean Candidate
  `4146125269f0ea351912ab8606825a809b48628e`; primary execution `bash test.sh`
  from repository root exited 0 with stdout `fixture tests: pass`; safe
  provenance locator: telemetry run `20260826T002100Z-0196225d`, phase
  `remediation`, round `1`, command-id `work-on-tests`.
- Review scope: Begin at the exact correction delta. Inspect unchanged context
  only for a recorded concrete contract question, changed-mechanism question,
  reproduced finding or seed, or #62 same-mechanism neighborhood investigation.
  For #62, stay inside the same mechanism, governing criterion, and public flow;
  stop before another criterion, subsystem, external boundary, or speculative
  defense. Do not routinely reconstruct, repackage, or reread the full
  cumulative candidate.
