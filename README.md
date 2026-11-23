# ClaudePet

```
 ▐▛███▜▌
▝▜█████▛▘
  ▘▘ ▝▝
```

데스크탑 위를 돌아다니는 Claude 펫! 🐛

Claude Code / Desktop과 실시간 연동되어 작업 상태를 알려주고, 가끔 말도 걸어줍니다.

**macOS** (Dock 위) / **Windows** (작업 표시줄 위) 둘 다 지원해요.

**[홈페이지](https://devthekiwi.github.io/ClaudePet/)**

---

## 🍎 macOS 설치

```bash
curl -sL https://raw.githubusercontent.com/devTheKiwi/ClaudePet/main/remote-install.sh | bash
```
터미널에 붙여넣기 한 줄이면 끝! (빌드 + 설치 + Hook 설정 + 자동 시작 전부 자동)

### Requirements
- macOS 13.0+
- Apple Silicon

### Uninstall
```bash
pkill -f ClaudePet
rm -rf ~/Applications/ClaudePet.app
rm -f ~/.claude/hooks/claudepet-hook.sh
rm -f ~/Library/LaunchAgents/com.claudepet.app.plist
rm -f ~/.claudepet/state.json ~/.claudepet/state.json.tmp
rmdir ~/.claudepet 2>/dev/null   # 비어 있을 때만 지워져요
```

---

### 글 쓰는 자리에서 투명해지기 (손쉬운 사용 권한)

펫 배치 메뉴의 "글 쓰는 자리에서 투명해지기"를 켜면, 글자 커서가 있는 줄을 가린 펫이 투명해집니다. 기본은 꺼짐입니다.

- 이 기능은 macOS **손쉬운 사용** 권한을 씁니다. 권한 안내 창은 이 항목을 켤 때만 뜹니다.
- 읽는 것은 글자 커서의 화면 위치뿐이고, 입력한 글 내용은 읽지 않습니다. 비밀번호 칸에서는 위치도 묻지 않습니다.
- Electron 앱은 요청이 있어야 글자 위치를 알려 주므로, 글 입력 칸에서 위치를 못 읽는 동안 맨 앞 앱에 `AXManualAccessibility` 를 설정합니다(5초에 한 번, 되돌리지 않음).
- 앱을 다시 설치하거나 업데이트해서 실행 파일이 바뀌면 권한을 다시 허용해야 할 수 있습니다. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 예전 ClaudePet 항목을 `−` 로 지운 뒤 다시 추가하세요.
- 기능을 끈 뒤 권한까지 거두려면 시스템 설정에서 끄거나 `tccutil reset Accessibility com.claudepet.app` 을 실행하세요.

---

## 🪟 Windows 설치

**다운로드 (추천)**

[📥 ClaudePet 최신 버전 다운로드](https://github.com/devTheKiwi/ClaudePet/releases/latest)

위 링크에서 `ClaudePet.Setup.X.Y.Z.exe` 받고 더블클릭 → 설치 마법사 진행 → 끝!
시작 메뉴 등록, 자동 시작, Claude Code 연동까지 모두 자동입니다.

> SmartScreen 경고가 뜨면 "자세히 → 실행" 을 눌러주세요. (코드 사인은 아직 안 했어요)

**또는 소스 빌드 (개발자용)**
```bash
git clone https://github.com/devTheKiwi/ClaudePet.git
cd ClaudePet/windows
npm install
npm start
```

자세한 빌드/구조는 [windows/README.md](windows/README.md) 참고.

### Requirements
- Windows 10 (1809+) / Windows 11
- 별도 의존성 없음 (Electron + Chromium 번들)

### Uninstall
시작 → **앱** → **설치된 앱** → **ClaudePet** → **제거**

또는 수동으로 흔적 정리:
```bash
del "%USERPROFILE%\.claude\hooks\claudepet-hook.cmd"
del "%USERPROFILE%\.claude\hooks\claudepet-hook.ps1"
rmdir /s "%USERPROFILE%\.claudepet-windows"
```

자동 시작 등록도 같이 지우려면 컨텍스트 메뉴에서 **PC 시작 시 자동 실행** 토글을 OFF 한 다음 종료.

---

## ✨ Features

- **Claude Code 실시간 연동** — Hook 기반 작업 시작/완료/권한 요청 감지
- **Claude Desktop 지원** — Desktop 켜면 동그란 안경 쓰고 커피잔 든 펫 등장 ☕
- **토큰 사용량 추적** — 세션/일일 토큰, 캐시 절약률, 마일스톤 알림
- **도구별 상세 알림** — "명령어 실행 중...", "코드 수정 중..." 등
- **작업시간 트래커** — 초 단위 실시간 뱃지
- **스킨 시스템** — 기본 / 봄 에디션 🌸 / 여름 에디션 🍉 / 가을 에디션 🍁 (우클릭으로 시즌 변경)
- **멀티 세션** — 세션마다 랜덤 색상 캐릭터
- **등장·퇴장 장면 (macOS)** — 새 세션 감자는 땅에서 싹을 틔우고 솟아오르고, 끝난 세션 감자는 인사하고 땅속으로 들어가요 🌱
- **쉬는 펫 숨기기 (macOS)** — 오래 쉰 세션 감자는 숨었다가 다시 일하면 그대로 돌아와요 (15분·30분·1시간·2시간, 기본 2시간)
- **펫 배치 (macOS)** — 펫이 지낼 화면 고르기, 가까이 가면 투명해지기, 세션 많으면 구석에 모여 있기
- **글 쓰는 자리에서 투명해지기 (macOS)** — 글자 커서가 있는 줄을 가린 펫이 투명해져요 (기본 꺼짐, 손쉬운 사용 권한 필요)
- **상호작용** — 클릭 / 더블클릭 / 드래그 / 우클릭 메뉴
- **세션 창으로 가기 (macOS)** — 펫을 더블클릭하면 그 세션이 열린 Orca·터미널·iTerm2 탭이나 Claude Desktop 세션으로 이동
- **자동 업데이트 알림** — 새 버전 나오면 말풍선 + 아이콘 배지 🎉로 알려줌
- **PC 시작 시 자동 실행**
- **상태 파일 내보내기 (macOS)** — 펫과 같은 세션 상태를 `~/.claudepet/state.json`에 써서 위젯·장비 같은 다른 프로그램이 읽을 수 있어요 ([형식](#-상태-파일-macos))

## 📄 상태 파일 (macOS)

ClaudePet이 화면의 펫과 같은 세션 상태를 `~/.claudepet/state.json`에 써 둡니다. 다른 프로그램은 이 파일만 읽으면 돼요.

```json
{
  "version": 1,
  "updated_at": 1763540000,
  "today_minutes": 312,
  "sessions": [
    { "id": "0b5e…", "status": "working", "project": "my-app", "tool": "Bash", "updated_at": 1763539990 },
    { "id": "41e9…", "status": "waiting_permission", "project": "web", "tool": "Edit", "updated_at": 1763539950 }
  ]
}
```

| 값 | 뜻 |
|---|---|
| `version` | 형식 버전 (지금은 `1`) |
| `updated_at` | 파일을 쓴 시각 (유닉스 초) |
| `today_minutes` | 오늘 작업시간 (분, 메뉴의 "오늘 작업"과 같은 값) |
| `sessions[].id` | Claude Code 세션 ID |
| `sessions[].status` | `working` · `waiting_permission` · `idle` |
| `sessions[].project` | 작업 폴더 이름 (전체 경로는 넣지 않아요) |
| `sessions[].tool` | 마지막으로 쓴 도구 이름, 없으면 `""` |
| `sessions[].updated_at` | 그 세션의 마지막 훅 이벤트 시각 (유닉스 초) |

- **들어가는 세션**: 화면에 펫이 있는 Claude Code 세션만 들어가요. 기본 펫, Desktop 펫, 숨은(오래 쉰) 세션, 시작만 하고 요청이 없던 세션은 빠져요. 세션이 없으면 `sessions`는 빈 배열이에요.
- **갱신 주기**: 내용이 바뀌면 2초 안에, 바뀌지 않아도 10초마다 다시 써요.
- **오래된 파일**: ClaudePet이 꺼지면 파일은 마지막 상태로 남아요. `updated_at`이 30초 넘게 지났으면 앱이 꺼진 것으로 보면 돼요.
- 임시 파일에 쓴 뒤 이름을 바꾸기 때문에 반쯤 쓴 파일을 읽을 일은 없어요. 파일은 본인만 읽을 수 있게(`600`) 만들어져요.

## License

[MIT](LICENSE)
