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

## Conventions

- All script output, comments, and documentation in **English**
- Scripts live only in this project directory – no copies elsewhere

## Development

Vibe-coded with [Claude Code](https://claude.ai/code), reviewed by a human developer.

## Contact

Marc Kemmer – marc@kemmer.team

## License

MIT
