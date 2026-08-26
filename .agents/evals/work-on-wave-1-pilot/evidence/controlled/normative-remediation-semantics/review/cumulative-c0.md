Cumulative review assignment: independently review the exact cumulative
candidate against the full accepted review contract.
- Comparison-base identity: commit/tree endpoint `dea1579185416cfa0bd4198bb2b904bae67d96ba`.
- Exact current Candidate identity: clean commit/tree endpoint `836989632875cc3020a579b2415601f6f4a29208`.
- Mechanically exact cumulative diff: the two-endpoint command
  `git diff dea1579185416cfa0bd4198bb2b904bae67d96ba^{tree} 836989632875cc3020a579b2415601f6f4a29208^{tree}` produces exactly:

```diff
diff --git a/bin/check-access b/bin/check-access
index b7d35e4..814c6c0 100755
--- a/bin/check-access
+++ b/bin/check-access
@@ -6,6 +6,6 @@ project="${2:?project required}"
 if [[ "$owner" == "$project" ]]; then
   echo allowed
 else
-  echo denied
+  echo "denied: $project"
   exit 1
 fi
diff --git a/test.sh b/test.sh
index e2f7613..7004446 100755
--- a/test.sh
+++ b/test.sh
@@ -7,6 +7,6 @@ if "$root/bin/check-access" alpha beta >"$root/.denied.out" 2>&1; then
   echo "cross-project access unexpectedly allowed" >&2
   exit 1
 fi
-grep -qx denied "$root/.denied.out"
+grep -qx 'denied: beta' "$root/.denied.out"
 rm -f "$root/.denied.out"
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
- Qualifying raw validation evidence: exact clean Candidate `836989632875cc3020a579b2415601f6f4a29208`; primary execution `bash test.sh` from repository root exited 0 with stdout `fixture tests: pass`; safe provenance locator: telemetry run `20260826T002100Z-0196225d`, phase `gate`, round `1`, command-id `work-on-tests`. This evidence directly exercises AC1/AC4 only; no policy-file assertion exists in this Candidate.
