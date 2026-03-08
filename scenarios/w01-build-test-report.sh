#!/bin/zsh
# ============================================================
# W01: Build -> Test -> Report (통합 워크플로우)
# ============================================================
#
# 흐름:
#   Phase 1: 3개 프로젝트 병렬 빌드 (각각 별도 워크스페이스)
#   Phase 2: 빌드 성공한 프로젝트만 병렬 테스트
#   Phase 3: 결과 수집 -> 리포트 생성 -> 알림
#
# 실행: zsh scenarios/w01-build-test-report.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/cmux-helpers.sh"

PROJECT_BASE="$SCRIPT_DIR/../mock-projects"
PROJECTS=(alpha beta gamma)
REPORT_DIR="$SCRIPT_DIR/../reports/w01-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$REPORT_DIR"

# 고유 마커 (명령어 echo와 구분하기 위해 길고 고유한 문자열 사용)
MARKER="__CMUX_STEP_COMPLETE__"

# 정리용 리소스 추적
declare -a WS_LIST=()
trap 'for ws in "${WS_LIST[@]}"; do cmux_close_workspace "$ws"; done; cmux_clear_sidebar' EXIT

# ============================================================
# Phase 1: 병렬 빌드
# ============================================================

cmux_status "pipeline" "Phase 1: Build" "$COLOR_YELLOW"
cmux_progress 0.0 "build: starting"
cmux_log info "w01" "=== Phase 1: Parallel Build ==="

declare -A BUILD_WS=()

for proj in "${PROJECTS[@]}"; do
  # 마커를 변수로 전달해서 명령어에 직접 노출되지 않게 함
  ws=$(cmux_named_workspace "build-$proj" \
    "cd $PROJECT_BASE/$proj && node build.js; echo $MARKER\$(echo \$?)")
  BUILD_WS[$proj]="$ws"
  WS_LIST+=("$ws")
  cmux_ws_status "$ws" "phase" "building" "$COLOR_YELLOW"
  cmux_log info "w01" "Started build: $proj"
done

cmux_status "alpha" "building..." "$COLOR_YELLOW"
cmux_status "beta" "building..." "$COLOR_YELLOW"
cmux_status "gamma" "building..." "$COLOR_YELLOW"

# 빌드 완료 대기 (폴링)
cmux_log info "w01" "Waiting for builds..."

