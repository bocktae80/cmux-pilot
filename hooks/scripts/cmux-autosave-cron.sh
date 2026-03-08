#!/bin/bash
# cmux-autosave-cron.sh — cron 등록/해제 관리
# 사용: cmux-autosave-cron.sh install | uninstall | status

set -euo pipefail

AUTOSAVE_SCRIPT="/Users/kent/Work/cmux-pilot/hooks/scripts/cmux-autosave.sh"
CRON_ENTRY="*/15 * * * * $AUTOSAVE_SCRIPT"
CRON_MARKER="# cmux-pilot-autosave"

case "${1:-status}" in
  install)
    # 기존 항목 제거 후 추가
    ( (crontab -l 2>/dev/null || true) | grep -v "$CRON_MARKER" || true ; echo "$CRON_ENTRY $CRON_MARKER") | crontab -
    echo "cron 등록 완료: 15분마다 자동 저장 (변경 시에만)"
    echo "  스크립트: $AUTOSAVE_SCRIPT"
    ;;
  uninstall)
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" | crontab -
    echo "cron 해제 완료"
    ;;
  status)
    if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
      echo "autosave cron: 활성"
      crontab -l 2>/dev/null | grep "$CRON_MARKER"
    else
      echo "autosave cron: 비활성"
      echo "  등록: $0 install"
    fi
    ;;
  *)
    echo "사용법: $0 [install|uninstall|status]"
    ;;
esac
