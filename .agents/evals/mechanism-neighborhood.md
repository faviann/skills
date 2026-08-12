# Mechanism-neighborhood pilot

Date: 2026-08-12

This proportionate pilot tests the compact reviewer brief added for #62. It is
not the issue's full three-samples-per-arm comparison; filtered runs count as
missing data, never as successes or failures.

## Fixtures and results

| Fixture | Pinned artifact | Successful fresh samples | Result |
|---|---|---:|---|
| Path resolution | `faviann/homelab-iac@6ec521639fb16af759d07fee0305160bd4274d71` | 2 | Both grouped the runbook seed with repository-root and identity siblings, cited separate locations and impacts, and stopped at the three `Path.resolve(strict=True)` sites. |
| Untrusted diagnostic | `faviann/homelab-iac@a2cc9885bf6f1eea2ecefbfbbf02fb320ff1f055` | 1 | Grouped raw Compose stderr with the adjacent process-launch diagnostic, reproduced both through public renderings, and stopped at the Compose subprocess boundary. |
| No-sibling control | Stored below | 1 | Returned only the malformed-JSON seed, distinguished additional inputs at the same location from siblings, and stated the stop boundary. |

Before the final wording, three fresh path-resolution baseline samples all
reproduced the runbook seed and none found the repository-root sibling. The two
successful final-wording samples therefore simulate one remediation/gate round
instead of two for that fixture. One final path sample and two decoded-shape
attempts returned no usable result and are omitted.

The pilot supports adopting the brief: it preserved the seed, increased
reproduced same-mechanism findings on the path fixture, and did not pad the
control. It does not establish #62's full adoption thresholds or the expected
decoded-shape behavior.

## No-sibling control

```python
import json
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class ConfigResult:
    value: dict[str, object] | None
    error: str | None

def read_config(path: Path) -> ConfigResult:
    decoded = json.loads(path.read_text())
    if not isinstance(decoded, dict):
        return ConfigResult(None, "configuration must be an object")
    return ConfigResult(decoded, None)
```

Contract: malformed JSON returns
`ConfigResult(None, "malformed configuration")`. Seed: the file contains
`{"enabled":`. The immediate neighborhood has one decode operation, one call
site with valid object JSON, and the decoded non-object branch.
