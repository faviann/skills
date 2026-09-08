# Logic prototype delivery

Read this before handing over a logic prototype. It governs the delivery portion of LOGIC.md's handoff; the interaction and iteration loop continue there. UI prototypes keep their existing route and development-server handoff.

Finish the self-contained HTML file in the worktree before attempting publication. That file is the canonical source for further edits and the existing throwaway-branch capture flow. Publication creates only a delivery copy: keep the canonical file in place and unchanged while publishing, and never move, link, or replace it with the published copy.

1. Check whether the model-invoked `/publish-artifact` skill is available.
   - Available: invoke `/publish-artifact` from the producing repository or worktree with producer `prototype`, the canonical file's absolute path as source, and that file's basename as the relative primary name. Reach it through the skill relationship; let the publisher resolve its own bundled command.
   - Unavailable and `FAVIANN_SKILLS_ARTIFACT_CONFIG` is unset: use LOGIC.md's existing send/open file handoff.
   - Unavailable and `FAVIANN_SKILLS_ARTIFACT_CONFIG` is set, including an empty value: report a delivery failure because the explicitly selected publication cannot run. Include the canonical worktree path for recovery.
2. Handle the publisher's result:
   - `published`: hand back the direct HTTP URL from `url` instead of the send/open file handoff. Keep the canonical worktree path available for iteration and branch capture.
   - `unconfigured`: use the existing send/open file handoff.
   - Any error, including dependency, configuration, or publication failure: report delivery failure and the canonical worktree path for recovery. Preserve any reported cleanup residual path. A local file remains recoverable, but local fallback does not turn failed publication into successful delivery.

Apply the same handoff after requested revisions. Continue editing and eventually capturing the canonical worktree file; a published generation is a delivery copy, not the prototype's primary source.
