## What it does

Publish Artifact copies one completed file beneath a host-configured web root and returns both its filesystem path and direct HTTP URL as JSON. It is for files produced on a remote machine that you want to open in your own browser.

The configured mapping is optional, but never vague: an absent default configuration reports `unconfigured`, while an explicitly selected, invalid, or operationally broken setup fails with a stable category. The publisher does not test the URL or silently invent a local fallback.

## When to reach for it

Type `/publish-artifact`, or the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) reaches for it automatically when a completed file needs remote browser access. Reach for it after a producer has finished a single HTML report, image, or other file; directory trees are not supported in this version.

## Prerequisites

Publication runs on Linux with Bash and `jq`; publishing from a linked worktree also requires Git so the primary-checkout group can be derived. Outside Git, the invocation-directory name is used. The host operator must provide an existing publishing directory and arrange for a web server to expose it. The skill never creates that root or changes its permissions, ownership, access control, or retention.

## One host mapping

The default file is `${XDG_CONFIG_HOME:-$HOME/.config}/faviann-skills/artifacts.json`:

```json
{
  "directory": "/srv/artifacts",
  "baseUrl": "https://artifacts.example.com/files"
}
```

`directory` is the existing filesystem root; `baseUrl` is the HTTP(S) URL that serves the same root. The URL accepts a non-bracketed host authority and optional port, with no query or fragment; bracketed IP literals are not supported in this version. Set `FAVIANN_SKILLS_ARTIFACT_CONFIG` when one session needs a different configuration. Every invocation snapshots its selected file once, and the next invocation sees later changes.

Published files sit beneath readable repository and producer groups, then a UTC timestamp with a random suffix. Linked worktrees share the primary checkout's repository group, so temporary branch and worktree names do not fragment the collection.

## Common questions

**What happens on a machine where I have not configured publishing?**

An absent default configuration returns a successful `unconfigured` result. A producer can preserve its normal local handoff. If you explicitly select a configuration, its absence is an error because your request to publish should not disappear silently.

**Can the configured root be a symlink or mount?**

Yes. Infrastructure may map the root that way. Everything the publisher owns beneath its canonical location must remain a real directory or regular file; descendant symlinks are refused.

**Does a returned URL prove that my web server can serve the file?**

No. The result is derived from the configured filesystem-to-URL mapping, and the publisher makes no HTTP request. Serving, authentication, VPN access, and reachability remain host concerns.

## It's working if

- An unconfigured machine returns one `{"status":"unconfigured"}` result without creating directories.
- A configured publication returns one JSON result whose `path` is a copied regular file and whose `url` names that exact relative path under `baseUrl`.
- Concurrent publications land in different generation directories, including when they come from linked worktrees.
- Invalid configuration and failed copies return a nonzero result with a stable error category instead of falling back.

## Where it fits

This is a reach-for-it-anytime standalone and a shared delivery adapter for skills that produce browser-viewable files. It owns publishing mechanics so producers can own their artifacts. See [ask-matt](https://aihero.dev/skills-ask-matt) for the map of the whole skill set.
