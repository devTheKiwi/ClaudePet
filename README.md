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

**Homebrew (추천)**
```bash
brew tap devTheKiwi/claudepet && brew install --cask claudepet
```

**또는 소스 빌드**
```bash
curl -sL https://raw.githubusercontent.com/devTheKiwi/ClaudePet/main/remote-install.sh | bash
```

### Requirements
- macOS 13.0+
- Apple Silicon

### Uninstall
```bash
brew uninstall --cask claudepet
```

또는 수동:
```bash
pkill -f ClaudePet
rm -rf ~/Applications/ClaudePet.app
rm -f ~/.claude/hooks/claudepet-hook.sh
rm -f ~/Library/LaunchAgents/com.claudepet.app.plist
```

---

## 🪟 Windows 설치

> 윈도우 버전은 현재 로컬 빌드만 지원합니다. 곧 설치 파일(.exe) 형태로도 배포할 예정이에요.

**로컬 빌드 (Node.js 18+ 필요)**
```bash
git clone https://github.com/devTheKiwi/ClaudePet.git
cd ClaudePet/windows
npm install
npm start
```

자세한 내용은 [windows/README.md](windows/README.md) 참고.

### Requirements
- Windows 10 (1809+) / Windows 11
- Node.js 18 이상 (빌드 시에만 필요)
- PowerShell 5.1+ (Windows 기본 내장)

### Uninstall
```bash
# Claude Code 연동 해제
del "%USERPROFILE%\.claude\hooks\claudepet-hook.cmd"
del "%USERPROFILE%\.claude\hooks\claudepet-hook.ps1"

# 사용자 데이터 (시간 트래킹, 설정) 제거
rmdir /s "%USERPROFILE%\.claudepet-windows"
```

자동 시작 등록도 같이 지우려면 컨텍스트 메뉴에서 **PC 시작 시 자동 실행** 토글을 OFF 한 다음 종료.

---

## ✨ Features

- **Claude Code 실시간 연동** — Hook 기반 작업 시작/완료/권한 요청 감지
- **Claude Desktop 지원** — Desktop 켜면 커피잔 든 펫 등장 ☕
- **토큰 사용량 추적** — 세션/일일 토큰, 캐시 절약률, 마일스톤 알림
- **도구별 상세 알림** — "명령어 실행 중...", "코드 수정 중..." 등
- **작업시간 트래커** — 초 단위 실시간 뱃지
- **스킨 시스템** — 기본 / 봄 에디션 🌸
- **멀티 세션** — 세션마다 랜덤 색상 캐릭터
- **상호작용** — 클릭 / 더블클릭 / 드래그 / 우클릭 메뉴
- **자동 업데이트 알림** — 새 버전 나오면 Pet이 알려줌
- **PC 시작 시 자동 실행**

## License

MIT
