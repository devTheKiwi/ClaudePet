import Cocoa

class UpdateChecker {
    let currentVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }()
    private let repoAPI = "https://api.github.com/repos/devTheKiwi/ClaudePet/releases/latest"

    var latestVersion: String?
    var updateAvailable: Bool = false
    var onResult: ((String) -> Void)?

    func checkOnLaunch() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.check(announceWhenCurrent: true)
        }
    }

    private var lastCheckAt: Date?

    /// 주기적/이벤트 재확인 — 새 버전일 때만 알림. 30분 쿨다운(깨어남·활성화 연타로 API 도배 방지)
    func checkPeriodic() {
        if let last = lastCheckAt, Date().timeIntervalSince(last) < 1800 { return }
        lastCheckAt = Date()
        DispatchQueue.global().async { [weak self] in
            self?.check(announceWhenCurrent: false)
        }
    }

    private func check(announceWhenCurrent: Bool) {
        guard let url = URL(string: repoAPI) else {
            if announceWhenCurrent {
                DispatchQueue.main.async { self.onResult?(L10n.isKorean ? "업데이트 확인 실패" : "Update check failed") }
            }
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latestTag = json["tag_name"] as? String else {
                if announceWhenCurrent {
                    DispatchQueue.main.async { self.onResult?(L10n.isKorean ? "업데이트 확인 실패" : "Update check failed") }
                }
                return
            }

            let latest = latestTag.replacingOccurrences(of: "v", with: "")
            self.latestVersion = latest

            if self.isNewer(latest: latest, current: self.currentVersion) {
                self.updateAvailable = true
                DispatchQueue.main.async {
                    self.onResult?(L10n.updateAvailable(latest))
                }
            } else {
                self.updateAvailable = false
                if announceWhenCurrent {
                    DispatchQueue.main.async {
                        self.onResult?(L10n.updateLatest(self.currentVersion))
                    }
                }
            }
        }
        task.resume()
    }

    private func isNewer(latest: String, current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        // 현재 버전을 못 읽으면(빈 값/파싱 실패) 업데이트 알림을 띄우지 않음 — 무한 알림 방지
        if l.isEmpty || c.isEmpty { return false }
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv > cv { return true }
            if lv < cv { return false }
        }
        return false
    }

    func runUpdate() {
        let installCommand = "curl -sL https://raw.githubusercontent.com/devTheKiwi/ClaudePet/main/remote-install.sh | bash"

        // .command 임시 파일로 터미널 실행 (권한 문제 없음)
        let tmpFile = "/tmp/claudepet-update.command"
        let script = "#!/bin/bash\n\(installCommand)\nrm -f \(tmpFile)\n"
        do {
            try script.write(toFile: tmpFile, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpFile)
            NSWorkspace.shared.open(URL(fileURLWithPath: tmpFile))
        } catch {
            // 실패 시 클립보드에 복사
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(installCommand, forType: .string)
        }
    }
}
