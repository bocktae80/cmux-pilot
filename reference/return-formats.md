# cmux Return Format Reference

> 실제 실행으로 확인한 반환값 포맷 (2026-03-07)

## 패턴 요약

| 명령 | 반환 포맷 | 파싱 키 |
|------|----------|---------|
| `new-workspace` | `OK <UUID>` | UUID 추출 |
| `browser open` | `OK surface=surface:N pane=pane:N placement=split` | `surface:N` 추출 |
| `rename-workspace` | `OK workspace:N` | ref 반환 |
| `close-workspace` | `OK workspace:N` | ref 반환 |
| `close-surface` | `OK surface:N workspace:N` | ref 반환 |
| `set-status/progress/log` | `OK` | 성공 확인만 |
| `notify` | `OK` | 성공 확인만 |
| `wait-for -S` | `OK` | 성공 확인만 |
| `read-screen` | 터미널 텍스트 (raw) | 줄 단위 파싱 |
| `identify` | JSON | jq 파싱 |
| `list-workspaces` | 텍스트 목록, `*`=selected | grep/awk |

## 상세

### new-workspace

```
$ cmux new-workspace --command "sleep 1"
OK 07BD2D68-5784-4009-94AC-84D99284F6B3
```

- 반환: `OK <UUID>`
- UUID로 직접 참조 가능, 또는 `list-workspaces`로 `workspace:N` ref 확인
- `--command` 플래그만 지원 (`--json` 없음)

### browser open

```
$ cmux browser open "about:blank"
OK surface=surface:8 pane=pane:8 placement=split
```

- key=value 포맷
- surface ref: `grep -o 'surface:[0-9]*'`

### list-workspaces

```
$ cmux list-workspaces
  workspace:1  work
  workspace:2  cc-project
* workspace:3  poly  [selected]
  workspace:4  ~/Work
```

- `*` prefix = 현재 선택된 워크스페이스
- `[selected]` suffix
- 컬럼: (선택마크) ref title [tag]

### read-screen

```
$ cmux read-screen --workspace "workspace:6" --lines 3
Last login: Fri Mar  6 23:59:31 on ttys019
kent@Kent-MacBook-M4-Pro camfit-cpf % sleep 1
kent@Kent-MacBook-M4-Pro camfit-cpf %
```

- raw 터미널 출력 (ANSI escape 포함 가능)
- `--lines N`: 마지막 N줄
- `--scrollback`: 스크롤백 버퍼 포함

### sidebar-state

```
$ cmux sidebar-state
tab=595818C7-...
cwd=/Users/kent/Work
focused_cwd=/Users/kent/Work
git_branch=none
progress=0.50 demo: 50%
status_count=2
  demo=testing color=#3b82f6
  claude_code=Needs input icon=bell.fill color=#4C8DFF
log_count=2
  [info] hello from claude
  [info] S6 sidebar works
```

- key=value 포맷
- status/log는 들여쓰기된 하위 항목

### identify

```json
{
  "socket_path": "/tmp/cmux.sock",
  "caller": {
    "surface_ref": "surface:1",
    "surface_type": "terminal",
    "workspace_ref": "workspace:1",
    "pane_ref": "pane:1",
    "tab_ref": "tab:1",
    "window_ref": "window:1",
    "is_browser_surface": false
  },
  "focused": { ... }
}
```

- JSON 출력 (유일하게 구조화된 출력)
- `--json` 플래그가 아닌 기본 출력이 JSON
