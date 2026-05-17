---
name: pensieve-update-meta
description: Updates a single frontmatter field on a vault project meta note (`projects/<slug>`) via Basic Memory MCP, then refreshes the local meta-mirror cache so the SessionStart hook stays in sync. Use this skill whenever you need to change one targeted field — `docs.context`, `sync.last_synced_commit`, `tags`, `status`, `related_projects`, `related_dictionary`, etc. — without doing a full reconcile. Trigger phrases: "update project meta", "set project field", "bump last_synced_at", "mark project as paused", "add this to project's related_dictionary", "fix the project meta entry".
---

# pensieve-update-meta

Narrow, surgical updates to a single project meta note. **Not** for full reconciles (use `pensieve-reconcile`) and **not** for creating a new project (use `/pensieve-init-project`).

## Inputs you need

- `slug`: the project slug (e.g. `bicycle-handlebar`)
- `field`: a dotted path into the frontmatter (e.g. `docs.context`, `sync.last_synced_commit`, `tags`, `status`)
- `value`: the new value (string, list, or nested object — match the frontmatter shape from spec §5)

If any input is missing or ambiguous, ask the user before touching the vault.

## Procedure

1. **Load the current state.** Call `read_note(identifier="projects/<slug>")`. If it returns nothing, stop and tell the user the project meta doesn't exist — they should run `/pensieve-init-project` first.
2. **Compute the patch.** Identify the existing frontmatter value for `field` and the new value. If they're identical, skip the write and tell the user nothing needed to change. **Never modify the narrative body.**
3. **Bump `sync.last_synced_at`** to today's date as a side-effect of the same edit. Do not touch `sync.last_synced_commit` here — that field belongs to reconcile, which has the full repo state in view.
4. **Apply via MCP.** Call `edit_note(identifier="projects/<slug>", ...)` with the targeted frontmatter operation. Preserve all other frontmatter and body content.
5. **Refresh the mirror.** Immediately afterwards, build a JSON object with the post-update frontmatter subset the hook needs:
   ```json
   {
     "slug": "<slug>",
     "repo_path": "<absolute path from frontmatter>",
     "default_branch": "<branch from frontmatter>",
     "docs": { ...post-update docs map... },
     "sync": { "last_synced_commit": "<unchanged sha from frontmatter>" }
   }
   ```
   Pipe it into `${CLAUDE_PLUGIN_ROOT}/scripts/write-mirror.sh <slug>` via Bash. The script validates and writes `~/.cache/the-pensieve/meta-mirror/<slug>.json`. If you skip this step, the SessionStart hook silently runs on stale data — this is the most common way the plugin's contract breaks.
6. **Report back.** Tell the user which field changed, from what to what, and confirm the mirror was refreshed.

## Constraints (from spec §6.5 + §8)

- Vault access is **only** via Basic Memory MCP — never `Read`/`Grep`/`Write` against the vault path.
- The cache mirror is local-only and **must** be rewritten on every `edit_note` you perform on a project meta. Treat the mirror write as part of `edit_note`'s contract.
- This skill does not delete fields. To remove a field, use `pensieve-reconcile` so the deletion can be reviewed in context.

## What this skill refuses

- Creating new project metas (delegate to `/pensieve-init-project`)
- Multi-field "while I'm here" edits (delegate to `pensieve-reconcile`)
- Edits to the narrative body of the note (out of scope; the narrative is human territory)
