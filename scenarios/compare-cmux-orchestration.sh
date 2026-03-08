#!/bin/zsh
# ============================================================
# 방식 B: cmux 직접 오케스트레이션으로 health.js 생성
# ============================================================
# 3개 워크스페이스에서 각각 claude -p 실행
# 사이드바로 진행 추적 + 결과 수집 + 알림

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/cmux-helpers.sh"

PROJECT_BASE="$SCRIPT_DIR/../mock-projects-cmux"
MARKER="__CMUX_AGENT_DONE__"
START_TIME=$(date +%s)

declare -a WS_LIST=()
trap 'for ws in "${WS_LIST[@]}"; do cmux_close_workspace "$ws"; done; cmux_clear_sidebar' EXIT

cmux_status "method" "cmux orchestration" "$COLOR_PURPLE"
cmux_progress 0.0 "cmux: spawning agents"
cmux_log info "cmux-orch" "=== cmux Orchestration Start ==="

# ============================================================
# Agent 정의
# ============================================================

declare -A AGENTS=(
  [alpha]="mock-projects-cmux/alpha/health.js 파일을 생성해. HTTP 헬스체크 모듈: checkHttp(url) 함수가 Node.js http 모듈로 URL에 GET 요청, {status, latencyMs, ok} 반환. module.exports 내보내기. 코드만 작성."
  [beta]="mock-projects-cmux/beta/health.js 파일을 생성해. DB 헬스체크 모듈: checkDb(connectionString) 함수가 setTimeout으로 지연 시뮬레이션, {status, latencyMs, ok} 반환. module.exports 내보내기. 코드만 작성."
  [gamma]="mock-projects-cmux/gamma/health.js 파일을 생성해. 디스크 헬스체크 모듈: checkDisk(path) 함수가 fs.statfs로 디스크 사용량 확인, {status, usedPct, freeGb, ok} 반환. module.exports 내보내기. 코드만 작성."
)

declare -A AGENT_WS=()
declare -A AGENT_RESULT=()

# ============================================================
# 3개 에이전트 동시 스폰
# ============================================================

for name in alpha beta gamma; do
  prompt="${AGENTS[$name]}"
  ws=$(cmux_named_workspace "cmux-$name" \
    "cd $PROJECT_BASE/$name && unset CLAUDECODE && claude -p '$prompt' --dangerously-skip-permissions 2>&1; echo $MARKER")
  AGENT_WS[$name]="$ws"
  WS_LIST+=("$ws")
  cmux_status "$name" "running..." "$COLOR_BLUE"
  cmux_log info "cmux-orch" "Spawned: $name"
done

cmux_progress 0.2 "cmux: 3 agents running"
cmux_log info "cmux-orch" "All agents spawned. Polling..."

# ============================================================
# 완료 대기
# ============================================================

PENDING=3
MAX_WAIT=180
WAITED=0

while [[ $PENDING -gt 0 ]] && [[ $WAITED -lt $MAX_WAIT ]]; do
  sleep 10
  WAITED=$((WAITED + 10))

  for name in alpha beta gamma; do
    [[ -n "${AGENT_RESULT[$name]:-}" ]] && continue

    # 파일 존재 여부로 완료 감지 (마커보다 안정적)
    if [[ -f "$PROJECT_BASE/$name/health.js" ]]; then
      lines=$(wc -l < "$PROJECT_BASE/$name/health.js" 2>/dev/null || echo 0)
      if [[ $lines -gt 3 ]]; then
        AGENT_RESULT[$name]="PASS"
        cmux_status "$name" "DONE ($lines lines)" "$COLOR_GREEN"
        cmux_log info "cmux-orch" "$name: health.js created ($lines lines)"
        PENDING=$((PENDING - 1))
      fi
    fi
  done

  DONE=$((3 - PENDING))
  PCT=$(printf "%.2f" $(echo "0.2 + ($DONE.0 / 3.0) * 0.6" | bc))
  cmux_progress "$PCT" "cmux: $DONE/3 done (${WAITED}s)"
done

# 타임아웃
for name in alpha beta gamma; do
  if [[ -z "${AGENT_RESULT[$name]:-}" ]]; then
    AGENT_RESULT[$name]="TIMEOUT"
    cmux_status "$name" "TIMEOUT" "$COLOR_RED"
  fi
done

# ============================================================
# 결과 수집
# ============================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

cmux_progress 0.9 "cmux: collecting results"

pass=0
for name in alpha beta gamma; do
  [[ "${AGENT_RESULT[$name]}" == "PASS" ]] && pass=$((pass + 1))
done

cmux_status "method" "cmux: $pass/3 in ${ELAPSED}s" \
  "$([ $pass -eq 3 ] && echo $COLOR_GREEN || echo $COLOR_RED)"
cmux_progress 1.0 "cmux: complete (${ELAPSED}s)"
cmux_notify "cmux Orchestration" "$pass/3 agents done in ${ELAPSED}s"
cmux_log info "cmux-orch" "=== Complete: $pass/3 in ${ELAPSED}s ==="

# 결과 출력
echo ""
echo "=============================="
echo "cmux Orchestration Result"
echo "=============================="
echo "Time: ${ELAPSED}s"
echo ""
for name in alpha beta gamma; do
  result="${AGENT_RESULT[$name]}"
  if [[ -f "$PROJECT_BASE/$name/health.js" ]]; then
    lines=$(wc -l < "$PROJECT_BASE/$name/health.js")
    echo "$name: $result ($lines lines)"
  else
    echo "$name: $result"
  fi
done
echo "=============================="

echo ""
echo "Cleaning up in 3s..."
sleep 3
