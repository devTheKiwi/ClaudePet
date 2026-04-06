import Cocoa

class HookSetup {
    private static let hookFileName = "claudepet-hook.sh"
    private static let hookDir = NSHomeDirectory() + "/.claude/hooks"
    private static let hookPath = NSHomeDirectory() + "/.claude/hooks/claudepet-hook.sh"
    private static let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
    private static let claudeDir = NSHomeDirectory() + "/.claude"

    /// 첫 실행 시 Hook 설정 여부를 확인하고 팝업 표시
    static func checkAndPrompt() {
        // 이미 설정되어 있으면 스킵
        if FileManager.default.fileExists(atPath: hookPath) { return }

        // Claude Code가 설치되어 있지 않으면 스킵
        if !FileManager.default.fileExists(atPath: claudeDir) { return }

        // 팝업 표시
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showSetupAlert()
        }
    }

    private static func showSetupAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Claude Code 연동"
        alert.informativeText = "Claude Code와 연동하면 작업 상태를 실시간으로 알려줘요!\n\n- 작업 시작/완료 알림\n- 권한 요청 알림\n- 세션별 상태 표시\n\n연동하시겠습니까?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "연동하기")
        alert.addButton(withTitle: "나중에")

        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .alertFirstButtonReturn {
            let success = installHooks()
            if success {
                showResultAlert(success: true)
            } else {
                showResultAlert(success: false)
            }
        }
    }

    private static func showResultAlert(success: Bool) {
        let alert = NSAlert()
        if success {
            alert.messageText = "연동 완료!"
            alert.informativeText = "Claude Code와 연동되었습니다.\nClaude Code를 새로 시작하면 적용됩니다."
            alert.alertStyle = .informational
        } else {
            alert.messageText = "연동 실패"
            alert.informativeText = "Hook 설정 중 문제가 발생했습니다.\n수동으로 install.sh를 실행해주세요."
            alert.alertStyle = .warning
        }
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    // MARK: - Hook Installation

    static func installHooks() -> Bool {
        let fm = FileManager.default

        // 1. Hook 디렉토리 생성
        do {
            try fm.createDirectory(atPath: hookDir, withIntermediateDirectories: true)
        } catch {
            return false
        }

        // 2. Hook 스크립트 작성
        let hookScript = """
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
        """

        do {
            try hookScript.write(toFile: hookPath, atomically: true, encoding: .utf8)
            // 실행 권한 부여
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookPath)
        } catch {
            return false
        }

        // 3. settings.json 업데이트
        return updateSettings()
    }

    private static func updateSettings() -> Bool {
        let fm = FileManager.default

        var settings: [String: Any]
        if fm.fileExists(atPath: settingsPath),
           let data = fm.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        } else {
            settings = [:]
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let eventsWithMatcher = ["PreToolUse", "PostToolUse", "PermissionRequest"]
        let eventsWithoutMatcher = ["SessionStart", "SessionEnd", "Stop", "SubagentStop", "UserPromptSubmit"]

        for event in eventsWithMatcher {
            let hookCommand = "~/.claude/hooks/\(hookFileName) \(event)"
            let hookEntry: [String: String] = ["type": "command", "command": hookCommand]

            if var groups = hooks[event] as? [[String: Any]] {
                var added = false
                for i in 0..<groups.count {
                    if var groupHooks = groups[i]["hooks"] as? [[String: Any]] {
                        let existing = groupHooks.compactMap { $0["command"] as? String }
                        if !existing.contains(hookCommand) {
                            groupHooks.append(hookEntry)
                            groups[i]["hooks"] = groupHooks
                        }
                        added = true
                        break
                    }
                }
                if !added {
                    groups.append(["matcher": "*", "hooks": [hookEntry]])
                }
                hooks[event] = groups
            } else {
                hooks[event] = [["matcher": "*", "hooks": [hookEntry]]]
            }
        }

        for event in eventsWithoutMatcher {
            let hookCommand = "~/.claude/hooks/\(hookFileName) \(event)"
            let hookEntry: [String: String] = ["type": "command", "command": hookCommand]

            if var groups = hooks[event] as? [[String: Any]] {
                var added = false
                for i in 0..<groups.count {
                    if var groupHooks = groups[i]["hooks"] as? [[String: Any]] {
                        let existing = groupHooks.compactMap { $0["command"] as? String }
                        if !existing.contains(hookCommand) {
                            groupHooks.append(hookEntry)
                            groups[i]["hooks"] = groupHooks
                        }
                        added = true
                        break
                    }
                }
                if !added {
                    groups.append(["hooks": [hookEntry]])
                }
                hooks[event] = groups
            } else {
                hooks[event] = [["hooks": [hookEntry]]]
            }
        }

        settings["hooks"] = hooks

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: settingsPath))
            return true
        } catch {
            return false
        }
    }
}
