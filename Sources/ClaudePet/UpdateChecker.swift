import Cocoa

class UpdateChecker {
    private let currentVersion = "2.0.0"
    private let repoAPI = "https://api.github.com/repos/devTheKiwi/ClaudePet/releases/latest"
    private let installCommand = "curl -sL https://raw.githubusercontent.com/devTheKiwi/ClaudePet/main/remote-install.sh | bash"

    func checkOnLaunch() {
        // 앱 시작 3초 후 체크
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.check()
        }
    }

    private func check() {
        guard let url = URL(string: repoAPI) else { return }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self,
                  error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latestTag = json["tag_name"] as? String else { return }

            let latest = latestTag.replacingOccurrences(of: "v", with: "")
            if self.isNewer(latest: latest, current: self.currentVersion) {
                DispatchQueue.main.async {
                    self.showUpdateAlert(version: latest)
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

    private func showUpdateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "새 버전이 나왔어요! 🎉"
        alert.informativeText = "ClaudePet v\(version) 이 출시되었습니다.\n\n터미널에서 아래 명령어로 업데이트할 수 있어요."
        alert.addButton(withTitle: "터미널에서 업데이트")
        alert.addButton(withTitle: "나중에")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            runUpdate()
        }
    }

    private func runUpdate() {
        // Terminal.app에서 업데이트 명령어 실행
        let script = """
        tell application "Terminal"
            activate
            do script "\(installCommand)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
