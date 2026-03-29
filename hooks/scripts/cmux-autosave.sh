#!/bin/bash
# cmux-autosave.sh — UserPromptSubmit hook: 워크스페이스 + 세션 자동 동기화
#
# 동작:
#   1. 호출자 워크스페이스의 cwd/workspace_id를 sidebar-state로 실시간 반영
#   2. list-workspaces로 삭제된 워크스페이스 감지 → 제거
#   3. session-map에서 최신 세션 매칭
#   4. session_active heartbeat 기록
#
# cmux 호출: list-workspaces (1회) + sidebar-state (호출자 1회) = 2회, ~1초
#
# 트리거 조건 (OR):
#   1. session-map.jsonl이 마지막 저장 이후 변경됨
#   2. 마지막 저장 후 15분 경과

export PATH="/Applications/cmux.app/Contents/Resources/bin:${PATH}"

CONFIG_DIR="${HOME}/.config/cmux-pilot"
SAVE_FILE="${CONFIG_DIR}/workspaces.json"
SESSION_MAP="${CONFIG_DIR}/session-map.jsonl"
LOG_FILE="${CONFIG_DIR}/autosave.log"

FORCE_INTERVAL=900  # 15분

# 빠른 종료
[[ ! -S /tmp/cmux.sock ]] && exit 0
[[ -L /tmp/cmux.sock ]] && exit 0

# --- session_active heartbeat 기록 (항상, 트리거 무관, python 없이 printf로) ---
if [[ -n "${CMUX_WORKSPACE_ID:-}" && -n "${CMUX_SURFACE_ID:-}" ]]; then
  ts=$(date '+%Y-%m-%dT%H:%M:%S+09:00')
  printf '{"type":"session_active","workspace_id":"%s","surface_id":"%s","session_id":"%s","timestamp":"%s"}\n' \
    "$CMUX_WORKSPACE_ID" "$CMUX_SURFACE_ID" "${CLAUDE_SESSION_ID:-}" "$ts" >> "$SESSION_MAP" 2>/dev/null || true

  # session-map 로테이션 (파일 크기 ~300KB ≈ 1000줄 초과 시 tail로 정리)
  if [[ -f "$SESSION_MAP" ]]; then
    map_size=$(stat -f '%z' "$SESSION_MAP" 2>/dev/null || echo 0)
    if (( map_size > 300000 )); then
      tail -500 "$SESSION_MAP" > "${SESSION_MAP}.tmp" && mv -f "${SESSION_MAP}.tmp" "$SESSION_MAP" 2>/dev/null || true
    fi
  fi
fi

# --- 트리거 판단 (파일 stat만) ---
should_save=false
reason=""

if [[ -f "$SESSION_MAP" ]]; then
  if [[ ! -f "$SAVE_FILE" ]] || [[ "$SESSION_MAP" -nt "$SAVE_FILE" ]]; then
    should_save=true
    reason="session-map 변경"
  fi
fi

