# cmux-lab Journal

## 2026-03-07 Session 1: 셋업 + W01 + Agent Teams 비교

### 완료

- [x] 프로젝트 구조 생성 (scenarios/, lib/, reference/, reports/)
- [x] cmux 반환값 레퍼런스 작성 (`reference/return-formats.md`)
- [x] 헬퍼 라이브러리 작성 + 테스트 (`lib/cmux-helpers.sh`)
- [x] 목업 프로젝트 3개 생성 (alpha/beta/gamma)
- [x] W01 Build-Test-Report 통합 워크플로우 실행 성공
- [x] Agent Teams vs cmux Orchestration 비교 실험 완료

### Agent Teams vs cmux 비교 핵심 발견

1. **Agent Teams는 cmux 안에서 동작한다** — 에이전트 스폰/통신/태스크 관리 모두 동작. 단, tmux 패널 시각화 안됨 (TMUX 환경변수 미설정)
2. **cmux = 인프라 레이어** — 사이드바, 브라우저, 알림, 시그널은 Agent Teams에 없는 기능
3. **Agent Teams = 에이전트 레이어** — 태스크 관리, 메시지 통신, worktree 격리는 cmux에 없는 기능
4. **경쟁이 아니라 보완** — 최적 조합은 Agent Teams(에이전트 조율) + cmux(인프라 시각화)
5. **cmux claude 래퍼** — cmux 번들에 claude 래퍼가 포함. hooks 자동 주입 (session-start/stop/notification)
6. **cmux는 Agent Teams 백엔드가 아님** — Claude Code는 TmuxBackend/ITermBackend만 인식. cmux 백엔드는 미등록

### 비교 결과 요약

| 항목 | Agent Teams | cmux Orchestration |
|------|------------|-------------------|
| 성공률 | 3/3 | 3/3 |
| 시간 | ~15s | 36s |
| 사이드바 | 없음 | 실시간 |
| 알림 | 없음 | macOS notify |
| 코드 필요 | 없음 (도구 호출만) | 셸 스크립트 필요 |
| 브라우저 | 불가 | 가능 |
| 상세 리포트 | `reports/comparison-report.md` |

### 삽질 기록

1. **bash 3.x에서 declare -A 불가** — zsh로 전환
2. **마커 오탐** — 쉘 명령어에도 마커 출현. 파일 존재 체크가 더 안정적
3. **grep 실패 + set -e** — `|| echo ""`로 방어
4. **claude -p 시작 지연** — 쉘 초기화 ~5s + 실행 ~20s. 폴링 간격 10s, 타임아웃 180s 필요
5. **zsh glob 에러** — `rm -f dir/*/file` 매치 없을 때 에러. 명시적 경로 나열로 해결

### 다음 할 것

- 브라우저 + 에이전트 조합 시나리오 (cmux만의 차별점)
- ~~cmux를 Agent Teams 백엔드로 등록 가능한지 탐구~~ → 완료 (Session 2)
- reference에 macOS bash 3.x 제약사항 추가

## 2026-03-07 Session 2: Agent Teams 백엔드 호환성 탐구

### 완료

- [x] Claude Code v2.1.70 바이너리 역공학 (strings + 코드 패턴 분석)
- [x] 백엔드 레지스트리 구조 완전 해독
- [x] 3가지 접근법 분석 + 호환성 리포트 작성

### 핵심 발견: 백엔드 시스템 역공학

1. **백엔드는 하드코딩 3개만**: InProcessBackend, TmuxBackend, ITermBackend — 플러그인 API 없음
2. **감지 순서**: `env.TMUX` → tmux | `TERM_PROGRAM=iTerm.app` → iTerm2 | `tmux -V` → tmux(외부) | 에러
3. **cmux는 감지 대상 아님**: `CMUX_*` 환경변수는 Claude Code가 무시
4. **TmuxBackend는 tmux CLI 직접 호출**: `tmux split-window`, `tmux send-keys` 등 20+ 명령어
5. **PaneBackendExecutor가 래핑**: 모든 pane 백엔드를 감싸서 에이전트 스폰/통신/종료 관리
6. **cmux에 tmux 호환 섹션 존재**: `capture-pane`, `display-message` 등 일부만 대응, 핵심 명령어(`split-window`, `send-keys`) 미대응

### 접근법 분석 결과

| 접근법 | 실현 가능성 | 비용 | 결론 |
|--------|-----------|------|------|
| A: tmux Shim (cmux 전용) | 낮음 | 매우 높음 | 비현실적 (20+ 명령어 + 포맷 문자열 에뮬레이션) |
| B: tmux inside cmux | 높음 | 제로 | **가장 현실적** — 지금 당장 사용 가능 |
| C: 네이티브 통합 | 가능 | 양쪽 협조 | 장기적 최적해, Feature Request 필요 |

