---
name: pensieve-reconcile
description: Interactive repair walk for one project meta note — computes a full drift report (file diff + structural checks + verification against the remote), then walks the user through each finding one at a time with yes/no/edit/skip, applying accepted changes via `pensieve-update-meta` and finally bumping `sync.last_synced_commit` to current HEAD. Use this skill when SessionStart reports moderate/heavy drift, when `pensieve-verify-project` shows mismatch, or whenever the user says "reconcile this project". Trigger phrases: "run reconcile", "/pensieve-reconcile", "fix the project meta", "the drift detector fired, repair it", "walk me through the project drift".
---

# pensieve-reconcile

The full repair flow. Slower than `pensieve-update-meta` (multi-step, interactive, may make several MCP calls) but the only way to bring a drifted project meta back to truth.

## Inputs

- `slug`: defaults to the current repo's slug (from the SessionStart status block). If you're not inside a git repo, the user must supply it.

## Procedure

### 1. Compute the full drift report

Combine multiple signals:

- **Shell**: `git -C <repo_path> diff --name-only <last_synced_commit>..HEAD` for the file list. Split into doc files (regex from config) and code files.
- **Shell**: For each `docs.*` path in the frontmatter, check whether it exists in the working tree at `<repo_path>`. List the missing ones.
- **Shell**: `git -C <repo_path> symbolic-ref refs/remotes/origin/HEAD` to detect default branch changes against the stored `default_branch`.
- **MCP**: `read_note(identifier="projects/<slug>")` to load current frontmatter for comparison.
- **Optional shell**: `git -C <repo_path> log --oneline <last_synced_commit>..HEAD -- <doc paths>` to surface noteworthy commits for narrative-body candidates.

If `slug` is not the current repo, also invoke `pensieve-verify-project` first to get the remote view — local checks alone don't cover the case where the local clone is itself out of date.

### 2. Walk findings one at a time

For each finding, present it concisely and ask the user. **One question at a time.** Do not batch.

Templates:

- **Missing path**: "Frontmatter says `docs.context` = `CONTEXT.md` but no such file exists in the repo. Options: (1) remove the field, (2) point it at a different path, (3) leave as-is and flag for later." → wait for the user.
- **Default branch changed**: "Vault has `default_branch: master`, repo has `main`. Update?" → wait.
- **Doc file changed**: "`docs/adr/0007-something.md` was modified in the diff. Want me to read it and propose a frontmatter or narrative update?" → wait.
- **New ADR / doc not in frontmatter**: "I see `docs/adr/0009-new-decision.md` added since last sync — should it be in the `docs.adrs` glob or referenced explicitly?" → wait.
- **Heavy code churn, no docs**: "50+ files changed but no docs. Not a frontmatter concern — only the `sync.last_synced_commit` will be bumped at the end. OK?" → wait.

### 3. Apply accepted changes

For each accepted finding, call `pensieve-update-meta` with the targeted `field` and `value`. This keeps the mirror write central to one skill — never call `edit_note` directly from this skill.

If the user wants a narrative-body addition (e.g. "mention the new ADR in the project notes"), call `edit_note` once at the end for the body change, then **immediately** call `${CLAUDE_PLUGIN_ROOT}/scripts/write-mirror.sh <slug>` with the post-update frontmatter to refresh the mirror. (The body change doesn't affect the mirror's content but the slug-level edit must still re-sync the mirror file as a precaution against partial writes.)

### 4. Finalize

After all findings are processed:

1. Get the current HEAD: `git -C <repo_path> rev-parse HEAD`.
2. Call `pensieve-update-meta` to set:
   - `sync.last_synced_commit` = current HEAD
   - `sync.last_synced_at` = today
   - `sync.last_verified_at` = today
   - `sync.last_seen_drift.files_changed` = 0
   - `sync.last_seen_drift.doc_files_changed` = 0
   - `sync.last_seen_drift.paths_missing` = 0
   - `sync.last_seen_drift.default_branch_changed` = false
3. Report a one-line summary of what changed.

### 5. If nothing was drifted

Tell the user that — and still bump `sync.last_verified_at` so the verify TTL is happy. No other writes.

## Constraints

- **One MCP write per finding**, via `pensieve-update-meta`. Batch operations make rollback messy.
- Never assume an answer. If the user is ambiguous on a finding, ask again.
- Respect the spec's "Compose, don't substitute" rule (§7): if the user wants a doc-writing skill to make the actual repo-side change (e.g. write a new ADR), defer to that skill — this skill only updates vault frontmatter.
- The final `sync.last_synced_commit` bump is the **only** place this commit field is touched. Other skills must not write it.
