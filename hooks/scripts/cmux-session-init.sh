#!/bin/bash
# cmux-session-init.sh — SessionStart 훅: cmux 환경 감지 + 사이드바 초기화

# cmux 실행 여부 확인
if [[ ! -S /tmp/cmux.sock ]]; then
  exit 0
fi

# cmux 바이너리 확인
if ! command -v cmux &>/dev/null; then
  exit 0
fi

# 현재 워크스페이스 정보 수집
ws_id="${CMUX_WORKSPACE_ID:-}"
ws_info=""

if [[ -n "$ws_id" ]]; then
  ws_name=$(cmux list-workspaces 2>/dev/null | grep "$ws_id" | head -1 | awk '{print $NF}' || echo "unknown")
  ws_info="워크스페이스: ${ws_name} (${ws_id})"
else
  ws_count=$(cmux list-workspaces 2>/dev/null | wc -l | tr -d ' ')
  ws_info="워크스페이스: ${ws_count}개 활성"
fi

# 사이드바에 Claude Code 세션 표시
cmux set-status "claude" "active" --color "#8b5cf6" 2>/dev/null || true

echo "cmux 환경 감지됨. ${ws_info}. /cmux-ws로 워크스페이스를 관리할 수 있습니다."
