import Foundation
import Cocoa

enum ClaudeStatus: Equatable {
    case notRunning
    case idle
    case working
    case waitingForPermission
}

struct SessionInfo: Equatable {
    let sessionId: String
    let status: ClaudeStatus
    let cwd: String
    let tool: String
    let timestamp: Int
    // 세션이 열린 창 찾기용 (훅 v2부터, SessionJump)
    var pid: Int32 = 0           // claude 프로세스
    var app: String = ""         // 세션을 띄운 앱 (__CFBundleIdentifier)
    var term: String = ""        // TERM_PROGRAM
    var orcaTerminal: String = "" // ORCA_TERMINAL_HANDLE

    static func == (lhs: SessionInfo, rhs: SessionInfo) -> Bool {
        return lhs.sessionId == rhs.sessionId && lhs.status == rhs.status
    }
}

class ClaudeMonitor {
    private let staleTimeout: Int = 7200 // 2시간 이상 업데이트 없으면 정리
    // 쉬는 세션은 마지막 활동 15분 뒤 화면에서 뺀다(파일은 두므로 다시 일하면 감자가 돌아온다).
    // 데스크톱 앱은 사이드바에 열린 세션마다 claude 프로세스를 살려 둬서, 이게 없으면 쉬는 감자가 수십 마리 쌓였다(2026-11-19 실측 22마리).
    private let idleHideAfter: Int = 15 * 60

    func isDesktopRunning() -> Bool {
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.anthropic.claudefordesktop"
        }
    }

    func checkSessions() -> [SessionInfo] {
        var sessions: [SessionInfo] = []
        let fileManager = FileManager.default

        guard let files = try? fileManager.contentsOfDirectory(atPath: "/tmp") else {
            return sessions
        }

        let now = Int(Date().timeIntervalSince1970)

        for file in files {
            guard file.hasPrefix("claudepet-") && file.hasSuffix(".json") else { continue }

            let path = "/tmp/\(file)"
            guard let data = fileManager.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = json["status"] as? String,
                  let sessionId = json["session_id"] as? String,
                  let ts = json["ts"] as? Int else { continue }

            // 오래된 상태 파일 정리
            if now - ts > staleTimeout {
                try? fileManager.removeItem(atPath: path)
                continue
            }

            let cwd = json["cwd"] as? String ?? ""
            let tool = json["tool"] as? String ?? "none"

            let status: ClaudeStatus
            switch event {
            case "UserPromptSubmit", "PreToolUse":
                status = .working
            case "PostToolUse", "SubagentStop":
                // 도구 하나 끝났지만 아직 작업 중일 수 있음
                status = .working
            case "Stop":
                // Claude가 응답 완료 → 진짜 작업 끝
                status = .idle
            case "PermissionRequest":
                status = .waitingForPermission
            case "SessionStart":
                status = .idle
            default:
                status = .idle
            }

            // 시작만 하고 요청을 받은 적 없는 세션(자동·백그라운드 세션 포함)은 감자를 띄우지 않는다.
            if event == "SessionStart" { continue }
            if status == .idle && now - ts > idleHideAfter { continue }
            sessions.append(SessionInfo(
                sessionId: sessionId,
                status: status,
                cwd: cwd,
                tool: tool,
                timestamp: ts,
                pid: Int32(truncatingIfNeeded: json["pid"] as? Int ?? 0),
                app: json["app"] as? String ?? "",
                term: json["term"] as? String ?? "",
                orcaTerminal: json["orca_terminal"] as? String ?? ""
            ))
        }

        return sessions
    }
}
