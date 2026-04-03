# cmux-pilot

한국어 | [English](./CLAUDE.en.md)

> cmux Claude Code 플러그인 — 워크스페이스 + Claude Code 세션 통합 관리

## 설치

```bash
claude install-plugin https://github.com/bocktae80/cmux-pilot.git
```

설치 후 Claude Code를 재시작하면 자동으로 훅이 동작합니다.
업데이트는 SessionStart 시 하루 1번 자동 `git pull`로 처리됩니다.

---

## 사용 가이드

### 일상 워크플로우 (아무것도 안 해도 됨)

플러그인이 설치되면 다음이 **자동으로** 동작합니다:

| 이벤트 | 자동 동작 | 데이터 |
|--------|----------|--------|
| Claude Code 세션 시작 | 워크스페이스-세션 매핑 기록 | session-map.jsonl |
| 프롬프트 입력 | 워크스페이스 상태 동기화 + heartbeat | workspaces.json |
| Claude Code 응답 완료 | 세션 활성 heartbeat | session-map.jsonl |
| 플러그인 업데이트 확인 | git pull (하루 1번) | - |

### 수동 커맨드

| 커맨드 | 용도 | 언제 사용 |
|--------|------|-----------|
| `/cmux-ws` | 워크스페이스 목록 | 현재 상태 확인 |
| `/cmux-ws new` | 새 워크스페이스 생성 | 프로젝트 추가 |
| `/cmux-ws save` | full save (모든 워크스페이스 상세) | 중요한 시점에 수동 저장 |
| `/cmux-ws resume` | Claude Code 세션 일괄 복원 | 컴퓨터 재시작 후 |
| `/cmux-ws resume --dry-run` | resume 미리보기 | 복원 전 확인 |
| `/cmux-ws resume --force` | 만료 세션도 강제 복원 | 오래된 세션 복원 |
| `/cmux-ws restart` | 모든 세션 exit → resume | 플러그인 업데이트 후 |

### 컴퓨터 재시작 후 복원

```
1. cmux 앱 실행 (워크스페이스는 cmux가 자동 복원)
2. 아무 워크스페이스에서 Claude Code 시작
3. /cmux-ws resume 실행
→ 모든 워크스페이스의 이전 Claude Code 세션이 자동 복원됨
```

---

## 데이터 구조

### 저장 위치

```
~/.config/cmux-pilot/
├── session-map.jsonl      # 세션 매핑 이력 (append-only, 자동 로테이션)
├── workspaces.json        # 워크스페이스 스냅샷 (autosave + 수동 save)
├── .last-update-check     # 자동 업데이트 마지막 체크 시간
├── .pre-update-head       # 업데이트 전 커밋 (업데이트 알림용)
├── hook-debug.log         # SessionStart 훅 디버그 로그 (최근 50줄)
└── autosave.log           # autosave 실행 이력
```

### session-map.jsonl — 세션 이력

```jsonl
{"type":"session_start","surface_id":"...","workspace_id":"...","workspace_name":"cpf","session_id":"abc123","cwd":"/path","timestamp":"..."}
{"type":"session_active","workspace_id":"...","surface_id":"...","session_id":"abc123","timestamp":"..."}
{"type":"workspace_restored","old_workspace_id":"...","new_workspace_id":"...","workspace_name":"cpf","timestamp":"..."}
```

- **session_start**: Claude Code 세션 시작 시 기록
- **session_active**: Stop/UserPromptSubmit 시 heartbeat (세션 종료 추정용)
- **workspace_restored**: restore 시 old→new UUID 매핑
- 자동 로테이션: ~300KB 초과 시 최근 500줄만 유지

### workspaces.json — 워크스페이스 스냅샷

```json
{
  "version": 2,
  "saved_at": "2026-03-29T...",
  "workspaces": [
    {
      "name": "cpf",
      "cwd": "/Users/kent/Work/camfit/camfit-cpf",
      "workspace_id": "UUID",
      "status": [{"key": "project", "value": "cpf", "color": "#3b82f6"}],
      "panels": [{"type": "terminal", "focused": true}],
      "claude_sessions": [
        {"session_id": "abc123", "surface_id": "UUID", "resume_cmd": "claude --resume abc123", "last_active": "..."}
      ]
    }
  ]
}
```

---

## 기술 상세

### 훅 동작

