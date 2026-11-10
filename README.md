# Claude Utilities

This project contains utility scripts for managing Claude Code locally.

## Scripts

### `delete-marked-claude-sessions.sh`

Finds and deletes Claude Code conversation sessions that have been marked with the custom title `"TODELETE"`.

**Background:** Claude Code stores conversations as JSONL files under `~/.claude/projects/<project>/<session-uuid>.jsonl`. When a user assigns a custom name to a conversation, it is stored as an entry with `"type":"custom-title"` and `"customTitle":"..."` inside that JSONL file. This script uses that mechanism as a way to mark conversations for deletion from within the Claude Code UI.

**Marking sessions for deletion:** Inside Claude Code, run `/rename TODELETE` in any conversation you want to delete. Then run this script to clean them all up at once.

**Usage:**

```bash
# Dry-run (default) – lists what would be deleted
./delete-marked-claude-sessions.sh

# Actually delete – prompts for confirmation first
./delete-marked-claude-sessions.sh --delete
```

**What gets deleted:**
- The `.jsonl` session file itself
- The matching directory `~/.claude/projects/<project>/<session-uuid>/` if it exists (contains `subagents/`, `tool-results/`, etc.)
- `~/.claude/session-env/<session-uuid>/` if it exists
- `~/.claude/file-history/<session-uuid>/` if it exists

**Notes:**
- Only the **most recent** custom title counts: a session renamed to `TODELETE` and later renamed to something else is kept
- Mentions of `TODELETE` inside conversation content (e.g. quoted JSON) are ignored – only real `custom-title` entries match
- Files whose name is not a session UUID are skipped
- Entries in the prompt history (`~/.claude/history.jsonl`) are left untouched
- Files in `*/subagents/*` are excluded from the search to avoid double-counting
- Deleted files are **not** moved to trash – no recovery possible
- Passing `--delete` directly skips the interactive prompt (safe for scripting/cron)

### `delete-orphaned-claude-projects.sh`

Finds Claude Code project folders under `~/.claude/projects/` whose original project directory no longer exists (e.g. because the project was deleted or moved) and cleans them up.

**How orphans are detected:** The folder name cannot be reliably decoded back into a path, because Claude Code replaces every non-alphanumeric character (`/`, spaces, `_`, umlauts, …) with `-`. Instead, the script reads the `"cwd"` field from the session files, which holds the real original path. A project counts as orphaned only if:
- none of its sessions' `cwd` directories exist anymore, **and**
- re-encoding the `cwd` reproduces the folder name exactly (sanity check)

**Usage:**

```bash
# Dry-run (default) – lists what would be deleted
./delete-orphaned-claude-projects.sh

# Actually delete – prompts for confirmation first
./delete-orphaned-claude-projects.sh --delete
```

**What gets deleted:**
- **Orphaned projects:** the project folder with all sessions, plus `~/.claude/session-env/<session-uuid>/` and `~/.claude/file-history/<session-uuid>/` for each session
- **Empty project folders:** folders containing nothing but `.DS_Store` files or empty directories

**What is never deleted automatically (listed for manual review instead):**
- A non-empty `memory/` folder – in orphaned projects only the sessions around it are removed
- Folders without sessions that still contain other files (typically memories)
- Projects whose path is on an unmounted volume under `/Volumes/`
- Projects whose `cwd` does not match the folder name

**Notes:**
- Entries in `~/.claude.json` and the prompt history (`~/.claude/history.jsonl`) are left untouched
- Deleted files are **not** moved to trash – no recovery possible
- Passing `--delete` directly skips the interactive prompt (safe for scripting/cron)

## Conventions

- All script output, comments, and documentation in **English**
- Scripts live only in this project directory – no copies elsewhere

## Development

Vibe-coded with [Claude Code](https://claude.ai/code), reviewed by a human developer.

## Contact

Marc Kemmer – marc@kemmer.team

## License

MIT
