#!/bin/bash
# ClaudePet 설치 도우미
# 이 파일을 더블클릭하면 자동으로 설정됩니다.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/ClaudePet.app"

echo ""
echo "  ▐▛███▜▌    ClaudePet Setup"
echo " ▝▜█████▛▘"
echo "   ▘▘ ▝▝"
echo ""

if [ ! -d "$APP_PATH" ]; then
    echo "❌ ClaudePet.app을 찾을 수 없습니다."
    echo "   이 파일과 같은 폴더에 ClaudePet.app이 있어야 합니다."
    echo ""
    read -p "아무 키나 누르면 종료합니다..." -n 1
    exit 1
fi

echo "✅ ClaudePet.app 발견"
echo "🔧 보안 설정 해제 중..."

xattr -cr "$APP_PATH"

echo "🚀 ClaudePet 실행 중..."
open "$APP_PATH"

echo ""
echo "✅ 완료! ClaudePet이 실행되었습니다."
echo "   메뉴바의 🐛 아이콘을 확인하세요."
echo ""
echo "   다음부터는 ClaudePet.app을 바로 더블클릭하면 됩니다."
echo ""
read -p "아무 키나 누르면 이 창을 닫습니다..." -n 1
