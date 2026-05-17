#!/usr/bin/env bash
# write-mirror.sh — write the cache-mirror JSON for one project.
#
# The SessionStart hook reads these files instead of touching the vault
# (spec §6.5 + §8). Every skill that performs an `edit_note` on a project
# meta MUST also call this script so the hook stays in sync.
#
# Usage:
#   write-mirror.sh <slug>          # reads JSON on stdin
#
# The stdin JSON should mirror the subset of project-meta frontmatter the
# hook cares about:
#   {
#     "slug": "<slug>",
#     "repo_path": "<absolute repo path>",
#     "default_branch": "<branch>",
#     "docs": { "context": "...", "adrs": "...", "readme": "...", "custom": {...} },
#     "sync": { "last_synced_commit": "<sha>" }
#   }
#
# Fields not present are simply omitted from the written file. The hook
# tolerates missing fields gracefully (they degrade severity, not break it).

set -euo pipefail

slug="${1:?usage: write-mirror.sh <slug>}"

# shellcheck source=./read-config.sh
. "$(dirname "$0")/read-config.sh"

mirror_dir="${PENSIEVE_CACHE_DIR}/meta-mirror"
mkdir -p "$mirror_dir"

target="${mirror_dir}/${slug}.json"
tmp="$(mktemp "${target}.XXXXXX")"

# Validate JSON AND pretty-print in one python pass. Using `python3 -c` keeps
# stdin available for the JSON payload — heredoc-on-stdin (`python3 - <<PY`)
# would consume stdin with the script itself.
if ! python3 -c '
import json, sys
path = sys.argv[1]
data = json.load(sys.stdin)
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
' "$tmp" 2>/dev/null
then
  rm -f "$tmp"
  echo "write-mirror: input is not valid JSON" >&2
  exit 1
fi

mv "$tmp" "$target"
echo "wrote $target"
