#!/usr/bin/env bash
# verify-commit.sh — one GitHub API call to resolve the HEAD SHA of a branch.
#
# Used by the pensieve-verify-project skill (spec §9). Sub-second when gh is
# authenticated. Caches nothing — caller is responsible for memoization via
# ~/.cache/the-pensieve/verify/<slug>.json.
#
# Usage:
#   verify-commit.sh <repo_url> <branch>
#
# repo_url may be HTTPS or SSH; we extract owner/repo from either form.
# Outputs the SHA on stdout. Exit code 0 on success, non-zero on any failure.

set -euo pipefail

repo_url="${1:?usage: verify-commit.sh <repo_url> <branch>}"
branch="${2:?usage: verify-commit.sh <repo_url> <branch>}"

# Parse owner/repo. Accepts:
#   git@github.com:owner/repo.git
#   https://github.com/owner/repo.git
#   https://github.com/owner/repo
owner_repo="$(printf '%s' "$repo_url" | sed -E \
  -e 's#^git@github\.com:##' \
  -e 's#^https?://github\.com/##' \
  -e 's#\.git$##')"

if [[ ! "$owner_repo" =~ ^[^/]+/[^/]+$ ]]; then
  echo "verify-commit: could not parse owner/repo from '$repo_url'" >&2
  exit 1
fi

# gh handles auth via the user's logged-in session. --jq trims output to SHA.
gh api "repos/${owner_repo}/commits/${branch}" --jq '.sha'
