---
name: pensieve-fetch-project
description: Fetches a specific document (CONTEXT.md, an ADR, README, custom doc path) from another project's remote default branch — for when you're working in repo A and need a file from repo B without cloning it. Use this skill whenever an agent needs cross-repo context. Trigger phrases: "grab the CONTEXT.md from project X", "what does bicycle-handlebar's README say", "fetch the latest ADR from claude-mem0-plugin", "I need the design doc from the other project", "pull project X's pipeline notes".
---

# pensieve-fetch-project

Fetches one doc from another project's remote default branch. Verifies first (if past TTL), then either reads from a local clone (`git show origin/<branch>:<path>`) or falls back to `gh api ... contents`. Caches results locally.

## Inputs you need

- `slug`: the project slug
- `doc`: either a key from the project meta's `docs.*` map (e.g. `context`, `readme`, `adrs`, `custom.pipeline_notes`) OR an explicit path relative to the repo root

If neither is given, ask the user which doc they want. Don't guess.

## Procedure

1. **Verify freshness first.** Invoke `pensieve-verify-project` for this slug if `sync.last_verified_at` is past TTL OR the user signaled a recent change. If verification reports drift, surface it to the user and let them decide whether to fetch anyway — stale doc content may be misleading.

2. **Load the project meta.** Call `read_note(identifier="projects/<slug>")`. Extract `repo`, `default_branch`, `repo_path` (if present — used for local-clone shortcut), and the relevant `docs.*` entry.

3. **Resolve the path.** If the input was a `docs.*` key, look up the value in the frontmatter. If it was an explicit path, use it as-is. If the resolved path is a directory (e.g. `docs/adr/`), ask the user which file they want — fetching whole directories is out of scope.

4. **Check the fetch cache.** Look at `~/.cache/the-pensieve/fetch/<slug>/<path>` (filesystem read; local cache, not vault). If it exists AND its mtime is within `[cache].ttl_days` (default 14) AND no signal suggests staleness, return the cached content.

5. **Fetch.** Run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/fetch-remote-doc.sh "<repo>" "<default_branch>" "<path>" "<repo_path>"
   ```
   The script prefers `git show origin/<branch>:<path>` when a local clone is at `repo_path`, falls back to `gh api ... contents` otherwise. Authenticates via the user's logged-in `gh` session for private repos.

6. **Cache it.** Write the fetched content to `~/.cache/the-pensieve/fetch/<slug>/<path>` (create parent dirs as needed). Then run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/cache-manager.sh fetch
   ```
   to enforce TTL + LRU bounds.

7. **Stale-frontmatter check.** If the fetched file's shape contradicts what the frontmatter implied (e.g. you fetched `CONTEXT.md` and it 404'd, or it exists but is structured very differently from the `docs.*` map suggests), surface this to the user and propose calling `pensieve-update-meta` (or running a full `pensieve-reconcile`). Don't silently update — the user owns the call.

## Output

Return the file contents and a short freshness header:

```
slug: <slug>
path: <resolved path>
source: local-clone | gh-api | cache
fetched_at: <ISO>
content:
<actual file content>
```

## Constraints (from spec §6.5 + §13)

- The fetch cache is **outside** the vault. Never write fetched content into the vault.
- Every cache write is followed by a `cache-manager.sh` run.
- If the user passes `--no-cache` (or otherwise signals they want fresh content), skip step 4 and force the fetch. Default is to use the cache when available.
- Respect a `remote: <name>` field in the project meta if present — pass it through to the fetch script (extension point: the current script assumes `origin`; flag if you hit a multi-remote project before fetching).
