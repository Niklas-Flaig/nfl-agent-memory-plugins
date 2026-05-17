---
description: Scaffold a new project meta note in the vault for the current repo (or another repo by path). Walks the user through confirming slug, repo URL, default branch, and the docs.* map, then writes to `projects/<slug>` via Basic Memory MCP and refreshes the local meta-mirror cache.
argument-hint: "[repo_path]"
---

# /pensieve-init-project

Scaffold a new vault entry at `projects/<slug>`. Per spec §16 ("Resolved during design"), this is never automatic — only invoked when the user asks for it.

## Procedure

1. **Resolve the repo.** If the user passed a path argument, use it. Otherwise use the current working directory. Confirm it's inside a git repo.

2. **Generate a proposal.** Run:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/init-project.sh "<repo_path>"
   ```
   It returns a JSON document with proposed `slug`, `repo`, `default_branch`, `repo_path`, `docs.*` (populated only with files/dirs that actually exist), empty `tags` / `related_projects` / `related_dictionary`, and an initialized `sync` block at the current HEAD.

3. **Walk the user through it.** Show the proposal and ask, **one field at a time**:
   - **Slug**: confirm the basename-derived slug or override (spec §16).
   - **Status**: `active` (default) | `paused` | `shipped` | `archived`.
   - **Docs map**: confirm each detected entry (or mark missing). For any `_hints.*` flag that's true, ask the user whether they want to add a different path for that doc kind.
   - **Tags**: prompt for keywords.
   - **Related projects**: prompt for any slugs from `projects/`. If the user names projects, validate by calling `search_notes(query="<name>", folder="projects/")` against the vault.
   - **Related dictionary**: prompt for entries from `dictionary/`. Validate via `search_notes(query="<name>", folder="dictionary/")`.
   - **Body narrative**: ask the user for a few sentences describing the project (purpose, current state, notable context). Free-form, not required.

4. **Pre-flight: check for existing meta.** Before writing, call `read_note(identifier="projects/<slug>")`. If it returns content, stop and tell the user — direct them to `/pensieve-reconcile` instead. **Never silently overwrite an existing project meta.**

5. **Write to the vault.** Call `write_note` with:
   - `identifier="projects/<slug>"`
   - `folder="projects/"`
   - `title=<slug>` (or a human-friendlier title if the user gave one)
   - `tags`, frontmatter, and body as composed above
   - Frontmatter shape exactly as in spec §5

6. **Refresh the mirror.** Build the mirror JSON from the same data and pipe to:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/write-mirror.sh "<slug>"
   ```
   Skipping this step breaks the SessionStart hook for the next session.

7. **Confirm.** Tell the user the slug, where it was written, and that the mirror is now in sync. Suggest they restart Claude Code to see the SessionStart status block update.

## Constraints

- **No silent overwrite** of an existing project meta.
- All vault writes via Basic Memory MCP — never filesystem against the vault.
- Cache mirror written every time, even when only metadata changed.
- If the user wants to track a repo that isn't on GitHub (or doesn't have a remote at all), still scaffold the meta — but warn that `pensieve-verify-project` and `pensieve-fetch-project` will not function for it until a remote is added.
