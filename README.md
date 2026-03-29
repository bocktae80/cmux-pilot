# cmux-pilot

[cmux](https://cmux.app) 워크스페이스와 Claude Code 세션을 통합 관리하는 Claude Code 플러그인.

여러 cmux 워크스페이스에서 Claude Code를 동시에 사용할 때, 세션 매핑/동기화/복원을 자동화합니다.

## 주요 기능

- **자동 세션 매핑** — Claude Code 세션 시작 시 워크스페이스-세션 관계를 자동 기록
- **자동 동기화** — 프롬프트 입력마다 워크스페이스 상태(cwd, 세션)를 자동 저장
- **일괄 복원** — 컴퓨터 재시작 후 모든 워크스페이스의 Claude Code 세션을 한 번에 resume
- **신선도 검증** — 오래된 세션은 자동 건너뛰고, 셸 프롬프트 확인 후 안전하게 resume
- **자동 업데이트** — 하루 1번 `git pull`로 최신 버전 유지

## 설치

```bash
claude install-plugin https://github.com/bocktae80/cmux-pilot.git
```

설치 후 Claude Code를 재시작하면 자동으로 동작합니다.

## 사전 요구사항

- [cmux](https://cmux.app) 앱 설치 및 실행
- Claude Code CLI

## 사용법

### 자동 동작 (설치만 하면 됨)

| 이벤트 | 동작 |
|--------|------|
| Claude Code 세션 시작 | 워크스페이스-세션 매핑 기록 |
| 프롬프트 입력 | 워크스페이스 상태 동기화 |
| Claude Code 응답 완료 | 세션 활성 heartbeat |
| 하루 1번 | 플러그인 자동 업데이트 |

### 커맨드

```bash
/cmux-ws              # 워크스페이스 목록
/cmux-ws new          # 새 워크스페이스 생성 (이름, 경로, 색상)
/cmux-ws save         # 전체 워크스페이스 상세 저장 (full save)
/cmux-ws resume       # 모든 워크스페이스의 Claude Code 세션 일괄 복원
/cmux-ws restart      # 모든 세션 exit → resume (플러그인 업데이트 후)
```

### 컴퓨터 재시작 후

```
1. cmux 앱 실행 (워크스페이스는 cmux가 자동 복원)
2. 아무 워크스페이스에서 Claude Code 시작
3. /cmux-ws resume
```

### resume 옵션

```bash
/cmux-ws resume              # 기본: fresh/stale 세션만 resume, expired는 건너뜀
/cmux-ws resume --dry-run    # 실행 없이 매칭 결과만 표시
/cmux-ws resume --force      # 만료 세션도 강제 resume
```

## 데이터

```
~/.config/cmux-pilot/
├── session-map.jsonl      # 세션 매핑 이력 (append-only, 자동 로테이션)
├── workspaces.json        # 워크스페이스 스냅샷
├── hook-debug.log         # 디버그 로그
└── autosave.log           # 자동 저장 이력
```

## 동작 원리

```
SessionStart 훅
  → session-map.jsonl에 {workspace_id, surface_id, session_id} 기록

UserPromptSubmit 훅
  → heartbeat 기록 + workspaces.json 동기화 (호출자 cwd 실시간 반영)

Stop 훅
  → heartbeat 기록 (세션 활성 상태 추적)

/cmux-ws resume
  → workspaces.json에서 이름 매칭 → 신선도 검증 → 셸 프롬프트 확인 → claude --resume
```

## 라이선스

MIT
