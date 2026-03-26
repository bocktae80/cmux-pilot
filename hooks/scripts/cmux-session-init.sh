#!/bin/bash
# cmux-session-init.sh — SessionStart 훅: cmux 환경 감지 + 세션 매핑 기록

CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SESSION_MAP_DIR="${HOME}/.config/cmux-pilot"
DEBUG_LOG="${SESSION_MAP_DIR}/hook-debug.log"
mkdir -p "$SESSION_MAP_DIR"

# --- stdin에서 session_id 추출 ---
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('session_id', '') or data.get('sessionId', ''))
except:
    print('')
" 2>/dev/null)

# 디버그 로그 (최근 50줄 유지)
{
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] stdin=${INPUT:-(empty)} sid=${SESSION_ID:-(empty)} ws=${CMUX_WORKSPACE_ID:-(empty)} sf=${CMUX_SURFACE_ID:-(empty)}"
} >> "$DEBUG_LOG"
tail -50 "$DEBUG_LOG" > "${DEBUG_LOG}.tmp" && mv "${DEBUG_LOG}.tmp" "$DEBUG_LOG"

# --- cmux 실행 여부 확인 ---
[[ ! -S /tmp/cmux.sock ]] && exit 0
[[ ! -x "$CMUX" ]] && exit 0

ws_id="${CMUX_WORKSPACE_ID:-}"
surface_id="${CMUX_SURFACE_ID:-}"

# --- 워크스페이스 이름 추출 ---
resolve_ws_name() {
  local ws_ref
  ws_ref=$("$CMUX" identify 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('caller', {}).get('workspace_ref', ''))
except:
    print('')
" 2>/dev/null)

  [[ -z "$ws_ref" ]] && return 1

  # list-workspaces에서 ref 매칭 후 이름 추출
  # 형식: "  workspace:N  name" 또는 "* workspace:N  name  [selected]"
  "$CMUX" list-workspaces 2>/dev/null | awk -v ref="$ws_ref" '{
    for (i = 1; i <= NF; i++) {
      if ($i == ref) {
        for (j = i + 1; j <= NF; j++) {
          if ($j !~ /^\[/) { print $j; exit }
        }
      }
    }
  }'
}

ws_name=""
ws_info=""
if [[ -n "$ws_id" ]]; then
  ws_name=$(resolve_ws_name 2>/dev/null) || true
  ws_name="${ws_name:-unknown}"
  ws_info="워크스페이스: ${ws_name} (${ws_id})"
else
  ws_count=$("$CMUX" list-workspaces 2>/dev/null | wc -l | tr -d ' ')
  ws_info="워크스페이스: ${ws_count}개 활성"
fi

# --- 세션 매핑 기록 ---
# session_id 없으면 fallback 생성 (복원 시 정확도 떨어지지만 매핑 자체는 유지)
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="no-sid-$(date +%s)"
fi

if [[ -n "$ws_id" && -n "$surface_id" ]]; then
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
" "$surface_id" "$ws_id" "$ws_name" "$SESSION_ID" "$PWD" >> "${SESSION_MAP_DIR}/session-map.jsonl"
fi

echo "cmux 환경 감지됨. ${ws_info}. /cmux-ws로 워크스페이스를 관리할 수 있습니다."
