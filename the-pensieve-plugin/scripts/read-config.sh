#!/usr/bin/env bash
# read-config.sh — source this file to export config values into the caller's env.
#
# Reads ~/.config/the-pensieve/config.toml (XDG location per spec §13) and
# exports the subset of fields the SessionStart hook needs. Unset fields fall
# back to the spec defaults.
#
# Narrow by design: only the [drift_severity] thresholds and the
# [drift_severity.doc_patterns] regex are parsed. TOML features beyond
# `key = value` on a single line (comments, inline tables, arrays, multi-line
# values) are NOT supported in this reader. The skill suite uses Basic Memory
# MCP for everything else and never reads config from shell, so the surface
# area stays small.

set -euo pipefail

# Spec §13 defaults.
export PENSIEVE_MODERATE_DOC_FILES_THRESHOLD="${PENSIEVE_MODERATE_DOC_FILES_THRESHOLD:-1}"
export PENSIEVE_HEAVY_DOC_FILES_THRESHOLD="${PENSIEVE_HEAVY_DOC_FILES_THRESHOLD:-3}"
export PENSIEVE_MODERATE_FILES_THRESHOLD="${PENSIEVE_MODERATE_FILES_THRESHOLD:-50}"
export PENSIEVE_MINOR_FILES_THRESHOLD="${PENSIEVE_MINOR_FILES_THRESHOLD:-10}"
export PENSIEVE_DOC_PATTERNS_REGEX="${PENSIEVE_DOC_PATTERNS_REGEX:-\\.(md|mdx)\$|^docs/|^adr/|^CONTEXT\\.md|^README\\.md}"
export PENSIEVE_CACHE_DIR="${PENSIEVE_CACHE_DIR:-$HOME/.cache/the-pensieve}"

CONFIG_FILE="${PENSIEVE_CONFIG_FILE:-$HOME/.config/the-pensieve/config.toml}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Strip comments and blank lines, then read key=value pairs.
# We track the current [section] to scope keys correctly.
_section=""
while IFS= read -r line; do
  # Strip trailing comments and whitespace.
  line="${line%%#*}"
  line="$(printf '%s' "$line" | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//')"
  [[ -z "$line" ]] && continue

  if [[ "$line" =~ ^\[(.+)\]$ ]]; then
    _section="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    # Unwrap surrounding quotes (double, single, or triple-single for regex).
    val="${val#\'\'\'}"
    val="${val%\'\'\'}"
    val="${val#\"}"
    val="${val%\"}"
    val="${val#\'}"
    val="${val%\'}"

    case "${_section}.${key}" in
      "drift_severity.moderate_doc_files_threshold")
        export PENSIEVE_MODERATE_DOC_FILES_THRESHOLD="$val" ;;
      "drift_severity.heavy_doc_files_threshold")
        export PENSIEVE_HEAVY_DOC_FILES_THRESHOLD="$val" ;;
      "drift_severity.moderate_files_threshold")
        export PENSIEVE_MODERATE_FILES_THRESHOLD="$val" ;;
      "drift_severity.minor_files_threshold")
        export PENSIEVE_MINOR_FILES_THRESHOLD="$val" ;;
      "drift_severity.doc_patterns.regex")
        export PENSIEVE_DOC_PATTERNS_REGEX="$val" ;;
      "cache.dir")
        # Expand leading ~.
        val="${val/#\~/$HOME}"
        export PENSIEVE_CACHE_DIR="$val" ;;
    esac
  fi
done < "$CONFIG_FILE"
