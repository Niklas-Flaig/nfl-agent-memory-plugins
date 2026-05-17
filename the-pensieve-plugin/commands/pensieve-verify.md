---
description: Force a verification against the remote default branch for a project meta. One GitHub API call, then a file-level drift breakdown if HEAD has moved. Bypasses the TTL cache.
argument-hint: "<slug>"
---

# /pensieve-verify

Manual verification trigger — for when the agent isn't going to invoke `pensieve-verify-project` on its own (e.g. the user wants a freshness number right now, or the TTL is masking known drift).

## Procedure

1. **Require a slug.** This command always takes an explicit slug. If none is passed, ask the user — don't default to the current repo, since the SessionStart hook already handled that one locally.

2. **Force-verify.** Invoke the `pensieve-verify-project` skill with `slug=<slug>` AND tell it to bypass the verify-cache for this run (treat as if `[verification].ttl_hours` were zero).

3. **Surface the result verbatim.** Show the verified/not-verified flag, both SHAs, the file counts, and the recommendation. Do not auto-trigger reconcile — the user decides.

## Notes

- This command is read-only against the vault (the skill itself only writes `sync.last_verified_at` and the `last_seen_drift` snapshot via `pensieve-update-meta` — no other writes happen here).
- Useful as a sanity check before invoking `pensieve-fetch-project` for a critical doc.
