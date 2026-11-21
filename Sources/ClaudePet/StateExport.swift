import Foundation

// MARK: - 상태 파일 내보내기 (State export)
//
// 화면의 펫과 같은 세션 상태를 ~/.claudepet/state.json 에 써서 다른 프로그램(위젯·장비 등)이 읽게 한다.
// - 훅은 건드리지 않는다. 앱이 이미 가진 값만 쓴다.
// - 쓰기는 백그라운드 큐에서 하고, 실패하거나 막혀도 앱은 그대로 돈다(다음 차례에 다시 시도).
// - 내용이 바뀌면 바로, 안 바뀌어도 heartbeatInterval 마다 다시 써서 updated_at 을 새로 찍는다.
//   앱이 꺼지면 파일은 마지막 상태로 남으므로, 읽는 쪽이 updated_at 으로 오래됐는지 판단한다.

final class StateExport {
    static let formatVersion = 1
    /// 내용이 그대로여도 이 간격마다 다시 쓴다(초)
    static let heartbeatInterval: TimeInterval = 10

    static var defaultDirectory: String { NSHomeDirectory() + "/.claudepet" }
    static let fileName = "state.json"

    /// 앱이 들고 있는 펫 하나. 내보낼지는 payload 가 고른다
    struct Pet {
        let id: String
        let status: ClaudeStatus
        let info: SessionInfo?
    }

    private let directory: String
    private let queue = DispatchQueue(label: "claudepet.state-export", qos: .utility)
    private var lastBody: Data?        // 마지막으로 쓴 내용 (updated_at 제외)
    private var lastWrite = Date.distantPast
    private var writing = false        // 앞선 쓰기가 아직 안 끝났으면 건너뛴다 (막힌 디스크에 쌓이지 않게)

    init(directory: String = StateExport.defaultDirectory) {
        self.directory = directory
    }

    var path: String { directory + "/" + StateExport.fileName }

    /// 펫과 같은 세션만 고른다: 기본 펫(default)·데스크톱 앱 펫(desktop)·마지막 세션이 끝난 뒤 남긴 펫(notRunning)은 뺀다.
    /// 오래 쉬어 숨긴 세션과 시작만 한 세션은 ClaudeMonitor 가 이미 걸러서 펫이 없다.
    static func payload(pets: [Pet], todayMinutes: Int) -> [String: Any] {
        var sessions: [[String: Any]] = []
        for pet in pets.sorted(by: { $0.id < $1.id }) {
            guard pet.id != "default", pet.id != "desktop", let info = pet.info else { continue }
            let status: String
            switch pet.status {
            case .working: status = "working"
            case .waitingForPermission: status = "waiting_permission"
            case .idle: status = "idle"
            case .notRunning: continue
            }
            sessions.append([
                "id": pet.id,
                "status": status,
                "project": (info.cwd as NSString).lastPathComponent,   // 전체 경로는 넣지 않는다
                "tool": info.tool == "none" ? "" : info.tool,
                "updated_at": info.timestamp,
            ])
        }
        return [
            "version": formatVersion,
            "today_minutes": todayMinutes,
            "sessions": sessions,
        ]
    }

    /// 메인 스레드에서 부른다. 값 조립만 여기서 하고 파일 쓰기는 백그라운드로 넘긴다
    func update(pets: [Pet], todayMinutes: Int, now: Date = Date()) {
        var payload = StateExport.payload(pets: pets, todayMinutes: todayMinutes)
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let changed = body != lastBody
        guard changed || now.timeIntervalSince(lastWrite) >= StateExport.heartbeatInterval else { return }
        guard !writing else { return }

        payload["updated_at"] = Int(now.timeIntervalSince1970)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }

        writing = true
        let directory = self.directory
        let path = self.path
        queue.async { [weak self] in
            let ok = StateExport.writeAtomically(data, directory: directory, path: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.writing = false
                if ok {
                    self.lastBody = body
                    self.lastWrite = now
                }
            }
        }
    }

    /// 임시 파일에 쓴 뒤 이름을 바꿔, 읽는 쪽이 반쯤 쓴 파일을 보지 않게 한다. 실패하면 false (던지지 않는다)
    @discardableResult
    static func writeAtomically(_ data: Data, directory: String, path: String) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory) {
            guard (try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)) != nil else { return false }
        }
        let tmp = path + ".tmp"
        // 프로젝트 이름이 들어가므로 본인만 읽게 둔다
        guard fm.createFile(atPath: tmp, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        if rename(tmp, path) != 0 {
            try? fm.removeItem(atPath: tmp)
            return false
        }
        return true
    }
}
