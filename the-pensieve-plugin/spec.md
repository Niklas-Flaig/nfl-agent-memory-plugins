# `the-pensieve-plugin` — Specification

**Status:** Draft v6 (renamed: "the-pensieve" plugin, "the Pensieve" in prose; user references generalized)
**Author:** designed collaboratively with Claude
**Target platform:** Claude Code (plugins API)
**Companion infrastructure:** Basic Memory MCP, memsearch CLI + plugin, GitHub CLI (`gh`)

---

## 1. Purpose

A Claude Code plugin that gives any agent a consistent, opinionated way to interact with the user's two-tier knowledge architecture:

- **Repo-local truth** (CONTEXT.md, ADRs, READMEs) committed in each project
- **Vault-local cross-project truth** (`~/the-pensieve/`) for preferences, dictionary, decisions, project meta

The plugin's job is **routing and orchestration**, not capture. memsearch handles session capture. Basic Memory handles vault read/write. Doc-writing skills (whichever ones are installed) handle in-repo writes. **This plugin makes them work together coherently and tells the agent when to use which.**

## 2. Design principles

1. **Compose, don't replace.** When another installed skill is the right tool, the plugin doesn't get in the way. When the vault layer is also relevant, the plugin runs alongside it. The default answer to "which tool?" is often "both, in order." Other skills are first-class peers, not competitors.
2. **One direction of truth per layer.** Repo defaults to canonical for project specifics. Vault defaults to canonical for cross-project knowledge. Remote default branch is the source for cross-repo project lookups.
3. **Format-agnostic to the repo.** The plugin must not require any particular doc structure inside repos. CONTEXT.md, ADRs, READMEs, a Notion link, a custom `docs/` tree — all valid. The frontmatter map tells agents where to look per-project.
4. **Active, not reactive.** Inject explicit instructions at session start. Don't rely on Claude noticing a skill description and choosing well.
5. **Repos remain self-contained and pushable.** No symlinks, no generated stubs, no required vault for someone else cloning the repo.
6. **Maintenance is part of the loop.** Anytime an agent changes something in a repo or notices drift, it updates the vault's project meta frontmatter. The map stays current as a side effect of normal work.

## 3. The vault structure

```
~/the-pensieve/                          ← shown as local path; cloud equivalent maps identically
├── shared/                       ← cross-project preferences, patterns, tools
│   ├── tools/
│   ├── patterns/
│   └── workflows/
├── dictionary/                   ← personal/cross-project ubiquitous language
│   ├── people/                   ← who is Jean, collaborators, the user themself
│   ├── tools/                    ← Railway, MinIO, Notion (as named entities)
│   ├── places/                   ← physical or virtual places (Berlin, Discord servers)
│   ├── concepts/                 ← terms the user uses with specific meanings
│   └── README.md                 ← how the dictionary works
├── decisions/                    ← cross-project ADRs (lifestyle/infra/career-scope)
├── projects/
│   ├── bicycle-handlebar.md      ← project meta notes (frontmatter + narrative)
│   ├── claude-mem0-plugin.md
│   └── ...
├── daily/                        ← optional personal journal layer
└── _archive/                     ← stale items moved here by defrag
```

> **Note on paths in this spec.** Folder paths like `shared/`, `dictionary/people/`, `projects/<slug>` are shown for human readability. Per §6.5, the plugin never accesses these paths via filesystem — they're always accessed via Basic Memory MCP, which resolves them internally. The `~/the-pensieve/` prefix appears only when discussing the local-vault topology; for cloud vaults the same logical layout applies but lives behind the MCP endpoint.

## 4. The dictionary layer

Inspired by the "ubiquitous language" idea Pocock encodes in `grill-with-docs`, but **lifted out of any single repo and into the personal layer**. The dictionary is for people, places, tools, and concepts that recur across the user's life and work.

### Structure

Each dictionary entry is one markdown file with a small, fixed frontmatter:

```markdown
---
entry: Jean
kind: person
aliases: [Jean-the-assistant, my AI assistant]
tags: [ai, personal, assistant]
related: [Claude, Notion, Bicycle Handlebar Project]
last_updated: 2026-05-17
---

# Jean

The user's personal AI assistant. A persistent agent context that runs across
the user's projects, with access to their Notion workspace, Mem0/Basic Memory,
and their code repositories.

## Key facts
- Jean is the assistant *persona*, not a specific model
- Lives in Claude Code primarily; reaches into Notion via MCP
- Tone: direct, opinionated, German-friendly
- Jean knows about all entries in `~/the-pensieve/dictionary/`
```

```markdown
---
entry: Railway
kind: tool
aliases: [railway.app]
tags: [hosting, infrastructure, preferences]
opinion: preferred
related: [MinIO, Postgres, Mem0]
last_updated: 2026-05-17
---

# Railway

The user's preferred hosting provider for self-hosted infrastructure.

## Why preferred
- Single-developer pricing model fits independent work
- Volume-mounted services + managed Postgres covers most stack needs
- Mem0 OpenMemory gateway runs here today; basic-memory will too
- Composes well with MinIO for asset hosting on other Railway projects

## When not to use
- Multi-region production loads (use proper cloud)
- Anything that needs sub-100ms cold start (use Vercel for edge)
```

### Why this layer is separate from `shared/`

`shared/` holds **patterns and preferences** that look like advice: "use Bun as the default JS runtime, configured with Prettier (2 spaces, trailing commas)."

`dictionary/` holds **entities** that look like definitions: "Jean is the persona the user adopts for their AI assistant. Railway is a hosting provider preferred for these reasons."

The split matters because:
- Dictionary entries get *referenced* in many contexts. Patterns are *applied* in specific contexts.
- Dictionary entries change rarely. Patterns evolve with experience.
- Agents fetch dictionary entries to resolve ambiguity ("who is Jean?"). Agents fetch patterns to make decisions ("how do I format this?").

### Kind → folder mapping

The `kind` frontmatter field determines which subfolder of `dictionary/` an entry lives in:

| `kind` value | Folder | Examples |
|---|---|---|
| `person` | `dictionary/people/` | Jean, collaborators, the user themself |
| `tool` | `dictionary/tools/` | Railway, MinIO, Notion, Basic Memory |
| `place` | `dictionary/places/` | physical or virtual locations |
| `concept` | `dictionary/concepts/` | terms with specific meanings ("the Pensieve", "session log") |

The mapping is enforced when writing new entries: `write_note` calls for dictionary content must derive `folder` from `kind`. Entries with unrecognized `kind` values default to `dictionary/concepts/` and the user is asked whether to extend the taxonomy.

### Dictionary discovery

The session-start instruction (see §7) tells the agent: *if a name, tool, or concept comes up that you're not certain about, look up the dictionary entry first* (via `read_note` or `search_notes` — see §6.5). This is cheap and prevents the "Claude invents a definition of Jean" failure mode.

## 5. The project meta note format

Every active project has exactly one file at `~/the-pensieve/projects/<slug>.md`. This is the authoritative *machine-readable* description of a project at the vault level.

### Required frontmatter

```markdown
---
project: bicycle-handlebar
slug: bicycle-handlebar
status: active                    # active | paused | shipped | archived
repo: git@github.com:<owner>/bicycle-handlebar.git
repo_path: ~/code/bicycle-handlebar
default_branch: main
docs:
  context: CONTEXT.md             # optional, omit if not present
  adrs: docs/adr/                 # optional
  readme: README.md
  custom:                          # arbitrary additional paths
    pipeline_notes: docs/pipeline.md
tags: [video, fabrication, vue3, gsap, minio]
related_projects: [project-docs, claude-mem0-plugin]
related_dictionary: [Railway, MinIO, Jean]
sync:
  last_synced_commit: a1b2c3d4    # SHA on default_branch at last reconciliation
  last_synced_at: 2026-05-17      # when reconciliation happened (human readability)
  last_verified_at: 2026-05-17    # when an agent last confirmed SHA via GitHub
  last_seen_drift:                # snapshot from most recent verification
    files_changed: 0              # total files in diff <last_synced_commit>..HEAD
    doc_files_changed: 0          # subset of files_changed matching doc patterns
    paths_missing: 0              # docs.* paths that no longer resolve
    default_branch_changed: false
---

# Bicycle Handlebar Video

[Free-form narrative — what this project is, why it exists, what state it's in.
Private context: client concerns, frustrations, half-formed ideas, anything
that doesn't belong in the repo.]

## Recent decisions
[High-level summary, not duplicating ADRs. Pointers to ADR slugs/paths.]

## Open questions
[Things the user is still thinking about.]
```