### 실용적 해결: 레이어링 아키텍처

```
cmux (인프라: 사이드바/브라우저/알림)
  └── tmux session (패널: Agent Teams 자동 관리)
      ├── team-lead pane
      ├── agent-alpha pane
      └── agent-beta pane
```

### 상세 리포트

- `reports/backend-compatibility-report.md`

### 실험: cmux에서 Agent Teams 스폰 테스트

- `teammateMode = "auto"` (기본) → **InProcessBackend 사용됨** (tmux 패널 생성 안 됨)
- 이유: `auto` 모드는 `isInsideTmuxSync()` 체크 → `TMUX` 없으면 in-process 폴백
- tmux 프로세스/소켓 생성 확인: 없음
- **결론: cmux에서 auto 모드는 항상 InProcess, 패널 시각화 원하면 `"teammateMode": "tmux"` 설정 필요**

### 실험 2: teammateMode=tmux + claude -p (비인터랙티브)

- `settings.json`에 `"teammateMode": "tmux"` 설정
- `claude -p`로 새 프로세스에서 Agent Teams 스폰
- **결과: 여전히 InProcessBackend** — tmux 소켓/프로세스 미생성
- **원인**: `isInProcessEnabled()`의 첫 번째 체크가 `m8()` (비인터랙티브 감지)
  - `claude -p`는 `process.stdout.isTTY = false` → non-interactive → **무조건 in-process**
  - `teammateMode: "tmux"` 설정이 있어도 비인터랙티브에서는 무시됨
- **결론: pane 백엔드는 인터랙티브 세션(터미널에서 직접 `claude` 실행)에서만 동작**

### 최종 정리: Agent Teams 백엔드 조건

```
isInProcessEnabled() 판정 흐름:
  1. 비인터랙티브 (claude -p)? → 항상 InProcess (설정 무시)
  2. teammateMode === "in-process"? → InProcess
  3. teammateMode === "tmux"? → Pane 백엔드 (TmuxBackend)
  4. auto + TMUX 환경변수 있음 → Pane 백엔드
  5. auto + TMUX 없음 (cmux 등) → InProcess
```

| 환경 | teammateMode | 결과 |
|------|-------------|------|
| cmux + `claude -p` | tmux | InProcess (비인터랙티브) |
| cmux + 인터랙티브 | auto | InProcess (TMUX 없음) |
| cmux + 인터랙티브 | tmux | **TmuxBackend 외부 세션** (유일한 방법) |
| tmux + 인터랙티브 | auto | TmuxBackend 네이티브 |

### 실험 3: --teammate-mode tmux CLI 플래그 (인터랙티브)

- cmux 워크스페이스에서 인터랙티브 Claude Code 실행
- CLI 플래그: `claude --dangerously-skip-permissions --teammate-mode tmux`
- TeamCreate → Agent 스폰 → SendMessage → TeamDelete 전체 플로우 실행
- **결과: TmuxBackend 동작 확인!**
  - tmux 소켓 생성됨: `/tmp/tmux-501/claude-swarm-1274`
  - 에이전트가 tmux pane에서 실행되어 `/tmp/cmux-tmux-pane-result.txt` 파일 생성 성공
  - 팀 삭제 후 tmux 세션은 정리됐지만 소켓 파일은 잔존 (정상)
- **결론: cmux 인터랙티브 + `--teammate-mode tmux` CLI 플래그 = TmuxBackend 외부 세션 동작**

### 최종 정리: cmux에서 Agent Teams Pane 백엔드 사용법

**동작하는 조합** (검증 완료):
```
cmux 워크스페이스에서 인터랙티브 claude 실행
  + --teammate-mode tmux CLI 플래그
  → TmuxBackend가 외부 tmux 세션(claude-swarm-*) 자동 생성
  → 에이전트가 tmux pane에서 독립 실행
  → 작업 완료 후 세션 자동 정리
```

**동작하지 않는 조합**:
- `claude -p` (비인터랙티브) → 항상 InProcess
- `teammateMode: "auto"` + cmux (TMUX 없음) → InProcess
- `settings.json`의 `teammateMode: "tmux"` → 미검증 (CLI 플래그로 해결)

### 다음 할 것

- 브라우저 + 에이전트 조합 시나리오 (cmux만의 차별점)
- reference에 macOS bash 3.x 제약사항 추가
