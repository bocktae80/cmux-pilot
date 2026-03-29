#!/bin/bash
# cmux-ws-resume.sh — workspaces.json + session-map.jsonl로 Claude Code 세션 일괄 복원
# 용도: cmux 크래시 후 모든 워크스페이스의 Claude Code 세션을 자동으로 resume
#
# 매칭 우선순위: workspace_id → 이름
# 신선도 검증: last_active 기반 (1h: 즉시, 24h: 시도, 24h+: 경고)
# 셸 프롬프트 확인: cmux read-screen으로 상태 확인 후 resume

set -euo pipefail

export PATH="/Applications/cmux.app/Contents/Resources/bin:${PATH}"

CONFIG_DIR="${HOME}/.config/cmux-pilot"
SAVE_FILE="${CONFIG_DIR}/workspaces.json"
SESSION_MAP="${CONFIG_DIR}/session-map.jsonl"

if [[ ! -f "$SAVE_FILE" ]]; then
  echo "ERROR: 저장 파일이 없습니다: $SAVE_FILE"
  echo "먼저 /cmux-ws save 로 저장하세요."
  exit 1
fi

if [[ ! -S /tmp/cmux.sock ]]; then
  echo "ERROR: cmux가 실행 중이 아닙니다."
  exit 1
fi

if ! command -v cmux &>/dev/null; then
  echo "ERROR: cmux 바이너리를 찾을 수 없습니다."
  exit 1
fi

# 옵션 파싱
FORCE=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --dry-run) DRY_RUN=true ;;
  esac
done

python3 -c "
import subprocess, json, sys, os, time, re
from datetime import datetime, timezone, timedelta

def run(cmd, timeout=5):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except:
        return ''

def is_shell_prompt(screen_text):
    \"\"\"화면 내용에서 셸 프롬프트인지 판별\"\"\"
    lines = [l.strip() for l in screen_text.strip().split('\n') if l.strip()]
    if not lines:
        return True  # 빈 화면은 프롬프트로 간주
    last = lines[-1]
    # 셸 프롬프트 패턴: $ or % or > 로 끝나거나, ~ 또는 경로 포함
    if re.search(r'[\$%>]\s*$', last):
        return True
    if 'claude' in last.lower() and ('>' in last or '─' in last):
        return False  # Claude Code UI
    return True

force = '$FORCE' == 'true'
dry_run = '$DRY_RUN' == 'true'

# 저장 파일 로드
with open('$SAVE_FILE') as f:
    saved = json.load(f)

saved_workspaces = saved.get('workspaces', [])
if not saved_workspaces:
    print('복원할 워크스페이스가 없습니다.')
    sys.exit(0)

