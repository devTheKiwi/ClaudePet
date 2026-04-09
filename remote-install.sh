#!/bin/bash
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

REPO="https://github.com/devTheKiwi/ClaudePet.git"
TMP_DIR=$(mktemp -d)
APP_DIR="$HOME/Applications"
APP_BUNDLE="$APP_DIR/ClaudePet.app"

echo -e "${BOLD}"
echo '  ▐▛███▜▌    ClaudePet Installer'
echo ' ▝▜█████▛▘   Dock 위의 Claude 친구!'
echo '   ▘▘ ▝▝'
echo -e "${NC}"

# ---- 1. Prerequisites ----
echo -e "${BOLD}[1/4] 환경 확인...${NC}"

if ! xcode-select -p &> /dev/null; then
    echo -e "${YELLOW}  Xcode Command Line Tools 설치 중...${NC}"
    echo "  설치 팝업이 뜨면 '설치' 버튼을 눌러주세요!"
    xcode-select --install 2>/dev/null
    echo ""
    echo -e "${YELLOW}  설치가 완료될 때까지 기다리는 중...${NC}"
    until xcode-select -p &> /dev/null; do
        sleep 5
    done
    echo -e "${GREEN}  Xcode Command Line Tools 설치 완료!${NC}"
fi
echo -e "${GREEN}  Swift & Git OK${NC}"

# ---- 2. Clone & Build ----
echo -e "${BOLD}[2/5] 다운로드 중...${NC}"
git clone --depth 1 --quiet "$REPO" "$TMP_DIR/ClaudePet"
cd "$TMP_DIR/ClaudePet"
echo -e "${GREEN}  다운로드 완료!${NC}"

echo -e "${BOLD}[3/5] 빌드 중...${NC}"
swift build -c release 2>&1 | while IFS= read -r line; do
    if [[ "$line" =~ \[([0-9]+)/([0-9]+)\] ]]; then
        current="${BASH_REMATCH[1]}"
        total="${BASH_REMATCH[2]}"
        pct=$((current * 100 / total))
        filled=$((pct / 5))
        empty=$((20 - filled))
        bar=$(printf '▓%.0s' $(seq 1 $filled 2>/dev/null))
        emp=$(printf '░%.0s' $(seq 1 $empty 2>/dev/null))
        printf "\r  ${bar}${emp} ${pct}%%"
    fi
done
printf "\r  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 100%%\n"
echo -e "${GREEN}  빌드 완료!${NC}"

# ---- 4. Create .app bundle ----
echo -e "${BOLD}[4/5] 앱 설치 중...${NC}"

# git 태그에서 버전 자동 추출
APP_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")

mkdir -p "$APP_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/ClaudePet" "$APP_BUNDLE/Contents/MacOS/ClaudePet"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudePet</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudepet.app</string>
    <key>CFBundleName</key>
    <string>ClaudePet</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo -e "${GREEN}  $APP_BUNDLE 설치 완료!${NC}"

# ---- 5. 자동 시작 등록 ----
echo -e "${BOLD}[5/6] 자동 시작 등록...${NC}"

LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/com.claudepet.app.plist"
mkdir -p "$LAUNCH_AGENT_DIR"

cat > "$LAUNCH_AGENT" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claudepet.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>open</string>
        <string>${APP_BUNDLE}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST

echo -e "${GREEN}  PC 시작 시 자동 실행 등록 완료!${NC}"

# ---- 6. Cleanup & Launch ----
echo -e "${BOLD}[6/6] 정리 및 실행...${NC}"
rm -rf "$TMP_DIR"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ClaudePet 설치 완료!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  실행: open ~/Applications/ClaudePet.app"
echo "  종료: 메뉴바 🐛 > 종료"
echo "  PC 시작 시 자동 실행됩니다!"
echo ""

open "$APP_BUNDLE"
echo -e "${GREEN}  ClaudePet이 시작되었습니다!${NC}"
echo "  첫 실행 시 Claude Code 연동 팝업이 뜹니다."
