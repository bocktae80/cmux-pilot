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
import subprocess, json, re, sys
from datetime import datetime, timezone, timedelta

def run(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except:
        return ''

raw = '''${raw}'''
workspaces = []

# 워크스페이스 파싱 (UUID + name)
for line in raw.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    # UUID 추출
    uuid_match = re.search(r'([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})', line)
    if not uuid_match:
        continue
    uuid = uuid_match.group(1)
    # 이름은 UUID 이후
    name = line[uuid_match.end():].strip() or uuid[:8]

    # cwd 추출 (sidebar-state)
    sidebar = run(f'cmux sidebar-state --workspace {uuid}')
    cwd_match = re.search(r'cwd[:\s]+(.+)', sidebar)
    cwd = cwd_match.group(1).strip() if cwd_match else ''

    # status 추출
    status_raw = run(f'cmux list-status --workspace {uuid}')
    status_items = []
    for sline in status_raw.split('\n'):
        sline = sline.strip()
        if not sline:
            continue
        # key=value 또는 key: value 패턴
        kv_match = re.search(r'(\w+)[=:\s]+(.+)', sline)
        if kv_match:
            status_items.append({
                'key': kv_match.group(1),
                'value': kv_match.group(2).strip()
            })

    # panels 추출
    panels_raw = run(f'cmux list-panels --workspace {uuid}')
    panels = []
    if panels_raw:
        for pline in panels_raw.split('\n'):
            pline = pline.strip()
            if not pline:
                continue
            if 'browser' in pline.lower():
                url_match = re.search(r'(https?://\S+)', pline)
                panels.append({
                    'type': 'browser',
                    'direction': 'right',
                    'url': url_match.group(1) if url_match else ''
                })
            elif 'terminal' in pline.lower() or 'pane' in pline.lower():
                panels.append({'type': 'terminal', 'focused': True})
    if not panels:
        panels.append({'type': 'terminal', 'focused': True})

    workspaces.append({
        'name': name,
        'cwd': cwd,
        'status': status_items,
        'panels': panels
    })

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
  while IFS=$'\t' read -r name cwd status_json panels_json; do
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
    print(f'{name}\t{cwd}\t{status}\t{panels}')
")

  echo ""
  echo "복원 완료: 성공 ${restored}개, 실패 ${failed}개"
}
