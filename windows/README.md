# ClaudePet for Windows

Windows 작업 표시줄 위를 돌아다니는 Claude 펫. macOS 버전(`../`)의 기능을 100% 동일하게 포팅했습니다.

> macOS 버전은 Swift + Cocoa, Windows 버전은 Electron + TypeScript 기반입니다. 맥 사용자에게는 영향 없이 윈도우 코드만 이 폴더에 격리되어 있어요.

## Requirements

- Windows 10 (1809 이상) / Windows 11
- Node.js 18 이상
- PowerShell 5.1+ (Windows 기본 내장)

## 빌드 & 실행

```bash
npm install
npm start
```

`npm start` 는 TypeScript 컴파일 + HTML 복사 + Electron 실행을 한 번에 처리합니다.

### 빌드만 (실행 안 함)
```bash
npm run build
```

산출물:
- `dist/main/` — main 프로세스 (CommonJS)
- `dist/preload/` — preload 스크립트
- `dist/renderer/` — renderer 프로세스 (ES2022 모듈) + HTML

### 인스톨러 (.exe) 패키징
```bash
npm run dist
```
NSIS 인스톨러가 `release/` 폴더에 생성됩니다. (배포는 미정)

---

## 첫 실행

처음 실행 시:

1. 펫이 작업 표시줄 가운데 위쪽에 등장
2. 시스템 트레이에 ClaudePet 아이콘 추가
3. **Claude Code 연동 다이얼로그** 가 떠요 — "연동하기" 선택 시:
   - `~/.claude/hooks/claudepet-hook.cmd` (cmd 래퍼) 생성
   - `~/.claude/hooks/claudepet-hook.ps1` (PowerShell 본체) 생성
   - `~/.claude/settings.json` 의 `hooks` 섹션에 자동 등록
4. **PC 시작 시 자동 실행**이 기본 ON (레지스트리 `Run` 키)

---

## 사용법

| 동작 | 결과 |
|---|---|
| 좌클릭 | 펫이 말풍선으로 답함 |
| 더블클릭 | 점프 (`우왕! 신난다~!`) |
| 드래그 | 자유롭게 이동 (다음 자동 행동에 작업표시줄로 복귀) |
| 우클릭 | 컨텍스트 메뉴 (세션/시간/토큰/스킨/자동시작/종료) |
| 트레이 우클릭 | 전체 세션 목록 + 종료 |

---

## 아키텍처

```
src/
├── main/                       Electron 메인 프로세스
│   ├── main.ts                  진입점 (단일 인스턴스 강제 + crash 핸들러)
│   ├── app.ts                   세션 오케스트레이션 (AppDelegate.swift 포팅)
│   ├── pet-window.ts            펫 BrowserWindow (transparent / always-on-top / 드래그)
│   ├── bubble-window.ts         말풍선 BrowserWindow (페이드 / 펫 따라다니기)
│   ├── claude-monitor.ts        %TEMP%\claudepet-*.json polling
│   ├── hook-setup.ts            PowerShell hook 자동 설치
│   ├── token-tracker.ts         ~/.claude/projects/**/*.jsonl 파싱
│   ├── time-tracker.ts          작업 시간 누적 + 사용자 설정
│   ├── update-checker.ts        GitHub Releases 체크
│   ├── tray-manager.ts          시스템 트레이
│   ├── icon-gen.ts              트레이 아이콘 PNG 동적 생성 (32x32 안티앨리어싱)
│   └── logger.ts                파일 로거 (~/.claudepet-windows/app.log)
├── preload/                    contextBridge → renderer 안전 IPC
│   ├── pet-preload.ts
│   └── bubble-preload.ts
└── renderer/                   Chromium renderer (Canvas 드로잉)
    ├── pet.html / pet.ts        PetView.swift draw() 1:1 포팅
    └── bubble.html / bubble.ts  SpeechBubbleView.swift 포팅
```

### 주요 포팅 결정

