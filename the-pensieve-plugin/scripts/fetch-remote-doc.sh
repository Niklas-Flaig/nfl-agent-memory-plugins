#!/usr/bin/env bash
# fetch-remote-doc.sh — fetch a single file from a remote default branch.
#
# Used by the pensieve-fetch-project skill (spec §9). Prefers a local clone
# (git show origin/<branch>:<path>) when one exists at `repo_path`, falls
# back to `gh api repos/<owner>/<repo>/contents/<path>?ref=<branch>` for
# private repos via the user's logged-in gh session.
#
# Usage:
#   fetch-remote-doc.sh <repo_url> <branch> <path> [repo_path]
#
# Outputs the file contents on stdout.

set -euo pipefail

repo_url="${1:?usage: fetch-remote-doc.sh <repo_url> <branch> <path> [repo_path]}"
branch="${2:?usage: fetch-remote-doc.sh <repo_url> <branch> <path> [repo_path]}"
path="${3:?usage: fetch-remote-doc.sh <repo_url> <branch> <path> [repo_path]}"
repo_path="${4:-}"

# Try local clone first if provided and present.
if [[ -n "$repo_path" && -d "$repo_path/.git" ]]; then
  if git -C "$repo_path" show "origin/${branch}:${path}" 2>/dev/null; then
    exit 0
  fi
  # Try to fetch latest then retry once.
  if git -C "$repo_path" fetch --quiet origin "$branch" 2>/dev/null; then
    if git -C "$repo_path" show "origin/${branch}:${path}" 2>/dev/null; then
      exit 0
    fi
  fi
fi

# Fall back to gh API.
owner_repo="$(printf '%s' "$repo_url" | sed -E \
  -e 's#^git@github\.com:##' \
  -e 's#^https?://github\.com/##' \
  -e 's#\.git$##')"

if [[ ! "$owner_repo" =~ ^[^/]+/[^/]+$ ]]; then
  echo "fetch-remote-doc: could not parse owner/repo from '$repo_url'" >&2
  exit 1
fi

# `gh api ... contents/<path>` returns base64-encoded content for files.
gh api "repos/${owner_repo}/contents/${path}?ref=${branch}" \
  --jq '.content' | base64 -d
