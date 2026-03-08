#!/bin/bash
# cmux-autosave.sh — cron용 자동 저장 (변경 시에만)
# crontab: */15 * * * * /Users/kent/Work/cmux-pilot/hooks/scripts/cmux-autosave.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MANAGER="$SCRIPT_DIR/../../lib/cmux-ws-manager.sh"
CONFIG_DIR="${HOME}/.config/cmux-pilot"
SAVE_FILE="${CONFIG_DIR}/workspaces.json"
HASH_FILE="${CONFIG_DIR}/.last-save-hash"
LOG_FILE="${CONFIG_DIR}/autosave.log"

mkdir -p "$CONFIG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# cmux 실행 중인지 확인
if [[ ! -S /tmp/cmux.sock ]]; then
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
current_hash=$(echo "$current_state" | md5 -q 2>/dev/null || echo "$current_state" | md5sum | cut -d' ' -f1)
if [[ -f "$HASH_FILE" ]]; then
  saved_hash=$(cat "$HASH_FILE")
  if [[ "$current_hash" == "$saved_hash" ]]; then
    exit 0
  fi
fi

# 변경 감지됨 → 저장 실행
source "$MANAGER"
cmux_ws_save "$SAVE_FILE" > /dev/null 2>&1

# 해시 갱신
echo "$current_hash" > "$HASH_FILE"

log "autosave: 변경 감지, 저장 완료"
