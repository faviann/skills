## What it does

Publish Artifact copies one completed file or prepared directory tree beneath a host-configured web root and returns the primary file's filesystem path and direct HTTP URL as JSON. It is for artifacts produced on a remote machine that you want to open in your own browser.

The configured mapping is optional, but never vague: an absent default configuration reports `unconfigured`, while an explicitly selected, invalid, or operationally broken setup fails with a stable category. The publisher does not test the URL or silently invent a local fallback.

## When to reach for it

Type `/publish-artifact`, or the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) reaches for it automatically when a completed artifact needs remote browser access. Reach for it after a producer has finished an HTML report, image, or prepared tree with linked assets.

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

`directory` is the existing filesystem root; `baseUrl` is the HTTP(S) URL that serves the same root. The URL accepts a hostname, IPv4 address, or bracketed IPv6 authority and optional port, with no query or fragment. Illegal host characters, malformed authority percent escapes, invalid dotted IPv4, and out-of-range ports are configuration errors. Set `FAVIANN_SKILLS_ARTIFACT_CONFIG` when one session needs a different configuration. Every invocation snapshots its selected file once, and the next invocation sees later changes.

Published files sit beneath readable repository and producer groups, then a UTC timestamp with a random suffix. Linked worktrees share the primary checkout's repository group, so temporary branch and worktree names do not fragment the collection.

## The exact publication set

- A file source publishes that file and returns its direct URL.
- A directory source publishes every regular file and directory beneath it, preserving relative paths, hidden entries, and empty directories. Identify one contained regular file as primary; if your request leaves that choice ambiguous, the agent asks you to name it.

Prepare only the files you intend to publish. The publisher does not filter a broad directory, combine roots, or transform content. It refuses source symlinks, special filesystem entries, traversal, control characters, and invalid UTF-8 names. Ordinary names, including spaces and Unicode, are encoded per URL path segment. Keep the completed source unchanged until publication returns.

Preparation space and publication space must not overlap. The source and publishing root cannot resolve to the same location or contain one another, including through a configured root symlink. Overlap returns `invalid-call` before writing, so repeated publication cannot pull earlier generations into a later copy.

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
- A directory's linked assets retain their relative layout beside the selected primary file.
- Concurrent publications land in different generation directories, including when they come from linked worktrees.
- Invalid configuration and failed copies return a nonzero result with a stable error category instead of falling back.

## Where it fits

This is a reach-for-it-anytime standalone and a shared delivery adapter for skills that produce browser-viewable files. It owns publishing mechanics so producers can own their artifacts. See [ask-matt](https://aihero.dev/skills-ask-matt) for the map of the whole skill set.

[improve-codebase-architecture](https://aihero.dev/skills-improve-codebase-architecture) uses it to deliver completed reports, and [prototype](https://aihero.dev/skills-prototype) uses it for logic demos while retaining their canonical worktree files.