# session-map에서 last_active 수집
last_active_map = {}  # session_id → latest timestamp
session_map_path = os.path.expanduser('$SESSION_MAP')
if os.path.isfile(session_map_path):
    with open(session_map_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                sid = entry.get('session_id', '')
                ts = entry.get('timestamp', '')
                if sid and ts:
                    if sid not in last_active_map or ts > last_active_map[sid]:
                        last_active_map[sid] = ts
            except:
                continue

# 현재 cmux 워크스페이스 목록
ws_raw = run('cmux list-workspaces')
current_ws_by_name = {}  # name → ref
current_ws_by_id = {}    # workspace_id → ref (sidebar-state로 확인 필요)
if ws_raw:
    for line in ws_raw.strip().split('\n'):
        line = line.strip()
        ref_match = re.search(r'(workspace:\d+)\s+(\S+)', line)
        if ref_match:
            ref = ref_match.group(1)
            name = ref_match.group(2)
            if not name.startswith('['):
                current_ws_by_name[name] = ref

print(f'저장된 워크스페이스: {len(saved_workspaces)}개')
print(f'현재 활성 워크스페이스: {len(current_ws_by_name)}개')
print()

# 신선도 판정
kst = timezone(timedelta(hours=9))
now = datetime.now(kst)

def freshness_check(session_id, last_active_ts):
    \"\"\"세션 신선도 검증: fresh/stale/expired\"\"\"
    if not last_active_ts:
        return 'unknown'
    try:
        la = datetime.fromisoformat(last_active_ts)
        delta = now - la
        hours = delta.total_seconds() / 3600
        if hours < 1:
            return 'fresh'
        elif hours < 24:
            return 'stale'
        else:
            return f'expired ({int(hours)}h ago)'
    except:
        return 'unknown'

resumed = 0
failed = 0
skipped = 0
stale_warned = 0

for ws in saved_workspaces:
    name = ws.get('name', 'unnamed')
    cwd = ws.get('cwd', '')
    ws_id = ws.get('workspace_id', '')
    sessions = ws.get('claude_sessions', [])

    if not sessions and ws.get('claude_session'):
        sessions = [ws['claude_session']]

    if not sessions:
        print(f'  [{name}] 세션 없음 — 건너뜀')
        skipped += 1
        continue

    # 워크스페이스 매칭: 이름 기반 (cmux 재시작 후 workspace_id가 바뀌므로)
    ws_ref = current_ws_by_name.get(name, '')
    if not ws_ref:
        print(f'  [{name}] 워크스페이스 없음 — 건너뜀')
        skipped += 1
        continue

    # surface 목록
    panels_raw = run(f'cmux list-panels --workspace {ws_ref}')
    surfaces = []
    if panels_raw:
        for pline in panels_raw.strip().split('\n'):
            pline = pline.strip()
            if not pline:
                continue
            surf_match = re.search(r'(surface:\d+)', pline)
            if surf_match and 'terminal' in pline.lower():
                surfaces.append(surf_match.group(1))

    print(f'  [{name}] 세션 {len(sessions)}개, surface {len(surfaces)}개')

    for i, session in enumerate(sessions):
        session_id = session.get('session_id', '')
        if not session_id:
            print(f'    SKIP: session_id 없음')
            skipped += 1
            continue

        resume_cmd = session.get('resume_cmd', f'claude --resume {session_id}')
        last_active_ts = session.get('last_active', '') or last_active_map.get(session_id, '')
        freshness = freshness_check(session_id, last_active_ts)

        # 신선도 경고
        if freshness.startswith('expired') and not force:
            print(f'    WARN: {session_id[:12]}... {freshness} — 건너뜀 (--force로 강제)')
            stale_warned += 1
            skipped += 1
            continue

        if freshness == 'stale':
            print(f'    INFO: {session_id[:12]}... stale — resume 시도')

        if dry_run:
            print(f'    DRY: {ws_ref} → {resume_cmd} ({freshness})')
            resumed += 1
            continue

        # surface 확보
        if i < len(surfaces):
            surf_ref = surfaces[i]
        else:
            new_cmd = f'cmux new-pane --type terminal --workspace {ws_ref}'
            if cwd:
                new_cmd += f' --command \"cd \'{cwd}\' && zsh\"'
            new_raw = run(new_cmd)
            surf_match = re.search(r'(surface:\d+)', new_raw) if new_raw else None
            if surf_match:
                surf_ref = surf_match.group(1)
                time.sleep(0.5)
            else:
                print(f'    FAIL: surface 생성 실패')
                failed += 1
                continue

        # 셸 프롬프트 확인
        screen = run(f'cmux read-screen --surface {surf_ref}')
        if not is_shell_prompt(screen):
            print(f'    WARN: {surf_ref} 셸 프롬프트 아님 — Ctrl+C 후 재시도')
            run(f'cmux send-key --surface {surf_ref} C-c')
            time.sleep(0.5)
            run(f'cmux send-keys --surface {surf_ref} -- \"\\n\"')
            time.sleep(0.3)

        # cwd 이동
        if cwd:
            run(f\"cmux send-keys --surface {surf_ref} -- \\\"cd '{cwd}'\\n\\\"\")
            time.sleep(0.3)

        # resume
        run(f'cmux send-keys --surface {surf_ref} -- \"{resume_cmd}\\n\"')
        resumed += 1
        print(f'    OK: {surf_ref} → {resume_cmd} ({freshness})')
        time.sleep(0.5)

print()
print(f'복원 완료: 성공 {resumed}, 실패 {failed}, 건너뜀 {skipped}')
if stale_warned:
    print(f'  만료된 세션 {stale_warned}개 건너뜀 (--force로 강제 resume 가능)')
"
