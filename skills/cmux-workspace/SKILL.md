---
name: cmux-workspace
description: "This skill MUST be used whenever the user wants to create, save, restore, or resume cmux workspaces, or manage Claude Code session mappings across workspaces. It provides the shell scripts and functions needed to execute these operations — without this skill, you won't know the correct commands. Triggers on: '워크스페이스 만들어', '워크스페이스 생성', '워크스페이스 저장', '워크스페이스 복원', '워크스페이스 목록', 'workspace save', 'workspace restore', 'workspace new', 'workspace list', '작업 환경 저장', '작업 환경 복원', '세션 복원', '세션 resume', '일괄 resume', '크래시 복구', 'cmux 복구', 'cmux 크래시', '자동 저장', 'autosave', '자동 저장 켜줘', '자동 저장 꺼줘', '세션 매핑', 'session-map', 'workspaces.json', '패널 레이아웃', 'cmux 레이아웃', '퇴근', '내일 복원'. Also trigger when user mentions saving/restoring their work environment before leaving, recovering after cmux crash, resuming multiple Claude Code sessions, checking session-map.jsonl, or any cmux workspace CRUD operation. NOT for: cmux sidebar status display (use cmux set-status directly), cmux browser screenshots (use cmux browser directly), cmux send-keys to specific surfaces (use cmux send-keys directly), workbook sessions (use wb-session)."
allowed-tools: [Bash, Read, Write, Glob]
---

# cmux 워크스페이스 관리 스킬

cmux 워크스페이스의 생성, 저장, 복원, 세션 매핑을 처리합니다.

## 핵심 스크립트

| 파일 | 역할 |
|------|------|
| `${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh` | save/restore/new/list 핵심 로직 |
| `${CLAUDE_PLUGIN_ROOT}/lib/cmux-helpers.sh` | cmux CLI 래퍼 (45개 헬퍼) |
| `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-resume.sh` | 세션 일괄 복원 독립 스크립트 |

## 사용 가능한 함수

### `cmux_ws_list` — 워크스페이스 목록

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh"
cmux_ws_list
```

### `cmux_ws_new <name> <path> [color] [browser_url]` — 새 워크스페이스

- **name**: 워크스페이스 이름 (필수)
- **path**: 작업 디렉토리 (필수)
- **color**: 상태바 색상, 기본 `#3b82f6` (선택)
- **browser_url**: 브라우저 패널 URL (선택)

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh"
cmux_ws_new "camfit" "/Users/kent/Work/camfit" "#22c55e" "http://localhost:3000"
```

### `cmux_ws_save [output_path]` — 워크스페이스 저장

모든 워크스페이스 구성 + Claude Code 세션 매핑을 JSON으로 저장합니다.

- **output_path**: 저장 경로, 기본 `~/.config/cmux-pilot/workspaces.json`
- 세션 매칭 우선순위: session-map.jsonl (UUID 정확 매칭) → 대화 내용 이름 유추 → 최신 파일 fallback

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh"
cmux_ws_save
```

### `cmux_ws_restore [input_path]` — 워크스페이스 복원 + 세션 자동 resume

저장된 JSON에서 워크스페이스를 재생성하고, 각 터미널에 `claude --resume`을 자동 전송합니다.

- 워크스페이스 생성 → 이름/status/panels 복원 → Claude Code 세션 자동 resume
- 다중 세션: `claude_sessions` 배열의 각 세션이 별도 surface에서 resume
- surface 부족 시 자동으로 새 터미널 패널 생성

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh"
cmux_ws_restore
```

### 세션 일괄 resume (독립 실행)

워크스페이스는 이미 있고 세션만 복원할 때 사용합니다.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-ws-resume.sh"
```

- 이름 기반으로 현재 워크스페이스와 저장된 세션을 자동 매칭
- 각 터미널에 `claude --resume <full-session-id>` 자동 전송 (사용자 개입 불필요)

## 세션 매핑 시스템

SessionStart hook이 자동으로 `{workspace_id, surface_id, session_id}` 매핑을 기록합니다.

- **매핑 파일**: `~/.config/cmux-pilot/session-map.jsonl` (append-only JSONL)
- **기록 시점**: 매 Claude Code 세션 시작 시 자동
- **복합키**: `surface_id + session_id` — 같은 surface에서 여러 세션 이력 보존

### 세션 매칭 우선순위 (save 시)

1. **session-map.jsonl**: workspace UUID로 정확 매칭 → surface별 최신 세션 수집
2. **이름 유추**: cwd의 `.jsonl` 세션 파일 대화 내용에서 워크스페이스 이름 검색 (최신순)
3. **최신 fallback**: 위 둘 다 실패 시 가장 최근 세션 파일

## JSON 스키마

```json
{
  "version": 1,
  "saved_at": "2026-03-17T12:00:00+09:00",
  "workspaces": [
    {
      "name": "camfit",
      "workspace_id": "814F6F9C-...",
      "cwd": "/Users/kent/Work/camfit",
      "status": [
        { "key": "project", "value": "camfit", "color": "#22c55e" }
      ],
      "panels": [
        { "type": "terminal", "focused": true },
        { "type": "browser", "direction": "right", "url": "http://localhost:3000" }
      ],
      "claude_sessions": [
        { "session_id": "abc12345-...", "surface_id": "D97FF2B6-...", "resume_cmd": "claude --resume abc12345-..." },
        { "session_id": "def67890-...", "surface_id": "A1B2C3D4-...", "resume_cmd": "claude --resume def67890-..." }
      ],
      "claude_session": {
        "session_id": "abc12345-...",
        "resume_cmd": "claude --resume abc12345-..."
      }
    }
  ]
}
```

- `claude_sessions` (복수): 워크스페이스의 모든 Claude Code 세션
- `claude_session` (단수): 하위호환용, 첫 번째 세션

## 자동 저장 (cron)

15분마다 워크스페이스 상태를 자동 저장합니다. 변경이 없으면 저장하지 않습니다.

```bash
# cron 등록
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-autosave-cron.sh" install

# cron 해제
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-autosave-cron.sh" uninstall

# 상태 확인
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-autosave-cron.sh" status
```

## cmux 주요 명령어 레퍼런스

| 명령어 | 설명 |
|--------|------|
| `cmux list-workspaces` | 전체 워크스페이스 목록 |
| `cmux new-workspace --command "cmd"` | 새 워크스페이스 (UUID 반환) |
| `cmux rename-workspace --workspace $uuid "name"` | 이름 변경 |
| `cmux close-workspace --workspace $uuid` | 워크스페이스 닫기 |
| `cmux sidebar-state --workspace $ref` | 사이드바 상태 (cwd, tab UUID 포함) |
| `cmux list-status --workspace $ref` | 상태 아이템 목록 |
| `cmux set-status "key" "value" --color "#hex"` | 상태 설정 |
| `cmux list-panels --workspace $ref` | 패널 구성 |
| `cmux new-pane --type terminal --workspace $ref` | 터미널 패널 추가 |
| `cmux new-pane --type browser --direction right --url "url"` | 브라우저 패널 추가 |
| `cmux send-keys --surface $ref -- "text"` | surface에 키 입력 전송 |

## 에러 핸들링

- **cmux 미설치/미실행**: `/tmp/cmux.sock` 확인 → 없으면 안내
- **워크스페이스 없음**: 목록이 비어있으면 안내
- **restore 실패**: 개별 워크스페이스 실패 시 건너뛰고 계속 진행
- **세션 매핑 없음**: fallback 체인(이름 유추 → 최신 파일)으로 자동 처리
