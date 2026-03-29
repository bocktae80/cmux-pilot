# 프로젝트 로드맵

> 최종 갱신: 2026-03-10

---

## 현재 마일스톤

### M1: 초기 설정 (2026-03-10)

**목표:** 프로젝트 기본 구조 확립

| 항목 | 상태 | 비고 |
|------|------|------|
| 워크북 초기화 | 완료 | /wb-admin init 실행 |
| 프로젝트 규칙 설정 | 대기 | 워크스페이스 규칙 오버라이드 |
| 첫 세션 완주 | 대기 | /wb-session → /wb-session end |

---

### M2: 세션 매핑 (2026-03-17)

**목표:** cmux 크래시 후 Claude Code 세션 정확 복원

| 항목 | 상태 | 비고 |
|------|------|------|
| SessionStart hook 세션 매핑 기록 | 완료 | session-map.jsonl append-only |
| save 매핑 활용 (UUID 정확 매칭 + 이름 유추 fallback) | 완료 | workspace UUID → surface별 최신 세션 |
| restore 다중 세션 자동 resume | 완료 | claude_sessions 배열 → surface별 send-keys |
| cmux-ws-resume.sh 일괄 복원 | 완료 | 독립 스크립트, 이름 기반 매칭 |
| SKILL.md 세션 매핑 반영 | 완료 | description 개선 + 이벨 |
| 커맨드/문서 업데이트 | 완료 | cmux-ws.md, CLAUDE.md |

---

### M3: 빈틈없는 동기화 + 자동 업데이트 (2026-03-29)

**목표:** 워크스페이스-세션 동기화 전면 개선, 플러그인 자동 배포

| ID | 항목 | 상태 | 비고 |
|----|------|------|------|
| M3-01 | session-map 레코드 타입 (session_start/session_active) | 완료 | 하위호환 유지 |
| M3-02 | autosave 훅 등록 + 호출자 cwd 실시간 반영 | 완료 | UserPromptSubmit, sidebar-state 1회 |
| M3-03 | Stop 훅 heartbeat (세션 종료 추정) | 완료 | session_active 레코드 |
| M3-04 | resume 신선도 검증 + 셸 프롬프트 확인 | 완료 | 1h/24h/expired, --force 옵션 |
| M3-05 | cmux_ws_new() 즉시 workspaces.json 반영 | 완료 | incremental append |
| M3-06 | restore workspace_restored 레코드 + 즉시 full save | 완료 | old→new UUID 매핑 |
| M3-07 | 플러그인 자동 업데이트 (SessionStart, 하루 1번 git pull) | 완료 | 백그라운드, ff-only |
| M3-08 | marketplace 배포 (git push → pull) | 완료 | 심링크 → git clone 정상화 |
| M3-09 | E2E 테스트 (5개 워크스페이스, 멀티 세션) | 완료 | 3세션/워크스페이스 검증 |

---

## 백로그

_백로그 항목이 없습니다._
