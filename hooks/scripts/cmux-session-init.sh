#!/bin/bash
# cmux-session-init.sh — SessionStart 훅: cmux 환경 감지 + 세션 매핑 기록

# stdin에서 session_id 추출 (Claude Code가 JSON으로 전달)
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")

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
surface_id="${CMUX_SURFACE_ID:-}"
ws_info=""

if [[ -n "$ws_id" ]]; then
  ws_name=$(cmux list-workspaces 2>/dev/null | grep "$ws_id" | head -1 | awk '{print $NF}' || echo "unknown")
  ws_info="워크스페이스: ${ws_name} (${ws_id})"
else
  ws_count=$(cmux list-workspaces 2>/dev/null | wc -l | tr -d ' ')
  ws_info="워크스페이스: ${ws_count}개 활성"
fi

# 세션 매핑 기록 (workspace_id + surface_id + session_id가 모두 있을 때)
if [[ -n "$ws_id" && -n "$surface_id" && -n "$SESSION_ID" ]]; then
  SESSION_MAP_DIR="${HOME}/.config/cmux-pilot"
  SESSION_MAP_FILE="${SESSION_MAP_DIR}/session-map.jsonl"
  mkdir -p "$SESSION_MAP_DIR"

  # ws_name이 아직 없으면 다시 추출
  if [[ -z "${ws_name:-}" ]]; then
    ws_name=$(cmux list-workspaces 2>/dev/null | grep "$ws_id" | head -1 | awk '{print $NF}' || echo "unknown")
  fi

  # JSONL append (python3로 안전한 JSON 생성)
  python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta
kst = timezone(timedelta(hours=9))
entry = {
    'surface_id': sys.argv[1],
    'workspace_id': sys.argv[2],
    'workspace_name': sys.argv[3],
    'session_id': sys.argv[4],
    'cwd': sys.argv[5],
    'timestamp': datetime.now(kst).isoformat()
}
print(json.dumps(entry, ensure_ascii=False))
" "$surface_id" "$ws_id" "${ws_name:-unknown}" "$SESSION_ID" "$PWD" >> "$SESSION_MAP_FILE"
fi

echo "cmux 환경 감지됨. ${ws_info}. /cmux-ws로 워크스페이스를 관리할 수 있습니다."
