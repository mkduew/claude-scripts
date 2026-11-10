#!/bin/bash
# Finds Claude Code sessions whose current custom title is "TODELETE" and optionally deletes them.
# WARNING: Deleted files are not moved to trash – no recovery possible!
# Usage: ./delete-marked-claude-sessions.sh [--delete]

DELETE_MODE=false
if [[ "$1" == "--delete" ]]; then
  DELETE_MODE=true
fi

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"
if [[ ! -d "$PROJECTS_DIR" ]]; then
  echo "Directory not found: $PROJECTS_DIR"
  exit 0
fi

UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Prints the most recent custom title of a session file (empty if none).
# Only unescaped "customTitle" keys match, so titles quoted inside
# conversation content (which appear as \"customTitle\") are ignored.
current_title() {
  grep -oE '"customTitle"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" \
    | tail -n 1 \
    | sed -E 's/^"customTitle"[[:space:]]*:[[:space:]]*"(.*)"$/\1/'
}

# Removes a path (file or directory) if it exists, or reports it in dry-run mode.
remove_path() {
  local path="$1" label="$2"
  [[ -e "$path" ]] || return 0
  if $DELETE_MODE; then
    rm -rf -- "$path"
    echo "           - Deleted $label: $path"
  else
    echo "           + $label: $path"
  fi
}

FOUND=0
while IFS= read -r -d '' jsonl_file; do
  [[ "$(current_title "$jsonl_file")" == "TODELETE" ]] || continue

  session_id="$(basename "$jsonl_file" .jsonl)"
  if [[ ! "$session_id" =~ $UUID_RE ]]; then
    echo "Skipping (unexpected file name): $jsonl_file"
    continue
  fi
  FOUND=$((FOUND + 1))

  if $DELETE_MODE; then
    rm -f -- "$jsonl_file"
    echo "Deleted: $jsonl_file"
  else
    echo "[DRY-RUN] Would delete: $jsonl_file"
  fi
  remove_path "${jsonl_file%.jsonl}"                "Session directory"
  remove_path "$CLAUDE_DIR/session-env/$session_id"  "Session env"
  remove_path "$CLAUDE_DIR/file-history/$session_id" "File history"
done < <(find "$PROJECTS_DIR" -name "*.jsonl" -not -path "*/subagents/*" -print0)

echo ""
echo "$FOUND conversation(s) found."

if $DELETE_MODE; then
  echo "Done."
else
  if [[ $FOUND -gt 0 ]]; then
    echo ""
    read -r -p "Permanently delete $FOUND conversation(s)? [y/N] " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
      exec "$0" --delete
    else
      echo "Aborted."
    fi
  else
    echo "To delete: $(basename "$0") --delete"
  fi
fi