### Why this shape

- **`repo` + `default_branch`**: agents in other repos can fetch project-specific docs from the remote without cloning
- **`docs.*`**: format-agnostic pointer. If a project uses CONTEXT.md + ADRs, fine. If it uses a single `NOTES.md`, also fine. The frontmatter declares where to look.
- **`related_projects`**: enables graph queries ("what other projects use Vue 3?")
- **`related_dictionary`**: enables dictionary-driven context loading ("this project relates to Railway; load that dictionary entry too")
- **`sync.last_synced_commit`**: the load-bearing field for drift detection. Records the SHA on default_branch that the frontmatter is known-aligned with. All drift detection is "what has changed since this commit?"
- **`sync.last_synced_at`**: timestamp of the last full reconciliation event (manual or via `/pensieve-reconcile`)
- **`sync.last_verified_at`**: timestamp of the last cheap verification (agent asked GitHub "is last_synced_commit still HEAD?"). Used to gate verification calls via TTL.
- **`sync.last_seen_drift`**: machine-readable snapshot of what was true at the last verification. Lets agents reason about staleness without re-fetching.

> **Note on timestamps:** project meta uses a structured `sync` block (commit-anchored, multi-field) instead of a single `last_updated` field like dictionary entries do. The reason is that project metas need to answer multiple distinct questions ("when was this last fully reconciled?", "when was the SHA last verified?", "what did we see at last check?") and a single timestamp can't answer them. Dictionary entries change rarely and only ever care about "when did the user last touch this?" — so they use the simpler `last_updated: <date>` field.

### Maintenance contract

Whenever an agent:

- **Modifies a file in the repo** that the frontmatter references → update `sync.last_synced_commit` to current HEAD if the change is committed, otherwise leave for next reconciliation
- **Notices the repo has changed shape** (new docs, removed files, restructured layout) → update `docs.*` paths and bump `sync.last_synced_at`
- **Adds a significant ADR or decision** → optionally mention it in the narrative body (not duplicating the ADR)
- **Detects the repo's default branch has changed** → update `default_branch` and bump `sync.last_synced_at`
- **Sees a related project or dictionary entry referenced** → add it to `related_*` lists if not already there

These updates are the *side effect* of the agent doing its actual work, not a separate ritual. The session-start instruction makes this explicit.

## 6. The plugin's runtime architecture

```
the-pensieve-plugin/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   ├── hooks.json
│   ├── session-start.sh          ← inject pensieve routing context + local drift check
│   └── session-end.sh            ← optional: log session summary entry
├── rules/
│   └── pensieve-routing.md          ← instruction injected at session start
├── agents/
│   └── project-auditor.md        ← subagent invoked by /pensieve-defrag per project
├── skills/
│   ├── pensieve-fetch-project/
│   │   └── SKILL.md              ← fetch project docs from remote
│   ├── pensieve-verify-project/
│   │   └── SKILL.md              ← verify last_synced_commit against GitHub
│   ├── pensieve-reconcile/
│   │   └── SKILL.md              ← interactive frontmatter repair for one project
│   ├── pensieve-update-meta/
│   │   └── SKILL.md              ← targeted frontmatter field update
│   └── pensieve-defrag/
│       └── SKILL.md              ← on-demand cross-project promotion orchestrator
├── commands/
│   ├── pensieve-init-project.md     ← /pensieve-init-project <slug>
│   ├── pensieve-reconcile.md        ← /pensieve-reconcile (current project)
│   ├── pensieve-verify.md           ← /pensieve-verify <slug> (force re-verify any project)
│   ├── pensieve-defrag.md           ← /pensieve-defrag (with consent and cost preview)
│   └── pensieve-status.md           ← /pensieve-status (sanity check)
└── scripts/
    ├── fetch-remote-doc.sh       ← gh-backed fetch from remote default branch
    ├── compute-drift.sh          ← local drift signal computation
    ├── verify-commit.sh          ← single GitHub API call to check HEAD
    └── init-project.sh           ← scaffold a new project meta note
```

## 6.5 Access patterns: when MCP, when filesystem

The plugin operates against several different data surfaces. Inconsistent access patterns are a real bug risk, so this section establishes one clear rule per surface. Every other section of the spec defers to this one.

### The rule

> **Vault content is accessed via Basic Memory MCP. Everything else uses filesystem tools or shell commands.**

"Vault content" means anything inside the configured vault directory (`~/the-pensieve/` locally, or its cloud-hosted equivalent). "Everything else" means session logs, repo files, the local cache, git operations, and GitHub API calls.

### Why this rule

Three reasons:

1. **Performance scaling.** Basic Memory's Postgres/SQLite index answers cross-cutting queries in single-digit milliseconds regardless of vault size. `grep` over a 5,000-note vault takes seconds. The database wins on every cross-cutting operation.
2. **Semantic over textual.** MCP returns structured entities, parsed observations, graph relations. Filesystem returns bytes.
3. **Cloud-vault portable.** The plugin must work whether `~/the-pensieve/` lives on disk or in a remote Basic Memory service. Filesystem tools fail in the remote case; MCP works in both.

### The mapping table

| Operation | Access mode | Why |
|---|---|---|
| Read a project meta note | MCP `read_note` | vault content |
| Search vault for content | MCP `search_notes` | vault content; uses hybrid index |
| Write a curated note | MCP `write_note` | vault content; triggers indexing |
| Edit/append a note's frontmatter | MCP `edit_note` | vault content; preserves graph |
| Resolve a dictionary entry by name | MCP `read_note(identifier="<name>")` | vault content |
| Find all projects with `status: active` | MCP `search_notes` with filter | vault content; indexed query |
| Walk the graph from a starting note | MCP `build_context(memory://...)` | vault content; graph semantics |
| Parse current repo's `.memsearch/memory/` | Filesystem (`Grep`, `Read`) | not vault content; lives in repo |
| Read cached fetched doc | Filesystem (`Read`) | not vault content; transient cache |
| Compute git drift (HEAD vs SHA, file diff) | `git` CLI via Bash | repo operation, not vault content |
| Verify a remote commit SHA | `gh api` via Bash | external API, not vault content |
| Fetch a doc from GitHub | `gh api` via Bash | external API |
| List recent project metas for defrag scope | MCP `search_notes` preferred; filesystem fallback if local-only and very small | vault content; see §11 for nuance |

### The cache is local, always

The fetched-doc cache (`~/.cache/the-pensieve/`) is **never** part of the vault. It holds transient copies of remote files for offline re-use. It must be:

- Outside the vault directory
- Excluded from any Basic Memory indexing
- Subject to LRU + TTL eviction (see §13 cache config)
- Wiped freely without data loss — every entry is re-fetchable

### Two specific known costs

1. **Bulk reads are slower via MCP.** Reading 50 project metas one-at-a-time means 50 MCP roundtrips. Prefer `search_notes` to get many results in one query when the operation is bulk in nature.
2. **Frontmatter field queries need schema declarations.** Basic Memory indexes known frontmatter fields (`title`, `tags`, `permalink`) by default. Custom fields like `sync.last_synced_commit` are stored but not queryable until you declare a schema for them via Basic Memory's `schema_infer` / `schema_validate` tools. Declare schemas for the project-meta and dictionary frontmatter shapes during plugin initialization — otherwise queries fall back to fetch-and-parse.

### Bulk-vs-individual access tradeoff in practice

For defrag scope detection (§11), the spec previously implied scanning all `~/the-pensieve/projects/*.md` files. With this rule applied:

- **Local vault, small (under ~50 projects):** filesystem is fine, but `search_notes` is also fine and consistent with the rule. Prefer MCP.
- **Local vault, large (50+ projects):** use `search_notes` — bulk filesystem reads start hurting.
- **Cloud vault:** `search_notes` is mandatory; filesystem is unavailable.

Everywhere else in this spec, when an operation involves reading or writing the vault, assume MCP. When an operation involves anything outside the vault, assume filesystem. The skill descriptions in §9 follow this convention explicitly.

## 7. The session-start instruction (the key piece)

This is the file `rules/pensieve-routing.md`, injected via the SessionStart hook's `additionalContext` field. It's not a skill description — it's a direct instruction that runs every session.

