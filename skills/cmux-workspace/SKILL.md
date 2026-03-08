---
name: cmux-workspace
description: "cmux 워크스페이스를 관리할 때 사용. '워크스페이스 만들어', 'workspace save', '워크스페이스 복원', 'cmux 레이아웃', '작업 환경 저장', '작업 환경 복원' 등의 키워드에 트리거."
allowed-tools: [Bash, Read, Write, Glob]
---

# cmux 워크스페이스 관리 스킬

cmux 워크스페이스를 생성, 저장, 복원하는 기능을 제공합니다.

## 핵심 스크립트

모든 워크스페이스 관리 로직은 `${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh`에 구현되어 있습니다.

## 사용 가능한 함수

### `cmux_ws_list` — 워크스페이스 목록

현재 열려있는 워크스페이스 목록을 출력합니다.

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

모든 워크스페이스 구성을 JSON으로 저장합니다.

- **output_path**: 저장 경로, 기본 `~/.config/cmux-pilot/workspaces.json`

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh"
cmux_ws_save
```

### `cmux_ws_restore [input_path]` — 워크스페이스 복원

저장된 JSON에서 워크스페이스를 재생성합니다.

- **input_path**: 불러올 경로, 기본 `~/.config/cmux-pilot/workspaces.json`

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh"
cmux_ws_restore
```

## JSON 스키마

저장/복원에 사용되는 JSON 형식:

```json
{
  "version": 1,
  "saved_at": "2026-03-09T12:00:00+09:00",
  "workspaces": [
    {
      "name": "camfit",
      "cwd": "/Users/kent/Work/camfit",
      "color": "#22c55e",
      "status": [
        { "key": "project", "value": "camfit", "color": "#22c55e" }
      ],
      "panels": [
        { "type": "terminal", "focused": true },
        { "type": "browser", "direction": "right", "url": "http://localhost:3000" }
      ]
    }
  ]
}
```

## cmux 주요 명령어 레퍼런스

| 명령어 | 설명 |
|--------|------|
| `cmux list-workspaces` | 전체 워크스페이스 목록 |
| `cmux new-workspace --command "cmd"` | 새 워크스페이스 (UUID 반환) |
| `cmux rename-workspace --workspace $uuid "name"` | 이름 변경 |
| `cmux close-workspace --workspace $uuid` | 워크스페이스 닫기 |
| `cmux sidebar-state --workspace $ref` | 사이드바 상태 (cwd 포함) |
| `cmux list-status --workspace $ref` | 상태 아이템 목록 |
| `cmux set-status "key" "value" --color "#hex"` | 상태 설정 |
| `cmux list-panels --workspace $ref` | 패널 구성 |
| `cmux new-pane --type browser --direction right --url "url"` | 브라우저 패널 추가 |

## 에러 핸들링

- **cmux 미설치/미실행**: `/tmp/cmux.sock` 확인 → 없으면 "cmux가 실행 중이지 않습니다" 안내
- **워크스페이스 없음**: 목록이 비어있으면 "열린 워크스페이스가 없습니다" 안내
- **restore 실패**: 개별 워크스페이스 복원 실패 시 건너뛰고 다음 진행, 마지막에 실패 목록 보고

## 기존 헬퍼 라이브러리

`${CLAUDE_PLUGIN_ROOT}/lib/cmux-helpers.sh`에 워크스페이스, 브라우저, 사이드바, 동기화 등 45개 헬퍼 함수가 있습니다. `cmux-ws-manager.sh`는 이 헬퍼를 내부적으로 활용합니다.
