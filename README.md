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

## Built-in alternatives in Claude Code

Claude Code ships its own cleanup mechanisms. The scripts above complement them; they do not replace them.

### Automatic cleanup: `cleanupPeriodDays`

Claude Code automatically deletes sessions older than `cleanupPeriodDays` (default: **30 days**, minimum 1, set in `settings.json`). This includes subagent transcripts, `tool-results/`, `session-env/` and parts of `file-history/`. Memory files are never deleted; an empty `memory/` folder is only removed after staying empty for the whole retention period.

The cleanup is purely **age-based**. It neither deletes individual sessions on demand nor cares whether a project directory still exists.

### Purging a project: `claude purge`

```bash
claude purge <project-path> --dry-run   # preview
claude purge <project-path>             # delete
claude purge                            # interactive project list
```

Deletes all local data of one project: transcripts, `memory/`, `file-history/`, the matching lines in `~/.claude/history.jsonl` and the project entry in `~/.claude.json`.

**Limitation:** if the project directory has already been deleted, `claude purge <old-path>` no longer finds the transcripts. It only removes the `~/.claude.json` entry and the prompt history.

### What is missing (and why these scripts exist)

| Need | Built-in | Script |
|---|---|---|
| Delete a single session right now | – (the `/resume` picker can rename, not delete; `claude rm` only hides background sessions) | `delete-marked-claude-sessions.sh` |
| Clean up projects whose directory is gone | only indirectly after 30 days | `delete-orphaned-claude-projects.sh` |
| Remove an existing project completely | `claude purge <path>` | – |

### Recommended workflow

- **Project still exists:** use `claude purge <path>`.
- **Project directory already deleted:** run `./delete-orphaned-claude-projects.sh` first (removes the transcripts), then `claude purge <old-path>` (removes the `~/.claude.json` entry and the prompt history).
- **Individual sessions:** `/rename TODELETE`, then `./delete-marked-claude-sessions.sh` – or simply wait for the automatic cleanup.

## Conventions

- All script output, comments, and documentation in **English**
- Scripts live only in this project directory – no copies elsewhere

## Development

Vibe-coded with [Claude Code](https://claude.ai/code), reviewed by a human developer.

## Contact

Marc Kemmer – marc@kemmer.team

## License

MIT
