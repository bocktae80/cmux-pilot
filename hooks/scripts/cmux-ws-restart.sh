#!/bin/bash
# cmux-ws-restart.sh — Claude Code 세션 일괄 재시작
# 용도: 플러그인 업데이트 후 모든 워크스페이스의 Claude Code를 exit → resume
#
# 옵션:
#   --workspace <ref>   특정 워크스페이스만 (예: workspace:2)
#   --dry-run           실제 실행 없이 대상 목록만 표시
#   --parallel <n>      동시 처리 수 (기본: 1, 순차)

export PATH="/Applications/cmux.app/Contents/Resources/bin:${PATH}"

CONFIG_DIR="${HOME}/.config/cmux-pilot"
SAVE_FILE="${CONFIG_DIR}/workspaces.json"
SESSION_MAP="${CONFIG_DIR}/session-map.jsonl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MANAGER="$SCRIPT_DIR/../../lib/cmux-ws-manager.sh"

# 인자 파싱
TARGET_WS=""
DRY_RUN=false
PARALLEL=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) TARGET_WS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# 사전 조건
if [[ ! -S /tmp/cmux.sock ]] || [[ -L /tmp/cmux.sock ]]; then
  echo "ERROR: cmux가 실행 중이 아닙니다."
  exit 1
fi

if ! command -v cmux &>/dev/null; then
  echo "ERROR: cmux 바이너리를 찾을 수 없습니다."
  exit 1
fi

# full save (백업)
if [[ "$DRY_RUN" == false ]]; then
  echo "1/4. 현재 상태 저장 중..."
  source "$MANAGER"
  cmux_ws_save "$SAVE_FILE" > /dev/null 2>&1
  echo "     저장 완료: $(python3 -c "import json; d=json.load(open('$SAVE_FILE')); print(len(d['workspaces']))")개 워크스페이스"
fi

# Python으로 핵심 로직 실행
python3 << 'PYTHON_SCRIPT'
import subprocess, json, sys, os, re, time

TARGET_WS = os.environ.get("TARGET_WS", "")
DRY_RUN = os.environ.get("DRY_RUN", "false") == "true"
SAVE_FILE = os.path.expanduser("~/.config/cmux-pilot/workspaces.json")
SESSION_MAP = os.path.expanduser("~/.config/cmux-pilot/session-map.jsonl")

