# ClaudePet

```
 ▐▛███▜▌
▝▜█████▛▘
  ▘▘ ▝▝
```

macOS Dock 위를 돌아다니는 Claude 데스크탑 펫!

Claude Code / Desktop과 실시간 연동되어 작업 상태를 알려주고, 가끔 말도 걸어줍니다.

**[홈페이지](https://devthekiwi.github.io/ClaudePet/)**

## Install

**Homebrew (추천)**
```bash
brew tap devTheKiwi/claudepet && brew install --cask claudepet
```

**또는 소스 빌드**
```bash
curl -sL https://raw.githubusercontent.com/devTheKiwi/ClaudePet/main/remote-install.sh | bash
```

## Features

- **Claude Code 실시간 연동** - Hook 기반 작업 시작/완료/권한 요청 감지
- **Claude Desktop 지원** - Desktop 켜면 커피잔 든 펫 등장 ☕
- **토큰 사용량 추적** - 세션/일일 토큰, 캐시 절약률, 마일스톤 알림
- **도구별 상세 알림** - "명령어 실행 중...", "코드 수정 중..." 등
- **작업시간 트래커** - 초 단위 실시간 뱃지
- **스킨 시스템** - 기본 / 봄 에디션 🌸
- **멀티 세션** - 세션마다 랜덤 색상 캐릭터
- **상호작용** - 클릭/더블클릭/우클릭
- **자동 업데이트 알림** - 새 버전 나오면 Pet이 알려줌
- **PC 시작 시 자동 실행**

## Uninstall

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

## Requirements

- macOS 13.0+
- Apple Silicon

## License

MIT
