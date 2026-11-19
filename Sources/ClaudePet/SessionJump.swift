import Cocoa
import Darwin

/// 펫을 더블클릭하면 그 세션이 열린 창으로 간다.
/// 순서: Orca 터미널 탭 → 클로드 데스크톱 Code 세션 → 맥 기본 터미널·iTerm2 탭 → 그 밖의 앱은 앞으로만 띄운다.
/// 누를 때만 돈다 (평소 비용 0). 훅이 남긴 값(pid·app·orcaTerminal)은 SessionInfo에 있다.
enum SessionJump {
    enum Outcome {
        case jumped           // 그 세션 탭·화면으로 갔다
        case appOnly          // 앱만 앞으로 띄웠다 (탭은 못 고르는 앱이거나 탭을 못 찾음)
        case needsPermission  // 맥 기본 터미널·iTerm2 제어를 허용하지 않음
        case closed           // 탭이 닫혔거나 세션이 끝남
        case oldHook          // 업데이트 전 훅이 남긴 기록이라 위치가 없음 (그 세션이 한 번 움직이면 생김)
        case notFound         // 어디서 켠 세션인지 모름
    }

    static let desktopBundleId = "com.anthropic.claudefordesktop"
    private static let orcaBundleId = "com.stablyai.orca"
    private static let terminalBundleId = "com.apple.Terminal"
    private static let iTermBundleId = "com.googlecode.iterm2"

    /// 명령 실행·파일 읽기는 백그라운드에서 하고, 결과는 메인 스레드로 돌려준다
    static func go(sessionId: String, info: SessionInfo?, completion: @escaping (Outcome) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = resolve(sessionId: sessionId, info: info)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private static func resolve(sessionId: String, info: SessionInfo?) -> Outcome {
        // 데스크톱 펫(커피잔) → 클로드 데스크톱 앱
        if sessionId == "desktop" {
            return activate(bundleId: desktopBundleId) ? .jumped : .notFound
        }

        // 1. Orca: 훅이 남긴 터미널 번호로 그 탭을 앞으로
        if let handle = info?.orcaTerminal, !handle.isEmpty {
            return jumpOrca(handle: handle)
        }

        // 2. 클로드 데스크톱 Code 세션: 데스크톱 세션 기록에서 같은 세션을 찾아 데스크톱 주소로 연다
        //    (세션 번호만 쓰므로 훅이 새 버전이 아니어도 된다)
        if let desktop = desktopSession(cliSessionId: sessionId) {
            if desktop.archived { return .closed }
            if let url = URL(string: "claude://code/continue?session=\(desktop.localId)") {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                return .jumped
            }
        }

        guard let info = info else { return .notFound }
        // 새 훅은 pid를 늘 남긴다 → 0이면 업데이트 전 훅이 쓴 기록
        if info.pid == 0 { return .oldHook }
        let app = !info.app.isEmpty ? info.app
            : info.term == "Apple_Terminal" ? terminalBundleId
            : info.term == "iTerm.app" ? iTermBundleId
            : ""

        // 3. 맥 기본 터미널·iTerm2: claude 프로세스의 tty로 탭을 찾는다
        if app == terminalBundleId || app == iTermBundleId {
            return jumpScriptableTerminal(bundleId: app, pid: info.pid)
        }

        // 4. 그 밖의 앱(VS Code·Warp 등)은 탭을 고를 방법이 없어 앞으로만 띄운다
        if !app.isEmpty, activate(bundleId: app) { return .appOnly }
        return .notFound
    }

    // MARK: - Orca

    private static func jumpOrca(handle: String) -> Outcome {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: orcaBundleId) else { return .notFound }
        let cli = appURL.appendingPathComponent("Contents/Resources/bin/orca")
        let switchArgs = ["terminal", "switch", "--terminal", handle, "--json"]

        var reply = orcaJSON(run(cli, switchArgs, timeout: 8))
        if reply == nil || (reply?["ok"] as? Bool != true && orcaErrorCode(reply) != "terminal_handle_stale") {
            // Orca 앱이 꺼져 있으면(세션은 뒤에서 계속 돎) 켜고 준비될 때까지 기다린 뒤 한 번 더
            _ = run(cli, ["open", "--json"], timeout: 30)
            reply = orcaJSON(run(cli, switchArgs, timeout: 8))
        }

        if reply?["ok"] as? Bool == true {
            activate(bundleId: orcaBundleId)
            return .jumped
        }
        if orcaErrorCode(reply) == "terminal_handle_stale" { return .closed }
        return activate(bundleId: orcaBundleId) ? .appOnly : .notFound
    }

