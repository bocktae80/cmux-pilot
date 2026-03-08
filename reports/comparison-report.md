# Agent Teams vs cmux Orchestration 비교 리포트

Date: 2026-03-07
Task: 3개 mock-project에 health.js 모듈 추가

---

## 실행 결과

| 항목 | Agent Teams (방식 A) | cmux Orchestration (방식 B) |
|------|---------------------|----------------------------|
| alpha | 29 lines (HTTP check) | 35 lines (HTTP check) |
| beta | 16 lines (DB check) | 19 lines (DB check) |
| gamma | 36 lines (disk check) | 27 lines (disk check) |
| 성공률 | 3/3 | 3/3 |
| 소요 시간 | ~15s (백그라운드) | 36s (폴링 포함) |
| 사이드바 | 없음 | 실시간 진행률 + 로그 |
| 알림 | 없음 (메시지로 대체) | macOS notify |

---

## 구조적 차이

### Agent Teams

```
현재 세션 (team-lead)
  ├── Agent(alpha) → 동일 프로세스 내 서브에이전트
  ├── Agent(beta)  → 동일 프로세스 내 서브에이전트
  └── Agent(gamma) → 동일 프로세스 내 서브에이전트

통신: SendMessage (내장 프로토콜)
조율: TaskCreate/TaskUpdate (공유 태스크 리스트)
시각화: tmux/iTerm2 패널 (cmux에서는 미지원)
```

- 에이전트 스폰/통신이 **내장 프로토콜**로 처리 → 안정적
- team-lead가 태스크 분배/수집을 **자동으로** 관리
- 코드 작성 없이 도구만 호출하면 됨
- cmux 안에서도 동작하지만 **패널 시각화 없음** (tmux 백엔드 미감지)

### cmux Orchestration

```
현재 세션 (오케스트레이터)
  ├── workspace:A → claude -p (독립 OS 프로세스)
  ├── workspace:B → claude -p (독립 OS 프로세스)
  └── workspace:C → claude -p (독립 OS 프로세스)

통신: 파일 시스템 + cmux signal
조율: 셸 스크립트 (폴링)
시각화: cmux 사이드바 + 알림 + 브라우저
```

- 각 에이전트가 **완전히 독립된 OS 프로세스**
- 사이드바에 실시간 진행률/상태 표시
- macOS 알림으로 완료 통보
- 셸 스크립트 작성 필요 (오케스트레이션 로직)
- read-screen 폴링으로 완료 감지 (마커 또는 파일 체크)

---

## 각 방식이 더 나은 경우

### Agent Teams가 더 나은 경우

- **같은 레포 안에서 협업** — 코드 수정 + 리뷰 + 테스트를 한 팀으로
- **태스크 간 의존성** — "A 끝나면 B 시작" 같은 체인을 TaskUpdate로 관리
- **메시지 기반 소통** — 에이전트끼리 SendMessage로 직접 대화
- **별도 코드 불필요** — 도구 호출만으로 팀 운영
- **worktree 격리** — `isolation: "worktree"`로 git worktree 자동 생성

### cmux Orchestration이 더 나은 경우

- **브라우저 + 에이전트 혼합** — 코드 수정 후 브라우저로 시각 검증
- **실시간 대시보드** — 사이드바에 전체 상태 시각화
- **비-Claude 프로세스 포함** — 빌드 서버, 테스트 러너, DB 마이그레이션 등
- **크로스 프로젝트** — 서로 다른 레포의 작업을 하나의 파이프라인으로
- **시스템 알림** — 작업 완료/실패 시 macOS 알림
- **CCS 프로필 분산** — 다른 API 계정으로 에이전트 실행 (레이트 리밋 분산)

### 최적 조합

```
cmux (인프라 레이어)
  ├── sidebar: 전체 상태 대시보드
  ├── browser: 시각 검증
  ├── notify: 시스템 알림
  └── signal: 프로세스 간 동기화
      ↑
Agent Teams (에이전트 레이어)
  ├── TeamCreate: 팀 구성
  ├── Agent: 에이전트 스폰
  ├── TaskCreate/Update: 태스크 관리
  └── SendMessage: 에이전트 간 통신
```

---

## 삽질 기록

1. **cmux 폴링 타이밍**: claude -p 시작까지 쉘 초기화 ~5s + 실행 ~20s. 최소 30s 대기 필요.
2. **마커 오탐 (재발)**: echo 명령이 쉘에 표시되어 조기 감지. 파일 존재 체크가 더 안정적.
3. **Agent Teams + cmux**: 에이전트 스폰은 되지만 tmux 패널 시각화 안됨 (TMUX 환경변수 미설정).
