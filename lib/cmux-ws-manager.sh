#!/bin/zsh
# cmux-ws-manager.sh — 워크스페이스 save/restore/new/list 핵심 로직
# source this file: source "$(dirname "$0")/../lib/cmux-ws-manager.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/cmux-helpers.sh"

CMUX_PILOT_CONFIG_DIR="${HOME}/.config/cmux-pilot"
CMUX_PILOT_DEFAULT_FILE="${CMUX_PILOT_CONFIG_DIR}/workspaces.json"

# ============================================================
# list — 현재 워크스페이스 목록
# ============================================================
cmux_ws_list() {
  local raw
  raw=$(cmux list-workspaces 2>&1) || {
    echo "ERROR: cmux list-workspaces 실패"
    return 1
  }

  if [[ -z "$raw" || "$raw" == "No workspaces" ]]; then
    echo "열린 워크스페이스가 없습니다."
    return 0
  fi

  echo "$raw"
}

# ============================================================
# new — 새 워크스페이스 생성
# ============================================================
cmux_ws_new() {
  local name="${1:?name 필수}"
  local path="${2:?path 필수}"
  local color="${3:-#3b82f6}"
  local browser_url="${4:-}"

  # 경로 유효성 확인
  if [[ ! -d "$path" ]]; then
    echo "ERROR: 디렉토리가 존재하지 않습니다: $path"
    return 1
  fi

  # 워크스페이스 생성
  local uuid
  uuid=$(cmux_new_workspace "cd '$path' && zsh")
  if [[ -z "$uuid" ]]; then
    echo "ERROR: 워크스페이스 생성 실패"
    return 1
  fi

  # 이름 변경
  cmux rename-workspace --workspace "$uuid" "$name" >/dev/null 2>&1

  # 상태 설정
  cmux set-status "project" "$name" --color "$color" --workspace "$uuid" >/dev/null 2>&1

  # 브라우저 패널 (선택)
  if [[ -n "$browser_url" ]]; then
    cmux new-pane --type browser --direction right --url "$browser_url" --workspace "$uuid" >/dev/null 2>&1
  fi

  echo "워크스페이스 생성 완료: $name ($uuid)"
  echo "  경로: $path"
  echo "  색상: $color"
  [[ -n "$browser_url" ]] && echo "  브라우저: $browser_url"
}

