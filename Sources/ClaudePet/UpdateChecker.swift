import Cocoa

class UpdateChecker {
    let currentVersion = "2.0.0"
    private let repoAPI = "https://api.github.com/repos/devTheKiwi/ClaudePet/releases/latest"

    var latestVersion: String?
    var updateAvailable: Bool = false
    var onResult: ((String) -> Void)?

    func checkOnLaunch() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.check()
        }
    }

    func checkNow() {
        DispatchQueue.global().async { [weak self] in
            self?.check()
        }
    }

    private func check() {
        guard let url = URL(string: repoAPI) else {
            DispatchQueue.main.async { self.onResult?(L10n.isKorean ? "업데이트 확인 실패" : "Update check failed") }
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latestTag = json["tag_name"] as? String else {
                DispatchQueue.main.async { self.onResult?(L10n.isKorean ? "업데이트 확인 실패" : "Update check failed") }
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
                DispatchQueue.main.async {
                    self.onResult?(L10n.updateLatest(self.currentVersion))
                }
            }
        }
        task.resume()
    }

    private func isNewer(latest: String, current: String) -> Bool {
        let l = latest.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
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
