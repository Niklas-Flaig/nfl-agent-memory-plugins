#!/usr/bin/env bash
# cache-manager.sh — TTL + LRU eviction for ~/.cache/the-pensieve.
#
# Called after every cache write (by the fetch and verify skills) per spec
# §13 "Cache eviction policy":
#   1. TTL pass: delete entries older than ttl_days.
#   2. LRU pass: if still over max_size_mb, delete oldest by mtime until under.
#
# We do not maintain sidecar .meta files; mtime is good enough for an
# operator-grade cache. If a future need surfaces (track last_accessed vs.
# created separately) the sidecar approach can be reintroduced here without
# changing the call sites.
#
# Usage:
#   cache-manager.sh [subdir]
# If subdir is omitted, evicts across the whole cache root. The meta-mirror
# subdirectory is always preserved (it is a derived state, not transient).

set -euo pipefail

# shellcheck source=./read-config.sh
. "$(dirname "$0")/read-config.sh"

TTL_DAYS="${PENSIEVE_CACHE_TTL_DAYS:-14}"
MAX_SIZE_MB="${PENSIEVE_CACHE_MAX_SIZE_MB:-500}"

cache_root="${PENSIEVE_CACHE_DIR}"
[[ -d "$cache_root" ]] || exit 0

if [[ $# -gt 0 ]]; then
  target="${cache_root}/$1"
else
  target="$cache_root"
fi
[[ -d "$target" ]] || exit 0

# 1. TTL pass — never touch meta-mirror/* even if old; that's the hook's
#    canonical local state, not a transient fetch.
find "$target" -path '*/meta-mirror/*' -prune -o \
  -type f -mtime +"${TTL_DAYS}" -print 2>/dev/null \
  | xargs -I{} rm -f "{}" 2>/dev/null || true

# 2. LRU pass.
size_mb() {
  du -sm "$1" 2>/dev/null | awk '{print $1}'
}

current="$(size_mb "$target")"
[[ -z "$current" ]] && exit 0

if (( current > MAX_SIZE_MB )); then
  # Build a list of (mtime, path) for non-meta-mirror files, sorted ascending.
  while IFS= read -r line; do
    file="${line#* }"
    rm -f "$file"
    new="$(size_mb "$target")"
    [[ -z "$new" ]] && break
    (( new <= MAX_SIZE_MB )) && break
  done < <(find "$target" -path '*/meta-mirror/*' -prune -o -type f -print 2>/dev/null \
    | xargs -I{} stat -f '%m {}' "{}" 2>/dev/null \
    | sort -n)
fi