# ============================================================
# save — 전체 워크스페이스를 JSON으로 저장
# ============================================================
cmux_ws_save() {
  local output="${1:-$CMUX_PILOT_DEFAULT_FILE}"
  mkdir -p "$(dirname "$output")"

  local raw
  raw=$(cmux list-workspaces 2>&1) || {
    echo "ERROR: cmux list-workspaces 실패"
    return 1
  }

  if [[ -z "$raw" || "$raw" == "No workspaces" ]]; then
    echo "저장할 워크스페이스가 없습니다."
    return 0
  fi

  # Python으로 JSON 생성 (jq 의존성 없이)
  python3 -c "
import subprocess, json, re, sys, os
from datetime import datetime, timezone, timedelta

def run(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except:
        return ''

raw = '''${raw}'''
workspaces = []

# session-map.jsonl 로딩 (workspace_id별 인덱스)
session_map_by_ws = {}
session_map_path = os.path.expanduser('~/.config/cmux-pilot/session-map.jsonl')
if os.path.isfile(session_map_path):
    with open(session_map_path) as f:
        for map_line in f:
            map_line = map_line.strip()
            if not map_line:
                continue
            try:
                entry = json.loads(map_line)
                wid = entry.get('workspace_id', '')
                if wid:
                    session_map_by_ws.setdefault(wid, []).append(entry)
            except:
                continue

# 워크스페이스 파싱: '* workspace:1  cmux-pilot  [selected]' 또는 '  workspace:59  work'
for line in raw.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    # workspace:N ref 추출
    ref_match = re.search(r'(workspace:\d+)\s+(\S+)', line)
    if not ref_match:
        continue
    ref = ref_match.group(1)
    name = ref_match.group(2)
    # [selected] 등 태그 제거
    if name.startswith('['):
        continue

    # cwd 추출 (sidebar-state)
    sidebar = run(f'cmux sidebar-state --workspace {ref}')
    cwd = ''
    for sline in sidebar.split('\n'):
        if sline.startswith('cwd='):
            cwd = sline[4:]
            break

    # status 추출: 'key=value color=#hex' 형식
    status_raw = run(f'cmux list-status --workspace {ref}')
    status_items = []
    for sline in status_raw.split('\n'):
        sline = sline.strip()
        if not sline:
            continue
        # 'claude=active color=#8b5cf6' 형식 파싱
        color_match = re.search(r'color=(#[0-9a-fA-F]{6})', sline)
        color = color_match.group(1) if color_match else ''
        # color 부분 제거하고 key=value 추출
        kv_part = re.sub(r'\s*color=#[0-9a-fA-F]{6}', '', sline)
        eq_match = re.match(r'(\w[\w-]*)=(.+)', kv_part)
        if eq_match:
            status_items.append({
                'key': eq_match.group(1),
                'value': eq_match.group(2).strip(),
                'color': color
            })

    # panels 추출: '* surface:1  terminal  [focused]  \"title\"'
    panels_raw = run(f'cmux list-panels --workspace {ref}')
    panels = []
    if panels_raw:
        for pline in panels_raw.split('\n'):
            pline = pline.strip()
            if not pline:
                continue
            is_focused = '[focused]' in pline
            if 'browser' in pline.lower():
                url_match = re.search(r'(https?://\S+)', pline)
                panels.append({
                    'type': 'browser',
                    'direction': 'right',
                    'url': url_match.group(1) if url_match else '',
                    'focused': is_focused
                })
            elif 'terminal' in pline.lower():
                panels.append({'type': 'terminal', 'focused': is_focused})
    if not panels:
        panels.append({'type': 'terminal', 'focused': True})

    # workspace UUID 추출 (sidebar-state의 tab= 필드)
    ws_uuid = ''
    for sline in sidebar.split('\n'):
        if sline.startswith('tab='):
            ws_uuid = sline[4:]
            break

    # Claude Code 세션 매칭 (session-map.jsonl 우선, cwd fallback)
    claude_sessions = []
    claude_session = None

    if ws_uuid and ws_uuid in session_map_by_ws:
        # session-map에서 workspace UUID로 매칭 → surface별 최신 세션
        surface_latest = {}
        for entry in session_map_by_ws[ws_uuid]:
            sid = entry.get('surface_id', '')
            if sid:
                if sid not in surface_latest or entry.get('timestamp', '') > surface_latest[sid].get('timestamp', ''):
                    surface_latest[sid] = entry
        for sid, entry in surface_latest.items():
            session_id = entry.get('session_id', '')
            if session_id:
                claude_sessions.append({
                    'session_id': session_id,
                    'surface_id': sid,
                    'resume_cmd': f'claude --resume {session_id}'
                })

    # fallback: cwd 기반 + 워크스페이스 이름으로 대화 내용 유추 매칭
    if not claude_sessions and cwd:
        project_dir = cwd.replace('/', '-')
        claude_projects_path = os.path.expanduser(f'~/.claude/projects/{project_dir}')
        if os.path.isdir(claude_projects_path):
            jsonl_files = [f for f in os.listdir(claude_projects_path) if f.endswith('.jsonl')]
            if jsonl_files:
                # 최신순 정렬
                jsonl_files.sort(
                    key=lambda f: os.path.getmtime(os.path.join(claude_projects_path, f)),
                    reverse=True
                )
                # 워크스페이스 이름으로 대화 내용 검색 (최신순, 첫 매칭 채택)
                matched_session = None
                for jf in jsonl_files:
                    jpath = os.path.join(claude_projects_path, jf)
                    try:
                        with open(jpath, 'r', errors='ignore') as fh:
                            content = fh.read(64 * 1024)  # 앞 64KB만 검색 (hook 출력은 초반에 있음)
                        if name.lower() in content.lower():
                            matched_session = jf.replace('.jsonl', '')
                            break
                    except:
                        continue
                # 매칭된 세션 없으면 최신 파일로 fallback
                session_id = matched_session if matched_session else jsonl_files[0].replace('.jsonl', '')
                claude_sessions.append({
                    'session_id': session_id,
                    'surface_id': '',
                    'resume_cmd': f'claude --resume {session_id}',
                    'match_type': 'name_inferred' if matched_session else 'latest_fallback'
                })

    if claude_sessions:
        claude_session = claude_sessions[0]

    ws_data = {
        'name': name,
        'cwd': cwd,
        'status': status_items,
        'panels': panels
    }
    if ws_uuid:
        ws_data['workspace_id'] = ws_uuid
    if claude_sessions:
        ws_data['claude_sessions'] = claude_sessions
    if claude_session:
        ws_data['claude_session'] = claude_session

    workspaces.append(ws_data)

kst = timezone(timedelta(hours=9))
result = {
    'version': 1,
    'saved_at': datetime.now(kst).isoformat(),
    'workspaces': workspaces
}

json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
" > "$output"

  echo "저장 완료: $output ($(python3 -c "import json; d=json.load(open('$output')); print(len(d.get('workspaces',[])))")개 워크스페이스)"
}

# ============================================================
# restore — JSON에서 워크스페이스 복원
# ============================================================
cmux_ws_restore() {
  local input="${1:-$CMUX_PILOT_DEFAULT_FILE}"

  if [[ ! -f "$input" ]]; then
    echo "ERROR: 저장 파일이 없습니다: $input"
    return 1
  fi

  local count
  count=$(python3 -c "import json; d=json.load(open('$input')); print(len(d.get('workspaces',[])))")

  if [[ "$count" == "0" ]]; then
    echo "복원할 워크스페이스가 없습니다."
    return 0
  fi

  echo "복원 시작: ${count}개 워크스페이스 (${input})"

  local failed=0
  local restored=0

  # Python으로 JSON 읽어서 각 워크스페이스 복원
  while IFS=$'\t' read -r name cwd status_json panels_json sessions_json; do
    echo "  복원 중: $name ($cwd)"

    # 워크스페이스 생성
    local uuid
    if [[ -n "$cwd" && -d "$cwd" ]]; then
      uuid=$(cmux_new_workspace "cd '$cwd' && zsh")
    else
      uuid=$(cmux_new_workspace "zsh")
    fi

    if [[ -z "$uuid" ]]; then
      echo "    FAIL: 워크스페이스 생성 실패"
      ((failed++))
      continue
    fi

    # 이름 변경
    cmux rename-workspace --workspace "$uuid" "$name" >/dev/null 2>&1 || true

    # status 복원
    if [[ -n "$status_json" && "$status_json" != "[]" ]]; then
      python3 -c "
import subprocess, json
items = json.loads('$status_json')
for item in items:
    key = item.get('key','')
    value = item.get('value','')
    color = item.get('color','')
    if key and value:
        cmd = f'cmux set-status \"{key}\" \"{value}\"'
        if color:
            cmd += f' --color \"{color}\"'
        cmd += f' --workspace $uuid'
        subprocess.run(cmd, shell=True, capture_output=True)
" 2>/dev/null || true
    fi

    # panels 복원 (terminal은 이미 생성됨, browser만 추가)
    if [[ -n "$panels_json" && "$panels_json" != "[]" ]]; then
      python3 -c "
import subprocess, json
panels = json.loads('$panels_json')
for panel in panels:
    if panel.get('type') == 'browser' and panel.get('url'):
        direction = panel.get('direction', 'right')
        url = panel['url']
        cmd = f'cmux new-pane --type browser --direction {direction} --url \"{url}\" --workspace $uuid'
        subprocess.run(cmd, shell=True, capture_output=True)
" 2>/dev/null || true
    fi

    # Claude Code 세션 자동 resume (claude_sessions 배열)
    if [[ -n "$sessions_json" && "$sessions_json" != "[]" ]]; then
      python3 -c "
import subprocess, json, time, re

def run(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except:
        return ''

sessions = json.loads('$sessions_json')
uuid = '$uuid'
cwd = '$cwd'

# 현재 워크스페이스의 terminal surface 목록
panels_raw = run(f'cmux list-panels --workspace {uuid}')
surfaces = []
if panels_raw:
    for pline in panels_raw.strip().split('\n'):
        pline = pline.strip()
        surf_match = re.search(r'(surface:\d+)', pline)
        if surf_match and 'terminal' in pline.lower():
            surfaces.append(surf_match.group(1))

for i, session in enumerate(sessions):
    session_id = session.get('session_id', '')
    resume_cmd = session.get('resume_cmd', f'claude --resume {session_id}')

    if i < len(surfaces):
        surf_ref = surfaces[i]
    else:
        # surface 부족 → 새로 생성
        new_cmd = f'cmux new-pane --type terminal --workspace {uuid}'
        if cwd:
            new_cmd += f\" --command \\\"cd '{cwd}' && zsh\\\"\"
        new_raw = run(new_cmd)
        surf_match = re.search(r'(surface:\d+)', new_raw) if new_raw else None
        if surf_match:
            surf_ref = surf_match.group(1)
            time.sleep(0.5)
        else:
            print(f'    FAIL: surface 생성 실패 (세션 {i+1})')
            continue

    # resume 명령 전송
    time.sleep(0.3)
    if cwd:
        run(f\"cmux send-keys --surface {surf_ref} -- \\\"cd '{cwd}'\\n\\\"\")
        time.sleep(0.3)
    run(f'cmux send-keys --surface {surf_ref} -- \"{resume_cmd}\n\"')
    print(f'    resume: {surf_ref} → {resume_cmd}')
    time.sleep(0.5)

    # session-map.jsonl에 새 매핑 기록
    from datetime import datetime, timezone, timedelta
    kst = timezone(timedelta(hours=9))
    # surface UUID 추출 (sidebar-state에서)
    sidebar = run(f'cmux sidebar-state --surface {surf_ref}')
    surface_uuid = ''
    for sline in sidebar.split('\n'):
        if sline.startswith('id='):
            surface_uuid = sline[3:]
            break
    if surface_uuid and session_id:
        import os
        map_path = os.path.expanduser('~/.config/cmux-pilot/session-map.jsonl')
        entry = json.dumps({
            'surface_id': surface_uuid,
            'workspace_id': uuid,
            'workspace_name': '$name',
            'session_id': session_id,
            'cwd': cwd,
            'timestamp': datetime.now(kst).isoformat()
        }, ensure_ascii=False)
        with open(map_path, 'a') as f:
            f.write(entry + '\n')
" 2>/dev/null || true
    fi

    ((restored++))
    echo "    OK: $name ($uuid)"
  done < <(python3 -c "
import json, sys
d = json.load(open('$input'))
for ws in d.get('workspaces', []):
    name = ws.get('name', 'unnamed')
    cwd = ws.get('cwd', '')
    status = json.dumps(ws.get('status', []))
    panels = json.dumps(ws.get('panels', []))
    # claude_sessions (복수) 우선, 없으면 claude_session (단수)를 배열로
    sessions = ws.get('claude_sessions', [])
    if not sessions and ws.get('claude_session'):
        sessions = [ws['claude_session']]
    sessions_json = json.dumps(sessions)
    print(f'{name}\t{cwd}\t{status}\t{panels}\t{sessions_json}')
")

  echo ""
  echo "복원 완료: 성공 ${restored}개, 실패 ${failed}개"
}
