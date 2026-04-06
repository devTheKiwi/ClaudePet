import Foundation

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

    static func == (lhs: SessionInfo, rhs: SessionInfo) -> Bool {
        return lhs.sessionId == rhs.sessionId && lhs.status == rhs.status
    }
}

class ClaudeMonitor {
    private let staleTimeout: Int = 7200 // 2시간 이상 업데이트 없으면 정리

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

            sessions.append(SessionInfo(
                sessionId: sessionId,
                status: status,
                cwd: cwd,
                tool: tool,
                timestamp: ts
            ))
        }

        return sessions
    }
}
