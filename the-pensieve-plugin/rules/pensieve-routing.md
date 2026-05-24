# Pensieve routing — operating rules for this session

You have access to the user's two-tier knowledge architecture. Use it actively.

## Where things live

- **Repo-local truth**: CONTEXT.md, ADRs, READMEs inside the current repository.
  Canonical for project-specific code, architecture, and decisions. Read with
  filesystem tools (`Read`, `Grep`).
- **Vault**: cross-project knowledge, **always accessed via Basic Memory MCP**.
  Use `search_notes`, `read_note`, `write_note`, `edit_note`, `build_context`.
  Never `Read` or `Grep` against the vault path directly — those bypass the
  index Basic Memory maintains (kept under `~/.basic-memory/`, separate from the
  vault), and break entirely if the vault is ever hosted remotely. This holds
  for the default local-first vault (`~/.pensieve`) too.
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
