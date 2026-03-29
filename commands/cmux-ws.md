---
name: cmux-ws
description: "cmux 워크스페이스 관리 (생성/저장/세션 복원)"
argument-hint: "[new|save|resume|restart] [options]"
allowed-tools: [Bash, Read, Write]
---

# cmux-ws — 워크스페이스 관리 커맨드

`$ARGUMENTS` 값에 따라 서브커맨드를 실행합니다.

## 서브커맨드 라우팅

- **빈 값 또는 `list`**: 현재 워크스페이스 목록을 표시합니다.
- **`new`**: 새 워크스페이스를 생성합니다.
- **`save`**: 전체 워크스페이스 구성을 JSON으로 저장합니다 (full save).
- **`resume`**: 저장된 Claude Code 세션을 현재 워크스페이스에 일괄 복원합니다.
- **`restart`**: 모든 워크스페이스의 Claude Code를 일괄 exit → resume합니다.

## 실행 방법

모든 핵심 로직은 `${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh`에 있습니다.

### list (기본)

```bash
bash -c 'source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh" && cmux_ws_list'
```

현재 열려있는 모든 워크스페이스의 이름, UUID, cwd를 표로 출력합니다.

### new

사용자에게 다음을 확인합니다:
- **name** (필수): 워크스페이스 이름
- **path** (필수): 작업 디렉토리 경로
- **color** (선택): 상태바 색상 (기본: `#3b82f6`)
- **browser_url** (선택): 브라우저 패널을 함께 열 URL

```bash
bash -c 'source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh" && cmux_ws_new "<name>" "<path>" "<color>" "<browser_url>"'
```

### save

```bash
bash -c 'source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh" && cmux_ws_save'
```

`~/.config/cmux-pilot/workspaces.json`에 저장됩니다. 저장 후 내용을 사용자에게 보여줍니다.

### resume

워크스페이스의 Claude Code 세션을 일괄 resume합니다. cmux가 워크스페이스를 자체적으로 복원하므로, 세션만 복원하면 됩니다.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-resume.sh"
```

이름 기반으로 현재 워크스페이스와 저장된 세션을 매칭합니다. 세션 신선도를 검증하고 (1h: 즉시, 24h: 시도, 24h+: 건너뜀), 셸 프롬프트를 확인한 후 `claude --resume` 명령을 전송합니다.

```bash
# dry-run (실행 안 함, 매칭 결과만 표시)
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-resume.sh" --dry-run

# 만료된 세션도 강제 resume
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-resume.sh" --force
```

### restart

모든 워크스페이스의 Claude Code 세션을 일괄 종료 후 동일 세션으로 재시작합니다.

```bash
# 대상 확인 (실행 안 함)
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-restart.sh" --dry-run

# 특정 워크스페이스만
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-restart.sh" --workspace workspace:5

# 전체 재시작
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-restart.sh"
```

흐름: full save → Claude Code surface 감지 → `/exit` 전송 → 종료 확인 → `claude --resume` 전송 → 시작 확인. 사이드바에 진행 상태가 표시됩니다.

## 자동 동기화

수동으로 autosave를 관리할 필요 없습니다. 훅이 자동으로 처리합니다:

- **SessionStart**: session-map.jsonl에 세션 매핑 기록
- **UserPromptSubmit**: 호출자 워크스페이스 cwd 갱신 + workspaces.json 동기화
- **Stop**: session_active heartbeat 기록 (세션 신선도 추적)

## 주의사항

- cmux가 실행 중이어야 합니다 (`/tmp/cmux.sock` 존재 확인)
- cmux가 워크스페이스를 자체적으로 persist하므로 restore는 불필요 (세션만 resume)
- save 시 현재 활성 워크스페이스의 모든 패널 구성이 저장됩니다
- 세션 매핑은 `~/.config/cmux-pilot/session-map.jsonl`에 append-only로 기록됩니다
