# cmux-pilot

[한국어](./CLAUDE.md) | English

> cmux Claude Code plugin — unified management for workspaces + Claude Code sessions

## Installation

```bash
claude install-plugin https://github.com/bocktae80/cmux-pilot.git
```

After installation, restart Claude Code and the hooks will run automatically.
Updates are handled once per day on `SessionStart` with an automatic `git pull`.

---

## User Guide

### Daily workflow (nothing required)

Once the plugin is installed, the following runs **automatically**:

| Event | Automatic behavior | Data |
|--------|----------|--------|
| Claude Code session start | Record workspace-session mapping | session-map.jsonl |
| Prompt submission | Synchronize workspace state + record heartbeat | workspaces.json |
| Claude Code response complete | Record a session-active heartbeat | session-map.jsonl |
| Check for plugin updates | `git pull` (once per day) | - |

### Manual commands

| Command | Purpose | When to use |
|--------|------|-----------|
| `/cmux-ws` | List workspaces | Check the current state |
| `/cmux-ws new` | Create a new workspace | Add a project |
| `/cmux-ws save` | Full save (detailed snapshot of all workspaces) | Save manually at an important point |
| `/cmux-ws resume` | Batch-restore Claude Code sessions | After restarting your computer |
| `/cmux-ws resume --dry-run` | Preview resume | Check matches before restoring |
| `/cmux-ws resume --force` | Force-restore expired sessions too | Restore older sessions |
| `/cmux-ws restart` | Exit all sessions -> resume them again | After a plugin update |

### Restore after restarting your computer

```
1. Launch the cmux app (cmux restores workspaces automatically)
2. Start Claude Code from any workspace
3. Run /cmux-ws resume
-> Previous Claude Code sessions for all workspaces are restored automatically
```

---

## Data Structure

### Storage location

```
~/.config/cmux-pilot/
├── session-map.jsonl      # Session mapping history (append-only, auto-rotated)
├── workspaces.json        # Workspace snapshots (autosave + manual save)
├── .last-update-check     # Timestamp of the last automatic update check
├── .pre-update-head       # Commit before update (for update notifications)
├── hook-debug.log         # SessionStart hook debug log (latest 50 lines)
└── autosave.log           # Autosave execution history
```

### session-map.jsonl — session history

```jsonl
{"type":"session_start","surface_id":"...","workspace_id":"...","workspace_name":"cpf","session_id":"abc123","cwd":"/path","timestamp":"..."}
{"type":"session_active","workspace_id":"...","surface_id":"...","session_id":"abc123","timestamp":"..."}
{"type":"workspace_restored","old_workspace_id":"...","new_workspace_id":"...","workspace_name":"cpf","timestamp":"..."}
```

- **session_start**: Recorded when a Claude Code session starts
- **session_active**: Heartbeat on Stop/UserPromptSubmit (used to estimate session termination)
- **workspace_restored**: old -> new UUID mapping during restore
- Auto-rotation: when the file exceeds about 300 KB, keep only the latest 500 lines

### workspaces.json — workspace snapshot

```json
{
  "version": 2,
  "saved_at": "2026-03-29T...",
  "workspaces": [
    {
      "name": "cpf",
      "cwd": "/Users/kent/Work/camfit/camfit-cpf",
      "workspace_id": "UUID",
      "status": [{"key": "project", "value": "cpf", "color": "#3b82f6"}],
      "panels": [{"type": "terminal", "focused": true}],
      "claude_sessions": [
        {"session_id": "abc123", "surface_id": "UUID", "resume_cmd": "claude --resume abc123", "last_active": "..."}
      ]
    }
  ]
}
```

---

## Technical Details

### Hook behavior

| Hook | Script | Timeout | Behavior |
|----|----------|---------|------|
| SessionStart | cmux-session-init.sh | 5 seconds | Check for automatic updates + detect the cmux environment + record the session mapping |
| UserPromptSubmit | cmux-autosave.sh | 5 seconds | Record heartbeat + synchronize workspaces (including caller cwd) |
| PreToolUse | cmux-sidebar-status.sh | 3 seconds | Show active work in the sidebar |
| Stop | cmux-sidebar-status.sh | 3 seconds | Set sidebar status to "Needs input" + record heartbeat |

### Session matching priority

1. **workspace_id (UUID)**: exact match from session-map
2. **Reverse lookup by name**: find the UUID from `workspace_name` in session-map
3. **cwd + name search**: search Claude Code conversation files using the workspace name
4. **Latest fallback**: use the most recent session file under the cwd

### Resume freshness validation

| Condition | Classification | Behavior |
|------|------|------|
| `last_active < 1 hour` | fresh | Resume immediately |
| `last_active < 24 hours` | stale | Attempt resume |
| `last_active > 24 hours` | expired | Skip (`--force` overrides) |
| No `last_active` value | unknown | Attempt resume |

### Automatic updates

- Run `git fetch + pull --ff-only` once per day from SessionStart (in the background)
- Show a notification on the next session after an update
- If there are local modifications, `ff-only` fails and the update is skipped safely

### Autosave trigger conditions (OR)

1. `session-map.jsonl` changed since the last save
2. 15 minutes have passed since the last save
3. `workspaces.json` does not exist (first save)

autosave performs 2 cmux calls:
- `cmux list-workspaces` (all workspaces)
- `cmux sidebar-state` (caller workspace only)

---

## Project Structure

```
cmux-pilot/
├── .claude-plugin/
│   └── plugin.json                # Plugin manifest
├── CLAUDE.md                      # This file
│
├── skills/
│   └── cmux-workspace/
│       └── SKILL.md               # Workspace management skill
│
├── commands/
│   └── cmux-ws.md                 # /cmux-ws command definition
│
├── hooks/
│   ├── hooks.json                 # Hook registration (SessionStart, UserPromptSubmit, PreToolUse, Stop)
│   └── scripts/
│       ├── cmux-session-init.sh   # SessionStart: auto-update + environment detection + session mapping
│       ├── cmux-autosave.sh       # UserPromptSubmit: heartbeat + workspace sync
│       ├── cmux-sidebar-status.sh # PreToolUse/Stop: sidebar status + heartbeat
│       ├── cmux-ws-resume.sh      # Batch session restore (freshness check + shell prompt confirmation)
│       └── cmux-ws-restart.sh     # Exit all sessions -> resume
│
├── lib/
│   ├── cmux-helpers.sh            # cmux API helpers (45 functions)
│   └── cmux-ws-manager.sh         # Core save/new/list logic
│
├── reference/                     # cmux reference docs
├── scenarios/                     # Verified scenarios
└── reports/                       # Execution reports
```

## Development Rules

1. **Commit only runnable code** — record only changes you actually ran
2. **Return-value parsing patterns** — record actual output formats per cmux command in `reference/`
3. **Korean journal** — record findings in `JOURNAL.md`
4. **Standalone scripts** — every `.sh` file must be runnable on its own
5. **Safe Python embedding** — pass shell variables only through `sys.argv` or environment variables (never interpolate directly)
6. **subprocess list arguments** — use `subprocess.run(['cmux', ...])` (avoid `shell=True`)

## cmux Environment

- **Location**: `/Applications/cmux.app/Contents/Resources/bin/cmux`
- **Socket**: `/tmp/cmux.sock`
- **Method count**: 139
- **Main categories**: terminal, browser, sidebar, notification, sync
- **Workspace persistence**: the cmux app saves and restores workspaces on its own (`~/Library/Application Support/cmux/`)
