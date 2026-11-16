import Cocoa

class UpdateChecker {
    let currentVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }()
    private let repoAPI = "https://api.github.com/repos/devTheKiwi/ClaudePet/releases/latest"

    var latestVersion: String?
    var updateAvailable: Bool = false
    var onResult: ((String) -> Void)?
    /// 릴리스 노트에 숨겨 둔 펫 멘트(업데이트 소식) — 놓치지 않게 길게 보여준다
    var onNews: ((String) -> Void)?

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
            let comment = (json["body"] as? String).flatMap(UpdateChecker.petComment(in:))
            let defaults = UserDefaults.standard

            if self.isNewer(latest: latest, current: self.currentVersion) {
                self.updateAvailable = true
                // 새 버전 예고 멘트는 버전마다 한 번만 (6시간마다 다시 확인해도 반복하지 않게)
                let teaser = defaults.string(forKey: "claudepet_teased_version") == latest ? nil : comment
                if teaser != nil { defaults.set(latest, forKey: "claudepet_teased_version") }
                DispatchQueue.main.async {
                    self.onResult?(L10n.updateAvailable(latest))
                    if let teaser = teaser {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.onNews?(teaser) }   // 앞 말풍선(4초 + 사라지기 0.5초) 뒤
                    }
                }
            } else {
                self.updateAvailable = false
                if announceWhenCurrent {
                    // 이 버전을 처음 켰으면 그 버전 소식(릴리스 노트 멘트), 아니면 평소처럼 '최신 버전'
                    let firstLaunch = defaults.string(forKey: "claudepet_last_launched_version") != self.currentVersion
                    let news = firstLaunch && latest == self.currentVersion ? comment : nil
                    defaults.set(self.currentVersion, forKey: "claudepet_last_launched_version")
                    DispatchQueue.main.async {
                        if let news = news {
                            self.onResult?(L10n.whatsNew(self.currentVersion))
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.onNews?(news) }
                        } else {
                            self.onResult?(L10n.updateLatest(self.currentVersion))
                        }
                    }
                }
            }
        }
        task.resume()
    }

    /// 릴리스 노트에 숨겨 둔 펫 멘트. GitHub 페이지엔 안 보이는 HTML 주석으로 쓴다:
    ///   <!-- pet-ko: 한국어 멘트 -->  <!-- pet-en: English line -->  (언어별 줄이 없으면 <!-- pet: … -->)
    static func petComment(in body: String) -> String? {
        func find(_ key: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "<!--\\s*\(key)\\s*:\\s*(.+?)\\s*-->", options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                  let range = Range(match.range(at: 1), in: body) else { return nil }
            return String(body[range].prefix(80))   // 말풍선은 2줄까지라 너무 길면 자른다
        }
        return find(L10n.isKorean ? "pet-ko" : "pet-en") ?? find("pet")
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