declare -A BUILD_RESULT=()
PENDING=${#PROJECTS[@]}
MAX_WAIT=60
WAITED=0

while [[ $PENDING -gt 0 ]] && [[ $WAITED -lt $MAX_WAIT ]]; do
  sleep 3
  WAITED=$((WAITED + 3))

  for proj in "${PROJECTS[@]}"; do
    [[ -n "${BUILD_RESULT[$proj]:-}" ]] && continue

    ws="${BUILD_WS[$proj]}"
    screen=$(cmux read-screen --workspace "$ws" --lines 30 2>/dev/null || echo "")

    # 마커+종료코드 패턴 검색: __CMUX_STEP_COMPLETE__0 또는 __CMUX_STEP_COMPLETE__1
    if echo "$screen" | grep -q "${MARKER}"; then
      exit_line=$(echo "$screen" | grep -o "${MARKER}[0-9]*" | tail -1 || echo "")
      exit_code="${exit_line#$MARKER}"

      if [[ "$exit_code" == "0" ]]; then
        BUILD_RESULT[$proj]="PASS"
        cmux_status "$proj" "build PASS" "$COLOR_GREEN"
        cmux_ws_status "$ws" "phase" "build PASS" "$COLOR_GREEN"
        cmux_log info "w01" "$proj build PASS"
      else
        BUILD_RESULT[$proj]="FAIL"
        cmux_status "$proj" "build FAIL" "$COLOR_RED"
        cmux_ws_status "$ws" "phase" "build FAIL" "$COLOR_RED"
        cmux_log error "w01" "$proj build FAIL (exit=$exit_code)"
      fi
      PENDING=$((PENDING - 1))
    fi
  done

  DONE=$((${#PROJECTS[@]} - PENDING))
  PCT=$(printf "%.2f" $(echo "0.1 + ($DONE.0 / ${#PROJECTS[@]}.0) * 0.25" | bc))
  cmux_progress "$PCT" "build: $DONE/${#PROJECTS[@]}"
done

# 타임아웃 처리
for proj in "${PROJECTS[@]}"; do
  if [[ -z "${BUILD_RESULT[$proj]:-}" ]]; then
    BUILD_RESULT[$proj]="TIMEOUT"
    cmux_status "$proj" "build TIMEOUT" "$COLOR_RED"
    cmux_log error "w01" "$proj build TIMEOUT"
  fi
done

cmux_progress 0.35 "build: complete"
cmux_log info "w01" "Phase 1 done"

# ============================================================
# Phase 2: 빌드 성공한 프로젝트만 테스트
# ============================================================

cmux_status "pipeline" "Phase 2: Test" "$COLOR_BLUE"
cmux_log info "w01" "=== Phase 2: Test ==="

declare -A TEST_WS=()
declare -A TEST_RESULT=()
TEST_TARGETS=()

for proj in "${PROJECTS[@]}"; do
  if [[ "${BUILD_RESULT[$proj]}" == "PASS" ]]; then
    TEST_TARGETS+=("$proj")
    ws=$(cmux_named_workspace "test-$proj" \
      "cd $PROJECT_BASE/$proj && node test.js; echo $MARKER\$(echo \$?)")
    TEST_WS[$proj]="$ws"
    WS_LIST+=("$ws")
    cmux_status "$proj" "testing..." "$COLOR_BLUE"
    cmux_ws_status "$ws" "phase" "testing" "$COLOR_BLUE"
    cmux_log info "w01" "Started test: $proj"
  else
    TEST_RESULT[$proj]="SKIPPED"
    cmux_log info "w01" "$proj test SKIPPED (build ${BUILD_RESULT[$proj]})"
  fi
done

if [[ ${#TEST_TARGETS[@]} -eq 0 ]]; then
  cmux_log error "w01" "No projects to test."
else
  PENDING=${#TEST_TARGETS[@]}
  WAITED=0

  while [[ $PENDING -gt 0 ]] && [[ $WAITED -lt $MAX_WAIT ]]; do
    sleep 3
    WAITED=$((WAITED + 3))

    for proj in "${TEST_TARGETS[@]}"; do
      [[ -n "${TEST_RESULT[$proj]:-}" ]] && continue

      ws="${TEST_WS[$proj]}"
      screen=$(cmux read-screen --workspace "$ws" --lines 40 2>/dev/null || echo "")

      if echo "$screen" | grep -q "${MARKER}"; then
        # 결과 파싱 (grep 실패 방어)
        summary=$(echo "$screen" | grep -o '[0-9]* passed, [0-9]* failed' | tail -1 || echo "")
        [[ -z "$summary" ]] && summary="unknown"

        exit_line=$(echo "$screen" | grep -o "${MARKER}[0-9]*" | tail -1 || echo "")
        exit_code="${exit_line#$MARKER}"

        if [[ "$exit_code" == "0" ]]; then
          TEST_RESULT[$proj]="PASS"
          cmux_status "$proj" "test PASS ($summary)" "$COLOR_GREEN"
          cmux_ws_status "$ws" "phase" "test PASS" "$COLOR_GREEN"
          cmux_log info "w01" "$proj test PASS: $summary"
        else
          TEST_RESULT[$proj]="FAIL"
          cmux_status "$proj" "test FAIL ($summary)" "$COLOR_RED"
          cmux_ws_status "$ws" "phase" "test FAIL" "$COLOR_RED"
          cmux_log error "w01" "$proj test FAIL: $summary"
        fi

        cmux_data_set "test-$proj" "$summary"
        PENDING=$((PENDING - 1))
      fi
    done

    DONE=$((${#TEST_TARGETS[@]} - PENDING))
    PCT=$(printf "%.2f" $(echo "0.35 + ($DONE.0 / ${#TEST_TARGETS[@]}.0) * 0.35" | bc))
    cmux_progress "$PCT" "test: $DONE/${#TEST_TARGETS[@]}"
  done

  for proj in "${TEST_TARGETS[@]}"; do
    if [[ -z "${TEST_RESULT[$proj]:-}" ]]; then
      TEST_RESULT[$proj]="TIMEOUT"
      cmux_status "$proj" "test TIMEOUT" "$COLOR_RED"
    fi
  done
fi

cmux_progress 0.7 "test: complete"
cmux_log info "w01" "Phase 2 done"

# ============================================================
# Phase 3: 리포트 생성 + 알림
# ============================================================

cmux_status "pipeline" "Phase 3: Report" "$COLOR_PURPLE"
cmux_log info "w01" "=== Phase 3: Report ==="

# 집계
build_pass=0; test_pass=0
for proj in "${PROJECTS[@]}"; do
  [[ "${BUILD_RESULT[$proj]}" == "PASS" ]] && build_pass=$((build_pass + 1))
  [[ "${TEST_RESULT[$proj]:-}" == "PASS" ]] && test_pass=$((test_pass + 1))
done

# 리포트 생성
{
  echo "# W01 Build-Test Report"
  echo ""
  echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Projects: ${PROJECTS[*]}"
  echo ""
  echo "## Results"
  echo ""
  echo "| Project | Build | Test | Details |"
  echo "|---------|-------|------|---------|"
  for proj in "${PROJECTS[@]}"; do
    build="${BUILD_RESULT[$proj]}"
    test_r="${TEST_RESULT[$proj]:-N/A}"
    detail=$(cmux_data_get "test-$proj" 2>/dev/null || echo "-")
    [[ -z "$detail" ]] && detail="-"
    echo "| $proj | $build | $test_r | $detail |"
  done
  echo ""
  echo "## Summary"
  echo ""
  echo "- Build: $build_pass/${#PROJECTS[@]} passed"
  echo "- Test: $test_pass/${#PROJECTS[@]} passed"
} > "$REPORT_DIR/report.md"

cmux_progress 0.9 "report: generated"

# 최종 상태
ALL_PASS=true
[[ $build_pass -lt ${#PROJECTS[@]} ]] && ALL_PASS=false
[[ $test_pass -lt ${#PROJECTS[@]} ]] && ALL_PASS=false

if $ALL_PASS; then
  cmux_status "pipeline" "ALL PASS" "$COLOR_GREEN"
  cmux_notify "W01 Complete" "All ${#PROJECTS[@]} projects passed!"
else
  cmux_status "pipeline" "ISSUES FOUND" "$COLOR_RED"
  cmux_notify "W01 Complete" "Build: $build_pass/${#PROJECTS[@]}, Test: $test_pass/${#PROJECTS[@]}"
fi

cmux_progress 1.0 "pipeline: done"
cmux_log info "w01" "=== Pipeline Complete ==="

# 리포트 출력
echo ""
echo "=============================="
cat "$REPORT_DIR/report.md"
echo "=============================="
echo ""
echo "Report: $REPORT_DIR/report.md"
echo "Sidebar: cmux list-log"

# 정리 전 대기
echo ""
echo "Cleaning up in 3s..."
sleep 3
