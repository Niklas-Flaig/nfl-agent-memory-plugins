# the-pensieve-plugin

A Claude Code plugin that routes agents between repo-local docs and a
cross-project Basic Memory vault. Injects opinionated routing rules at
session start, detects local drift against the vault's project meta, and
exposes a small set of skills for working across repos.

The full design lives in [`spec.md`](./spec.md) (v6, draft). What follows is
the operator-facing summary.

## Status

**Phases 1–3 complete.** Phase 4 (live end-to-end testing) is deferred to
the user — it needs a running Basic Memory MCP connector and a real
Claude Code session, neither of which can be exercised from the
implementation environment. Phase 5 (defrag) is explicitly out of scope
for v1. See [Backlog](#backlog) for what remains.

Shipped components:

- `SessionStart` hook + routing rules + local drift detection (Phase 1).
- 4 skills: `pensieve-update-meta`, `pensieve-verify-project`,
  `pensieve-fetch-project`, `pensieve-reconcile` (Phase 2).
- 4 slash commands: `/pensieve-init-project`, `/pensieve-reconcile`,
  `/pensieve-verify`, `/pensieve-status` (Phase 3).
- Helper scripts: `compute-drift.sh`, `read-config.sh`, `write-mirror.sh`,
  `verify-commit.sh`, `fetch-remote-doc.sh`, `cache-manager.sh`,
  `init-project.sh`.

## What it does today

- Injects `rules/pensieve-routing.md` into every Claude Code session via a
  `SessionStart` hook, so agents know to use Basic Memory MCP for vault
  content and filesystem tools for repo-local docs.
- Runs a local drift check against the meta-mirror cache
  (`~/.cache/the-pensieve/meta-mirror/<slug>.json`) and surfaces a status
  block scaled to severity (`clean` → `minor` → `moderate` → `heavy`).
- Surfaces a visible `systemMessage` for moderate / heavy drift so the user
  notices before the agent silently uses stale data.
- Exposes four skills the agent will auto-route to per the rules: verifying
  another project against GitHub, fetching cross-repo docs, surgical
  frontmatter updates, and full interactive reconcile.
- Exposes four slash commands for the user: init, reconcile, verify, status.

The hook never reads the vault directly. All vault access happens later on
the agent's first turn via Basic Memory MCP. See spec §6.5.

## Prerequisites

- **Claude Code** with plugin support.
- **`uv` / `uvx`** for running Basic Memory. `brew install uv` if missing.
- **`git` + `gh`** on `$PATH`. `gh` is needed by the verify/fetch skills,
  not by the hook itself.
- **`python3`** on `$PATH`. macOS ships one. Used by the hook for JSON
  escape/validation (no `pip` packages required).

## Why this setup has multiple moving parts

The plugin does **not** include the vault. It is a conductor without an
orchestra. Three components together make the system work:

| Component | Role |
|---|---|
| **the-pensieve-plugin** (this repo) | Tells Claude *how* and *when* to query the vault — routing rules, drift detection, skill descriptions. Pure orchestration. |
| **Basic Memory MCP server** | Implements the `read_note` / `write_note` / `search_notes` / `edit_note` / `build_context` tools against your vault. Runs as a local stdio process spawned by Claude Code. |
| **`~/the-pensieve/`** | The vault itself — plain markdown files on disk plus a SQLite index that Basic Memory manages. |

Two reasons it's split this way (per spec §1, §12, §17):

1. **Substitutability.** You can swap the vault between local-stdio Basic
   Memory today and a Railway-hosted remote later, without changing one
   line of plugin code. The plugin only knows the *protocol*, not where
   the data lives.
2. **Separation of concerns.** If the plugin breaks, your notes don't. If
   your notes move, the plugin doesn't care.

That's why installing the plugin alone produces a SessionStart message
that says "no project meta cached" — the routing rules are loaded and the
hook fires, but there's nothing on the other end of the MCP wire until
you set Basic Memory up.

## Setup (one-time)

### 1. Create the vault directory

```bash
mkdir -p ~/the-pensieve
```

The vault is just a folder of markdown files. Basic Memory will manage a
SQLite index next to it. Per spec §3 it organizes itself into
`shared/`, `dictionary/`, `decisions/`, `projects/`, `daily/`, `_archive/`.

### 2. Register the project with Basic Memory

```bash
uvx basic-memory project add pensieve ~/the-pensieve
```

`uvx` will install Basic Memory itself on first run (~150 packages,
one-time). The Basic Memory CLI tracks multiple "projects" (vaults) by
name — registering ours as `pensieve` lets the MCP server know which
folder to expose.

### 3. Wire Basic Memory into Claude Code as an MCP server

```bash
claude mcp add basic-memory --scope user -- \
  uvx basic-memory mcp --project pensieve
```

`--scope user` means the connector is available in every Claude Code
session, not just inside the project where you ran the command. The
trailing `uvx basic-memory mcp --project pensieve` is the stdio command
Claude Code will spawn whenever it needs the vault tools.

Verify:

```bash
claude mcp list | grep basic-memory
```

You should see `basic-memory: uvx basic-memory mcp --project pensieve - ✓ Connected`.

### 4. Install the plugin (if you haven't already)

From inside Claude Code:

```
/plugin marketplace add Niklas-Flaig/nfl-agent-memory-plugins
/plugin install the-pensieve-plugin@nfl-agent-memory-plugins
```

Then **fully quit and reopen Claude Code** so the SessionStart hook
registers. After restart you should see one of these messages at session
start (depending on whether a meta-mirror exists for the current repo):

- `[pensieve] hook ran (not inside a git repository)`
- `[pensieve] <slug>: no project meta cached — run /pensieve-init-project to track this repo`
- `[pensieve] <slug>: clean (no drift since last sync)`
- `[pensieve] <severity> drift on '<slug>': ...`

### 5. Confirm the MCP tools are loaded inside Claude

Open Claude Code in any git repo, then ask:

> *"Do you have `read_note` / `write_note` / `search_notes` tools available?"*

If yes → the full pipeline is live. Run `/pensieve-init-project` in a repo
you want to track and walk through the prompts.

If no → Claude Code didn't pick up the connector. Check `claude mcp list`
again; if `basic-memory` is missing, repeat step 3 with the correct shell
session. The MCP add modifies `~/.claude.json` under `mcpServers`.

## Install

See the full [Setup](#setup-one-time) section above. Short version:

```bash
mkdir -p ~/the-pensieve
uvx basic-memory project add pensieve ~/the-pensieve
claude mcp add basic-memory --scope user -- uvx basic-memory mcp --project pensieve
```

then inside Claude Code:

```
/plugin marketplace add Niklas-Flaig/nfl-agent-memory-plugins
/plugin install the-pensieve-plugin@nfl-agent-memory-plugins
```

then fully quit + reopen Claude Code.

## Configure

Copy the template and edit:

```bash
mkdir -p ~/.config/the-pensieve
cp the-pensieve-plugin/config.toml.example ~/.config/the-pensieve/config.toml
```

The shell-side reader at `scripts/read-config.sh` understands a narrow
subset of TOML — single-line `key = value` inside the documented sections.
Comments (`#`), single/double quoted strings, and `~` expansion for
`cache.dir` work. Anything fancier is parsed by skills, not the hook.

Environment overrides (for ad-hoc testing without editing the file):

| Var | Default |
|---|---|
| `PENSIEVE_MODERATE_DOC_FILES_THRESHOLD` | `1` |
| `PENSIEVE_HEAVY_DOC_FILES_THRESHOLD` | `3` |
| `PENSIEVE_MODERATE_FILES_THRESHOLD` | `50` |
| `PENSIEVE_MINOR_FILES_THRESHOLD` | `10` |
| `PENSIEVE_DOC_PATTERNS_REGEX` | `\.(md|mdx)$|^docs/|^adr/|^CONTEXT\.md|^README\.md` |
| `PENSIEVE_CACHE_DIR` | `~/.cache/the-pensieve` |

## Testing the hook locally

Without installing into Claude Code, you can dry-run the hook from any git
repo:

```bash
cd /path/to/some/repo
CLAUDE_PLUGIN_ROOT=/Users/ephandor/emdash/repositories/nfl-agent-memory-plugins/the-pensieve-plugin \
  /Users/ephandor/emdash/repositories/nfl-agent-memory-plugins/the-pensieve-plugin/hooks/session-start.sh \
  | python3 -m json.tool
```

You should see a JSON object with `hookSpecificOutput.additionalContext`
containing the routing rules and a `[pensieve] Session start status` block
appended. If there is no `~/.cache/the-pensieve/meta-mirror/<slug>.json` for
the current repo, severity will be `unknown` and the block will recommend
`/pensieve-init-project`.

To exercise drift detection, hand-craft a mirror file. Example:

```bash
mkdir -p ~/.cache/the-pensieve/meta-mirror
cat > ~/.cache/the-pensieve/meta-mirror/$(basename "$(git rev-parse --show-toplevel)").json <<'JSON'
{
  "slug": "nfl-agent-memory-plugins",
  "repo_path": "/Users/ephandor/emdash/repositories/nfl-agent-memory-plugins",
  "default_branch": "main",
  "docs": { "readme": "README.md" },
  "sync": { "last_synced_commit": "DEADBEEFCAFE" }
}
JSON
```

The hook will treat `DEADBEEFCAFE` as missing-from-git and report `heavy`
severity with a structural signal.

---

## Assumptions made during Phases 2–3

Documented here so they can be challenged later. Every assumption below was
made without confirmation from a live Basic Memory MCP server or a real
Claude Code skill-routing run, and may need to be revisited during Phase 4.

1. **Basic Memory MCP tool names and identifier shape.** Skills are written
   against `read_note(identifier="projects/<slug>")`,
   `write_note`, `edit_note`, `search_notes(query=..., folder="...")`,
   `build_context` — the names used in the spec. The exact identifier shape
   (e.g. `projects/<slug>` vs. `permalink` vs. a slash-prefixed path) may
   differ in the installed Basic Memory version. If routing fails because
   identifiers don't resolve, the fix is local to each skill body.

2. **Skill auto-routing is driven by `description:` frontmatter alone.**
   Each `SKILL.md` carries a description loaded with explicit trigger
   phrases. No `tools:` field is set — skills inherit the agent's tool
   permissions. If a specific Claude Code skill format adds required fields
   later, the front matter will need extending.

3. **Slash commands use `description:` + `argument-hint:` frontmatter.**
   The argument is passed through `$ARGUMENTS` / via the user's invocation
   and parsed inside the command body. No `allowed-tools:` restrictions are
   set; the commands may invoke any tool the session permits.

4. **`gh` is the only acceptable GitHub client.** `verify-commit.sh` and
   `fetch-remote-doc.sh` shell out to `gh`. Repos not on GitHub (Gitea,
   self-hosted GitLab, etc.) will not work with the verify/fetch skills
   until a provider abstraction is added. The init command warns the user
   if the resolved remote is not parseable as GitHub.

5. **Remote URL parsing is regex-based.** SSH and HTTPS GitHub URLs are
   normalized in `verify-commit.sh` and `fetch-remote-doc.sh` via a small
   sed pipeline. Forks, redirects, and SSH config aliases (e.g.
   `git@github-personal:owner/repo`) won't parse — the scripts will exit
   with a clear error message in that case.

6. **`python3` from the system path is sufficient.** Used for JSON
   escape/validation and the small init proposal. No `pip` packages
   required. If `python3` is missing, the hook and `write-mirror.sh` fail
   loud — the README lists `python3` as a prerequisite.

7. **TOML reader covers only the documented keys.** `read-config.sh`
   parses single-line `key = value` inside the documented sections and
   strips comments / unwraps quotes. Inline tables, arrays, dotted keys,
   multi-line strings, and TOML datetime values are not parsed. Skills
   that need richer config would have to read it via dedicated helpers
   (none do today).

8. **Cache mirror is the single source of truth for the hook.** Any path
   that updates the project meta in the vault (skills, `/pensieve-init-project`)
   must also call `scripts/write-mirror.sh` immediately afterwards. Skills'
   SKILL.md bodies call this out repeatedly; treat the mirror write as part
   of `edit_note`'s contract.

9. **macOS-flavored shell tools.** `stat -f '%m'`, `du -sm`, and `mtime
   +N` were tested on macOS 25 (Darwin 25.5). Linux equivalents use
   different `stat` flags — porting will need a one-line check or a
   `stat --format` fallback. The hook itself is portable; the cache
   eviction script is the macOS-specific one.

10. **The reconcile skill drives interactive turns, not batch.** Findings
    are surfaced one at a time. This works in interactive Claude Code
    sessions but would deadlock in a non-interactive runner (CI, cron).
    No batch mode is provided — `/pensieve-defrag` (deferred to Phase 5)
    will need to keep this in mind when dispatching.

---

## Backlog

Everything below is **deferred work**. Numbering matches the implementation
prompt's phase plan unless noted.

### Phase 4 — End-to-end testing (deferred to the user)

This phase requires a running Basic Memory MCP connector and an interactive
Claude Code session. It cannot be exercised from the implementation
environment. The scenarios to walk through:

- [ ] **Fresh install, no project meta anywhere.** Verify the routing
      instruction is injected and `/pensieve-init-project` scaffolds a
      meta + mirror correctly.
- [ ] **Project meta exists, no drift.** SessionStart should stay quiet
      (clean status, no `systemMessage`). Agent should use `read_note`
      correctly when asked about the project.
- [ ] **Project meta exists, moderate drift introduced by committing.**
      SessionStart should surface a moderate prompt. `/pensieve-reconcile`
      should walk through the findings.
- [ ] **Working in repo A, asking about repo B's recent state.** Agent
      should invoke `pensieve-verify-project` before answering. TTL and
      explicit-user-mention triggers should both fire as designed.
- [ ] Capture findings + iteration notes in this README under a new
      "Field notes" section.

The static smoke tests already run during build:

- [x] SessionStart hook emits valid `additionalContext` JSON in clean /
      heavy / unknown / non-git-repo states.
- [x] `compute-drift.sh` exits 0 in all four states.
- [x] `init-project.sh` produces valid JSON against a real repo.
- [x] `write-mirror.sh` round-trips the init proposal and is read
      correctly by the hook on the next invocation.
- [x] `write-mirror.sh` rejects invalid JSON.
- [x] `cache-manager.sh` runs cleanly against an empty cache.
- [x] URL parser in `verify-commit.sh` handles all 3 GitHub URL forms
      and rejects non-GitHub URLs.

### Phase 5 — Defrag (deferred, explicitly skipped for v1)

- [ ] `commands/pensieve-defrag.md` — currently absent; until built, the
      command should not appear. If a placeholder is shipped early it must
      refuse to run and link to this backlog.
- [ ] `skills/pensieve-defrag/SKILL.md` — the orchestrator described in
      spec §11. Audit-scope detection, consent gate with token estimate,
      parallel subagent dispatch, triage, interactive review, apply via
      MCP.
- [ ] `agents/project-auditor.md` — the source-agnostic per-project audit
      subagent defined verbatim in spec §10. Registers as
      `the-pensieve-plugin:project-auditor`. Read-only tool list. Source
      logs come from the configured `logs_path` (per-project frontmatter
      override → global default → `.memsearch/memory/`).
- [ ] `~/the-pensieve/_defrag-reports/<YYYY-MM-DD>.md` audit trail writes
      (spec §11 Step 6).

### Operational / infra (separate workstream, not this session)

- [ ] Railway-hosted Basic Memory MCP + Postgres + S3 + OpenResty gateway
      (spec §17 Topology B).
- [ ] Auth0 tenant + Native Application registration, fixed
      `--callback-port`, Protected Resource Metadata endpoint, and the
      `WWW-Authenticate` header on 401 (spec §18).
- [ ] Schema declarations for the custom frontmatter fields (`sync.*`,
      dictionary `kind` / `opinion`) via Basic Memory's
      `schema_infer` / `schema_validate` so they become queryable (spec
      §6.5 "Two specific known costs").

### Cross-cutting refinements (track during real usage, then revisit)

- Verification TTL value (default 12h — may need to drop on heavy multi-project days). spec §16.
- Fetch cache TTL (default 14 days) and `--no-cache` override for the fetch skill. spec §16.
- Subagent token estimation accuracy — refine the heuristic when off by >2x. spec §16.
- `/pensieve-defrag --since <date>` flag. spec §16.
- Doc-pattern regex tuning + per-project `docs_pattern` override field. spec §16.
- Severity threshold calibration (current values are guesses). spec §16.
- Headless / cron / mobile auth story — service tokens vs. M2M client-credentials. spec §19. Deferred until real need surfaces.

### Architectural notes worth keeping near the code

- **Hook never touches the vault.** Spec §6.5 + §8. Any temptation to have
  the SessionStart hook call MCP must be resisted; the cache-mirror is the
  contract.
- **Skills must write the mirror on every `edit_note`** to keep the hook
  honest. If the mirror gets out of date the hook lies, silently. Treat the
  mirror write as part of `edit_note`'s contract, not an afterthought.
- **memsearch is the default capture tool, not a dependency.** Spec §10 +
  §12. Anything that hard-codes `.memsearch/memory/` outside the
  `[defrag].default_logs_path_relative` config is a regression — the
  `logs_path` indirection must be honored everywhere.
- **No vault writes from shell.** Spec §6.5 + §8. The optional
  `session-end.sh` (currently a no-op stub) must use Basic Memory's CLI or
  a small MCP helper, never markdown parsing.
- **`/pensieve-defrag` never runs without consent.** Spec §11 + §15. The
  consent gate with a token-cost preview is load-bearing.
