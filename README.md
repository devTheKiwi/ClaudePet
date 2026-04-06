# ClaudePet

```
 ▐▛███▜▌
▝▜█████▛▘
  ▘▘ ▝▝
```

macOS Dock 위를 돌아다니는 Claude Code 데스크탑 펫!

Claude Code와 실시간 연동되어 작업 상태를 알려주고, 가끔 말도 걸어줍니다.

## Features

- Dock 바 위에서 걸어다니는 귀여운 Claude 캐릭터
- **Claude Code 실시간 연동** (Hook 기반)
  - 작업 시작/완료 알림
  - 권한 요청 시 알림 (승인할 때까지 말풍선 유지!)
- **멀티 세션 지원** - 세션마다 다른 색상의 캐릭터 스폰
- 클릭/더블클릭/우클릭 상호작용
- 랜덤 대화 (45~90초 간격)
- 메뉴바 아이콘 (🐛)으로 세션 상태 확인

## 세션별 색상

| 순서 | 색상 |
|------|------|
| 1 | 🟠 오렌지 (기본) |
| 2 | 🔵 블루 |
| 3 | 🟢 그린 |
| 4 | 🟣 퍼플 |
| 5 | 🩷 핑크 |
| 6 | 🩵 틸 |

## Requirements

- macOS 13.0+
- Swift 5.9+ (Xcode Command Line Tools)
- Claude Code (선택사항, 연동 기능에 필요)

## Install

```bash
git clone https://github.com/YOUR_USERNAME/ClaudePet.git
cd ClaudePet
chmod +x install.sh
./install.sh
```

설치 스크립트가 자동으로:
1. Swift 프로젝트 빌드
2. `~/Applications/ClaudePet.app` 생성
3. Claude Code Hook 설정

## Manual Build

```bash
swift build -c release
.build/release/ClaudePet
```

## Run

```bash
# .app 번들로 실행
open ~/Applications/ClaudePet.app

# 또는 직접 실행
~/Applications/ClaudePet.app/Contents/MacOS/ClaudePet
```

## Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## 상호작용

| 액션 | 반응 |
|------|------|
| 클릭 | 상태에 따른 말풍선 |
| 더블클릭 | 점프! |
| 우클릭 | 상태 메뉴 |
| 드래그 | 위치 이동 |

## Claude Code 연동 구조

```
Claude Code 이벤트 발생
  → Hook 스크립트 실행 (claudepet-hook.sh)
    → /tmp/claudepet-{session_id}.json 기록
      → ClaudePet이 파일 감시
        → 캐릭터 반응!
```

## License

MIT
