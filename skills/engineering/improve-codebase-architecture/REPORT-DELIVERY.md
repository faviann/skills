# Report delivery

Finish the entire HTML report in the OS temporary file specified in step 2 before attempting delivery. Preserve its content, diagrams, CDN usage, and the candidate-selection and grilling flow. Keep the completed source unchanged during publication and retain it afterward for recovery, whatever the result. The producer writes only the temporary source; `/publish-artifact` owns the publication destination and copy.

This reference governs delivery instead of step 2's local-opening instruction when publication succeeds or delivery fails. Use the following branches before running any local opener:

| Condition | Action |
| --- | --- |
| `/publish-artifact` is available | Invoke `/publish-artifact` from the repository being reviewed with producer `improve-codebase-architecture`, the absolute path to the completed temporary report as source, and that report's basename as the relative primary name. Use its shared one-file interface, then handle the result below. |
| Publisher unavailable and `FAVIANN_SKILLS_ARTIFACT_CONFIG` unset | Preserve step 2's local opener attempt and absolute temporary-path handoff. This is the standalone-installation fallback. |
| Publisher unavailable and `FAVIANN_SKILLS_ARTIFACT_CONFIG` explicitly set, including an empty value | Report a delivery failure: the explicitly selected publication requires `/publish-artifact`. Return the recoverable absolute temporary source path; do not invoke a local opener or claim successful delivery. |

Treat the selector as set by its presence in the environment, not by whether its value is nonempty. Leave configuration discovery and validation to the publisher when it is available.

| Publisher result | Handoff |
| --- | --- |
| `published` | Return the direct HTTP(S) `url` and published `path`, and identify the retained absolute temporary source path for recovery. Do not invoke a local opener on the agent host. |
| `unconfigured` | Preserve step 2's local opener attempt and absolute temporary-path handoff. |
| `error`, invocation failure, or an unusable result | Report delivery failure with the publisher's available category and explanation, plus the recoverable absolute temporary source path. Dependency, configuration, and publication errors remain failures; do not invoke a local opener or describe local fallback as success. |