| 훅 | 스크립트 | timeout | 동작 |
|----|----------|---------|------|
| SessionStart | cmux-session-init.sh | 5초 | 자동 업데이트 체크 + session-map 기록 + cmux 환경 감지 |
| UserPromptSubmit | cmux-autosave.sh | 5초 | heartbeat + 워크스페이스 동기화 (호출자 cwd 반영) |
| PreToolUse | cmux-sidebar-status.sh | 3초 | 사이드바에 작업 상태 표시 |
| Stop | cmux-sidebar-status.sh | 3초 | 사이드바 "Needs input" + heartbeat |

### 세션 매칭 우선순위

1. **workspace_id (UUID)**: session-map에서 정확 매칭
2. **이름 역조회**: session-map의 workspace_name으로 UUID 찾기
3. **cwd + 이름 검색**: Claude Code 대화 파일에서 워크스페이스 이름 검색
4. **최신 fallback**: cwd 아래 가장 최근 세션 파일

### resume 신선도 검증

| 조건 | 판정 | 동작 |
|------|------|------|
| last_active < 1시간 | fresh | 즉시 resume |
| last_active < 24시간 | stale | resume 시도 |
| last_active > 24시간 | expired | 건너뜀 (`--force`로 강제) |
| last_active 없음 | unknown | resume 시도 |

### 자동 업데이트

- SessionStart에서 하루 1번 `git fetch + pull --ff-only` (백그라운드)
- 업데이트 후 다음 세션에서 알림 표시
- 로컬 수정이 있으면 ff-only가 실패하여 안전하게 건너뜀

### autosave 트리거 조건 (OR)

1. session-map.jsonl이 마지막 저장 이후 변경됨
2. 마지막 저장 후 15분 경과
3. workspaces.json이 없음 (첫 저장)

autosave는 `cmux list-workspaces` (전체) + `cmux sidebar-state` (호출자만) = 2회 cmux 호출.

---

## 프로젝트 구조

```
cmux-pilot/
├── .claude-plugin/
│   └── plugin.json                # 플러그인 매니페스트
├── CLAUDE.md                      # 이 파일
│
├── skills/
│   └── cmux-workspace/
│       └── SKILL.md               # 워크스페이스 관리 스킬
│
├── commands/
│   └── cmux-ws.md                 # /cmux-ws 커맨드 정의
│
├── hooks/
│   ├── hooks.json                 # 훅 등록 (SessionStart, UserPromptSubmit, PreToolUse, Stop)
│   └── scripts/
│       ├── cmux-session-init.sh   # SessionStart: 자동 업데이트 + 환경 감지 + 세션 매핑
│       ├── cmux-autosave.sh       # UserPromptSubmit: heartbeat + 워크스페이스 동기화
│       ├── cmux-sidebar-status.sh # PreToolUse/Stop: 사이드바 상태 + heartbeat
│       ├── cmux-ws-resume.sh      # 세션 일괄 복원 (신선도 검증 + 셸 프롬프트 확인)
│       └── cmux-ws-restart.sh     # 전체 세션 exit → resume
│
├── lib/
│   ├── cmux-helpers.sh            # cmux API 헬퍼 (45함수)
│   └── cmux-ws-manager.sh         # save/new/list 핵심 로직
│
├── reference/                     # cmux 레퍼런스
├── scenarios/                     # 검증된 시나리오
└── reports/                       # 실행 결과 리포트
```

## 개발 규칙

1. **실행 가능한 코드만 커밋** — 실제 돌려본 것만 기록
2. **반환값 파싱 패턴** — cmux 명령별 실제 출력 포맷을 `reference/`에 기록
3. **한국어 저널** — JOURNAL.md에 발견사항 기록
4. **스크립트 독립 실행** — 각 .sh 파일은 단독으로 실행 가능해야 함
5. **Python 임베딩 안전** — shell 변수는 반드시 `sys.argv`/환경변수로 전달 (직접 보간 금지)
6. **subprocess 리스트 인자** — `subprocess.run(['cmux', ...])` 사용 (`shell=True` 지양)

## cmux 환경

- **위치**: `/Applications/cmux.app/Contents/Resources/bin/cmux`
- **소켓**: `/tmp/cmux.sock`
- **메서드 수**: 139개
- **주요 카테고리**: terminal, browser, sidebar, notification, sync
- **워크스페이스 persist**: cmux 앱이 자체적으로 워크스페이스를 저장/복원 (`~/Library/Application Support/cmux/`)
