# cmux를 Agent Teams 백엔드로 사용할 수 있는가?

Date: 2026-03-07
Method: Claude Code v2.1.70 바이너리 역공학 (strings + 코드 패턴 분석)

---

## 1. Claude Code 백엔드 시스템 구조

### 등록된 백엔드 (하드코딩, 3개만 존재)

| 백엔드 | 클래스 | 감지 조건 | 패널 생성 방식 |
|--------|--------|----------|--------------|
| InProcess | `Ecq` | 기본값 (auto 모드) | 같은 프로세스 내 서브에이전트 |
| Tmux | `GgR` | `process.env.TMUX` 존재 | `tmux split-window` → pane |
| iTerm2 | `ZgR` | `TERM_PROGRAM=iTerm.app` + `it2` CLI | `it2 session split` |

**플러그인 API 없음** — 커스텀 백엔드를 등록하는 공개 인터페이스가 존재하지 않는다.

### 백엔드 감지 순서 (`detectAndGetBackend`)

```
1. process.env.TMUX 존재?
   → YES → TmuxBackend (native, inside tmux)

2. iTerm2 내부? (TERM_PROGRAM=iTerm.app || ITERM_SESSION_ID)
   → YES → it2 CLI 사용 가능?
     → YES → ITermBackend
     → NO → preferTmuxOverIterm2 설정 확인
       → tmux -V 성공? → TmuxBackend (fallback)
       → 실패 → Error

3. tmux -V 성공?
   → YES → TmuxBackend (external session mode)

4. 모두 실패 → Error: "No pane backend available"
```

### TmuxBackend가 사용하는 tmux 명령어

```
tmux split-window [-v|-h] -t <target> -P -F "#{pane_id}"
tmux send-keys -t <pane> <command> Enter
tmux select-pane -t <pane> [-P bg=... | -T <title>]
tmux set-option -w -t <window> pane-border-status top
tmux kill-pane -t <pane>
tmux list-panes -t <target> -F "#{pane_id}"
tmux display-message -p "#{pane_id}"
tmux select-layout -t <target> [main-vertical|tiled]
tmux resize-pane -t <pane> -x "30%"
tmux new-session -d -s <name> -n <window> -P -F "#{pane_id}"
tmux has-session -t <name>
tmux break-pane / join-pane  (hide/show)
```

### PaneBackendExecutor (에이전트 스폰 흐름)

```
PaneBackendExecutor.spawn(agentDef)
  → backend.createTeammatePaneInSwarmView(name, color)  // 패널 생성
  → backend.sendCommandToPane(paneId, command)           // claude CLI 실행
  → D4(name, message, teamName)                          // 초기 프롬프트 전송
```

에이전트 실행 명령어:
```bash
cd <cwd> && env CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 \
  <claude-binary> --agent-id <id> --agent-name <name> --team-name <team> \
  --agent-color <color> --parent-session-id <sid> \
  --dangerously-skip-permissions --teammate-mode auto
```

---

## 2. cmux의 현재 상태

### 환경변수

| 변수 | cmux 설정 | Claude Code 기대 |
|------|----------|-----------------|
| `TMUX` | 미설정 | TmuxBackend 감지 |
| `TMUX_PANE` | 미설정 | 리더 패널 ID |
| `CMUX_SURFACE_ID` | 설정됨 | 무시 |
| `CMUX_WORKSPACE_ID` | 설정됨 | 무시 |
| `TERM_PROGRAM` | ghostty | iTerm.app 기대 |

### cmux의 tmux 호환 명령어

cmux는 `# tmux compatibility commands` 섹션을 제공하지만, Agent Teams가 사용하는 핵심 명령어와 1:1 매핑되지 않음:

| tmux 명령어 | cmux 대응 | 호환성 |
|------------|----------|--------|
| `split-window` | `new-split`, `new-pane` | 다른 인터페이스 |
| `send-keys` | `send`, `send-key` | 다른 인터페이스 |
| `select-pane` | `focus-pane` | 다른 인터페이스 |
| `kill-pane` | `close-workspace` | 다른 인터페이스 |
| `list-panes -F "#{pane_id}"` | `list-panes` | 포맷 미지원 |
| `display-message -p` | `display-message -p` | 호환 |
| `set-option` | 없음 | 미지원 |
| `select-layout` | 없음 | 미지원 |
| `new-session` | `new-workspace` | 다른 개념 |

---

## 3. 접근법 분석

### 접근법 A: tmux Shim (cmux 전용)

`tmux` 이름의 스크립트를 만들어 tmux 명령어를 cmux로 번역.

```bash
#!/bin/bash
# 가상의 tmux → cmux 번역기
case "$1" in
  split-window) cmux new-split ... ;;
  send-keys)    cmux send ... ;;
  kill-pane)    cmux close-workspace ... ;;
  ...
esac
```

| 장점 | 단점 |
|------|------|
| tmux 불필요, 순수 cmux | tmux 명령어 파싱 매우 복잡 |
| cmux 고유 기능 활용 가능 | `#{pane_id}` 포맷 문자열 에뮬레이션 |
| | Claude Code 업데이트마다 깨질 위험 |
| | 엄청난 구현 비용 (20+ 명령어) |

**결론: 비현실적** — tmux CLI의 복잡한 옵션 조합 + 포맷 문자열을 완벽히 에뮬레이션하는 건 사실상 불가능.

### 접근법 B: tmux inside cmux (레이어링)

cmux 터미널 안에서 tmux 세션을 실행. Claude Code는 tmux를 감지하여 TmuxBackend 사용.

