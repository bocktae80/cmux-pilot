# cmux-pilot

[한국어](./README.md) | English

A Claude Code plugin for integrated management of [cmux](https://cmux.app) workspaces and Claude Code sessions.

When you use Claude Code across multiple cmux workspaces at the same time, it automates session mapping, synchronization, and restore.

## Key Features

- **Automatic session mapping** — Records the workspace-to-session relationship whenever a Claude Code session starts
- **Automatic synchronization** — Automatically saves workspace state (`cwd`, session) on every prompt submission
- **Batch restore** — Resumes Claude Code sessions for all workspaces at once after a computer restart
- **Freshness validation** — Skips old sessions automatically and resumes only after safely checking the shell prompt
- **Automatic updates** — Keeps the plugin up to date with a daily `git pull`

## Installation

```bash
claude install-plugin https://github.com/bocktae80/cmux-pilot.git
```

After installation, restart Claude Code and it will start working automatically.

## Prerequisites

- [cmux](https://cmux.app) installed and running
- Claude Code CLI

## Usage

### Automatic behavior (works immediately after install)

| Event | Behavior |
|--------|------|
| Claude Code session start | Record workspace-session mapping |
| Prompt submission | Synchronize workspace state |
| Claude Code response complete | Record a session-active heartbeat |
| Once per day | Automatically update the plugin |

### Commands

```bash
/cmux-ws              # List workspaces
/cmux-ws new          # Create a new workspace (name, path, color)
/cmux-ws save         # Save full details for all workspaces (full save)
/cmux-ws resume       # Batch-resume Claude Code sessions for all workspaces
/cmux-ws restart      # Exit all sessions -> resume them again (after a plugin update)
```

### After restarting your computer

```
1. Launch the cmux app (cmux restores workspaces automatically)
2. Start Claude Code from any workspace
3. /cmux-ws resume
```

### Resume options

```bash
/cmux-ws resume              # Default: resume only fresh/stale sessions, skip expired ones
/cmux-ws resume --dry-run    # Show matching results without executing
/cmux-ws resume --force      # Force-resume expired sessions too
```

## Data

```
~/.config/cmux-pilot/
├── session-map.jsonl      # Session mapping history (append-only, auto-rotated)
├── workspaces.json        # Workspace snapshots
├── hook-debug.log         # Debug log
└── autosave.log           # Autosave history
```

## How It Works

```
SessionStart hook
  -> Record {workspace_id, surface_id, session_id} in session-map.jsonl

UserPromptSubmit hook
  -> Record a heartbeat + sync workspaces.json (reflect the caller cwd in real time)

Stop hook
  -> Record a heartbeat (track whether the session is still active)

/cmux-ws resume
  -> Match names from workspaces.json -> validate freshness -> check shell prompt -> claude --resume
```

## License

MIT
