#!/usr/bin/env bash
# init-project.sh — propose initial project-meta values from a local repo.
#
# Used by /pensieve-init-project (commands/pensieve-init-project.md). Outputs a
# JSON document on stdout with proposed values for the slug, repo URL, default
# branch, repo_path, and a docs.* map populated from files that actually exist
# in the working tree. The slash command then asks the user to confirm or edit
# before writing to the vault via `write_note`.
#
# Usage:
#   init-project.sh [repo_root]
# If repo_root is omitted, the current working directory's git root is used.

set -euo pipefail

repo_root="${1:-$(pwd)}"
if ! git_root="$(git -C "$repo_root" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "init-project: '$repo_root' is not inside a git repository" >&2
  exit 1
fi

slug="$(basename "$git_root")"
remote_url="$(git -C "$git_root" config --get remote.origin.url 2>/dev/null || echo "")"
default_branch="$(git -C "$git_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")"
[[ -z "$default_branch" ]] && default_branch="$(git -C "$git_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

# Probe for common doc paths.
context_path=""
[[ -f "$git_root/CONTEXT.md" ]] && context_path="CONTEXT.md"

readme_path=""
for cand in README.md Readme.md readme.md; do
  if [[ -f "$git_root/$cand" ]]; then
    readme_path="$cand"
    break
  fi
done

adrs_path=""
for cand in docs/adr/ docs/adrs/ adr/ adrs/ .adr/; do
  if [[ -d "$git_root/$cand" ]]; then
    adrs_path="$cand"
    break
  fi
done

docs_dir=""
[[ -d "$git_root/docs/" ]] && docs_dir="docs/"

current_head="$(git -C "$git_root" rev-parse HEAD 2>/dev/null || echo "")"

python3 - "$slug" "$remote_url" "$default_branch" "$git_root" \
  "$context_path" "$readme_path" "$adrs_path" "$docs_dir" "$current_head" <<'PY'
import json, sys
slug, repo, default_branch, repo_path, context, readme, adrs, docs_dir, head = sys.argv[1:10]

docs = {}
if context: docs["context"] = context
if readme:  docs["readme"]  = readme
if adrs:    docs["adrs"]    = adrs

proposal = {
    "project": slug,
    "slug": slug,
    "status": "active",
    "repo": repo,
    "repo_path": repo_path,
    "default_branch": default_branch,
    "docs": docs,
    "tags": [],
    "related_projects": [],
    "related_dictionary": [],
    "sync": {
        "last_synced_commit": head,
        "last_synced_at": __import__("datetime").date.today().isoformat(),
        "last_verified_at": __import__("datetime").date.today().isoformat(),
        "last_seen_drift": {
            "files_changed": 0,
            "doc_files_changed": 0,
            "paths_missing": 0,
            "default_branch_changed": False,
        },
    },
    "_hints": {
        "docs_dir_present": bool(docs_dir),
        "no_remote": not repo,
        "no_readme": not readme,
        "no_context": not context,
        "no_adrs": not adrs,
    },
}
print(json.dumps(proposal, indent=2))
PY