```markdown
# Pensieve routing — operating rules for this session

You have access to the user's two-tier knowledge architecture. Use it actively.

## Where things live

- **Repo-local truth**: CONTEXT.md, ADRs, READMEs inside the current repository.
  Canonical for project-specific code, architecture, and decisions. Read with
  filesystem tools (`Read`, `Grep`).
- **Vault**: cross-project knowledge, **always accessed via Basic Memory MCP**.
  Use `search_notes`, `read_note`, `write_note`, `edit_note`, `build_context`.
  Never `Read` or `Grep` against the vault path directly — those bypass the
  index and break when the vault is cloud-hosted.
  - `shared/` — preferences, patterns, workflows
  - `dictionary/` — people, tools, places, concepts the user uses by name
    (subfolders: `people/`, `tools/`, `places/`, `concepts/` — routed by the
    entry's `kind` frontmatter field)
  - `decisions/` — cross-project ADRs
  - `projects/<slug>` — project meta notes with frontmatter map
- **Session logs**: lives in the current repo at the configured `logs_path`
  (default `.memsearch/memory/`). Use the installed recall skill (e.g.
  memsearch's `memory-recall`) — not direct filesystem reads — when asking
  history questions, so retrieval stays in a subagent context.

## On every substantial response

1. **Resolve names first.** If the user mentions a person, tool, or concept by
   name (Jean, Railway, MinIO, Bicycle Handlebar Project, etc.) and you're not
   certain what's meant, call `read_note(identifier="<name>")` against the
   vault before guessing. If that returns nothing, try
   `search_notes(query="<name>", folder="dictionary/")`.

2. **For project-specific questions**, prefer the repo's own docs (CONTEXT.md,
   ADRs, README) read via filesystem tools. The vault's project meta note is a
   *pointer*, not a substitute. Read it via `read_note(identifier="projects/<slug>")`
   for project status, related projects, and dictionary references — then read
   the actual repo files for substance.

3. **For cross-project or personal questions**, call `search_notes` against
   `shared/` and `decisions/` before answering. Patterns and preferences live
   there.

4. **Compose, don't substitute.** Other installed skills, plugins, and rules
   are first-class. If a situation warrants invoking another skill (a doc
   writer, an interviewer, a planner, a reviewer), invoke it. If the same
   situation *also* warrants a vault action (updating project meta,
   recording a cross-project decision, adding a dictionary entry), do both.

   Specifically:
   - **Never skip another skill** because this plugin "covers it." This plugin
     orchestrates; it does not duplicate doc-writing, planning, or interview
     behavior owned by other skills.
   - **Never skip a vault action** because another skill is running. After
     any in-repo doc skill finishes, check whether project meta frontmatter
     needs updating (see "When you make a change" below).
   - The default ordering when both apply: run the in-repo skill first, then
     the vault action. The in-repo work is what produces the artifact;
     the vault action records its existence and shape.
   - If multiple skills could fit and they conflict, surface the choice to
     the user rather than guessing.

## When you make a change

- **Repo files modified**: also update the project meta note's frontmatter via
  `edit_note(identifier="projects/<slug>", ...)` if any `docs.*` path is now
  stale, missing, or newly created. After committing, update
  `sync.last_synced_commit` to the new HEAD.
- **Dictionary or shared knowledge surfaces in conversation**: if the user says
  something durable ("Bun is my default", "I prefer Railway because X"), call
  `write_note` or `edit_note` to record it in the right vault location *and*
  mention you've done so.
- **Repo's docs shape changes**: re-verify the project meta's `docs.*` map and
  bump `sync.last_synced_at` via `edit_note`.

## Verifying another project before using its meta

Project meta notes can drift. Before you rely on a project's meta note
(other than the one for the project you're currently working in), verify
it. The rules:

**Always verify before use when ANY of these is true:**
- `sync.last_verified_at` is more than 12 hours old
- The user just said something that implies a recent change to that project
  ("we just changed something in bicycle-handlebar", "I just merged a PR
  in claude-mem0-plugin", "the docs were restructured", etc.)
- The frontmatter has explicit signal that something is off
  (`sync.last_seen_drift.doc_files_changed > 0`, `paths_missing > 0`,
  `default_branch_changed: true`, etc.)
- You're about to make a decision that depends on the project's current
  shape (e.g. "does project X already have an ADR about Y?")

**How to verify:**
1. `read_note(identifier="projects/<slug>")` to load the frontmatter
2. Invoke the `pensieve-verify-project` skill (it makes one GitHub API call
   to compare `sync.last_synced_commit` against current HEAD of
   `default_branch`, then computes file-level drift)
3. If HEAD matches `last_synced_commit`: the skill updates
   `sync.last_verified_at` via `edit_note`, returns `verified: true`,
   you proceed
4. If HEAD has moved: surface to the user with the file-level breakdown.
   "Project bicycle-handlebar has N files changed since the vault's
   record, M of them docs. Want me to reconcile before I answer?"
   Do not silently use stale data.

**Skip verification when:**
- `sync.last_verified_at` is within the TTL (default 12h) AND no signal
  suggests drift AND the user hasn't indicated a recent change
- The project being referenced is the current working repo (the
  session-start hook already checked local drift)

## Fetching project docs from outside the repo

If you're working in a different repo (or no repo) and need a specific
project's CONTEXT.md or ADR:

1. `read_note(identifier="projects/<slug>")` for the frontmatter map
2. Apply the verification rules above first
3. Use the `pensieve-fetch-project` skill to fetch from `origin/<default_branch>`
4. If the fetched file looks substantially different from what the frontmatter
   describes, propose an `edit_note` to update the project meta before continuing

## What never happens

- Don't duplicate repo doc content into the vault. The vault holds *meta*
  about projects, not copies of their docs.
- Don't symlink between vault and repos.
- Don't write cross-project preferences inside a specific repo. Those go to
  `shared/` in the vault via `write_note`.
- Don't write project-specific implementation details to the vault. Those
  go in the repo.
- Don't use filesystem tools (`Read`, `Grep`, `Glob`) against the vault
  directory directly. Always use Basic Memory MCP for vault content. The
  cache directory at `~/.cache/the-pensieve/` is the only exception — it's
  not vault content.
- Don't run `/pensieve-defrag` without the user's explicit consent — it spawns
  subagents and burns real tokens. Always preview cost first.

## Trust signals

- If `sync.last_verified_at` is older than 12 hours, treat as stale until verified.
- If a `docs.*` path 404s when fetched, flag it and propose a fix.
- If a dictionary entry contradicts what the user says now, surface the conflict
  before deciding whose answer is correct.
- If `sync.last_seen_drift` shows non-zero values from a prior check that
  was never reconciled, surface this proactively.
```

This text is loaded verbatim into `additionalContext` on every session start. It's not subtle. It tells Claude exactly what to do, when to do it, and how to compose with other tools.

## 8. The hooks in detail

### `session-start.sh`

Runs once per Claude Code session. Performs the **local drift check** for the current project (the "hot path A" described in §11).

A note on the architecture: this hook is a shell script. Shell scripts cannot easily speak MCP. Per §6.5, vault content should be accessed via MCP. **The hook therefore does only the work it can do locally without touching the vault** — git operations, repo file checks, structural validation. It outputs a brief structured payload that tells the agent "drift status X for project Y" plus the routing instruction text. The agent then calls `read_note(identifier="projects/<slug>")` itself via MCP as one of its first actions if it needs the full project meta.

This keeps the rule from §6.5 intact — no vault content is read by filesystem from the hook — while still letting the hook do the cheap local drift detection.

**Steps:**

1. Detect current working directory
2. Determine if cwd is inside a known git repo
3. If yes, derive `<slug>` (basename of git root by default; see §16 for override)
4. Run local drift detection using only repo-local data (all local, no network, no vault access):

   **Step 4a — Structural checks (binary; any true = heavy drift immediately):**
   - Does the repo exist? (git root resolves?)
   - Does the current default branch (`git symbolic-ref refs/remotes/origin/HEAD`) match a stored `default_branch`? (See "Stored drift signal" below for how this is read.)
   - Each `docs.*` path from the stored project meta — does it exist in the working tree? (See "Stored drift signal" below.)

   **Step 4b — File-level diff (only if no structural drift):**
   - `git rev-parse HEAD` and compare against a stored `last_synced_commit` value
   - If equal → `files_changed: 0`, `doc_files_changed: 0`, severity: `clean`
   - If different:
     - `files_changed = git diff --name-only <last_synced_commit>..HEAD | wc -l`
     - `doc_files_changed = git diff --name-only <last_synced_commit>..HEAD | grep -E '<doc_patterns_regex from config>' | wc -l`

   **Step 4c — Compute severity:**
   ```
   if any structural check failed             → heavy
   elif doc_files_changed >= heavy_doc_files_threshold     → heavy
   elif doc_files_changed >= moderate_doc_files_threshold  → moderate
   elif files_changed >= moderate_files_threshold          → moderate (code churn, offer spot-check)
   elif files_changed >= minor_files_threshold             → minor
   else                                                    → clean
   ```

