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

if ! command -v swift &> /dev/null; then
    echo -e "${RED}Swift가 설치되어 있지 않습니다.${NC}"
    echo "  아래 명령어로 Xcode Command Line Tools를 먼저 설치해주세요:"
    echo ""
    echo "    xcode-select --install"
    echo ""
    echo "  설치 후 이 명령어를 다시 실행해주세요."
    rm -rf "$TMP_DIR"
    exit 1
fi
echo -e "${GREEN}  Swift OK${NC}"

if ! command -v git &> /dev/null; then
    echo -e "${RED}git이 설치되어 있지 않습니다.${NC}"
    echo "  xcode-select --install 로 설치해주세요."
    rm -rf "$TMP_DIR"
    exit 1
fi
echo -e "${GREEN}  Git OK${NC}"

# ---- 2. Clone & Build ----
echo -e "${BOLD}[2/4] 다운로드 및 빌드 중...${NC}"
git clone --depth 1 --quiet "$REPO" "$TMP_DIR/ClaudePet"
cd "$TMP_DIR/ClaudePet"
swift build -c release 2>&1 | tail -1
echo -e "${GREEN}  빌드 완료!${NC}"

# ---- 3. Create .app bundle ----
echo -e "${BOLD}[3/4] 앱 설치 중...${NC}"

mkdir -p "$APP_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/ClaudePet" "$APP_BUNDLE/Contents/MacOS/ClaudePet"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
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
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
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

# ---- 4. Cleanup & Launch ----
echo -e "${BOLD}[4/4] 정리 및 실행...${NC}"
rm -rf "$TMP_DIR"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ClaudePet 설치 완료!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  실행: open ~/Applications/ClaudePet.app"
echo "  종료: 메뉴바 🐛 > 종료"
echo ""

open "$APP_BUNDLE"
echo -e "${GREEN}  ClaudePet이 시작되었습니다!${NC}"
echo "  첫 실행 시 Claude Code 연동 팝업이 뜹니다."
