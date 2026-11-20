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

    /// 쉬는 세션을 몇 분 뒤 화면에서 뺄지 (설정 → 쉬는 펫 숨기기). 상태 파일은 두므로 다시 일하면 감자가 돌아온다.
    /// 데스크톱 앱은 사이드바에 열린 세션마다 claude 프로세스를 살려 둬서 쉬는 감자가 수십 마리 쌓이기도 한다(2026-11-19 실측 22마리).
    /// 기본 120분은 위 2시간 정리와 같아서, 따로 고르지 않으면 예전과 똑같다.
    static let idleHideOptions = [15, 30, 60, 120]
    static let defaultIdleHideMinutes = 120
    static var idleHideMinutes: Int {
        get {
            let minutes = UserDefaults.standard.integer(forKey: "claudepet_idle_hide_minutes")
            return minutes > 0 ? minutes : defaultIdleHideMinutes
        }
        set { UserDefaults.standard.set(newValue, forKey: "claudepet_idle_hide_minutes") }
    }

    /// 앱이 켜진 뒤 한 번이라도 일한 세션. 대화를 압축하면 같은 세션으로 SessionStart가 다시 오는데
    /// (2026-11-20 세션 기록으로 확인), 이걸 '시작만 한 세션'으로 보고 숨기면 일하던 감자가 나갔다가 다시 나온다.
    /// 상태 파일이 없어진 세션은 잊는다.
    private var workedSessions = Set<String>()

    /// 상태 파일이 남아 있는 세션 (숨긴 세션 포함). 숨었다 다시 나오는 감자의 색·작업시간을 언제까지 기억할지 정할 때 쓴다
    private(set) var sessionsOnDisk = Set<String>()

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
        let idleHideAfter = ClaudeMonitor.idleHideMinutes * 60
        var onDisk = Set<String>()   // 상태 파일이 남아 있는 세션 (훅이 쓰는 중이라 못 읽은 파일도 포함)

        for file in files {
            guard file.hasPrefix("claudepet-") && file.hasSuffix(".json") else { continue }
            let fileId = String(file.dropFirst("claudepet-".count).dropLast(".json".count))
            onDisk.insert(fileId)

            let path = "/tmp/\(file)"
            guard let data = fileManager.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = json["status"] as? String,
                  let sessionId = json["session_id"] as? String,
                  let ts = json["ts"] as? Int else { continue }

            // 오래된 상태 파일 정리
            if now - ts > staleTimeout {
                try? fileManager.removeItem(atPath: path)
                onDisk.remove(fileId)
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
            // 일한 적 있는 세션에 SessionStart가 오면 대화 압축이라 그대로 둔다.
            if event != "SessionStart" { workedSessions.insert(sessionId) }
            if event == "SessionStart" && !workedSessions.contains(sessionId) { continue }
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

        workedSessions.formIntersection(onDisk)
        sessionsOnDisk = onDisk
        return sessions
    }
}
