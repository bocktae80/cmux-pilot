#!/bin/zsh
# cmux-helpers.sh — cmux 시나리오용 공통 헬퍼
# source this file: source "$(dirname "$0")/../lib/cmux-helpers.sh"

set -euo pipefail

# ============================================================
# Workspace
# ============================================================

# 워크스페이스 생성 -> UUID 반환
cmux_new_workspace() {
  local cmd="${1:-zsh}"
  local raw
  raw=$(cmux new-workspace --command "$cmd" 2>&1)
  echo "$raw" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
}

# 워크스페이스 생성 + 이름 지정 -> UUID 반환
cmux_named_workspace() {
  local name=$1 cmd="${2:-zsh}"
  local uuid
  uuid=$(cmux_new_workspace "$cmd")
  cmux rename-workspace --workspace "$uuid" "$name" >/dev/null 2>&1
  echo "$uuid"
}

# 워크스페이스 정리 (에러 무시)
cmux_close_workspace() {
  local ws=$1
  cmux close-workspace --workspace "$ws" >/dev/null 2>&1 || true
}

# ============================================================
# Browser
# ============================================================

# 브라우저 열기 -> surface ref 반환 (surface:N)
cmux_browser_open() {
  local url="${1:-about:blank}"
  local raw
  raw=$(cmux browser open "$url" 2>&1)
  echo "$raw" | grep -o 'surface:[0-9]*'
}

# 브라우저 surface 닫기 (에러 무시)
cmux_browser_close() {
  local surf=$1
  cmux close-surface --surface "$surf" >/dev/null 2>&1 || true
}

# 브라우저 이동 + 대기
cmux_browser_goto() {
  local surf=$1 url=$2 timeout="${3:-10000}"
  cmux browser --surface "$surf" goto "$url" >/dev/null 2>&1
  cmux browser --surface "$surf" wait --load-state complete --timeout-ms "$timeout" >/dev/null 2>&1
}

# 브라우저 JS 실행 -> 결과 반환
# 주의: cmux browser eval은 DOM 조회 전용으로 사용. 외부 입력을 전달하지 않는다.
cmux_browser_js() {
  local surf=$1 js=$2
  cmux browser --surface "$surf" eval "$js" 2>/dev/null
}

# 브라우저 스크린샷
cmux_browser_screenshot() {
  local surf=$1 path=$2
  cmux browser --surface "$surf" snapshot --path "$path" >/dev/null 2>&1
}

# ============================================================
# Sidebar
# ============================================================

# 상태 설정 (color 선택)
cmux_status() {
  local key=$1 value=$2 color="${3:-}"
  if [[ -n "$color" ]]; then
    cmux set-status "$key" "$value" --color "$color" >/dev/null 2>&1
  else
    cmux set-status "$key" "$value" >/dev/null 2>&1
  fi
}

# 워크스페이스별 상태 설정
cmux_ws_status() {
  local ws=$1 key=$2 value=$3 color="${4:-}"
  if [[ -n "$color" ]]; then
    cmux set-status "$key" "$value" --color "$color" --workspace "$ws" >/dev/null 2>&1
  else
    cmux set-status "$key" "$value" --workspace "$ws" >/dev/null 2>&1
  fi
}

# 진행률
cmux_progress() {
  local pct=$1 label="${2:-}"
  if [[ -n "$label" ]]; then
    cmux set-progress "$pct" --label "$label" >/dev/null 2>&1
  else
    cmux set-progress "$pct" >/dev/null 2>&1
  fi
}

# 로그
cmux_log() {
  local level=$1 source=$2 msg=$3
  cmux log --level "$level" --source "$source" "$msg" >/dev/null 2>&1
}

# 알림
cmux_notify() {
  local title=$1 body="${2:-}"
  if [[ -n "$body" ]]; then
    cmux notify --title "$title" --body "$body" >/dev/null 2>&1
  else
    cmux notify --title "$title" >/dev/null 2>&1
  fi
}

# 정리
cmux_clear_sidebar() {
  cmux clear-progress >/dev/null 2>&1 || true
}

cmux_clear_status() {
  local key=$1
  cmux clear-status "$key" >/dev/null 2>&1 || true
}

# ============================================================
# Sync
# ============================================================

# 시그널 발신
cmux_signal() {
  local name=$1
  cmux wait-for -S "$name" >/dev/null 2>&1
}

# 시그널 대기 (타임아웃 초)
cmux_wait_signal() {
  local name=$1 timeout="${2:-60}"
  cmux wait-for "$name" --timeout "$timeout" >/dev/null 2>&1
}

# ============================================================
# Data Sharing (워크스페이스 간 데이터 공유)
# ============================================================
# cmux buffer는 클립보드 (paste = 터미널에 타이핑). 내용 읽기 불가.
# 대신 임시 파일로 데이터 공유.

CMUX_DATA_DIR="/tmp/cmux-lab-data"
mkdir -p "$CMUX_DATA_DIR" 2>/dev/null || true

cmux_data_set() {
  local key=$1 value=$2
  echo "$value" > "$CMUX_DATA_DIR/$key"
}

cmux_data_get() {
  local key=$1
  cat "$CMUX_DATA_DIR/$key" 2>/dev/null
}

cmux_data_clear() {
  rm -rf "$CMUX_DATA_DIR" 2>/dev/null || true
}

# ============================================================
# Colors
# ============================================================

COLOR_GREEN="#22c55e"
COLOR_RED="#ef4444"
COLOR_YELLOW="#f59e0b"
COLOR_BLUE="#3b82f6"
COLOR_PURPLE="#8b5cf6"
COLOR_GRAY="#94a3b8"

# ============================================================
# Cleanup trap
# ============================================================

# 사용법: CLEANUP_RESOURCES=("workspace:5" "surface:8")
#         trap cleanup EXIT
CLEANUP_RESOURCES=()

cleanup() {
  for res in "${CLEANUP_RESOURCES[@]}"; do
    case "$res" in
      workspace:*|[0-9A-F]*)
        cmux_close_workspace "$res" ;;
      surface:*)
        cmux_browser_close "$res" ;;
    esac
  done
  cmux_clear_sidebar
}
