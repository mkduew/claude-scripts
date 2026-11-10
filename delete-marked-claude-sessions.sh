#!/bin/bash
# Finds Claude Code sessions whose current custom title is "TODELETE" and optionally deletes them.
# WARNING: Deleted files are not moved to trash – no recovery possible!
# Usage: ./delete-marked-claude-sessions.sh [--delete]

DELETE_MODE=false
for arg in "$@"; do
  case "$arg" in
    --delete) DELETE_MODE=true ;;
    *) echo "Unknown option: $arg"; echo "Usage: $(basename "$0") [--delete]"; exit 1 ;;
  esac
done

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

# Prints the IDs of sessions that are currently running. Claude Code registers every
# running session in ~/.claude/sessions/<pid>.json; entries can outlive a crash, so the
# process must still be alive.
live_session_ids() {
  local f pid sid
  for f in "$CLAUDE_DIR"/sessions/*.json; do
    [[ -f "$f" ]] || continue
    pid="$(grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' "$f" | head -n 1 | grep -oE '[0-9]+$')"
    sid="$(grep -oE '"sessionId"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')"
    [[ -n "$pid" && -n "$sid" ]] && kill -0 "$pid" 2>/dev/null && echo "$sid"
  done
}
LIVE_IDS="$(live_session_ids)"

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

# Scans all sessions and deletes (or previews) the ones marked "TODELETE".
# With FILTER=true only sessions listed in APPROVED are touched, so confirming a
# preview never deletes a session that was marked after the preview was shown.
FILTER=false
APPROVED=""
PREVIEWED=()
scan() {
  FOUND=0
  SKIPPED=0
  local jsonl_file session_id
  while IFS= read -r -d '' jsonl_file; do
    [[ "$(current_title "$jsonl_file")" == "TODELETE" ]] || continue

    session_id="$(basename "$jsonl_file" .jsonl)"
    if [[ ! "$session_id" =~ $UUID_RE ]]; then
      echo "Skipping (unexpected file name): $jsonl_file"
      continue
    fi
    if $FILTER && ! grep -qxF -- "$jsonl_file" <<< "$APPROVED"; then
      echo "Skipping (marked after the preview – run the script again): $jsonl_file"
      continue
    fi
    # Deleting a running session would let Claude Code recreate a partial transcript.
    if grep -qxF -- "$session_id" <<< "$LIVE_IDS"; then
      echo "Skipping (session is still running – close it first): $jsonl_file"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    FOUND=$((FOUND + 1))

    if $DELETE_MODE; then
      rm -f -- "$jsonl_file"
      echo "Deleted: $jsonl_file"
    else
      PREVIEWED+=("$jsonl_file")
      echo "[DRY-RUN] Would delete: $jsonl_file"
    fi
    remove_path "${jsonl_file%.jsonl}"                "Session directory"
    remove_path "$CLAUDE_DIR/session-env/$session_id"  "Session env"
    remove_path "$CLAUDE_DIR/file-history/$session_id" "File history"
  done < <(find "$PROJECTS_DIR" -name "*.jsonl" -not -path "*/subagents/*" -print0)

  echo ""
  echo "$FOUND conversation(s) found."
  if [[ $SKIPPED -gt 0 ]]; then
    echo "$SKIPPED running conversation(s) skipped – exit them and run the script again."
  fi
}

scan

if $DELETE_MODE; then
  echo "Done."
elif [[ $FOUND -gt 0 ]]; then
  echo ""
  read -r -p "Permanently delete $FOUND conversation(s)? [y/N] " confirm
  if [[ "$confirm" =~ ^[yY]$ ]]; then
    # Delete exactly the previewed sessions. Every check (title, running state)
    # is repeated, so a session that changed in the meantime is skipped.
    echo ""
    DELETE_MODE=true
    FILTER=true
    APPROVED="$(printf '%s\n' "${PREVIEWED[@]}")"
    LIVE_IDS="$(live_session_ids)"
    scan
    echo "Done."
  else
    echo "Aborted."
  fi
else
  echo "To delete: $(basename "$0") --delete"
fi
