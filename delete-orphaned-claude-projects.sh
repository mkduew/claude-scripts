#!/bin/bash
# Finds Claude Code project folders whose original project directory no longer exists
# and optionally deletes them (including related per-session data).
# WARNING: Deleted files are not moved to trash – no recovery possible!
# Usage: ./delete-orphaned-claude-projects.sh [--delete] [--include-memory]
#   --include-memory  also delete non-empty memory/ folders of orphaned projects and
#                     memory-only folders for which no existing project directory is found

DELETE_MODE=false
INCLUDE_MEMORY=false
for arg in "$@"; do
  case "$arg" in
    --delete) DELETE_MODE=true ;;
    --include-memory) INCLUDE_MEMORY=true ;;
    *) echo "Unknown option: $arg"; echo "Usage: $(basename "$0") [--delete] [--include-memory]"; exit 1 ;;
  esac
done

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

# True if the folder has a memory/ subfolder with actual files in it.
has_memory() {
  [[ -d "$1/memory" ]] && ! is_effectively_empty "$1/memory"
}

# Searches the file system for an existing directory whose encoded path equals the
# given project folder name. Prints the path and returns 0 if one is found.
# Only descends into directories whose encoded path is a prefix of the name, so only
# the directories along candidate paths are read (no full file system scan; macOS
# privacy prompts can only appear if the project really lies in a protected folder).
find_existing_path() {
  local target="$1" dir="${2:-}" child enc
  for child in "$dir"/* "$dir"/.[!.]*; do
    [[ -d "$child" ]] || continue
    enc="$(encode_path "$child")"
    if [[ "$enc" == "$target" ]]; then
      echo "$child"
      return 0
    fi
    if [[ "$target" == "$enc-"* ]]; then
      find_existing_path "$target" "$child" && return 0
    fi
  done
  return 1
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

# True if any session of the project folder is currently running.
has_live_session() {
  local id
  for id in $(session_ids "$1"); do
    grep -qxF -- "$id" <<< "$LIVE_IDS" && return 0
  done
  return 1
}

# Usage: delete_project <folder> <keep_memory: true|false>
delete_project() {
  local project="$1" keep_memory="$2" id
  $DELETE_MODE || PREVIEWED+=("$project")
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
  # Without --include-memory a non-empty memory/ folder is kept – only the sessions around it go.
  if $keep_memory && has_memory "$project"; then
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

# Scans all project folders and deletes (or previews) the deletable ones.
# With FILTER=true only folders listed in APPROVED are touched, so confirming a
# preview never deletes a folder that only became deletable after the preview.
FILTER=false
APPROVED=""
PREVIEWED=()
shopt -s nullglob
scan() {
  ORPHANED=0
  EMPTY=0
  MEMORY_ONLY=0
  REVIEW=0
  REVIEW_LINES=()

  for project in "$PROJECTS_DIR"/*/; do
    project="${project%/}"
    if $FILTER && ! grep -qxF -- "$project" <<< "$APPROVED"; then
      continue
    fi
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
        delete_project "$project" false
        continue
      fi

      contents="$(cd "$project" && find . -type f ! -name .DS_Store | sed 's|^\./||' | head -3 | tr '\n' ' ')"
      other_files="$(find "$project" -type f ! -name .DS_Store ! -path "$project/memory/*" -print -quit)"

      if [[ -n "$other_files" ]]; then
        REVIEW=$((REVIEW + 1))
        REVIEW_LINES+=("$name  (no sessions, contains: $contents)")
        continue
      fi

      # Names longer than 200 characters are shortened by Claude Code and can never
      # match an encoded path, so the file system search would be pointless.
      if [[ ${#name} -gt 200 ]]; then
        REVIEW=$((REVIEW + 1))
        REVIEW_LINES+=("$name  (memory only, project path cannot be verified)")
        continue
      fi
      # Memory-only folder: if the project still exists somewhere on disk, it is active – skip it
      find_existing_path "$name" >/dev/null && continue
      if [[ "$name" == -Volumes-* ]]; then
        REVIEW=$((REVIEW + 1))
        REVIEW_LINES+=("$name  (memory only, project path cannot be verified)")
        continue
      fi
      if ! $INCLUDE_MEMORY; then
        REVIEW=$((REVIEW + 1))
        REVIEW_LINES+=("$name  (memory only, no existing project found – use --include-memory; contains: $contents)")
        continue
      fi

      MEMORY_ONLY=$((MEMORY_ONLY + 1))
      if $DELETE_MODE; then
        echo "Memory-only folder: $name"
      else
        echo "[DRY-RUN] Would delete memory-only folder: $name"
        (cd "$project" && find . -type f ! -name .DS_Store | sed 's|^\./|           · |')
      fi
      delete_project "$project" false
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

    if has_live_session "$project"; then
      REVIEW=$((REVIEW + 1))
      REVIEW_LINES+=("$name  (a session is still running – close it first: $matching_cwd)")
      continue
    fi

    ORPHANED=$((ORPHANED + 1))
    size="$(du -sh "$project" | cut -f1 | tr -d ' ')"
    if $DELETE_MODE; then
      echo "Orphaned project: $matching_cwd ($size, ${#sessions[@]} session(s))"
    else
      echo "[DRY-RUN] Would delete orphaned project: $matching_cwd ($size, ${#sessions[@]} session(s))"
    fi
    if $INCLUDE_MEMORY; then
      delete_project "$project" false
    else
      delete_project "$project" true
    fi
  done

  if [[ $REVIEW -gt 0 ]]; then
    echo ""
    echo "Not deleted – please review manually:"
    for line in "${REVIEW_LINES[@]}"; do
      echo "  $line"
    done
  fi

  TOTAL=$((ORPHANED + EMPTY + MEMORY_ONLY))
  echo ""
  if $INCLUDE_MEMORY; then
    echo "$ORPHANED orphaned project(s), $EMPTY empty folder(s), $MEMORY_ONLY memory-only folder(s), $REVIEW for manual review."
  else
    echo "$ORPHANED orphaned project(s), $EMPTY empty folder(s), $REVIEW for manual review."
  fi
}

scan

if $DELETE_MODE; then
  echo "Done."
elif [[ $TOTAL -gt 0 ]]; then
  echo ""
  if $INCLUDE_MEMORY; then
    echo "WARNING: --include-memory is set – stored memories will be deleted as well."
  fi
  read -r -p "Permanently delete $TOTAL project folder(s)? [y/N] " confirm
  if [[ "$confirm" =~ ^[yY]$ ]]; then
    # Delete exactly the previewed folders. Every check (path gone, running
    # sessions, …) is repeated, so a folder that changed in the meantime is skipped.
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
  echo "Nothing to delete."
fi
