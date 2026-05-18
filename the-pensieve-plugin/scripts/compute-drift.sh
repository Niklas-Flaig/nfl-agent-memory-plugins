#!/usr/bin/env bash
# compute-drift.sh — local drift detection for one repo. No network. No vault.
#
# Usage: compute-drift.sh <repo_root>
#
# Reads the meta-mirror cache at $PENSIEVE_CACHE_DIR/meta-mirror/<slug>.json
# if present. The mirror is written by skills whenever they edit a project
# meta in the vault (see spec §8 "Stored drift signal"). Without the mirror
# we cannot know last_synced_commit or the docs.* map, so drift is reported
# as "unknown" and the hook injects a hint to run /pensieve-init-project.
#
# Output: a single JSON object on stdout describing drift. Caller wraps it
# into the SessionStart additionalContext payload.

set -euo pipefail

REPO_ROOT="${1:?usage: compute-drift.sh <repo_root>}"

# shellcheck source=./read-config.sh
. "$(dirname "$0")/read-config.sh"

MIRROR_DIR="${PENSIEVE_CACHE_DIR}/meta-mirror"

# Slug: prefer mirror's slug field if present, else basename of repo root
# (spec §16 "Resolved during design"). The frontmatter `slug:` override only
# reaches the hook via the mirror, so on first session the basename is used
# and the agent fixes it on the first reconcile.
default_slug="$(basename "$REPO_ROOT")"

# Probe every mirror file for a matching repo_path before falling back to
# basename — that way an explicit `slug:` override in the project meta is
# honored as soon as the mirror exists, even if the directory name differs.
slug=""
if [[ -d "$MIRROR_DIR" ]]; then
  while IFS= read -r -d '' mirror; do
    if grep -q "\"repo_path\"[[:space:]]*:[[:space:]]*\"${REPO_ROOT}\"" "$mirror" 2>/dev/null; then
      slug="$(basename "$mirror" .json)"
      break
    fi
  done < <(find "$MIRROR_DIR" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
fi
[[ -z "$slug" ]] && slug="$default_slug"

mirror_file="${MIRROR_DIR}/${slug}.json"

emit_json() {
  # $1 severity, $2 files_changed, $3 doc_files_changed, $4 structural_json_array, $5 mirror_present (true|false), $6 message
  cat <<EOF
{
  "slug": $(printf '%s' "$slug" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "severity": "$1",
  "files_changed": $2,
  "doc_files_changed": $3,
  "structural": $4,
  "mirror_present": $5,
  "message": $(printf '%s' "$6" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
}
EOF
}

# No mirror → can't know vault state. Inject hint, no drift numbers.
if [[ ! -f "$mirror_file" ]]; then
  emit_json "unknown" 0 0 "[]" "false" "No project meta cached for slug '${slug}'. Run /pensieve-init-project if this project should be tracked in the vault."
  exit 0
fi

# Parse the fields we need from the mirror. Tolerant of pretty-printed JSON.
last_synced_commit="$(python3 -c "import json,sys; d=json.load(open('$mirror_file')); print(d.get('sync',{}).get('last_synced_commit',''))" 2>/dev/null || echo "")"
default_branch="$(python3 -c "import json,sys; d=json.load(open('$mirror_file')); print(d.get('default_branch',''))" 2>/dev/null || echo "")"
docs_paths="$(python3 -c "import json,sys; d=json.load(open('$mirror_file')); docs=d.get('docs',{}); custom=docs.pop('custom',{}) if isinstance(docs.get('custom'),dict) else {}; out=[v for v in docs.values() if isinstance(v,str)] + [v for v in custom.values() if isinstance(v,str)]; print('\\n'.join(out))" 2>/dev/null || echo "")"

structural=()
add_struct() { structural+=("$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")"); }

# Structural check: default branch.
if [[ -n "$default_branch" ]]; then
  current_default="$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)"
  if [[ -n "$current_default" && "$current_default" != "$default_branch" ]]; then
    add_struct "default_branch_changed: vault has '$default_branch', repo has '$current_default'"
  fi
fi

# Structural check: docs.* paths exist.
missing_paths=0
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  abs="$REPO_ROOT/$p"
  if [[ ! -e "$abs" ]]; then
    missing_paths=$((missing_paths + 1))
    add_struct "missing_path: $p"
  fi
done <<< "$docs_paths"

# File-level diff.
files_changed=0
doc_files_changed=0
if [[ -n "$last_synced_commit" ]] && git -C "$REPO_ROOT" cat-file -e "${last_synced_commit}^{commit}" 2>/dev/null; then
  files_changed=$(git -C "$REPO_ROOT" diff --name-only "${last_synced_commit}..HEAD" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$files_changed" -gt 0 ]]; then
    # grep returns 1 when nothing matches; pipefail would propagate that and
    # break the wc count. Wrap grep in { ... || true; } so the pipeline only
    # fails on a real error.
    doc_files_changed=$(git -C "$REPO_ROOT" diff --name-only "${last_synced_commit}..HEAD" 2>/dev/null \
      | { grep -E "$PENSIEVE_DOC_PATTERNS_REGEX" || true; } \
      | wc -l | tr -d ' ')
  fi
elif [[ -n "$last_synced_commit" ]]; then
  add_struct "unknown_last_synced_commit: ${last_synced_commit} not in local git history"
fi

# Severity.
severity="clean"
if [[ "${#structural[@]}" -gt 0 ]]; then
  severity="heavy"
elif [[ "$doc_files_changed" -ge "$PENSIEVE_HEAVY_DOC_FILES_THRESHOLD" ]]; then
  severity="heavy"
elif [[ "$doc_files_changed" -ge "$PENSIEVE_MODERATE_DOC_FILES_THRESHOLD" ]]; then
  severity="moderate"
elif [[ "$files_changed" -ge "$PENSIEVE_MODERATE_FILES_THRESHOLD" ]]; then
  severity="moderate"
elif [[ "$files_changed" -ge "$PENSIEVE_MINOR_FILES_THRESHOLD" ]]; then
  severity="minor"
fi

# Message scaled to severity.
case "$severity" in
  clean)
    msg="No drift detected for ${slug}." ;;
  minor)
    msg="${files_changed} files changed since last sync, no docs touched." ;;
  moderate)
    msg="${files_changed} files changed (${doc_files_changed} docs) since last sync. Consider /pensieve-reconcile." ;;
  heavy)
    if [[ "${#structural[@]}" -gt 0 ]]; then
      msg="Structural drift detected for ${slug}: $(IFS='; '; echo "${structural[*]}" | sed 's/"//g'). Run /pensieve-reconcile."
    else
      msg="${doc_files_changed} doc files changed since last sync. Run /pensieve-reconcile before relying on the project meta."
    fi
    ;;
esac

# Compose the structural JSON array.
if [[ "${#structural[@]}" -eq 0 ]]; then
  structural_json="[]"
else
  structural_json="[$(IFS=,; echo "${structural[*]}")]"
fi

emit_json "$severity" "$files_changed" "$doc_files_changed" "$structural_json" "true" "$msg"
