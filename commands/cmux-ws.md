---
name: cmux-ws
description: "cmux 워크스페이스 관리 (생성/저장/복원)"
argument-hint: "[new|save|restore|autosave] [options]"
allowed-tools: [Bash, Read, Write]
---

# cmux-ws — 워크스페이스 관리 커맨드

`$ARGUMENTS` 값에 따라 서브커맨드를 실행합니다.

## 서브커맨드 라우팅

- **빈 값 또는 `list`**: 현재 워크스페이스 목록을 표시합니다.
- **`new`**: 새 워크스페이스를 생성합니다.
- **`save`**: 전체 워크스페이스 구성을 JSON으로 저장합니다.
- **`restore`**: JSON에서 워크스페이스를 복원합니다.
- **`autosave`**, **`autosave install`**, **`autosave uninstall`**: 자동 저장 cron 관리.

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

### restore

```bash
bash -c 'source "${CLAUDE_PLUGIN_ROOT}/lib/cmux-ws-manager.sh" && cmux_ws_restore'
```

저장된 JSON에서 워크스페이스를 재생성합니다. 복원 전 현재 상태와 차이를 보여주고 확인을 받습니다.

### autosave

자동 저장 cron을 관리합니다.

```bash
# 상태 확인
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-autosave-cron.sh" status

# 등록 (15분마다, 변경 시에만 저장)
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-autosave-cron.sh" install

# 해제
bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/cmux-autosave-cron.sh" uninstall
```

## 주의사항

- cmux가 실행 중이어야 합니다 (`/tmp/cmux.sock` 존재 확인)
- restore는 기존 워크스페이스를 건드리지 않고 추가 생성합니다
- save 시 현재 활성 워크스페이스의 모든 패널 구성이 저장됩니다
- save 시 Claude Code 세션도 cwd 기반으로 매칭하여 저장됩니다
- restore 후 Claude Code 세션은 안내된 명령어로 수동 복원합니다