if [[ "$should_save" == false ]]; then
  if [[ ! -f "$SAVE_FILE" ]]; then
    should_save=true
    reason="첫 저장"
  else
    last_save_epoch=$(stat -f '%m' "$SAVE_FILE" 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    elapsed=$(( now_epoch - last_save_epoch ))
    if (( elapsed >= FORCE_INTERVAL )); then
      should_save=true
      reason="주기 저장 (${elapsed}초 경과)"
    fi
  fi
fi

[[ "$should_save" == false ]] && exit 0

# --- 동기화 ---
mkdir -p "$CONFIG_DIR"

# cmux 호출 1: list-workspaces (전체 목록)
ws_raw=$(cmux list-workspaces 2>/dev/null) || true
if [[ -z "$ws_raw" || "$ws_raw" == "No workspaces" ]]; then
  exit 0
fi

# cmux 호출 2: sidebar-state (호출자 워크스페이스만 — cwd + workspace_id 추출)
caller_sidebar=""
caller_ws_id="${CMUX_WORKSPACE_ID:-}"
if [[ -n "$caller_ws_id" ]]; then
  caller_ref=$(cmux identify 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('caller', {}).get('workspace_ref', ''))
except:
    print('')
" 2>/dev/null) || true
  if [[ -n "$caller_ref" ]]; then
    caller_sidebar=$(cmux sidebar-state --workspace "$caller_ref" 2>/dev/null) || true
  fi
fi

ws_count=$(python3 -c "
import json, os, re, sys, subprocess
from datetime import datetime, timezone, timedelta

ws_raw = sys.argv[1]
save_path = sys.argv[2]
caller_ws_id = sys.argv[3]
caller_sidebar = sys.argv[4]
session_map_path = os.path.expanduser('~/.config/cmux-pilot/session-map.jsonl')

# --- 호출자 workspace cwd 파싱 ---
caller_cwd = ''
caller_ws_uuid = ''
for sline in caller_sidebar.split('\n'):
    if sline.startswith('cwd='):
        caller_cwd = sline[4:]
    if sline.startswith('tab='):
        caller_ws_uuid = sline[4:]

# --- session-map 로딩 ---
session_map_by_ws = {}           # workspace_id → [entries]
session_map_name_to_wid = {}     # workspace_name → workspace_id (최신)
last_active_by_session = {}      # session_id → latest timestamp

if os.path.isfile(session_map_path):
    with open(session_map_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                etype = entry.get('type', 'session_start')
                wid = entry.get('workspace_id', '')
                wname = entry.get('workspace_name', '')
                sid = entry.get('session_id', '')
                ts = entry.get('timestamp', '')

                if etype == 'session_active':
                    if sid and ts:
                        if sid not in last_active_by_session or ts > last_active_by_session[sid]:
                            last_active_by_session[sid] = ts
                else:
                    # session_start or legacy (no type)
                    if wid and sid:
                        session_map_by_ws.setdefault(wid, []).append(entry)
                    if wid and wname:
                        session_map_name_to_wid[wname] = wid
            except:
                continue

# --- 기존 저장 파일 로딩 ---
existing_by_id = {}    # workspace_id → ws_data
existing_by_name = {}  # name → ws_data
if os.path.isfile(save_path):
    try:
        with open(save_path) as f:
            old = json.load(f)
        for ws in old.get('workspaces', []):
            wid = ws.get('workspace_id', '')
            wname = ws.get('name', '')
            if wid:
                existing_by_id[wid] = ws
            if wname:
                existing_by_name[wname] = ws
    except:
        pass

# --- 현재 워크스페이스 순회 (삭제된 것은 자연 제거) ---
workspaces = []
for line in ws_raw.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    ref_match = re.search(r'(workspace:\d+)\s+(\S+)', line)
    if not ref_match:
        continue
    ref = ref_match.group(1)
    name = ref_match.group(2)
    if name.startswith('['):
        continue

    ws_data = {'name': name, 'ref': ref}

    # --- 기존 데이터 병합 (workspace_id 우선, 이름 fallback) ---
    matched = None

    # 1) 호출자 워크스페이스는 실시간 cwd 반영
    if caller_ws_id and caller_ws_uuid:
        # 기존 데이터에서 workspace_id 매칭 시도
        if caller_ws_uuid in existing_by_id and existing_by_id[caller_ws_uuid].get('name') == name:
            matched = existing_by_id[caller_ws_uuid]
            matched['cwd'] = caller_cwd  # 실시간 cwd

    # 2) workspace_id로 기존 데이터 매칭
    if not matched:
        for wid, old_ws in existing_by_id.items():
            if old_ws.get('name') == name:
                matched = old_ws
                break

    # 3) 이름으로 기존 데이터 매칭 (fallback)
    if not matched and name in existing_by_name:
        matched = existing_by_name[name]

    if matched:
        ws_data['cwd'] = matched.get('cwd', '')
        ws_data['status'] = matched.get('status', [])
        ws_data['panels'] = matched.get('panels', [{'type': 'terminal', 'focused': True}])
        ws_data['workspace_id'] = matched.get('workspace_id', '')
    else:
        ws_data['cwd'] = ''
        ws_data['panels'] = [{'type': 'terminal', 'focused': True}]
        # 호출자 워크스페이스인데 기존 데이터 없는 경우 직접 반영
        if caller_ws_id and caller_ws_uuid:
            ws_data['cwd'] = caller_cwd
            ws_data['workspace_id'] = caller_ws_uuid

    # --- session-map에서 세션 매칭 ---
    ws_id = ws_data.get('workspace_id', '')
    # workspace_id로 매칭 안 되면 이름 역조회 (cmux 재시작 후 UUID가 바뀌는 경우)
    map_ws_id = ws_id
    if not map_ws_id or map_ws_id not in session_map_by_ws:
        if name in session_map_name_to_wid:
            map_ws_id = session_map_name_to_wid[name]

    claude_sessions = []
    if map_ws_id and map_ws_id in session_map_by_ws:
        surface_latest = {}
        for entry in session_map_by_ws[map_ws_id]:
            sid = entry.get('surface_id', '')
            session_id = entry.get('session_id', '')
            if sid and session_id:  # session_id null인 것 제외
                if sid not in surface_latest or entry.get('timestamp', '') > surface_latest[sid].get('timestamp', ''):
                    surface_latest[sid] = entry
        for sid, entry in surface_latest.items():
            session_id = entry.get('session_id', '')
            if session_id:
                last_active = last_active_by_session.get(session_id, entry.get('timestamp', ''))
                claude_sessions.append({
                    'session_id': session_id,
                    'surface_id': sid,
                    'resume_cmd': f'claude --resume {session_id}',
                    'last_active': last_active
                })

    if claude_sessions:
        ws_data['claude_sessions'] = claude_sessions
        ws_data['claude_session'] = claude_sessions[0]

    workspaces.append(ws_data)

kst = timezone(timedelta(hours=9))
result = {
    'version': 2,
    'saved_at': datetime.now(kst).isoformat(),
    'workspaces': workspaces
}

with open(save_path, 'w') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)

print(f'{len(workspaces)}')
" "$ws_raw" "$SAVE_FILE" "$caller_ws_id" "$caller_sidebar" 2>/dev/null)

# 로그 기록 + 사용자 메시지
if [[ -f "$SAVE_FILE" ]]; then
  save_epoch=$(stat -f '%m' "$SAVE_FILE" 2>/dev/null || echo 0)
  check_epoch=$(date +%s)
  diff=$(( check_epoch - save_epoch ))
  if (( diff <= 5 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] autosave: ${reason}" >> "$LOG_FILE"
    echo "cmux 워크스페이스 동기화 완료 (${ws_count:-?}개, ${reason})"
  fi
fi

exit 0
