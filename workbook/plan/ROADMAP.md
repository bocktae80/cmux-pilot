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

## 백로그

_백로그 항목이 없습니다._
