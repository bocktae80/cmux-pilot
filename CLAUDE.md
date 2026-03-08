# cmux-pilot

> cmux Claude Code 플러그인 — 워크스페이스 관리, 사이드바, 브라우저, 오케스트레이션

## 목적

- cmux 워크스페이스 생성/저장/복원 자동화
- cmux 사이드바/브라우저/알림을 Claude Code에서 직접 활용
- 멀티 워크스페이스 오케스트레이션 지원

## 구조

```
cmux-pilot/                        # 플러그인 루트
├── .claude-plugin/
│   └── plugin.json                # 플러그인 매니페스트
├── CLAUDE.md                      # 이 파일
├── JOURNAL.md                     # 탐구 일지 (기존 연구 기록)
│
├── skills/                        # 스킬
│   └── cmux-workspace/
│       └── SKILL.md               # 워크스페이스 관리 스킬
│
├── commands/                      # 슬래시 커맨드
│   └── cmux-ws.md                 # /cmux-ws (save/restore/new/list)
│
├── hooks/                         # 훅
│   ├── hooks.json
│   └── scripts/
│       └── cmux-session-init.sh   # SessionStart: cmux 환경 감지
│
├── lib/                           # 라이브러리
│   ├── cmux-helpers.sh            # 기존 헬퍼 (45함수)
│   └── cmux-ws-manager.sh         # save/restore/new 핵심 로직
│
├── reference/                     # cmux 레퍼런스 (기존 연구)
│   └── return-formats.md
├── scenarios/                     # 검증된 시나리오 (기존 연구)
├── reports/                       # 실행 결과 리포트 (기존 연구)
└── mock-projects/                 # 테스트용 (기존 연구)
```

## 커맨드

- `/cmux-ws` — 워크스페이스 목록
- `/cmux-ws new` — 새 워크스페이스 (이름, 경로, 컬러, 브라우저 URL)
- `/cmux-ws save` — 전체 구성을 JSON으로 저장
- `/cmux-ws restore` — JSON에서 워크스페이스 복원

## 규칙

1. **실행 가능한 코드만 커밋** — 실제 돌려본 것만 기록
2. **반환값 파싱 패턴** — cmux 명령별 실제 출력 포맷을 `reference/`에 기록
3. **한국어 저널** — JOURNAL.md에 발견사항 기록
4. **스크립트 독립 실행** — 각 .sh 파일은 단독으로 실행 가능해야 함

## cmux 환경

- **위치**: `/Applications/cmux.app/Contents/Resources/bin/cmux`
- **소켓**: `/tmp/cmux.sock`
- **메서드 수**: 139개
- **주요 카테고리**: terminal, browser, sidebar, notification, sync
