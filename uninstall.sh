#!/bin/bash
set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

APP_BUNDLE="$HOME/Applications/ClaudePet.app"
HOOK_FILE="$HOME/.claude/hooks/claudepet-hook.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo -e "${BOLD}ClaudePet 제거 중...${NC}"

# 실행 중인 프로세스 종료
pkill -f "ClaudePet" 2>/dev/null && echo "  프로세스 종료" || true

# .app 번들 삭제
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
    echo "  $APP_BUNDLE 삭제"
fi

# Hook 스크립트 삭제
if [ -f "$HOOK_FILE" ]; then
    rm -f "$HOOK_FILE"
    echo "  Hook 스크립트 삭제"
fi

# settings.json에서 hook 제거
if [ -f "$SETTINGS_FILE" ] && grep -q "claudepet-hook.sh" "$SETTINGS_FILE"; then
    python3 << 'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")

with open(settings_path, 'r') as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
for event in list(hooks.keys()):
    for group in hooks[event]:
        if "hooks" in group:
            group["hooks"] = [h for h in group["hooks"] if "claudepet-hook.sh" not in h.get("command", "")]
            if not group["hooks"]:
                hooks[event] = [g for g in hooks[event] if g != group]
    if not hooks[event]:
        del hooks[event]

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("  settings.json에서 hook 제거")
PYEOF
fi

# 상태 파일 정리
rm -f /tmp/claudepet-*.json 2>/dev/null && echo "  상태 파일 정리" || true

echo -e "${GREEN}ClaudePet이 완전히 제거되었습니다!${NC}"
