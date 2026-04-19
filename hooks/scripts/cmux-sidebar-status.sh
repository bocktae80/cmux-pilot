#!/bin/bash
# cmux-sidebar-status.sh — Claude Code 상태를 cmux 네이티브 claude-hook으로 전달
# 훅 이벤트: PreToolUse, Stop
#
# cmux claude-hook 네이티브 상태:
#   session-start → Running (볼트 아이콘, 파란색)
#   stop          → Needs input (벨 아이콘)

export PATH="/Applications/cmux.app/Contents/Resources/bin:${PATH}"

[[ ! -S /tmp/cmux.sock ]] && exit 0

INPUT=$(cat)
HOOK_EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null || echo "")

SESSION_MAP="${HOME}/.config/cmux-pilot/session-map.jsonl"

case "$HOOK_EVENT" in
  PreToolUse)
    echo '{}' | cmux claude-hook session-start >/dev/null 2>&1
    ;;

  Stop)
    echo '{}' | cmux claude-hook stop >/dev/null 2>&1

    # session_active heartbeat
    if [[ -n "${CMUX_WORKSPACE_ID:-}" && -n "${CMUX_SURFACE_ID:-}" ]]; then
      ts=$(date '+%Y-%m-%dT%H:%M:%S+09:00')
      printf '{"type":"session_active","workspace_id":"%s","surface_id":"%s","session_id":"%s","timestamp":"%s"}\n' \
        "$CMUX_WORKSPACE_ID" "$CMUX_SURFACE_ID" "${CLAUDE_SESSION_ID:-}" "$ts" >> "$SESSION_MAP" 2>/dev/null || true
    fi
    ;;
esac

exit 0
