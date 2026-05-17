---
name: pensieve-verify-project
description: Verifies a vault project meta note is still aligned with the project's remote default branch — one cheap GitHub API call to compare `sync.last_synced_commit` against HEAD, plus file-level drift if they diverge. Use this skill before relying on any project meta other than the one for the current working repo, per the verification rules in `rules/pensieve-routing.md`. Trigger phrases: "verify the project meta", "is bicycle-handlebar up to date", "check that vault record against github", "before I answer about project X", "freshness check on the project meta".
---

# pensieve-verify-project

Cheap, lazy freshness check. Sub-second when `gh` is authenticated. Run this before trusting a project meta for anything beyond a passing reference.

## When to invoke

Per `rules/pensieve-routing.md`, verify when ANY of:

- `sync.last_verified_at` is more than `[verification].ttl_hours` old (default 12h)
- The user just signaled a recent change to that project ("we just merged a PR in X", "I restructured the docs", etc.)
- The frontmatter has explicit signal that something is off (`sync.last_seen_drift.doc_files_changed > 0`, `paths_missing > 0`, `default_branch_changed: true`)
- You're about to make a decision that depends on the project's current shape

Skip verification when the project being referenced **is** the current working repo — the SessionStart hook already did local drift detection for that one.

## Inputs you need

- `slug`: the project slug

## Procedure

1. **Load the project meta.** Call `read_note(identifier="projects/<slug>")`. Extract `repo` (URL), `default_branch`, and `sync.last_synced_commit`. If any is missing the meta is malformed — surface that and recommend `pensieve-reconcile` instead.

2. **Check the verify-cache.** Look at `~/.cache/the-pensieve/verify/<slug>.json` (filesystem read; this is local cache, not vault). If it exists, has a `verified_at` within `[verification].ttl_hours` of now, AND no override signal applies, return its result without an API call.

3. **Resolve HEAD via gh.** Run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/verify-commit.sh "<repo>" "<default_branch>"
   ```
   The script parses owner/repo from the URL and calls `gh api repos/<owner>/<repo>/commits/<default_branch> --jq .sha`. If it fails (network, auth, or branch missing), surface the error verbatim and stop — do not silently mark the project verified.

4. **Compare.**
   - **Match** → update `sync.last_verified_at` to now via `pensieve-update-meta`, write `~/.cache/the-pensieve/verify/<slug>.json` with `{"verified": true, "verified_at": "<ISO>", "sha": "<sha>"}`, return `verified: true`.
   - **Mismatch** → compute file-level drift:
     ```bash
     gh api "repos/<owner>/<repo>/compare/<last_synced_commit>...<current_head>" --jq '.files[].filename'
     ```
     Count total files and the subset matching the doc-pattern regex from config (default `\.(md|mdx)$|^docs/|^adr/|^CONTEXT\.md|^README\.md`). Then call `pensieve-update-meta` once to update `sync.last_verified_at` and `sync.last_seen_drift.{files_changed,doc_files_changed}`. Write the verify-cache file with `{"verified": false, ...}`. Return the breakdown to the caller along with a recommendation to run `pensieve-reconcile` before relying on the meta.

5. **Trigger cache eviction.** After any write to `~/.cache/the-pensieve/verify/`, run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/cache-manager.sh verify
   ```

## Output to the agent that called this skill

Structured, short:

```
verified: true | false
slug: <slug>
last_synced_commit: <sha>
current_head: <sha>
files_changed: <N>
doc_files_changed: <N>
recommendation: <"proceed" | "run pensieve-reconcile before trusting this meta">
```

Pass that back to the calling context. Do **not** auto-invoke reconcile; the user decides.

## Constraints

- One API call on the hot path. Don't fetch contents or compare twice.
- The verify cache is **local only** (`~/.cache/the-pensieve/verify/`). Never write to the vault directly from this skill — all vault writes go through `pensieve-update-meta`, which keeps the mirror in sync.
- If the project meta has a custom `remote` field (other than `origin`), respect it when parsing the repo URL.
