---
description: Read-only sanity check — prints the configured vault endpoint, the current project (if any), last sync info from the meta-mirror, and the local cache size. Writes nothing to the vault.
---

# /pensieve-status

Quick health check. Never writes.

## Procedure

1. **Vault endpoint.** Read `~/.config/the-pensieve/config.toml`. Show whichever of `[vault].url` or `[vault].path` is configured, plus `basic_memory_project`. If neither is set, surface the gap.

2. **Current project.** If inside a git repo:
   - Resolve the slug (mirror file's `slug` if present, basename otherwise).
   - If a meta-mirror exists at `~/.cache/the-pensieve/meta-mirror/<slug>.json`, parse and show: `slug`, `default_branch`, `sync.last_synced_commit`, the keys of `docs.*`.
   - If none exists, say so and recommend `/pensieve-init-project`.

3. **Cache footprint.** Run `du -sh ~/.cache/the-pensieve/` (or `$PENSIEVE_CACHE_DIR` if set). Break it down by subdir (`meta-mirror`, `verify`, `fetch`) if present.

4. **Live MCP probe (optional).** If the Basic Memory MCP connector is reachable, do a one-call sanity check: `search_notes(query="status:active", folder="projects/")` and report the count of active project metas. If MCP is unreachable, say so — do not error out.

5. **Output format.** Plain text, compact:

   ```
   pensieve status
   ───────────────
   vault     : <url or path>  (project: <name>)
   cwd       : <git root or "(not a git repo)">
   project   : <slug>          (mirror: present / absent)
   last sync : <commit>  on <branch>   ←  <date if available>
   docs map  : context, readme, adrs   (or "—" if none)
   cache     : <total>   meta-mirror=<N> verify=<N> fetch=<N>
   mcp probe : <N active projects> | unreachable
   ```

## Constraints

- **Zero vault writes.** This command never calls `write_note`, `edit_note`, or `pensieve-update-meta`.
- No GitHub API calls — that's `/pensieve-verify`'s job, not status.
- If anything fails (mirror is corrupt JSON, du errors, MCP unreachable), report the failure inline; never throw.