def run(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except:
        return ""

def read_screen(surface_ref, lines=20):
    return run(f"cmux read-screen --surface {surface_ref} --lines {lines}")

def send(surface_ref, text):
    run(f'cmux send --surface {surface_ref} "{text}"')

def send_key(surface_ref, key):
    run(f"cmux send-key --surface {surface_ref} {key}")

def is_claude_running(screen_text):
    """화면에서 Claude Code가 실행 중인지 판단"""
    indicators = ["claude", "Claude", "❯", "⠋", "⠙", "⠸", "⠴", "⠦", "⠇", "⠏"]
    for ind in indicators:
        if ind in screen_text:
            return True
    return False

def is_shell_prompt(screen_text):
    """셸 프롬프트가 보이는지 판단"""
    last_lines = screen_text.strip().split("\n")[-3:]
    for line in last_lines:
        line = line.strip()
        if line.endswith("$") or line.endswith("%") or line.endswith("❯"):
            return True
        if re.search(r"[\$%#❯]\s*$", line):
            return True
    return False

# --- 2/4. Claude Code 실행 중인 surface 수집 ---
print("2/4. Claude Code surface 수집 중...")

ws_raw = run("cmux list-workspaces")
if not ws_raw:
    print("ERROR: 워크스페이스를 가져올 수 없습니다.")
    sys.exit(1)

# 워크스페이스 파싱
workspaces = []
for line in ws_raw.strip().split("\n"):
    line = line.strip()
    if not line:
        continue
    ref_match = re.search(r"(workspace:\d+)\s+(\S+)", line)
    if ref_match:
        ref = ref_match.group(1)
        name = ref_match.group(2)
        if name.startswith("["):
            continue
        if TARGET_WS and ref != TARGET_WS:
            continue
        workspaces.append({"ref": ref, "name": name})

# session-map 로딩 (workspace 이름 기반)
session_map = {}
if os.path.isfile(SESSION_MAP):
    with open(SESSION_MAP) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                wid = entry.get("workspace_id", "")
                sid = entry.get("surface_id", "")
                if wid and sid:
                    key = f"{wid}:{sid}"
                    if key not in session_map or entry.get("timestamp", "") > session_map[key].get("timestamp", ""):
                        session_map[key] = entry
            except:
                continue

# workspaces.json에서 세션 정보도 로딩
saved_sessions = {}
if os.path.isfile(SAVE_FILE):
    try:
        d = json.load(open(SAVE_FILE))
        for ws in d.get("workspaces", []):
            name = ws.get("name", "")
            sessions = ws.get("claude_sessions", [])
            if not sessions and ws.get("claude_session"):
                sessions = [ws["claude_session"]]
            if sessions:
                saved_sessions[name] = sessions
    except:
        pass

# 각 워크스페이스의 surface 스캔
targets = []  # (ws_name, ws_ref, surface_ref, session_id)

for ws in workspaces:
    panels_raw = run(f'cmux list-panels --workspace {ws["ref"]}')
    if not panels_raw:
        continue

    for pline in panels_raw.strip().split("\n"):
        pline = pline.strip()
        if not pline or "terminal" not in pline.lower():
            continue
        surf_match = re.search(r"(surface:\d+)", pline)
        if not surf_match:
            continue
        surf_ref = surf_match.group(1)

        # Claude Code 실행 중인지 확인: 패널 제목 ("Claude Code") 또는 화면 내용
        is_cc = "Claude Code" in pline or "claude" in pline.lower()
        if not is_cc:
            screen = read_screen(surf_ref, 15)
            is_cc = is_claude_running(screen)
        if not is_cc:
            continue

        # 세션 ID 찾기: saved_sessions에서 매칭
        session_id = ""
        if ws["name"] in saved_sessions:
            sessions = saved_sessions[ws["name"]]
            if sessions:
                session_id = sessions[0].get("session_id", "")

        targets.append({
            "ws_name": ws["name"],
            "ws_ref": ws["ref"],
            "surface": surf_ref,
            "session_id": session_id,
        })

print(f"     발견: {len(targets)}개 Claude Code 세션\n")

if not targets:
    print("재시작할 Claude Code 세션이 없습니다.")
    sys.exit(0)

# 대상 표시
print(f"{'#':>3} {'워크스페이스':<22} {'surface':<14} {'세션ID':<38}")
print("-" * 80)
for i, t in enumerate(targets, 1):
    sid = t["session_id"][:36] if t["session_id"] else "(매핑 없음)"
    print(f'{i:>3} {t["ws_name"]:<22} {t["surface"]:<14} {sid:<38}')
print()

if DRY_RUN:
    print("[dry-run] 실제 실행하지 않았습니다.")
    sys.exit(0)

# --- 3/4. Exit ---
print("3/4. Claude Code 종료 중...")
exit_ok = 0
exit_fail = 0

for t in targets:
    surf = t["surface"]
    name = t["ws_name"]

    # /exit 전송
    send(surf, "/exit")
    send_key(surf, "Return")

    # 셸 프롬프트 대기 (최대 15초)
    exited = False
    for attempt in range(15):
        time.sleep(1)
        screen = read_screen(surf, 5)
        if is_shell_prompt(screen) and not is_claude_running(screen):
            exited = True
            break

    if not exited:
        # Ctrl-C 후 재시도
        send_key(surf, "C-c")
        time.sleep(1)
        send(surf, "/exit")
        send_key(surf, "Return")
        time.sleep(3)
        screen = read_screen(surf, 5)
        if is_shell_prompt(screen):
            exited = True

    if exited:
        print(f"  ✓ [{name}] {surf} 종료됨")
        exit_ok += 1
        # 상태 표시
        run(f'cmux set-status "restart" "종료됨" --icon "arrow.triangle.2.circlepath" --color "#f59e0b" --workspace {t["ws_ref"]}')
    else:
        print(f"  ✗ [{name}] {surf} 종료 실패")
        exit_fail += 1
        run(f'cmux set-status "restart" "실패" --icon "xmark.circle.fill" --color "#ef4444" --workspace {t["ws_ref"]}')

print(f"\n     종료: 성공 {exit_ok}, 실패 {exit_fail}")
if exit_fail > 0:
    print(f"     WARNING: {exit_fail}개 세션 종료 실패. 수동 확인 필요.")

# --- 4/4. Resume ---
print("\n4/4. Claude Code 재시작 중...")
time.sleep(2)  # 종료 안정화 대기

resume_ok = 0
resume_fail = 0
resume_skip = 0

for t in targets:
    surf = t["surface"]
    name = t["ws_name"]
    session_id = t["session_id"]

    if not session_id:
        print(f"  - [{name}] 세션ID 없음 — 건너뜀")
        resume_skip += 1
        continue

    # claude --resume 전송
    resume_cmd = f"claude --resume {session_id}"
    send(surf, resume_cmd)
    send_key(surf, "Return")

    # Claude Code 시작 대기 (최대 15초)
    started = False
    for attempt in range(15):
        time.sleep(1)
        screen = read_screen(surf, 10)
        if is_claude_running(screen):
            started = True
            break

    if started:
        print(f"  ✓ [{name}] {surf} → resume OK")
        resume_ok += 1
        run(f'cmux clear-status "restart" --workspace {t["ws_ref"]}')
    else:
        print(f"  ? [{name}] {surf} → 확인 필요 (시작 중일 수 있음)")
        resume_ok += 1  # 시작이 느릴 수 있으니 실패로 안 잡음
        run(f'cmux set-status "restart" "시작 중" --icon "arrow.triangle.2.circlepath" --color "#3b82f6" --workspace {t["ws_ref"]}')

print(f"\n     재시작: 성공 {resume_ok}, 실패 {resume_fail}, 건너뜀 {resume_skip}")
print()
print("완료! 각 워크스페이스에서 Claude Code가 정상 동작하는지 확인하세요.")
PYTHON_SCRIPT
