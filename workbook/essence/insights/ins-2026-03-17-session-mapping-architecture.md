---
id: "ins-session-mapping-arch"
type: insight
title: "세션 매핑 3-레이어 아키텍처"
tags: [session-mapping, cmux, architecture, M2]
source:
  type: session
maturity: draft
confidence: 0.8
linkedRules: []
scope: project
created: "2026-03-17T15:00:00+09:00"
author: "@kent"
---

# 세션 매핑 3-레이어 아키텍처

## 핵심 교훈

세션 매핑 시스템은 기록/조회/복원 3개 레이어로 분리하면 각 레이어가 독립적으로 동작하고 실패에 강해진다.

1. **기록 레이어** (SessionStart hook): JSONL append-only — 파일 잠금 불필요, hook 5초 제한 안전
2. **조회 레이어** (save): workspace UUID로 정확 매칭 → 이름 유추 fallback → 최신 파일 fallback
3. **복원 레이어** (restore/resume): `cmux send-keys`로 각 surface에 `claude --resume <full-id>` 자동 전송

## 경험 기반

- 같은 cwd에 8개 워크스페이스가 있는 환경에서 cwd 기반 매칭은 구분 불가
- JSONL append-only 선택 이유: JSON read-modify-write는 동시 쓰기 시 데이터 손실 위험
- `session_id[:8]` 축약 시 Claude Code가 선택 프롬프트를 띄워 자동화 불가 → 전체 UUID 사용

## 적용 방안

- 새로운 매핑이 필요할 때 JSONL append-only 패턴 재사용
- fallback 체인은 정확도 순서로 배치 (UUID → 이름 유추 → 최신)
- hook에서 stdin 소비 시 반드시 `INPUT=$(cat)`으로 먼저 캡처
