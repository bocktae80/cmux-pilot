#!/bin/bash
# cmux-sidebar-status.sh — Claude Code 작업 상태를 cmux 사이드바에 표시
# 훅 이벤트: PreToolUse, Stop

# cmux 환경 아닐 때 즉시 종료
[[ ! -S /tmp/cmux.sock ]] && exit 0
command -v cmux &>/dev/null || exit 0

# stdin에서 훅 데이터 읽기
INPUT=$(cat)
# hook_event_name은 stdin JSON에서 추출 (CLAUDE_HOOK_EVENT 환경변수는 비어있음)
HOOK_EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null || echo "")

# JSON 필드 추출 헬퍼
json_get() {
  echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null || echo ""
}

# ─── 도구별 상태 메시지 매핑 (간결 모드) ───
tool_status_message() {
  local tool_name="$1"
  case "$tool_name" in
    Read|Glob|Grep)   echo "Reading code" ;;
    Edit|Write)       echo "Editing code" ;;
    Bash)             echo "Running command" ;;
    Agent)            echo "Thinking..." ;;
    WebSearch|WebFetch) echo "Searching web" ;;
    *)                echo "" ;;
  esac
}

# ─── 메인 로직 ───
case "$HOOK_EVENT" in
  PreToolUse)
    tool_name=$(json_get "tool_name")
    tool_input=$(echo "$INPUT" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('tool_input',{})))" 2>/dev/null || echo "{}")

    message=$(tool_status_message "$tool_name" "$tool_input")
    if [[ -n "$message" ]]; then
      cmux set-status claude_code "$message" --color "#3b82f6" >/dev/null 2>&1
    fi
    ;;

  Stop)
    cmux set-status claude_code "Needs input" --icon "bell.fill" --color "#f59e0b" >/dev/null 2>&1

    # session_active heartbeat → session-map.jsonl
    if [[ -n "${CMUX_WORKSPACE_ID:-}" && -n "${CMUX_SURFACE_ID:-}" ]]; then
      python3 -c "
import json, sys, os
from datetime import datetime, timezone, timedelta
kst = timezone(timedelta(hours=9))
entry = {
    'type': 'session_active',
    'workspace_id': sys.argv[1],
    'surface_id': sys.argv[2],
    'session_id': os.environ.get('CLAUDE_SESSION_ID', ''),
    'timestamp': datetime.now(kst).isoformat()
}
print(json.dumps(entry, ensure_ascii=False))
" "$CMUX_WORKSPACE_ID" "$CMUX_SURFACE_ID" >> "${HOME}/.config/cmux-pilot/session-map.jsonl" 2>/dev/null || true
    fi
    ;;
esac

exit 0
