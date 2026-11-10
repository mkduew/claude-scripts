#!/bin/bash
# Finds Claude Code project folders whose original project directory no longer exists
# and optionally deletes them (including related per-session data).
# WARNING: Deleted files are not moved to trash – no recovery possible!
# Usage: ./delete-orphaned-claude-projects.sh [--delete]

DELETE_MODE=false
if [[ "$1" == "--delete" ]]; then
  DELETE_MODE=true
fi

# UTF-8 locale so that multi-byte characters (e.g. umlauts) count as one character
# when re-encoding paths the way Claude Code does.
export LC_ALL=en_US.UTF-8

CLAUDE_DIR="$HOME/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"
if [[ ! -d "$PROJECTS_DIR" ]]; then
  echo "Directory not found: $PROJECTS_DIR"
  exit 0
fi

UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# Claude Code names project folders after the project path with every
# non-alphanumeric character replaced by "-".
# Characters are listed explicitly: ranges like a-z can match umlauts in UTF-8 locales.
encode_path() {
  local p="$1"
  echo "${p//[^abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]/-}"
}

# Prints the working directory a session was started in (first "cwd" entry).
session_cwd() {
  grep -m 1 -oE '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" \
    | sed -E 's/^"cwd"[[:space:]]*:[[:space:]]*"(.*)"$/\1/'
}

# True if the folder contains nothing but .DS_Store files and empty directories.
is_effectively_empty() {
  [[ -z "$(find "$1" -type f ! -name .DS_Store -print -quit)" ]]
}

# Prints the session UUIDs belonging to a project folder (from .jsonl files and UUID directories).
session_ids() {
  local entry name
  for entry in "$1"/*; do
    [[ -e "$entry" ]] || continue
    name="$(basename "$entry" .jsonl)"
    [[ "$name" =~ $UUID_RE ]] && echo "$name"
  done | sort -u
}

delete_project() {
  local project="$1" id
  for id in $(session_ids "$project"); do
    for extra in "$CLAUDE_DIR/session-env/$id" "$CLAUDE_DIR/file-history/$id"; do
      if [[ -e "$extra" ]]; then
        if $DELETE_MODE; then
          rm -rf -- "$extra"
          echo "           - Deleted: $extra"
        else
          echo "           + $extra"
        fi
      fi
    done
  done
  # A non-empty memory/ folder is never deleted automatically – only the sessions around it.
  if [[ -d "$project/memory" ]] && ! is_effectively_empty "$project/memory"; then
    local entry
    for entry in "$project"/* "$project"/.[!.]*; do
      [[ -e "$entry" ]] || continue
      [[ "$(basename "$entry")" == "memory" ]] && continue
      if $DELETE_MODE; then
        rm -rf -- "$entry"
        echo "           - Deleted: $entry"
      else
        echo "           + $entry"
      fi
    done
    if $DELETE_MODE; then
      echo "           = Kept: $project/memory"
    else
      echo "           = Would keep: $project/memory"
    fi
  elif $DELETE_MODE; then
    rm -rf -- "$project"
    echo "           - Deleted: $project"
  else
    echo "           + $project"
  fi
}

ORPHANED=0
EMPTY=0
REVIEW=0
REVIEW_LINES=()

shopt -s nullglob
for project in "$PROJECTS_DIR"/*/; do
  project="${project%/}"
  name="$(basename "$project")"
  sessions=("$project"/*.jsonl)

  # Case 1: no session files at all
  if [[ ${#sessions[@]} -eq 0 ]]; then
    if is_effectively_empty "$project"; then
      EMPTY=$((EMPTY + 1))
      if $DELETE_MODE; then
        echo "Empty project folder: $name"
      else
        echo "[DRY-RUN] Would delete empty project folder: $name"
      fi
      delete_project "$project"
    else
      REVIEW=$((REVIEW + 1))
      REVIEW_LINES+=("$name  (no sessions, contains: $(cd "$project" && find . -type f ! -name .DS_Store | sed 's|^\./||' | head -3 | tr '\n' ' '))")
    fi
    continue
  fi

  # Case 2: sessions exist – determine the original project path from "cwd"
  cwds=()
  for s in "${sessions[@]}"; do
    c="$(session_cwd "$s")"
    [[ -n "$c" ]] && cwds+=("$c")
  done

  if [[ ${#cwds[@]} -eq 0 ]]; then
    REVIEW=$((REVIEW + 1))
    REVIEW_LINES+=("$name  (sessions without cwd information)")
    continue
  fi

  exists=false
  matching_cwd=""
  unmounted=""
  for c in "${cwds[@]}"; do
    if [[ -d "$c" ]]; then
      exists=true
      break
    fi
    if [[ "$c" == /Volumes/* ]]; then
      vol="/Volumes/$(echo "${c#/Volumes/}" | cut -d/ -f1)"
      [[ -d "$vol" ]] || unmounted="$vol"
    fi
    [[ "$(encode_path "$c")" == "$name" ]] && matching_cwd="$c"
  done

  $exists && continue

  if [[ -n "$unmounted" ]]; then
    REVIEW=$((REVIEW + 1))
    REVIEW_LINES+=("$name  (volume not mounted: $unmounted)")
    continue
  fi

  if [[ -z "$matching_cwd" ]]; then
    REVIEW=$((REVIEW + 1))
    REVIEW_LINES+=("$name  (path not found, but folder name does not match: ${cwds[0]})")
    continue
  fi

  ORPHANED=$((ORPHANED + 1))
  size="$(du -sh "$project" | cut -f1 | tr -d ' ')"
  if $DELETE_MODE; then
    echo "Orphaned project: $matching_cwd ($size, ${#sessions[@]} session(s))"
  else
    echo "[DRY-RUN] Would delete orphaned project: $matching_cwd ($size, ${#sessions[@]} session(s))"
  fi
  delete_project "$project"
done

if [[ $REVIEW -gt 0 ]]; then
  echo ""
  echo "Not deleted – please review manually:"
  for line in "${REVIEW_LINES[@]}"; do
    echo "  $line"
  done
fi

TOTAL=$((ORPHANED + EMPTY))
echo ""
echo "$ORPHANED orphaned project(s), $EMPTY empty folder(s), $REVIEW for manual review."

if $DELETE_MODE; then
  echo "Done."
else
  if [[ $TOTAL -gt 0 ]]; then
    echo ""
    read -r -p "Permanently delete $TOTAL project folder(s)? [y/N] " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
      exec "$0" --delete
    else
      echo "Aborted."
    fi
  else
    echo "Nothing to delete."
  fi
fi
