#!/bin/bash
set -e

# ============================================
#  ClaudePet Installer
#  Dock 위를 돌아다니는 Claude 캐릭터!
# ============================================

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

APP_NAME="ClaudePet"
APP_DIR="$HOME/Applications"
APP_BUNDLE="$APP_DIR/$APP_NAME.app"
HOOK_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BOLD}"
echo '  ▐▛███▜▌    ClaudePet Installer'
echo ' ▝▜█████▛▘   Dock 위의 Claude 친구!'
echo '   ▘▘ ▝▝'
echo -e "${NC}"

# ---- 1. Prerequisites ----
echo -e "${BOLD}[1/5] 환경 확인...${NC}"

if ! command -v swift &> /dev/null; then
    echo -e "${YELLOW}Swift가 없습니다. Xcode Command Line Tools를 설치합니다...${NC}"
    echo "  설치 팝업이 뜨면 '설치' 버튼을 눌러주세요!"
    echo ""
    xcode-select --install 2>/dev/null

    # 설치 완료 대기
    echo -e "${YELLOW}  설치가 완료될 때까지 기다리는 중...${NC}"
    until command -v swift &> /dev/null; do
        sleep 5
    done
    echo -e "${GREEN}  Xcode Command Line Tools 설치 완료!${NC}"
fi

if ! command -v claude &> /dev/null; then
    echo -e "${YELLOW}경고: Claude Code CLI가 감지되지 않았습니다.${NC}"
    echo "  ClaudePet은 Claude Code 없이도 실행 가능하지만, 연동 기능이 제한됩니다."
fi

echo -e "${GREEN}  Swift $(swift --version 2>&1 | head -1 | grep -o 'version [0-9.]*')${NC}"

# ---- 2. Build ----
echo -e "${BOLD}[2/5] 빌드 중...${NC}"
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | tail -1
echo -e "${GREEN}  빌드 완료!${NC}"

# ---- 3. Create .app bundle ----
echo -e "${BOLD}[3/5] .app 번들 생성...${NC}"

mkdir -p "$APP_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary 복사
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist
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

echo -e "${GREEN}  $APP_BUNDLE 생성 완료!${NC}"

# ---- 4. Install Hook ----
echo -e "${BOLD}[4/5] Claude Code Hook 설정...${NC}"

mkdir -p "$HOOK_DIR"

# Hook 스크립트 설치
cat > "$HOOK_DIR/claudepet-hook.sh" << 'HOOKSCRIPT'
#!/bin/bash
EVENT="$1"
cat | python3 -c "
import json, time, os, sys

event = '$EVENT'
ts = int(time.time())

try:
    data = json.load(sys.stdin)
except:
    data = {}

session_id = data.get('session_id', 'unknown')
cwd = data.get('cwd', '')
tool = data.get('tool_name', 'none')

status_file = f'/tmp/claudepet-{session_id}.json'

if event == 'SessionEnd':
    try:
        os.remove(status_file)
    except:
        pass
else:
    status = {
        'status': event,
        'tool': tool,
        'cwd': cwd,
        'session_id': session_id,
        'ts': ts
    }
    with open(status_file, 'w') as f:
        json.dump(status, f)
" 2>/dev/null
HOOKSCRIPT
chmod +x "$HOOK_DIR/claudepet-hook.sh"

# settings.json에 hook 추가
if [ -f "$SETTINGS_FILE" ]; then
    # 이미 claudepet-hook이 설정되어 있으면 스킵
    if grep -q "claudepet-hook.sh" "$SETTINGS_FILE"; then
        echo -e "${YELLOW}  Hook이 이미 설정되어 있습니다. 스킵!${NC}"
    else
        # Python으로 안전하게 JSON 수정
        python3 << 'PYEOF'
import json, sys, copy

settings_path = sys.argv[1] if len(sys.argv) > 1 else ""
import os
settings_path = os.path.expanduser("~/.claude/settings.json")

with open(settings_path, 'r') as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# 추가할 이벤트 목록
events_with_matcher = ["PreToolUse", "PostToolUse", "PermissionRequest"]
events_without_matcher = ["SessionStart", "SessionEnd", "Stop", "SubagentStop", "UserPromptSubmit"]

for event in events_with_matcher:
    hook_entry = {
        "type": "command",
        "command": f"~/.claude/hooks/claudepet-hook.sh {event}"
    }
    if event in hooks:
        for group in hooks[event]:
            if "hooks" in group:
                # 중복 확인
                existing = [h["command"] for h in group["hooks"] if "command" in h]
                if hook_entry["command"] not in existing:
                    group["hooks"].append(hook_entry)
            break
    else:
        hooks[event] = [{"matcher": "*", "hooks": [hook_entry]}]

for event in events_without_matcher:
    hook_entry = {
        "type": "command",
        "command": f"~/.claude/hooks/claudepet-hook.sh {event}"
    }
    if event in hooks:
        for group in hooks[event]:
            if "hooks" in group:
                existing = [h["command"] for h in group["hooks"] if "command" in h]
                if hook_entry["command"] not in existing:
                    group["hooks"].append(hook_entry)
            break
    else:
        hooks[event] = [{"hooks": [hook_entry]}]

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("  Hook 설정 완료!")
PYEOF
    fi
else
    # settings.json이 없으면 새로 생성
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    python3 << 'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
hooks = {}

events_with_matcher = ["PreToolUse", "PostToolUse", "PermissionRequest"]
events_without_matcher = ["SessionStart", "SessionEnd", "Stop", "SubagentStop", "UserPromptSubmit"]

for event in events_with_matcher:
    hooks[event] = [{"matcher": "*", "hooks": [{"type": "command", "command": f"~/.claude/hooks/claudepet-hook.sh {event}"}]}]

for event in events_without_matcher:
    hooks[event] = [{"hooks": [{"type": "command", "command": f"~/.claude/hooks/claudepet-hook.sh {event}"}]}]

settings = {"hooks": hooks}

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("  새 settings.json 생성 완료!")
PYEOF
fi

echo -e "${GREEN}  Hook 설정 완료!${NC}"

# ---- 5. Done ----
echo -e "${BOLD}[5/5] 설치 완료!${NC}"
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ClaudePet이 설치되었습니다!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  실행 방법:"
echo "    open $APP_BUNDLE"
echo ""
echo "  또는 터미널에서:"
echo "    $APP_BUNDLE/Contents/MacOS/ClaudePet"
echo ""
echo "  종료: 메뉴바의 🐛 아이콘 > 종료"
echo ""

# 바로 실행할지 묻기
read -p "  지금 바로 실행할까요? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "$APP_BUNDLE"
    echo -e "${GREEN}  ClaudePet이 시작되었습니다!${NC}"
fi
