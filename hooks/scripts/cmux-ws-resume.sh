#!/bin/bash
# cmux-ws-resume.sh — workspaces.json + session-map.jsonl로 Claude Code 세션 일괄 복원
# 용도: cmux 크래시 후 모든 워크스페이스의 Claude Code 세션을 자동으로 resume

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

# Python으로 매칭 + resume 실행
python3 -c "
import subprocess, json, sys, os, time

def run(cmd, timeout=5):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except:
        return ''

def send_keys(surface_ref, text):
    \"\"\"surface에 텍스트 전송 (cmux send-keys)\"\"\"
    subprocess.run(
        f'cmux send-keys --surface {surface_ref} -- {text}',
        shell=True, capture_output=True, text=True, timeout=5
    )

# 저장 파일 로드
with open('$SAVE_FILE') as f:
    saved = json.load(f)

saved_workspaces = saved.get('workspaces', [])
if not saved_workspaces:
    print('복원할 워크스페이스가 없습니다.')
    sys.exit(0)

# 현재 cmux 워크스페이스 목록 (이름:ref 맵)
ws_raw = run('cmux list-workspaces')
current_ws = {}  # name -> ref
if ws_raw:
    import re
    for line in ws_raw.strip().split('\n'):
        line = line.strip()
        ref_match = re.search(r'(workspace:\d+)\s+(\S+)', line)
        if ref_match:
            ref = ref_match.group(1)
            name = ref_match.group(2)
            if not name.startswith('['):
                current_ws[name] = ref

print(f'저장된 워크스페이스: {len(saved_workspaces)}개')
print(f'현재 활성 워크스페이스: {len(current_ws)}개')
print()

resumed = 0
failed = 0
skipped = 0

for ws in saved_workspaces:
    name = ws.get('name', 'unnamed')
    cwd = ws.get('cwd', '')
    sessions = ws.get('claude_sessions', [])

    # 하위호환: claude_session (단수)만 있는 경우
    if not sessions and ws.get('claude_session'):
        sessions = [ws['claude_session']]

    if not sessions:
        print(f'  [{name}] 세션 없음 — 건너뜀')
        skipped += 1
        continue

    # 이름으로 현재 워크스페이스 매칭
    ws_ref = current_ws.get(name, '')
    if not ws_ref:
        print(f'  [{name}] 워크스페이스 없음 — 건너뜀 (먼저 /cmux-ws restore 실행)')
        skipped += 1
        continue

    # 해당 워크스페이스의 surface 목록
    panels_raw = run(f'cmux list-panels --workspace {ws_ref}')
    surfaces = []
    if panels_raw:
        import re as re2
        for pline in panels_raw.strip().split('\n'):
            pline = pline.strip()
            if not pline:
                continue
            surf_match = re2.search(r'(surface:\d+)', pline)
            if surf_match and 'terminal' in pline.lower():
                surfaces.append(surf_match.group(1))

    print(f'  [{name}] 세션 {len(sessions)}개, surface {len(surfaces)}개')

    for i, session in enumerate(sessions):
        session_id = session.get('session_id', '')
        resume_cmd = session.get('resume_cmd', f'claude --resume {session_id}')

        if i < len(surfaces):
            # 기존 surface에 resume
            surf_ref = surfaces[i]
        else:
            # surface 부족 → 새로 생성
            new_cmd = f'cmux new-pane --type terminal --workspace {ws_ref}'
            if cwd:
                new_cmd += f\" --command \\\"cd '{cwd}' && zsh\\\"\"
            new_raw = run(new_cmd)
            surf_match = re.search(r'(surface:\d+)', new_raw) if new_raw else None
            if surf_match:
                surf_ref = surf_match.group(1)
                time.sleep(0.5)  # 셸 초기화 대기
            else:
                print(f'    FAIL: surface 생성 실패 (세션 {i+1})')
                failed += 1
                continue

        # Ctrl+C로 현재 실행 중인 것 중단 후 resume 명령 전송
        # Esc 키 전송 (진행 중인 입력 취소)
        run(f'cmux send-keys --surface {surf_ref} -- \"\\x1b\"')
        time.sleep(0.2)
        # Enter로 깨끗한 프롬프트 확보
        run(f'cmux send-keys --surface {surf_ref} -- \"\\n\"')
        time.sleep(0.3)

        # cwd가 다르면 cd 먼저
        if cwd:
            run(f\"cmux send-keys --surface {surf_ref} -- \\\"cd '{cwd}'\\n\\\"\")
            time.sleep(0.3)

        # claude --resume 전송
        run(f'cmux send-keys --surface {surf_ref} -- \"{resume_cmd}\\n\"')
        resumed += 1
        print(f'    OK: {surf_ref} → {resume_cmd}')
        time.sleep(0.5)

print()
print(f'복원 완료: 성공 {resumed}개, 실패 {failed}개, 건너뜀 {skipped}개')
"
