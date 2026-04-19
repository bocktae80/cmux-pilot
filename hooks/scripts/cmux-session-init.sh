#!/bin/bash
# cmux-session-init.sh — SessionStart 훅: 자동 업데이트 + cmux 환경 감지 + 세션 매핑 기록

CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SESSION_MAP_DIR="${HOME}/.config/cmux-pilot"
DEBUG_LOG="${SESSION_MAP_DIR}/hook-debug.log"
LAST_UPDATE_CHECK="${SESSION_MAP_DIR}/.last-update-check"
mkdir -p "$SESSION_MAP_DIR"

# --- 플러그인 자동 업데이트 (하루 1번, 백그라운드) ---
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -d "${CLAUDE_PLUGIN_ROOT}/.git" ]]; then
  should_check=false
  if [[ ! -f "$LAST_UPDATE_CHECK" ]]; then
    should_check=true
  else
    last_epoch=$(stat -f '%m' "$LAST_UPDATE_CHECK" 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    if (( now_epoch - last_epoch > 86400 )); then
      should_check=true
    fi
  fi
  if [[ "$should_check" == true ]]; then
    # 현재 커밋 저장 (업데이트 감지용)
    local_head=$(cd "$CLAUDE_PLUGIN_ROOT" && git rev-parse HEAD 2>/dev/null)
    echo "$local_head" > "${SESSION_MAP_DIR}/.pre-update-head" 2>/dev/null || true

    # 백그라운드 업데이트
    (cd "$CLAUDE_PLUGIN_ROOT" && git fetch origin --quiet 2>/dev/null && git pull origin main --ff-only --quiet 2>/dev/null) &
    touch "$LAST_UPDATE_CHECK" 2>/dev/null || true
  fi

  # 이전 세션에서 업데이트가 있었는지 확인
  if [[ -f "${SESSION_MAP_DIR}/.pre-update-head" ]]; then
    old_head=$(cat "${SESSION_MAP_DIR}/.pre-update-head" 2>/dev/null)
    cur_head=$(cd "$CLAUDE_PLUGIN_ROOT" && git rev-parse HEAD 2>/dev/null)
    if [[ -n "$old_head" && -n "$cur_head" && "$old_head" != "$cur_head" ]]; then
      update_msg="cmux-pilot 플러그인이 업데이트되었습니다 ($(cd "$CLAUDE_PLUGIN_ROOT" && git log --oneline -1 2>/dev/null))."
      rm -f "${SESSION_MAP_DIR}/.pre-update-head" 2>/dev/null
    fi
  fi
fi

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

# 디버그 로그 (최근 50줄 유지, 원자적 교체)
echo "[$(date '+%Y-%m-%dT%H:%M:%S')] stdin=${INPUT:-(empty)} sid=${SESSION_ID:-(empty)} ws=${CMUX_WORKSPACE_ID:-(empty)} sf=${CMUX_SURFACE_ID:-(empty)}" >> "$DEBUG_LOG" 2>/dev/null || true
if [[ -f "$DEBUG_LOG" ]] && (( $(wc -l < "$DEBUG_LOG" 2>/dev/null || echo 0) > 60 )); then
  tail -50 "$DEBUG_LOG" > "${DEBUG_LOG}.tmp" 2>/dev/null && mv -f "${DEBUG_LOG}.tmp" "$DEBUG_LOG" 2>/dev/null || true
fi

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
# session_id 없으면 null로 기록 (resume 후보에서 제외됨)
if [[ -n "$ws_id" && -n "$surface_id" ]]; then
  python3 -c "
import json, sys
from datetime import datetime, timezone, timedelta
kst = timezone(timedelta(hours=9))
sid = sys.argv[4] if sys.argv[4] else None
entry = {
    'type': 'session_start',
    'surface_id': sys.argv[1],
    'workspace_id': sys.argv[2],
    'workspace_name': sys.argv[3],
    'session_id': sid,
    'cwd': sys.argv[5],
    'timestamp': datetime.now(kst).isoformat()
}
print(json.dumps(entry, ensure_ascii=False))
" "$surface_id" "$ws_id" "$ws_name" "$SESSION_ID" "$PWD" >> "${SESSION_MAP_DIR}/session-map.jsonl"
fi

# --- 사이드바 상태 초기화 (네이티브 claude-hook) ---
"$CMUX" clear-status "claude" >/dev/null 2>&1 || true
echo '{}' | "$CMUX" claude-hook session-start >/dev/null 2>&1 || true

# --- 출력 ---
output="cmux 환경 감지됨. ${ws_info}. /cmux-ws로 워크스페이스를 관리할 수 있습니다."
[[ -n "${update_msg:-}" ]] && output="${update_msg}\n${output}"
echo -e "$output"