5. Build `additionalContext` payload:
    - The full text of `rules/pensieve-routing.md`
    - The detected `<slug>` so the agent knows which project meta to load
    - A drift status block, scaled to severity:
      - `clean` — nothing surfaced
      - `minor` — one-line note: "[pensieve] N files changed since last sync, no docs touched"
      - `moderate` — `systemMessage` recommending `/pensieve-reconcile` with file counts
      - `heavy` — strong prompt to reconcile now, listing which structural/doc signals fired
    - An instruction to the agent: "If drift is moderate or heavy, call `read_note(identifier='projects/<slug>')` to load the full project meta before proceeding."
6. Output via stdout JSON (Claude Code hook contract)

The hook does *not* do any network calls and does *not* touch the vault.

### Stored drift signal (how the hook gets last-known frontmatter without MCP)

The hook needs to know `last_synced_commit`, `default_branch`, and the `docs.*` paths to compute drift — but it can't call MCP. Two implementation options:

1. **Cache-on-write approach (recommended).** Every time the agent updates a project meta via `edit_note`, the Pensieve plugin also writes a tiny mirror file at `~/.cache/the-pensieve/meta-mirror/<slug>.json` containing just the fields the hook needs. This file is a derived cache, not a source of truth; the canonical project meta is still in the vault. The hook reads this cache.
2. **Hook-defers-everything approach.** The hook does no drift detection at all — it only injects the routing rules — and the agent computes drift itself via `read_note` plus local git commands on its first turn. Slightly slower per-session but eliminates the cache mirror.

The cache-on-write approach is preferred because session-start drift detection should be instant and not consume agent tokens. The mirror file is small, kept current by the same operations that update the vault, and harmless if stale (the agent re-verifies via `pensieve-verify-project` when the stake matters).

If the mirror file is missing (first session in a project, cache cleared), the hook injects only the routing rules and a one-line note: "[pensieve] no project meta cached; run /pensieve-init-project if this project should be tracked."

### Why file-level, not commit-level

A commit count is a poor proxy for "did the frontmatter become stale." 25 typo-fix commits don't affect the frontmatter; one squash-merged PR rewriting `CONTEXT.md` very much does. The metric this plugin needs is **"how much of what the frontmatter describes has actually changed,"** which is a function of files touched (especially doc files), not commits authored. File-level diff is cheap (millisecond-scale git operation), bounded, and directly answers the question.

### Token budget impact

The routing instruction is ~1500 tokens injected on every session start. That's a deliberate cost (per design principle 4, "Active not reactive"). For typical Claude Code sessions of 10K-100K+ context tokens this is a 1-15% overhead, acceptable. If it becomes a problem, the `[behavior].inject_dictionary_summary` flag and similar future toggles can be tuned to trim the payload.

### `session-end.sh` (optional)

Append a one-line entry to a daily log in the vault at `daily/YYYY-MM-DD` via `write_note` / `edit_note` summarizing what project was worked on. This is the one vault write a shell hook performs — and it does so by shelling out to a small helper script that calls Basic Memory's CLI rather than parsing markdown directly. Lightweight — not duplicating the recall plugin's per-project session logs.

## 9. Skills

Per §6.5, vault content uses Basic Memory MCP; everything else uses filesystem or shell. Each skill's behavior steps below are explicit about which mode each call uses.

### `pensieve-verify-project`

**Trigger:** agent needs to confirm a project meta's freshness before relying on it. Invoked per the verification rules in §7.

**Inputs:** project slug

**Behavior:**
1. **MCP** `read_note(identifier="projects/<slug>")` — fetch the project meta and parse `sync.*` frontmatter
2. **Shell** run `scripts/verify-commit.sh <slug>` which uses `gh api repos/<owner>/<repo>/commits/<default_branch>` (one API call, sub-second) to get the current HEAD SHA on the default branch
3. Compare returned SHA against `sync.last_synced_commit`
4. If match: **MCP** `edit_note` to update `sync.last_verified_at` to now, return `verified: true`
5. If mismatch:
   - **Shell** fetch the diff file list via `gh api repos/<owner>/<repo>/compare/<last_synced_commit>...<current_head>` and count files
   - Compute `files_changed` and `doc_files_changed` (same regex as session-start)
   - **MCP** `edit_note` to update `sync.last_verified_at`, `sync.last_seen_drift.files_changed`, `sync.last_seen_drift.doc_files_changed`
   - Return `verified: false` with the file-level breakdown
6. **Filesystem** cache the verification result locally at `~/.cache/the-pensieve/verify/<slug>.json` with timestamp; the next call within TTL skips the API hit

### `pensieve-fetch-project`

**Trigger:** agent needs a project's CONTEXT.md, ADR, or arbitrary doc from a project other than the current repo.

**Inputs:** project slug, optional specific doc path

**Behavior:**
1. Run `pensieve-verify-project` first if `sync.last_verified_at` is past TTL
2. **MCP** `read_note(identifier="projects/<slug>")` to parse the frontmatter's `docs.*` map
3. Determine which file to fetch (from `docs.*` map or explicit input)
4. **Shell** run `gh api repos/<owner>/<repo>/contents/<path>?ref=<default_branch>` — or `git show origin/<branch>:<path>` if a local clone exists at `repo_path`
5. **Filesystem** cache result at `~/.cache/the-pensieve/fetch/<slug>/<path>` with timestamp (NOT inside the vault; see §6.5 and §13 cache config)
6. Return file contents + freshness metadata
7. If fetched file's structure suggests frontmatter is stale: **MCP** propose an `edit_note` update before continuing

### `pensieve-reconcile`

**Trigger:** drift was detected (in session-start or via cross-project verification) and the agent wants to apply repairs interactively. Also exposed as `/pensieve-reconcile` slash command.

**Inputs:** project slug (defaults to current)

**Behavior:**
1. **Shell + MCP** compute full drift report:
   - **Shell** git diff for files changed (with doc-file subset highlighted)
   - **Shell** check broken paths against `repo_path` working tree
   - **Shell** detect default branch changes
   - **MCP** `read_note` to load current frontmatter for comparison
2. Walk the user through each finding one at a time with yes/no/edit/skip
3. For each accepted change: **MCP** `edit_note` to apply the frontmatter update
4. Optionally **shell** `git log` recent commit messages for doc-file changes; surface noteworthy ADRs or doc updates as candidates for narrative-body updates
5. At the end: **MCP** `edit_note` to update `sync.last_synced_commit` to current HEAD and `sync.last_synced_at` to now; reset `sync.last_seen_drift` counters to zero

### `pensieve-update-meta`

**Trigger:** the agent has a single specific frontmatter field to update — narrower than full reconciliation.

**Inputs:** project slug, field path, new value

**Behavior:**
1. **MCP** `read_note(identifier="projects/<slug>")` to load current state
2. Apply targeted frontmatter update (preserve narrative body untouched)
3. Bump `sync.last_synced_at` only
4. **MCP** `edit_note` to write back

### `pensieve-defrag`

**Trigger:** only on-demand via `/pensieve-defrag` slash command. Never automatic. Never scheduled.

See §11 for the full orchestration design and the per-step access patterns.

## 10. The `project-auditor` subagent

The defrag flow in §11 depends on a single subagent definition shipped with the plugin. It lives at `agents/project-auditor.md` in the plugin and registers as `<plugin-name>:project-auditor` per Claude Code's plugin agent naming. Up to 10 subagents can run in parallel in Claude Code, so even multi-project audits typically complete in one round.

### Source-agnostic by design

The auditor reads markdown files from a configured `logs_path` and treats them as conversational session logs. **It is not coupled to memsearch.** Any tool that writes session logs as timestamped markdown files into a known directory satisfies the contract:

- memsearch's `.memsearch/memory/YYYY-MM-DD.md` — the default and most common case
- A custom capture plugin writing to `<repo>/session-log/`
- A shell wrapper appending to `<repo>/.agent-history/`
- Manually-maintained handwritten daily notes in a project folder

The auditor doesn't care. It just reads the markdown and looks for promotion candidates. If the user swaps memsearch for a different capture tool later, the auditor needs zero changes — just point its `logs_path` at the new directory.

