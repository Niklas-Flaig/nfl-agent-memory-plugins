# the-pensieve: local-first vault (`~/.pensieve`) — design

**Date:** 2026-05-24
**Status:** approved (verbal), implementation in progress
**Plugin version:** 0.1.0 → 0.2.0

## Goal

Flip the Pensieve vault from cloud-first (Railway-hosted Basic Memory, accessed
over HTTP) to **local-first**: a plain local vault at `~/.pensieve`, with cloud
sync layered on top by the operator (Google Drive for Desktop). Then publish the
plugin as `0.2.0`.

The user's three asks:
1. Update the plugin so it uses a local vault (`~/.pensieve`).
2. Migrate the vault's content from Railway to the new local path.
3. Publish the plugin with a new `0.2.0` version tag.

## Key facts discovered

- **The plugin does not consume the vault location.** `scripts/read-config.sh`
  only parses `[drift_severity]`, `[drift_severity.doc_patterns].regex`, and
  `[cache].dir`. The `[vault] url`/`path`/`basic_memory_project` keys are
  informational; the only reader is `/pensieve-status`, which just *displays*
  them. The real connection lives in `~/.claude.json` → `mcpServers`, configured
  via `claude mcp add basic-memory`. So "use a local vault" is a docs + config +
  MCP-wiring change, not a code-path change.
- **Basic Memory stores its SQLite index outside the vault** — at
  `~/.basic-memory/memory.db` (+ `-shm`, `-wal`). The vault folder holds only
  markdown. This makes Google Drive sync safe: only markdown syncs; each device
  rebuilds its own index. No SQLite-over-cloud-sync corruption risk.
- **Two connectors exist today:** `basic-memory` (local stdio →
  `uvx basic-memory mcp --project pensieve` → `~/the-pensieve`, 8 notes) and
  `the-pensieve` (HTTP → `https://pensieve.flaig.design/mcp`, Railway).
- **Railway is canonical** (user's call). Local `~/the-pensieve` is stale.
- **Railway is currently unreachable from this environment.** `/mcp` returns
  401 (OAuth required), `railway` CLI is logged out (`invalid_grant`), and the
  railway MCP shares that logged-out state. Extraction needs an interactive
  `railway login` (browser) that only the user can perform.

## §1 — Target architecture

- Vault: plain local dir `~/.pensieve`. **No symlink** (user's explicit
  instruction). Standard layout: `shared/`, `dictionary/`, `decisions/`,
  `projects/`, `daily/`, `_archive/`.
- Served by the existing local stdio connector
  (`uvx basic-memory mcp --project pensieve`), with the `pensieve` project
  repointed `~/the-pensieve` → `~/.pensieve`.
- Index stays at `~/.basic-memory/memory.db` — per-device, never synced.
- Cloud sync of `~/.pensieve`: **operator wires Google Drive** (out of scope
  here).
- Railway: remains up as the migration *source*; operator tears it down later.
- Cache (`~/.cache/the-pensieve`) and config (`~/.config/the-pensieve`) dirs are
  **unchanged**. Renaming them is risky and out of scope. This leaves an
  intentional naming split: vault = `.pensieve`, cache/config = `the-pensieve`.

## §2 — Plugin changes (→ 0.2.0)

| File | Change |
|---|---|
| `config.toml.example` | Comment out `[vault] url`; set `path = "~/.pensieve"`; `[defrag] report_dir = "~/.pensieve/_defrag-reports"`; reword the url-vs-path header toward local-first default. |
| `README.md` | Swap `~/the-pensieve` → `~/.pensieve` throughout; reframe "substitutability" so local-first is the default and Railway is the optional swap; note Drive sync is the operator's job. |
| `rules/pensieve-routing.md` | Keep the MCP-only rule; soften the "breaks when cloud-hosted" justification to "keeps the index authoritative" (still true local-first). |
| `commands/pensieve-status.md` | Ensure example output reflects a local `path`. |
| `spec.md` | Add a short note marking local-first as the chosen default; full §17/§18 rewrite is out of scope (captured as the ADR below). |
| `.claude-plugin/plugin.json` | `version` 0.1.0 → 0.2.0. |
| `.claude-plugin/marketplace.json` | `metadata.version` 0.1.0 → 0.2.0. |

## §3 — Migration runbook (Railway → `~/.pensieve`) — operator-gated

I cannot perform Railway's interactive auth. The remaining steps, in order:

1. **(Operator)** `railway login` — completes browser auth. (Alternatively
   re-auth the HTTP connector: `claude mcp` OAuth for `the-pensieve`.)
2. **(Then me / scripted) Discover the backend.** Inspect the Railway service +
   volume to determine whether notes are markdown-on-a-volume or Postgres+S3
   (the spec §17 Topology B possibility).
3. **Extract:**
   - *Markdown on a volume* → `railway ssh`/`railway run` to tar the vault dir,
     download, extract into `~/.pensieve`. Byte-perfect (frontmatter, folders,
     assets preserved). Preferred.
   - *Postgres+S3* → enumerate via the re-authed HTTP MCP (`list_directory` +
     `read_content` per note) and reconstruct files under `~/.pensieve`; or pull
     markdown straight from the S3 bucket if files live there.
4. **Repoint Basic Memory** — only after content is verified present in
   `~/.pensieve`: set the `pensieve` project path to `~/.pensieve` (edit
   `~/.basic-memory/config.json` `projects.pensieve.path`, or via
   `basic-memory project` CLI), then trigger a local sync so `memory.db`
   rebuilds.
5. **Verify** — note counts match; local stdio MCP returns the migrated notes.
6. **(Operator)** wire Google Drive at `~/.pensieve`; tear down Railway.

**Safety:** `~/the-pensieve` (stale local copy) is **not deleted** — kept as a
fallback. Nothing destructive runs automatically.

## §4 — Publish

- No tags exist yet; `v0.2.0` is the first.
- Commit plugin changes in logical groups (include `.memsearch/memory/` per the
  operator's commit rule).
- Tag `v0.2.0`; push branch + tag to `origin`
  (`github.com/Niklas-Flaig/nfl-agent-memory-plugins`).
- Marketplace installs pull directly from the repo; there is no release
  workflow.

## §5 — Vault bookkeeping (follow-up, currently blocked)

Per the Pensieve routing rules, after the repo change + migration:
- Update `projects/nfl-agent-memory-plugins` meta note (`docs.*` map,
  `sync.last_synced_commit` → new HEAD) via the local vault MCP.
- Add the ADR below to the vault `decisions/`.

Both are **deferred**: the only vault MCP exposed this session is the Railway
connector (401), and the local stdio connector's tools are not registered here.
Doing these now would write to the stale `~/the-pensieve`, which the migration
will supersede. Run them against `~/.pensieve` after migration.

### ADR (to add to `decisions/` post-migration)

> **Pensieve vault is local-first.** The canonical vault is a local directory at
> `~/.pensieve`, synced across devices via Google Drive for Desktop (operator
> responsibility). Basic Memory's SQLite index stays per-device at
> `~/.basic-memory/`, so only markdown syncs. The Railway-hosted Basic Memory
> (Topology B) is demoted from canonical to an optional remote swap; the plugin
> is location-agnostic (it speaks the MCP protocol, not a path), so this is a
> config/wiring change, not a code change.

## Out of scope

- Renaming `~/.cache/the-pensieve` / `~/.config/the-pensieve`.
- Setting up Google Drive sync (operator does this).
- Tearing down Railway (operator does this).
- A full `spec.md` §17/§18 rewrite.
