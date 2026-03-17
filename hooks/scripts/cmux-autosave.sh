#!/bin/bash
# cmux-autosave.sh — cron용 자동 저장 (변경 시에만)
# crontab: */15 * * * * /Users/kent/Work/cmux-pilot/hooks/scripts/cmux-autosave.sh

set -euo pipefail

# cron 환경에서 cmux 바이너리를 찾기 위한 PATH 보강
export PATH="/Applications/cmux.app/Contents/Resources/bin:${PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MANAGER="$SCRIPT_DIR/../../lib/cmux-ws-manager.sh"
CONFIG_DIR="${HOME}/.config/cmux-pilot"
SAVE_FILE="${CONFIG_DIR}/workspaces.json"
HASH_FILE="${CONFIG_DIR}/.last-save-hash"
LOG_FILE="${CONFIG_DIR}/autosave.log"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

MAX_LOG_SIZE=102400  # 100KB

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
  # 로그 로테이션: 100KB 초과 시 최근 100줄만 유지
  if [[ -f "$LOG_FILE" ]] && (( $(wc -c < "$LOG_FILE") > MAX_LOG_SIZE )); then
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
}

# cmux 실행 중인지 확인 (-L 제외로 심볼릭 링크 공격 방지)
if [[ -L /tmp/cmux.sock || ! -S /tmp/cmux.sock ]]; then
  exit 0
fi

if ! command -v cmux &>/dev/null; then
  exit 0
fi

# 현재 워크스페이스 상태 수집
current_state=$(cmux list-workspaces 2>/dev/null || echo "")
if [[ -z "$current_state" || "$current_state" == "No workspaces" ]]; then
  exit 0
fi

# 해시 비교 — 변경 없으면 스킵
if command -v md5 &>/dev/null; then
  current_hash=$(echo "$current_state" | md5 -q)
else
  current_hash=$(echo "$current_state" | md5sum | cut -d' ' -f1)
fi
if [[ -f "$HASH_FILE" ]]; then
  saved_hash=$(cat "$HASH_FILE")
  if [[ "$current_hash" == "$saved_hash" ]]; then
    exit 0
  fi
fi

# 변경 감지됨 → 저장 실행
source "$MANAGER"
if cmux_ws_save "$SAVE_FILE" > /dev/null 2>&1; then
  echo "$current_hash" > "$HASH_FILE"
  log "autosave: 변경 감지, 저장 완료"
else
  log "autosave: 저장 실패, 다음 주기에 재시도"
  exit 1
fi