The `logs_path` is determined by, in order:
1. Per-project override: optional `logs_path` field in `projects/<slug>` frontmatter
2. Global default: `[defrag].default_logs_path_relative` in plugin config (default: `.memsearch/memory/`)
3. Resolved as `<repo_path>/<logs_path>` if relative, or used as-is if absolute

This makes memsearch a default implementation, not a hard dependency.

### Subagent directory layout note

The plugin ships a single subagent at `agents/project-auditor.md` (flat layout). If more subagents are added later, putting them in subfolders such as `agents/audit/project-auditor.md` would scope their identifiers (e.g. `the-pensieve:audit:project-auditor`). For now the flat layout is sufficient.

### The full subagent file

```markdown
---
name: project-auditor
description: Audits a single project's session logs for vault promotion candidates. Invoked by the Pensieve plugin's /pensieve-defrag command. Reads session logs from the configured logs_path and the current vault state, returns a structured report of proposed promotions (preferences, dictionary entries, decisions) and project meta corrections. Use proactively when /pensieve-defrag is invoked.
tools: Read, Glob, Grep, Bash
model: sonnet
---

You are the `project-auditor` subagent for the user's Pensieve plugin.

## Your job

Audit ONE project's session logs since its last audit and propose what should be promoted into the user's cross-project vault. You return a structured report. You do not write any files.

## Inputs you receive

- `slug`: the project slug (e.g. `bicycle-handlebar`)
- `repo_path`: absolute path to the repo
- `logs_path`: absolute path to the directory holding session logs for this project. Default is `<repo_path>/.memsearch/memory/` but this is configurable per project — do not assume any particular log format beyond "markdown files with timestamps in the name or frontmatter."
- `since`: ISO date string; only consider logs newer than this
- `vault_summaries`: short summaries of what already exists in `shared/`, `dictionary/`, `decisions/` so you don't re-propose existing content

## What you scan for

Read every session log in `logs_path` modified after `since`. Look for:

1. **Cross-project preferences** — statements like "I prefer X over Y", "use X for ...", "always do Z". Candidate for `shared/`.
2. **New named entities** — people, tools, services, libraries mentioned by name 2+ times that don't appear in `vault_summaries.dictionary`. Candidate for `dictionary/` (folder by `kind`: people, tools, places, concepts).
3. **Architectural decisions with cross-project relevance** — choices that explain reasoning and could apply elsewhere ("self-host on Railway because...", "use ONNX local embeddings for X reasons"). Candidate for `decisions/`.
4. **Project meta drift** — references to docs, file paths, or repo structure that contradict the project's current frontmatter map. Candidate for project meta correction.
5. **Existing entity updates** — if a dictionary entry already exists for "Railway" and the logs contain new opinion or context, propose an update.

## What you ignore

- Project-implementation-specific details (those belong in repo docs, not vault)
- One-off statements without recurrence or strong opinion markers
- Routine session activity ("worked on the auth flow today")
- Anything that doesn't generalize beyond this single project

## Output format

Return a structured markdown report, exactly this shape:

\`\`\`markdown
# Project audit: <slug>

**Logs scanned:** <N>
**Window:** <since> to <now>

## Proposed: shared/

### <pattern-title>
- **Destination:** shared/<category>/<slug>
- **Evidence:** <quote or summary>, appeared <N> times
- **Confidence:** high | medium | low
- **Suggested content:** <2-3 sentence draft>

## Proposed: dictionary/

### <entity-name>
- **Destination:** dictionary/<kind>/<entity-slug>
- **Kind:** person | tool | place | concept
- **Evidence:** <quote or summary>
- **Suggested frontmatter and content:** <draft>

## Proposed: decisions/

### <decision-title>
- **Destination:** decisions/<slug>
- **Evidence:** <quote or summary>
- **Reasoning surfaced:** <why this was decided>
- **Confidence:** high | medium | low

## Project meta corrections needed

- <field>: current value <X>, observed value <Y>, evidence <quote>

## Existing entries that may need updates

- dictionary/tools/Railway — new context: <quote>
\`\`\`

## Confidence calibration

- **High:** mentioned 3+ times across the window, explicit preference markers, no contradictions
- **Medium:** mentioned 2+ times, or once with strong unambiguous wording
- **Low:** single mention, or ambiguous interpretation possible

The user's interactive review will filter low-confidence items. Err on the side of inclusion — surface things, let them decide.

## Constraints

- Read-only: you have Read, Glob, Grep, Bash (for filesystem traversal only). You have no write tools.
- Stay focused on ONE project. You do not see other projects' logs.
- Do not invent. Every proposal must cite evidence from the logs.
- Keep proposals concise. Drafts should be 2-3 sentences, not full documents.

## Failure modes to avoid

- Proposing project-specific implementation details for promotion (they're not cross-project knowledge)
- Proposing low-confidence items as high-confidence
- Re-proposing content that already exists in `vault_summaries`
- Hallucinating evidence — if you can't quote it, don't propose it
```

The `/pensieve-defrag` command (§11) dispatches this subagent once per approved project, with appropriate `slug`, `repo_path`, `logs_path`, `since`, and `vault_summaries` filled in from the audit-scope detection step.

## 11. Drift detection and on-demand promotion

Maintenance happens at the point of use, not on a schedule. Three distinct paths cover the three real situations:

### Path A — Working IN a project (local drift check)

Fires automatically via the SessionStart hook (§8). All local computation, no network calls.

- Reads the cached `sync.last_synced_commit` from the meta-mirror cache (see §8 "Stored drift signal")
- Compares against current `HEAD` of `default_branch`
- Computes file-level diff: total `files_changed` and the doc-relevant subset `doc_files_changed`
- Checks structural signals: default branch match, all `docs.*` paths resolve, repo exists
- Scales surfacing to severity (heavy on any structural drift or 3+ doc files; moderate on 1+ doc file or 50+ total files; minor on 10+ total files with no docs; clean otherwise)
- The user (or Claude with consent) runs `/pensieve-reconcile` to apply repairs

### Path B — Referencing ANOTHER project (TTL + signal verification)

Fires lazily via the `pensieve-verify-project` skill, invoked per §7's verification rules:

- **TTL check:** if `sync.last_verified_at` is more than 12 hours old, verify
- **Signal check:** if the user explicitly mentions a recent change to that project ("we just changed something in X", "I just merged a PR in Y"), force-verify regardless of TTL
- **Drift signal:** if previous `sync.last_seen_drift` showed non-zero values, verify before trusting

Verification is one GitHub API call: "is `last_synced_commit` still the HEAD of `default_branch`?" Sub-second, cheap. If drift is detected, the agent surfaces and offers reconciliation. Nothing is silently used stale.

### Path C — Cross-project promotion (`/pensieve-defrag`, fully on-demand)

The vault is intended to be a clean single source of truth on the user's preferences, style, and decision-making. Over time, patterns appearing in session logs across multiple projects deserve promotion into `shared/`, `dictionary/`, or `decisions/`. This is what `/pensieve-defrag` does — but **only when the user asks for it.**

#### The orchestration model

`/pensieve-defrag` is **not a script**. It is a Claude-driven orchestration that uses a fleet of subagents (one per project) to produce reports, then synthesizes them. Subagents are token-intensive, so the command **always asks for consent before spawning anything**.

#### Flow

**Step 1 — Audit scope detection (no tokens spent)**

The command first determines which projects to audit. Per §6.5, vault queries use MCP:

1. **MCP** `search_notes(query="status:active OR status:paused", folder="projects/")` — returns all candidate project metas in one indexed query
2. For each candidate, parse `repo_path` and `sync.last_synced_at` from frontmatter, and resolve `logs_path` per §10 ("Source-agnostic by design")
3. **Filesystem** scan the resolved `logs_path` for the most recent file timestamp (session logs live in the repo, not the vault — see §6.5)
4. Include the project if its session logs are newer than `sync.last_synced_at` — meaning real work happened since the last audit

The result is a list of projects with new session activity since they were last reconciled/audited.

**Note on local-vault fallback:** for very small local vaults (fewer than ~50 projects), reading project meta files via filesystem is roughly equivalent in speed to `search_notes`. The MCP path is still preferred because it works identically whether the vault is local or cloud-hosted — the plugin shouldn't carry two code paths for the same operation.

**Step 2 — Consent gate (the safety gate)**

Before spawning any subagent, present to the user:

