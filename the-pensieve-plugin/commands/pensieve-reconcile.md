---
description: Run the interactive reconcile flow for the current project (or another by slug). Computes drift, walks each finding with yes/no/edit/skip, and finalizes by bumping `sync.last_synced_commit` to current HEAD.
argument-hint: "[slug]"
---

# /pensieve-reconcile

Thin delegator over the `pensieve-reconcile` skill.

## Procedure

1. **Resolve the slug.**
   - If the user passed a slug as argument, use it.
   - Otherwise, derive the current project's slug:
     - First, look at the SessionStart status block in this session for `Project: <slug>` or `Slug (basename): <slug>`.
     - As a fallback, run `basename "$(git rev-parse --show-toplevel)"` inside the current cwd.
   - If neither yields a slug (no git repo, no session context), ask the user.

2. **Invoke the skill.** Call the `pensieve-reconcile` skill with `slug=<resolved>`.

3. **Stay in the conversation.** The skill drives the interactive walk; surface its prompts to the user and forward each answer back to the skill.

## Notes

- This command does no MCP writes itself — every write goes through the skill, which in turn goes through `pensieve-update-meta` (so the mirror stays in sync).
- If the slug doesn't yet have a project meta in the vault, the skill will surface that and recommend `/pensieve-init-project` instead. Don't try to scaffold from here.