```
cmux (인프라 레이어)
  └── cmux workspace: 사이드바, 브라우저, 알림
      └── tmux session (패널 레이어)
          ├── tmux pane: team-lead (Claude Code)
          ├── tmux pane: agent-alpha
          ├── tmux pane: agent-beta
          └── tmux pane: agent-gamma
              ↑ Agent Teams가 자동 생성
```

| 장점 | 단점 |
|------|------|
| 양쪽 시스템 모두 네이티브 동작 | 터미널 안의 터미널 (중첩) |
| 구현 비용 제로 | cmux 패널 분할과 tmux 패널 분할 혼재 |
| cmux 고유 기능 (브라우저/사이드바) 유지 | tmux 패널은 cmux 사이드바에 미표시 |
| Agent Teams 패널 시각화 완전 동작 | UX가 약간 어색할 수 있음 |

**결론: 가장 현실적** — 지금 당장 사용 가능.

### 접근법 C: 네이티브 통합 (Feature Request)

**cmux 측**: `TMUX` 호환 환경변수 설정 옵션 추가, 또는 tmux CLI 호환 모드
**Claude Code 측**: `CmuxBackend` 추가 (cmux CLI 사용)

| 장점 | 단점 |
|------|------|
| 가장 깔끔한 통합 | 양쪽 개발자 협조 필요 |
| 중첩 없는 네이티브 UX | 구현 시점 불확실 |

**결론: 장기적 최적해** — 현재는 불가능, Feature Request 필요.

---

## 4. 결론

### 현재 답: "직접 대체는 불가, 레이어링으로 공존 가능"

cmux를 Agent Teams 백엔드로 **직접 등록**하는 것은 현재 불가능하다:
- 백엔드 레지스트리가 하드코딩 (TmuxBackend, ITermBackend만)
- 플러그인/확장 API 없음
- cmux와 tmux의 CLI 인터페이스가 다름

### 실험 결과: auto 모드의 실제 동작

cmux 환경에서 Agent Teams 스폰 테스트 (2026-03-07):

```
teammateMode = "auto" (기본값)
  → isInProcessEnabled() 호출
  → isInsideTmuxSync() = false (TMUX 미설정)
  → !false = true → InProcessBackend 사용
  → tmux 세션 생성 없음, 에이전트는 같은 프로세스 내에서 동작
```

**`auto` 모드의 핵심 로직:**
```javascript
function isInProcessEnabled() {
  if (nonInteractive) return true;
  let mode = getTeammateModeFromSnapshot();
  if (mode === "in-process") return true;
  if (mode === "tmux") return false;
  // auto mode:
  return !isInsideTmuxSync();  // tmux 안이 아니면 → in-process
}
```

| teammateMode | cmux 환경 (TMUX 없음) | tmux 환경 (TMUX 있음) |
|-------------|---------------------|---------------------|
| `"auto"` | InProcess (패널 없음) | TmuxBackend (패널 분할) |
| `"tmux"` | TmuxBackend (외부 세션) | TmuxBackend (네이티브) |
| `"in-process"` | InProcess | InProcess |

**tmux 패널을 원하면**: `settings.json`에 `"teammateMode": "tmux"` 설정 필요.

### 실험 결과: --teammate-mode tmux CLI 플래그 (2026-03-07)

cmux 인터랙티브 워크스페이스에서 `--teammate-mode tmux` CLI 플래그로 테스트:

```
claude --dangerously-skip-permissions --teammate-mode tmux
→ TeamCreate(t1) → Agent(a1, "echo PANE_MODE > /tmp/result.txt") → SendMessage → TeamDelete
```

**결과: TmuxBackend 동작 확인!**
- tmux 소켓 생성됨: `/tmp/tmux-501/claude-swarm-1274`
- 에이전트가 tmux pane에서 실행, 결과 파일 생성 성공
- 팀 삭제 후 tmux 세션 자동 정리, 소켓 파일만 잔존

### 실용적 해결 (3가지)

#### 방법 1: CLI 플래그 (검증 완료, 가장 확실)

```bash
# cmux 인터랙티브 워크스페이스에서:
claude --teammate-mode tmux
```
→ Agent Teams 스폰 시 외부 tmux 세션(`claude-swarm-*`) 자동 생성

#### 방법 2: teammateMode 설정 변경

`~/.claude/settings.json`에 추가:
```json
{ "teammateMode": "tmux" }
```
→ 모든 인터랙티브 세션에 적용 (비인터랙티브는 여전히 InProcess)

#### 방법 3: tmux inside cmux (수동 레이어링)

```bash
# cmux 터미널에서:
tmux new-session -s agent-work
# tmux 안에서 claude 실행 → Agent Teams가 tmux 패널 자동 생성
# cmux의 사이드바/브라우저/알림은 그대로 사용
```

### 최적 아키텍처 (현재 가능)

```
cmux window/workspace
  ├── [pane 1: terminal] tmux session
  │     ├── team-lead + agent panes (Agent Teams 자동 관리)
  │     └── tmux가 패널 분할/통신 담당
  ├── [pane 2: browser] 시각 검증용 (cmux 고유)
  └── [sidebar] 대시보드 (cmux 고유)
```

이 구조에서:
- **Agent Teams** = 에이전트 스폰/통신/태스크 (tmux 패널 안에서)
- **cmux** = 브라우저, 사이드바, 알림, 시그널 (감싸는 레이어)
- **양쪽 모두 네이티브 동작**, 서로 간섭 없음
