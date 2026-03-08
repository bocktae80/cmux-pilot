#!/bin/zsh
# ============================================================
# cmux에서 teammateMode=tmux 설정으로 Agent Teams 테스트
# ============================================================
# 이 스크립트는 새 Claude Code 프로세스를 실행하여
# tmux pane 백엔드가 활성화되는지 확인합니다.
#
# 사전 조건: ~/.claude/settings.json에 "teammateMode": "tmux" 설정됨
# 실행: zsh scenarios/test-tmux-backend.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

echo "=== Pre-test: tmux status ==="
echo "tmux sessions before:"
tmux list-sessions 2>&1
echo "tmux sockets:"
ls -la /tmp/tmux-$(id -u)/ 2>/dev/null
echo ""

echo "=== Settings check ==="
python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); print('teammateMode:', d.get('teammateMode', 'NOT SET'))"
echo ""

echo "=== Spawning Claude Code with Agent Teams test ==="
# unset CLAUDECODE to avoid nested session detection
unset CLAUDECODE

# Run claude with a prompt that creates a team and spawns an agent
/Users/kent/.local/bin/claude -p "
다음을 순서대로 해줘:
1. TeamCreate로 팀 'tmux-pane-test'를 만들어
2. Agent 도구로 에이전트 'test-agent'를 팀에 스폰해. 프롬프트: 'echo HELLO > /tmp/cmux-lab-tmux-test.txt 파일을 Bash로 생성해'
3. 10초 대기 후 에이전트 종료
4. TeamDelete로 팀 삭제
5. 완료 출력
" --dangerously-skip-permissions 2>&1 &

CLAUDE_PID=$!
echo "Claude PID: $CLAUDE_PID"

# Monitor tmux sessions while claude runs
echo ""
echo "=== Monitoring tmux (every 5s for 60s) ==="
for i in $(seq 1 12); do
  sleep 5
  echo "--- Check $i (${i}*5s) ---"

  # Check tmux processes
  TMUX_PROCS=$(ps aux | grep -c "[t]mux" 2>/dev/null)
  echo "tmux processes: $TMUX_PROCS"

  # Check tmux sockets
  SOCKETS=$(find /tmp -name "tmux*" -o -name "claude*" 2>/dev/null | grep -v "^/tmp/tmux-$(id -u)$" | head -5)
  if [[ -n "$SOCKETS" ]]; then
    echo "Sockets found:"
    echo "$SOCKETS"
  fi

  # Check default tmux sessions
  tmux list-sessions 2>/dev/null && echo "(default server sessions found)"

  # Check all sockets in tmux dir
  for sock in /tmp/tmux-$(id -u)/*; do
    [[ -S "$sock" ]] && echo "Socket: $sock" && tmux -S "$sock" list-sessions 2>/dev/null
  done

  # Check result file
  [[ -f /tmp/cmux-lab-tmux-test.txt ]] && echo "RESULT FILE EXISTS!" && cat /tmp/cmux-lab-tmux-test.txt

  # Check if claude is still running
  kill -0 $CLAUDE_PID 2>/dev/null || { echo "Claude finished."; break; }
done

echo ""
echo "=== Post-test cleanup ==="
rm -f /tmp/cmux-lab-tmux-test.txt
wait $CLAUDE_PID 2>/dev/null

echo ""
echo "=== Final tmux status ==="
tmux list-sessions 2>&1
ls -la /tmp/tmux-$(id -u)/ 2>/dev/null
echo ""
echo "=== Done ==="