| Cocoa | Electron | 메모 |
|---|---|---|
| `NSWindow` borderless + floating | `BrowserWindow { transparent, frame:false, alwaysOnTop }` | 거의 1:1 대응 |
| `NSBezierPath` (Core Graphics) | HTML5 Canvas 2D | Y축이 반대라 `translate + scale(1,-1)` 로 좌표계 뒤집음 |
| `NSStatusItem` | `Tray` | 메뉴 외부 클릭으로 닫기 위해 `setFocusable(true)` 임시 토글 |
| `NSWorkspace.runningApplications` (bundleId) | PowerShell `Get-CimInstance` (ExecutablePath) | `claude.exe` 가 Code CLI 와 Desktop 둘 다 쓰는 이름이라 경로 매칭 필요 |
| `LaunchAgent .plist` | `app.setLoginItemSettings` | 레지스트리 Run 키에 등록 |
| Bash + Python3 hook | PowerShell `.ps1` + `.cmd` 래퍼 | UTF-8 BOM 회피하려고 `[System.IO.File]::WriteAllText` 사용 |

### 좌표계 변환

PetView.swift `draw()` 메서드는 Cocoa 좌표계 (origin=bottom-left, y up) 기준으로 작성되어 있습니다. Canvas 는 정반대 (origin=top-left, y down) 라서, 렌더러 시작에 다음을 적용해 좌표계를 뒤집습니다:

```ts
ctx.translate(0, H);
ctx.scale(1, -1);
// 이제 Swift draw() 코드를 1:1 로 옮길 수 있음
```

텍스트 (시간 뱃지) 만 변환 후 별도 처리.

---

## Hook 동작 원리

1. Claude Code 가 hook 이벤트 발생 시 `claudepet-hook.cmd PreToolUse` 같은 명령 실행
2. `.cmd` 래퍼가 `powershell -ExecutionPolicy Bypass -File claudepet-hook.ps1 PreToolUse` 호출
3. PowerShell 이 stdin 의 JSON 파싱 → `%TEMP%\claudepet-<sessionId>.json` 작성 (BOM 없는 UTF-8)
4. Electron 메인 프로세스가 2초마다 `%TEMP%` 폴링 → 세션 상태 동기화

`SessionEnd` 이벤트는 temp 파일을 삭제. Stale timeout (2시간) 은 Claude Code 가 비정상 종료된 경우의 안전장치.

---

## 트러블슈팅

### 펫이 안 보여요
- 시스템 트레이 (시계 옆 ^) 에 ClaudePet 아이콘 있는지 확인
- 작업 표시줄을 위쪽이 아닌 좌/우/상단으로 옮긴 경우 정상 동작 안 할 수 있음 (개선 예정)

### Claude Code 연동이 안 돼요
1. `~/.claude/hooks/claudepet-hook.cmd` 가 존재하는지 확인
2. `~/.claude/settings.json` 의 `hooks` 섹션에 `claudepet-hook.cmd` 가 등록되어 있는지 확인
3. Claude Code 를 새 터미널에서 다시 시작 (settings.json 변경은 새 세션부터 적용)

### 에러가 떴어요
- `~/.claudepet-windows/app.log` 확인 (uncaughtException 등이 자동 기록됨)
- 평소에는 로그 거의 안 쌓이고, 256KB 넘으면 자동 truncate

### Claude Desktop 펫 (커피잔) 이 안 떠요
- Claude Desktop 이 `AnthropicClaude` 폴더 (`%LOCALAPPDATA%\AnthropicClaude\` 또는 Program Files) 에 설치되어 있어야 함
- 일반 `claude.exe` (Code CLI) 와 구분하기 위해 실행 파일 경로로 매칭

---

## 사용자 데이터

| 경로 | 내용 |
|---|---|
| `~/.claude/hooks/claudepet-hook.cmd` | hook 진입점 |
| `~/.claude/hooks/claudepet-hook.ps1` | PowerShell 본체 |
| `~/.claude/settings.json` | hook 등록 (다른 도구와 공유) |
| `~/.claudepet-windows/time.json` | 오늘 작업 시간 (분 단위) |
| `~/.claudepet-windows/settings.json` | 스킨 / 시간 표시 / 자동 시작 토글 |
| `~/.claudepet-windows/app.log` | 에러 로그 (평소엔 비어있음) |
| `%TEMP%\claudepet-*.json` | 활성 세션 상태 (hook 이 작성, monitor 가 읽음) |

---

## License

MIT (macOS 버전과 동일)
