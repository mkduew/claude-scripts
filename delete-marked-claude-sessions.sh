#!/bin/bash
# Finds JSONL files with customTitle "TODELETE" and optionally deletes them.
# WARNING: Deleted files are not moved to trash – no recovery possible!
# Usage: ./delete-todelete-sessions.sh [--delete]

DELETE_MODE=false
if [[ "$1" == "--delete" ]]; then
  DELETE_MODE=true
fi

PROJECTS_DIR="$HOME/.claude/projects"
if [[ ! -d "$PROJECTS_DIR" ]]; then
  echo "Directory not found: $PROJECTS_DIR"
  exit 0
fi

FOUND=0
while IFS= read -r -d '' jsonl_file; do
  if grep -qE '"customTitle"[[:space:]]*:[[:space:]]*"TODELETE"' "$jsonl_file"; then
    FOUND=$((FOUND + 1))
    dir="${jsonl_file%.jsonl}"

    if $DELETE_MODE; then
      rm "$jsonl_file"
      [[ -d "$dir" ]] && rm -rf "$dir"
      echo "Deleted: $jsonl_file"
    else
      echo "[DRY-RUN] Would delete: $jsonl_file"
      [[ -d "$dir" ]] && echo "           + Directory: $dir"
    fi
  fi
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
