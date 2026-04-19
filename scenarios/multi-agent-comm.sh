#!/bin/bash
# multi-agent-comm.sh — cmux 멀티 에이전트 통신 데모
#
# 2개의 Claude Code 세션이 각자 워크스페이스에서 실행되며,
# cmux 시그널과 공유 파일로 협업합니다.
#
# 흐름:
#   [Agent A: reviewer]  코드 리뷰 → 결과 저장 → 시그널 "review-done"
#   [Agent B: improver]  시그널 대기 → 결과 읽기 → 개선안 작성
#
# 사용: bash scenarios/multi-agent-comm.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/cmux-helpers.sh"

# ── 공유 디렉토리 ──
SHARED="/tmp/cmux-agent-comm"
rm -rf "$SHARED"
mkdir -p "$SHARED"

PROJECT_DIR="/Users/kent/Work/cmux-pilot"
SIGNAL_NAME="review-done"

echo "╔══════════════════════════════════════════════╗"
echo "║  cmux 멀티 에이전트 통신 데모                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Agent A 스크립트 생성 ──
cat > "$SHARED/agent-a.sh" << 'AGENT_A'
#!/bin/bash
SHARED="/tmp/cmux-agent-comm"
PROJECT_DIR="/Users/kent/Work/cmux-pilot"

echo "🔍 [Agent A: reviewer] 코드 리뷰 시작..."
echo ""

# Claude Code로 리뷰 실행
cd "$PROJECT_DIR"
claude -p "$(cat <<'PROMPT'
cmux-pilot 프로젝트의 hooks/scripts/cmux-autosave.sh 파일을 리뷰해줘.
다음 3가지 관점에서만 간결하게 (각 2-3줄):
1. 버그 또는 엣지케이스
2. 보안 이슈
3. 개선 제안

한국어로 답변. 마크다운 사용하지 마.
PROMPT
)" --output-format text 2>&1 | tee "$SHARED/review-result.txt"

echo ""
echo "📝 리뷰 결과 저장: $SHARED/review-result.txt"
echo ""

# 시그널 발신: "리뷰 완료"
echo "📡 시그널 발신: review-done"
cmux wait-for -S "review-done" 2>/dev/null || true

echo ""
echo "✅ [Agent A] 완료. Agent B에게 바톤 넘김."
echo ""
echo "--- Agent A 종료. 아무 키나 누르세요 ---"
read
AGENT_A
chmod +x "$SHARED/agent-a.sh"

# ── Agent B 스크립트 생성 ──
cat > "$SHARED/agent-b.sh" << 'AGENT_B'
#!/bin/bash
SHARED="/tmp/cmux-agent-comm"
PROJECT_DIR="/Users/kent/Work/cmux-pilot"

echo "⏳ [Agent B: improver] Agent A의 리뷰 완료 대기 중..."
echo ""

# 시그널 대기
cmux wait-for "review-done" --timeout 120 2>/dev/null || {
  echo "⚠️  타임아웃: Agent A 응답 없음"
  exit 1
}

echo "📥 시그널 수신! 리뷰 결과 읽는 중..."
echo ""

REVIEW=$(cat "$SHARED/review-result.txt" 2>/dev/null || echo "결과 없음")

echo "═══ Agent A의 리뷰 결과 ═══"
echo "$REVIEW"
echo "════════════════════════════"
echo ""

# Claude Code로 개선안 작성
cd "$PROJECT_DIR"
claude -p "$(cat <<PROMPT
동료가 cmux-autosave.sh를 리뷰하고 다음 피드백을 남겼어:

---
$REVIEW
---

이 피드백을 바탕으로 cmux-autosave.sh의 구체적인 수정 코드를 작성해줘.
전체 파일이 아니라, 수정이 필요한 부분의 diff만 보여줘.
한국어로 설명. 마크다운 사용하지 마.
PROMPT
)" --output-format text 2>&1 | tee "$SHARED/improvement-result.txt"

echo ""
echo "📝 개선안 저장: $SHARED/improvement-result.txt"
echo ""
echo "✅ [Agent B] 완료."
echo ""
echo "--- Agent B 종료. 아무 키나 누르세요 ---"
read
AGENT_B
chmod +x "$SHARED/agent-b.sh"

# ── 워크스페이스 생성 ──
echo "워크스페이스 생성 중..."

# Agent A: 리뷰어 (보라색)
RAW_A=$(cmux new-workspace --command "bash $SHARED/agent-a.sh" 2>&1)
UUID_A=$(echo "$RAW_A" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
cmux rename-workspace --workspace "$UUID_A" "agent-reviewer" 2>/dev/null
cmux set-status "role" "코드 리뷰" --color "#8b5cf6" --workspace "$UUID_A" 2>/dev/null
cmux set-status "status" "실행 중" --color "#f59e0b" --workspace "$UUID_A" 2>/dev/null
echo "  ✓ agent-reviewer ($UUID_A)"

# Agent B: 개선자 (초록색)
RAW_B=$(cmux new-workspace --command "bash $SHARED/agent-b.sh" 2>&1)
UUID_B=$(echo "$RAW_B" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
cmux rename-workspace --workspace "$UUID_B" "agent-improver" 2>/dev/null
cmux set-status "role" "개선안 작성" --color "#22c55e" --workspace "$UUID_B" 2>/dev/null
cmux set-status "status" "대기 중" --color "#94a3b8" --workspace "$UUID_B" 2>/dev/null
echo "  ✓ agent-improver ($UUID_B)"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  스폰 완료!                                  ║"
echo "║                                              ║"
echo "║  agent-reviewer  → 코드 리뷰 진행 중 (보라)  ║"
echo "║  agent-improver  → 리뷰 완료 대기 중 (초록)  ║"
echo "║                                              ║"
echo "║  cmux 사이드바에서 워크스페이스 전환해서      ║"
echo "║  각 에이전트의 진행 상황을 확인하세요.        ║"
echo "║                                              ║"
echo "║  통신 흐름:                                   ║"
echo "║  A: 리뷰 → 파일 저장 → 시그널 발신           ║"
echo "║  B: 시그널 수신 → 파일 읽기 → 개선안 작성    ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "결과 파일:"
echo "  리뷰:   $SHARED/review-result.txt"
echo "  개선안: $SHARED/improvement-result.txt"
