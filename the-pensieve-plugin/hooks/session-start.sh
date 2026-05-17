#!/usr/bin/env bash
# session-start.sh — Pensieve SessionStart hook.
#
# Emits a JSON payload with `hookSpecificOutput.additionalContext` containing:
#   1. The full text of rules/pensieve-routing.md
#   2. A slug + drift-status block scaled to severity
#   3. An instruction to read the project meta if drift is moderate/heavy
#
# Per spec §6.5 + §8 this hook never touches the vault — it reads only the
# meta-mirror cache, runs local git work via scripts/compute-drift.sh, and
# delegates all vault reads to the agent's first turn via MCP.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
RULES_FILE="${PLUGIN_ROOT}/rules/pensieve-routing.md"
COMPUTE_DRIFT="${PLUGIN_ROOT}/scripts/compute-drift.sh"

# Find the current repo root, if any. The hook fires regardless of cwd; if
# we're not in a git repo we still inject the routing rules but skip drift.
cwd="$(pwd)"
repo_root=""
if git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then
  repo_root="$git_root"
fi

rules_text=""
if [[ -f "$RULES_FILE" ]]; then
  rules_text="$(cat "$RULES_FILE")"
fi

# Compute drift if we're inside a repo. Failure here must not break the hook —
# at worst we emit the routing rules with no drift block.
drift_json='{"slug":"","severity":"none","mirror_present":false,"message":"Not inside a git repository — no drift check performed."}'
if [[ -n "$repo_root" && -x "$COMPUTE_DRIFT" ]]; then
  if out="$("$COMPUTE_DRIFT" "$repo_root" 2>/dev/null)"; then
    drift_json="$out"
  fi
fi

# Build the additionalContext text. Python handles JSON escaping for stdout.
python3 - "$rules_text" "$drift_json" <<'PY'
import json
import sys

rules_text = sys.argv[1]
drift = json.loads(sys.argv[2])

severity = drift.get("severity", "none")
slug = drift.get("slug", "")
message = drift.get("message", "")
mirror_present = drift.get("mirror_present", False)
files_changed = drift.get("files_changed", 0)
doc_files_changed = drift.get("doc_files_changed", 0)
structural = drift.get("structural", [])

# Drift status block.
status_lines = ["", "## [pensieve] Session start status", ""]
if severity == "none":
    status_lines.append(message or "No active project.")
elif severity == "unknown":
    status_lines.append(f"- Slug (basename): `{slug}`")
    status_lines.append(f"- {message}")
elif severity == "clean":
    status_lines.append(f"- Project: `{slug}` — clean (no drift since last sync).")
else:
    status_lines.append(f"- Project: `{slug}`")
    status_lines.append(f"- Drift severity: **{severity}**")
    status_lines.append(f"- Files changed: {files_changed} (of which docs: {doc_files_changed})")
    if structural:
        status_lines.append("- Structural signals:")
        for s in structural:
            status_lines.append(f"  - {s}")
    status_lines.append(f"- {message}")
    if severity in ("moderate", "heavy"):
        status_lines.append("")
        status_lines.append(
            f"**Action:** call `read_note(identifier=\"projects/{slug}\")` before relying on this project's meta, "
            "and surface to the user whether `/pensieve-reconcile` should run."
        )

additional_context = rules_text + "\n" + "\n".join(status_lines) + "\n"

payload = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": additional_context,
    }
}

# systemMessage surfaces visibly to the user for moderate/heavy drift.
if severity in ("moderate", "heavy"):
    payload["systemMessage"] = f"[pensieve] {severity} drift on '{slug}': {message}"

print(json.dumps(payload))
PY