    private static func orcaJSON(_ result: RunResult?) -> [String: Any]? {
        guard let out = result?.out, let start = out.firstIndex(of: "{"),
              let data = String(out[start...]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func orcaErrorCode(_ reply: [String: Any]?) -> String? {
        (reply?["error"] as? [String: Any])?["code"] as? String
    }

    // MARK: - 클로드 데스크톱

    /// 데스크톱은 Code 세션마다 기록 파일(local_*.json)을 둔다. cliSessionId가 훅의 session_id와 같다.
    /// 공식 기능이 아니라 데스크톱 업데이트로 바뀔 수 있다 → 못 찾으면 다음 단계로 넘어간다.
    private static func desktopSession(cliSessionId: String) -> (localId: String, archived: Bool)? {
        let fm = FileManager.default
        let base = NSHomeDirectory() + "/Library/Application Support/Claude/claude-code-sessions"
        guard let accounts = try? fm.contentsOfDirectory(atPath: base) else { return nil }
        let needle = Data(cliSessionId.utf8)

        for account in accounts {
            guard let orgs = try? fm.contentsOfDirectory(atPath: "\(base)/\(account)") else { continue }
            for org in orgs {
                let dir = "\(base)/\(account)/\(org)"
                guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for file in files where file.hasPrefix("local_") && file.hasSuffix(".json") {
                    guard let data = fm.contents(atPath: "\(dir)/\(file)"),
                          data.range(of: needle) != nil,   // 파싱 전에 빠르게 거른다
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          json["cliSessionId"] as? String == cliSessionId,
                          let localId = json["sessionId"] as? String,
                          localId.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil
                    else { continue }
                    return (localId, json["isArchived"] as? Bool == true)
                }
            }
        }
        return nil
    }

    // MARK: - 맥 기본 터미널 · iTerm2

    private static func jumpScriptableTerminal(bundleId: String, pid: Int32) -> Outcome {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty else { return .closed }
        // claude가 이미 끝났으면 tty가 없다 → 앱만 띄운다
        guard pid > 0, let tty = ttyPath(of: pid) else {
            activate(bundleId: bundleId)
            return .appOnly
        }

        let script = bundleId == terminalBundleId ? terminalScript : iTermScript
        // 처음엔 macOS가 "ClaudePet이 터미널을 제어하려고 합니다"를 묻고, 답할 때까지 기다린다
        let result = run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script, tty], timeout: 120)
        if result?.out == "ok" { return .jumped }

        activate(bundleId: bundleId)
        if result?.err.contains("-1743") == true { return .needsPermission }   // 제어 허용 안 함
        return .appOnly   // tmux 안에서 돌면 tty가 탭과 달라 못 찾는다
    }

    private static let terminalScript = """
    on run argv
        set target to item 1 of argv
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is target then
                        if miniaturized of w then set miniaturized of w to false
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "notfound"
    end run
    """

    private static let iTermScript = """
    on run argv
        set target to item 1 of argv
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is target then
                            if miniaturized of w then set miniaturized of w to false
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "notfound"
    end run
    """

    /// 프로세스의 터미널 장치(/dev/ttys003 같은 것). 프로세스가 없거나 터미널이 없으면 nil
    private static func ttyPath(of pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, let name = devname(dev, S_IFCHR) else { return nil }
        let tty = String(cString: name)
        return tty == "??" ? nil : "/dev/" + tty
    }

    // MARK: - 공통

    @discardableResult
    private static func activate(bundleId: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return false }
        DispatchQueue.main.async {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
        return true
    }

    private struct RunResult {
        let status: Int32
        let out: String
        let err: String
    }

    /// 명령을 실행하고 출력을 받는다. timeout이 지나면 끊는다.
    private static func run(_ executable: URL, _ args: [String], timeout: TimeInterval) -> RunResult? {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { process.terminate() }
        }
        var errData = Data()
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            errDone.signal()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        process.waitUntilExit()

        return RunResult(
            status: process.terminationStatus,
            out: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            err: String(decoding: errData, as: UTF8.self)
        )
    }
}