```
/pensieve-defrag will scan the following projects for promotion candidates:

  - bicycle-handlebar    (28 new session logs since 2026-04-01)
  - claude-mem0-plugin   (12 new session logs since 2026-03-15)
  - project-docs         (3 new session logs since 2026-05-10)

Each scan spawns a project-auditor subagent which reads the relevant logs
and generates a report.

Rough token estimate: ~45,000 input tokens, ~8,000 output tokens total
(across all 3 projects). Estimate is order-of-magnitude — actual may
vary 2x in either direction.

Reply 'yes' to proceed, or specify a subset (e.g. 'only bicycle-handlebar').
```

The token estimate is computed from session log volume (lines × average tokens-per-line) plus subagent system prompt overhead. The goal is to tell the user whether this is a 1,000-token operation or a 100,000-token operation — not to give a precise dollar figure (rates change, their subscription tier varies, and they can do the math themselves if they care). The user can:
- Approve the full set
- Approve a subset
- Cancel entirely

**Nothing runs without explicit approval.**

**Step 3 — Parallel subagent audits**

Once approved, the main agent dispatches one `project-auditor` subagent per approved project. Up to 10 subagents can run in parallel in Claude Code, so most defrag runs fit in a single batch.

Each subagent receives:
- Project slug
- Path to session logs
- Window since last audit
- The current vault state (`~/the-pensieve/shared/`, `~/the-pensieve/dictionary/`, `~/the-pensieve/decisions/` summaries — so it knows what's already there)

Each subagent returns a structured report (see `agents/project-auditor.md` in §10 for the full agent definition).

**Step 4 — Main agent triage**

The main agent receives all subagent reports and:

1. Deduplicates proposals across reports (if 3 subagents propose the same "Bun as default" promotion, surface once with the cross-project evidence)
2. Resolves conflicts (if one subagent proposes a dictionary entry and another proposes editing an existing one for the same entity, merge proposals)
3. Categorizes by destination: `shared/` patterns, `dictionary/` entries, `decisions/` ADRs, project meta corrections
4. Sorts by confidence (multiple-project evidence ranks higher than single-project)

**Step 5 — Interactive review with the user**

The triaged list is walked through one item at a time. For each:

```
Proposal: Add "Use Bun for new TypeScript projects" to ~/the-pensieve/shared/tools/

Evidence:
  - Mentioned 4 times across bicycle-handlebar sessions
  - Mentioned 2 times across claude-mem0-plugin sessions
  - Stated as preference 3 times: "Bun is my default", "use Bun"

Proposed file: ~/the-pensieve/shared/tools/javascript-runtime.md
Proposed content: [draft preview]

Action: [accept | edit | skip | view-evidence]
```

Nothing is auto-applied. The user approves each item explicitly.

**Step 6 — Apply accepted changes**

For each accepted item:
- Write/edit the appropriate vault file via Basic Memory MCP
- For project meta corrections, update the relevant frontmatter
- Log the action to `~/the-pensieve/_defrag-reports/<YYYY-MM-DD>.md` for audit trail

### Why this design

- **Token cost is visible upfront.** the user knows what the run will cost before approving.
- **Parallel subagents keep wall time reasonable.** A 5-project audit completes in roughly the time of one project, not five.
- **Subagents prevent main-context pollution.** Each project's session logs are read in a subagent's isolated context; the main agent only sees the structured report.
- **The single source of truth principle is the goal.** Every accepted promotion makes the vault a cleaner, more accurate representation of the user's actual preferences and decision patterns.
- **Capture-tool-agnostic.** The auditor reads markdown session logs from a configured `logs_path` — it does not care whether memsearch, a custom capture script, or hand-written notes produced them (see §10).

### What `/pensieve-defrag` does NOT do

- Run on a schedule
- Run without consent
- Auto-apply any changes
- Touch the repos themselves (only the vault changes)
- Make decisions about project status (active/paused/archived) — that's still the user's call

## 12. Composition rules with other Claude Code plugins/skills

This plugin coexists with any other installed plugin, skill, or rule set. It does not enumerate a fixed list of partners — it follows a principle.

### The principle

**The Pensieve orchestrates, others execute.** This plugin's job is to (1) tell the agent where knowledge lives, (2) keep the vault and frontmatter map current, and (3) fetch project specifics on demand. Doc writing, interviewing, planning, reviewing, testing, and any other domain-specific work is owned by other plugins/skills.

### How composition works in practice

The Pensieve plugin **never claims exclusivity** over a domain another skill covers. Concretely:

- If a doc-writing skill is invoked, the Pensieve plugin does not write docs. After the skill finishes, the Pensieve's instruction prompts the agent to update project meta frontmatter if anything in the `docs.*` map is now stale.
- If an interview/planning skill is invoked, the Pensieve plugin does not also interview. It may surface dictionary entries (e.g. "Jean", "Railway") that come up during the interview, but it does not duplicate the skill's behavior.
- If a memory/recall skill is invoked, the Pensieve plugin does not also recall. It tells the agent that the recall skill is the right tool for session history queries.

### Categories of partner tools (illustrative, not exhaustive)

These categories describe what *kinds* of partner tools this plugin expects to coexist with. The plugin must work cleanly regardless of which specific tool occupies each slot — slots are fillable and replaceable.

| Slot | Role | Pensieve's relationship |
|---|---|---|
| **Doc writers** | Write CONTEXT.md, ADRs, READMEs, design docs into the repo | Never duplicates; updates project meta after they finish |
| **Interview/planning** | Grill the user, draft plans, refine specs | Never duplicates; surfaces dictionary context if relevant |
| **Memory capture** | Record session history per-project | Never duplicates; defrag reads their output for promotion candidates |
| **Memory recall** | Search past sessions, retrieve transcripts | Never duplicates; instruction tells agent to invoke them for history queries |
| **Engineering workflow** | TDD, PR creation, code review, refactor planning | Never duplicates; the Pensieve is invisible to them |
| **Project-local docs maintenance** | Other plugins maintaining in-repo docs | Defrag tolerates whatever doc shape they produce, via frontmatter map |

### Substitutability

Any tool listed above can be **swapped out without changing the Pensieve plugin**. If the user replaces a doc-writing skill, the Pensieve plugin doesn't need updating — it only checks that *some* tool produced the docs the frontmatter map declares. If the user removes a memory-recall skill, the Pensieve plugin loses one option in its instruction but continues to function.

### memsearch is the current default — not a hard dependency

This is worth calling out explicitly because memsearch is referenced by name throughout the spec. The Pensieve plugin's contract with the capture/recall slot is:

- **Capture side:** "Some tool writes timestamped markdown session logs into a known directory per project." That directory is configurable via `logs_path` (see §10).
- **Recall side:** "The agent has access to some skill or tool that searches session history." The session-start instruction tells the agent to use it for history queries.

memsearch happens to satisfy both today. The Pensieve plugin doesn't import memsearch, depend on its file format beyond "markdown," call its CLI, or assume any of its internals. If the user swaps it for:

- A custom shell script that appends to daily files → works, point `logs_path` at it
- A different capture plugin → works, configure `logs_path`, install the new recall skill
- Nothing at all → works, but `/pensieve-defrag` would have no logs to scan; the rest of the plugin functions normally

The implementation should treat memsearch as "the default capture tool we happen to use" — never as "the capture tool we require." Anyone reading the code should be able to swap it without grep-replacing the word "memsearch" everywhere.

### The injection rule

When the session-start instruction lists "other doc skills are available," it does not enumerate them by name. It says: *use whatever doc skill is installed; this plugin won't get in your way.* The agent's existing skill-discovery mechanism handles the rest.

### What this plugin will refuse to do

Even if the user asks for it directly mid-session, the Pensieve plugin refuses to:

- Write CONTEXT.md or ADR files inside a repo — delegate to a doc-writing skill. (If no doc skill is installed, say so and let the user install one or write it themselves.)
- Capture session transcripts — delegate to memsearch or another capture plugin.
- Auto-apply defrag promotions without explicit confirmation per item.

These are the same refusals implied by "The Pensieve orchestrates, others execute," restated as hard rules because mid-session pressure (someone asks "just write it for me") is the failure mode this list prevents.

## 13. Configuration

A single config file at `~/.config/the-pensieve/config.toml`. On macOS the XDG `~/.config/` location is used (not `~/Library/Application Support/`) to match Claude Code's own conventions and stay portable.

```toml
[vault]
# Pick exactly ONE of `url` or `path`. If both are set, `url` wins and `path`
# is ignored with a warning at plugin load. There is no "hybrid mode" — the
# plugin always talks to one Basic Memory MCP endpoint, never two.
url = "https://pensieve.your-domain.app"        # remote Basic Memory MCP endpoint
# path = "~/the-pensieve"                           # local-only alternative
basic_memory_project = "pensieve"               # Basic Memory project name on the server
                                              # (multiple projects on one server are supported
                                              # by Basic Memory, but each plugin install is
                                              # bound to one. For a second vault, run a
                                              # second plugin config with a different project.)

# AUTH IS HANDLED BY CLAUDE CODE'S BUILT-IN MCP OAUTH.
# No token configuration needed in this file. See §18 for setup.
# Configure the connector once via:
#   claude mcp add basic-memory --transport http https://pensieve.your-domain.app/mcp
#   claude mcp auth basic-memory

[cache]
# Local cache for fetched remote docs and verification results.
# NEVER inside the vault — this is transient, every entry re-fetchable.
dir = "~/.cache/the-pensieve"
max_size_mb = 500                            # LRU eviction kicks in above this
ttl_days = 14                                # entries older than this evicted on access
                                              # both bounds apply: whichever triggers first

[git]
gh_command = "gh"
remote_fetch_enabled = true

[verification]
ttl_hours = 12                               # skip remote verify if last_verified_at is within this window
                                              # overridden by explicit user signal or detected drift

[drift_severity]
# All thresholds compare against files in `git diff <last_synced_commit>..HEAD`
moderate_doc_files_threshold = 1             # at this many doc files changed: moderate severity
heavy_doc_files_threshold = 3                # at this many doc files changed: heavy severity
moderate_files_threshold = 50                # at this many total files changed (no docs): moderate
minor_files_threshold = 10                   # at this many total files changed (no docs): minor

[drift_severity.doc_patterns]
# Regex matched against file paths in the diff to classify them as "doc files".
# Default covers Markdown, common doc folders, and common root-level doc files.
# Override or extend to match your project conventions.
regex = '\.(md|mdx)$|^docs/|^adr/|^CONTEXT\.md|^README\.md'

[defrag]
# No schedule, no auto-run. /pensieve-defrag is always explicitly invoked with consent.
report_dir = "~/the-pensieve/_defrag-reports"       # audit reports stored here (committed to vault, OK)
default_logs_path_relative = ".memsearch/memory/"
                                              # default capture log location, relative to repo_path
                                              # per-project override via project meta frontmatter `logs_path`

[behavior]
auto_inject_instruction = true
inject_dictionary_summary = false            # if true, also inject dict overview at session start
```

### Cache eviction policy

The cache directory at `~/.cache/the-pensieve/` is **managed by the plugin**, not by the OS. Without active management it would grow forever — `~/.cache/` is conventional but most apps that drop files there never clean up. The plugin runs eviction on every cache write:

1. **TTL pass first.** Any cache entry older than `ttl_days` is deleted before considering the size bound. Each cache file has a sidecar `.meta` JSON with `created_at` and `last_accessed_at` timestamps.
2. **LRU pass if still over `max_size_mb`.** Sort remaining entries by `last_accessed_at` ascending and delete oldest until under the bound.
3. **Bounded check on read.** When `pensieve-fetch-project` returns a cached entry, it updates `last_accessed_at` and lets the next write trigger eviction if needed.

This keeps the cache directory under the configured size in the steady state without requiring a separate cron or daemon. macOS's Time Machine excludes `~/.cache/` from backups by default, which is the right behavior for transient data.

### Why no `[auth]` section

Authentication to the remote Basic Memory MCP server is handled entirely by Claude Code's built-in OAuth 2.1 support. The plugin never sees a token, never stores a credential, never makes an auth-aware HTTP call. The vault is reachable via MCP, and MCP's transport handles auth transparently. See §18 for the gateway-side setup.

This is a meaningful simplification over earlier design drafts that had `auth_token_command`, 1Password integrations, or keychain wrappers. None of that is needed.

## 14. What this plugin is NOT

- Not a memory system. memsearch + Basic Memory are the memory systems.
- Not a documentation writer. Doc-writing skills (whichever ones the user has installed) write docs.
- Not a sync tool. The remote default branch is the sync mechanism.
- Not opinionated about repo doc structure. The frontmatter map is.
- Not a search engine. Basic Memory's `search_notes` and memsearch's `memory_search` are.
- Not exclusive. Every other installed skill/plugin runs whenever it's the right tool. This plugin runs alongside, not instead.

## 15. Success criteria

After installation and 2 weeks of use, the following should be true:

1. The user does not have to remember to "tell Claude about Jean" — the dictionary handles it
2. Agents in repo A can answer questions about repo B without manual context dumping
3. Project meta frontmatter drift is surfaced **at the moment of relevant work** (entering the project, or referencing it from elsewhere) — not via background jobs
4. Verification against GitHub fires on the right signals: stale TTL, explicit user mention of recent change, or detected drift indicators
5. Any installed doc-writing skill runs cleanly when invoked, and the project meta gets updated afterward — without the Pensieve plugin getting in the way
6. `/pensieve-defrag` always asks for consent and shows token-cost preview before spawning subagents
7. Subagent reports get triaged and presented for interactive review; no auto-applied promotions
8. No file in any repo is a symlink, a generated stub, or a vault copy
9. Cloning any repo onto a fresh machine gives a complete, self-contained record of that project (the repo carries its own truth; the Pensieve only enriches it with cross-project context)

## 16. Open questions to resolve before implementation

These are tunables and edge cases that can't be settled without real usage feedback. They're not blockers — defaults are chosen — but worth revisiting after the plugin has been in use for a few weeks.

- **Verification TTL value**: 12 hours is the current default. May need tuning based on real usage — if the user does heavy multi-project days, this may need to drop.
- **Fetch cache invalidation**: doc-fetch cache TTL is 14 days, max size 500MB (see §13). Manual `--no-cache` flag for `pensieve-fetch-project` if needed before the TTL.
- **Dictionary entry conflicts**: if the user updates their preferences mid-conversation, when does the dictionary get rewritten? Proposal: agent flags it in real time and proposes an `edit_note`; `/pensieve-defrag` may surface additional pattern context. Refine after real usage.
- **Subagent token estimation accuracy**: order-of-magnitude is the goal (1K vs 10K vs 100K), not precision. Refine the heuristic if estimates are off by more than 2x consistently.
- **Defrag scope override**: should `/pensieve-defrag` accept a `--since <date>` flag to widen or narrow the scan window, independent of `last_synced_at`? Lean yes, for flexibility.
- **Doc-pattern regex tuning**: the default regex in `[drift_severity.doc_patterns]` covers Markdown plus common doc folders. Projects using non-standard doc layouts (e.g. `architecture/`, `wiki/`, `.adr/`) need to extend it via config or via per-project override. Add a per-project override field `docs_pattern: <regex>` in the project meta frontmatter when this becomes needed.
- **Severity threshold calibration**: current defaults (1 doc file = moderate, 3 = heavy, 50 total files = moderate, 10 total = minor) are guesses. Adjust after real usage — if the user finds themselves dismissing too many moderate prompts, raise thresholds.
- **Schema declarations for custom frontmatter**: Basic Memory's index handles known frontmatter fields (`title`, `tags`) by default. Custom fields like `sync.last_synced_commit` and the dictionary's `kind` / `opinion` need schema declarations to be queryable. Declare these at plugin install time via Basic Memory's `schema_infer` / `schema_validate` tools.

### Resolved during design (kept here as a record)

- **Slug derivation**: defaults to the basename of the repo's git root (`basename "$(git rev-parse --show-toplevel)"`). Override via the explicit `slug` field in the project meta frontmatter — which always wins if present. The session-start hook uses this rule directly.
- **Multiple remotes**: a repo with multiple remotes uses `origin` by default. Override via a frontmatter `remote: <name>` field. Both `pensieve-verify-project` and `pensieve-fetch-project` respect this.
- **Project meta auto-creation**: an agent working in a repo without a project meta note offers to create one via `/pensieve-init-project` — never automatically. The slash command scaffolds the frontmatter with sensible defaults and lets the user edit before writing.

## 17. Deployment topology

The plugin supports two main topologies. Both are local-plugin setups; the difference is where the vault lives.

### Topology A: Local vault

```
Local machine:
  ~/the-pensieve/                     ← vault as local markdown files
  Basic Memory MCP (stdio, `uvx basic-memory mcp`)
  the-pensieve plugin installed in Claude Code
  ~/.cache/the-pensieve/              ← fetch + verify cache (local)
  ~/code/*/                            ← repos with .memsearch/memory/
```

The Basic Memory MCP server runs as a local stdio process spawned by Claude Code. All vault operations are local Postgres/SQLite + filesystem. Zero network involved for vault access. Best for solo development, fastest, no auth complexity.

### Topology B: Cloud vault (recommended for multi-device)

```
Railway (or Basic Memory Cloud):
  Basic Memory MCP server (HTTP/SSE transport)
  + Postgres index
  + S3/volume for markdown files
  OpenResty gateway in front, with Auth0 OIDC validation

Local machine:
  the-pensieve plugin installed in Claude Code
  ~/.cache/the-pensieve/              ← fetch + verify cache (still local)
  ~/code/*/                            ← repos with .memsearch/memory/ (still local)

  Claude Code connects to Basic Memory MCP via authenticated HTTP/SSE.
  OAuth handshake handled by Claude Code's built-in MCP OAuth support (§18).
```

The vault lives in the cloud. The plugin runs locally and talks to the remote Basic Memory MCP via Claude Code's HTTP/SSE MCP transport. The cache stays local — every cached file is re-fetchable from the cloud, so the cache is purely a performance optimization, not a backup.

memsearch session logs always stay in their respective repos. They never go to the cloud regardless of topology. This is by design: session logs travel with the code, the vault holds cross-project knowledge.

### What does NOT change between topologies

- The plugin's code
- The session-start hook's behavior
- All skills (per §6.5, they're written against the MCP contract)
- The subagent
- The defrag flow
- Filesystem operations against repos (`.memsearch/memory/`, `git`, `gh`)

The user can move between topologies by changing `[vault]` in `config.toml` and re-adding the MCP connector. The plugin doesn't care.

### Not supported (yet)

- **Vault-only-in-cloud, no local mirror at all** (sometimes called "A3"): supported in principle — all vault operations are MCP, no filesystem dependency on `~/the-pensieve/`. But there is no local copy for Obsidian, offline use, or backup. Recommended against unless there's a specific use case (rented dev machines, locked-down work laptops).
- **Multiple vaults**: one vault per plugin install. Basic Memory supports multiple projects on the same MCP server (selected via the `basic_memory_project` config field), but a single plugin install talks to exactly one of them. For a second vault (e.g. client work), run a second plugin config pointing to a different `basic_memory_project` — same MCP server, different project name. Switching active vault means switching config files.

## 18. Authentication (cloud vault setup)

When `[vault].url` is set, Claude Code's built-in MCP OAuth 2.1 support handles authentication end-to-end. The plugin never touches credentials. This section documents the one-time gateway setup needed to make that work.

### What Claude Code does automatically

When Claude Code tries to call the remote Basic Memory MCP server:

1. Sends the request without auth on first contact
2. Receives `401 Unauthorized` with a `WWW-Authenticate` header pointing to the gateway's Protected Resource Metadata
3. Fetches Protected Resource Metadata to discover the authorization server (Auth0)
4. Fetches Auth0's `.well-known/openid-configuration` to learn endpoints
5. Registers itself as an OAuth client (or uses pre-registered credentials)
6. Opens a browser, the user authenticates with Auth0
7. Auth0 redirects with authorization code
8. Claude Code exchanges code for access token + refresh token (with PKCE)
9. Stores tokens encrypted locally
10. Sends subsequent requests with `Authorization: Bearer <access_token>`
11. Refreshes tokens automatically when they expire

The plugin sees none of this. Tools just work.

### What the user configures on the gateway side

The user's OpenResty gateway in front of Basic Memory already validates Auth0 JWTs. For MCP, two additional pieces:

**1. Protected Resource Metadata endpoint**

The gateway must serve a static JSON document at `https://pensieve.your-domain.app/.well-known/oauth-protected-resource`:

```json
{
  "resource": "https://pensieve.your-domain.app",
  "authorization_servers": ["https://your-tenant.auth0.com"]
}
```

This tells Claude Code which Auth0 tenant to use. Trivial OpenResty addition.

**2. WWW-Authenticate header on 401**

When the gateway returns 401 for unauthenticated requests to the MCP endpoint, the response must include:

```
WWW-Authenticate: Bearer realm="pensieve", resource_metadata="https://pensieve.your-domain.app/.well-known/oauth-protected-resource"
```

This points Claude Code to the metadata document.

**3. Auth0 application registration**

Auth0's Dynamic Client Registration is usually disabled by default. The user pre-registers Claude Code as an OAuth application in their Auth0 tenant. The correct application type depends on whether you want a public client (PKCE-only, recommended for CLI tools) or a confidential client:

- **Native Application** (recommended) — public client using PKCE, no `client_secret` needed. Matches how Claude Code actually operates as a local CLI.
- **Single Page Application** — also a public client option, viable alternative.
- **Regular Web Application** — confidential client with `client_secret`. Use only if your security model requires it; the secret then has to be configured in Claude Code's Advanced settings during connector add.

Then:

- Note the `client_id` (and `client_secret` only if confidential)
- **Configure the redirect URI explicitly.** Auth0 does NOT accept wildcards like `http://localhost:*` — it requires exact matches. By default Claude Code picks a random local port for the OAuth callback, which will not match a pre-registered Auth0 URI. **Solution:** use Claude Code's `--callback-port <port>` flag during connector add to fix the port, then register the matching `http://localhost:<port>/callback` URI in Auth0. Pick a port unlikely to collide (e.g. 47891).
- Configure scopes appropriately (basic profile + `offline_access` for refresh tokens)

### Client-side setup (one-time)

```bash
# Add the MCP connector with a fixed callback port to match the Auth0 redirect URI
claude mcp add basic-memory --transport http \
  --callback-port 47891 \
  https://pensieve.your-domain.app/mcp

# Trigger initial OAuth flow (opens browser)
claude mcp auth basic-memory

# If using a confidential client, configure client_id and client_secret in
# Advanced settings during `claude mcp add` (or via the configurator UI).
```

After this, tokens refresh automatically. The user may need to re-authenticate every few weeks when refresh tokens themselves expire (depends on Auth0 configuration).

### Known issues to watch for

As of early 2026, the OAuth-with-MCP space had a few rough edges worth being aware of:

- Claude Code CLI had a bug where it didn't send the `scope` parameter in OAuth requests. Auth0 is typically tolerant of this, but if the initial flow fails, check whether the bug is still open.
- Refresh token handling has been inconsistent across MCP SDK versions. If Claude Code suddenly can't authenticate after working for weeks, `claude mcp auth basic-memory` again.
- Audience binding (RFC 8707) is not always sent. OpenResty's JWT validation should be lenient on the `aud` claim initially; tighten later.

These are upstream issues, not plugin issues. If they go away, nothing in this spec changes.

## 19. Future: headless agents (POST-IMPLEMENTATION QUESTION FOR THE USER)

The current design assumes an interactive human user is present to complete OAuth flows. Tokens refresh transparently, but the initial authorization needs a browser session and a human clicking "allow."

This is correct for the primary use case (Claude Code running on the user's local machine). It does not cover:

- **Cron jobs or scheduled tasks** that need to access the vault without a human present
- **CI runners** running Claude Code or other agents against the vault
- **Background processes** like a defrag script that wants to run at 3am
- **Truly headless cloud agents** with no associated user session
- **Phone/mobile agents** where the OAuth flow may be friction-heavy

If any of these become needed, the plugin's auth story will need to be extended. The two reasonable paths:

1. **Long-lived service tokens.** A separately-issued bearer token (not OAuth-derived) that the gateway accepts for specific endpoints. Stored encrypted on the headless machine. Simple, but represents a long-lived credential.
2. **Auth0 Client Credentials Grant (M2M).** A non-interactive OAuth flow where a service account authenticates with `client_id` + `client_secret` to get a short-lived token. More complex setup, but composes cleanly with existing Auth0 infrastructure.

**Both bypass Claude Code's built-in MCP OAuth.** A headless agent isn't Claude Code running interactively for a human — it's some other process (a cron job, a background script, a different MCP client). It would NOT go through the OAuth dance documented in §18; it would talk to the gateway with whatever credential the chosen path provides. This means:

- The plugin's auth story splits in two: interactive (Claude Code → OAuth via §18) and headless (whatever this future design picks)
- The OpenResty gateway needs to accept both auth modes if both are in use
- The non-interactive path is *parallel* to OAuth, not a replacement; Claude Code on the Mac keeps using OAuth as designed

Both are feasible. Neither needs to be designed now. **Once the plugin is implemented and the user has used it for a while, this becomes a real question worth revisiting** — at that point we'll know which (if any) headless use cases actually matter.

For now: defer. Note this as a known limitation in the README. Revisit after first real usage.

---

*End of spec v6. Review before implementation begins.*
