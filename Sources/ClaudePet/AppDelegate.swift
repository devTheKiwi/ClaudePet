import Cocoa

// MARK: - Per-session Pet Data

struct PetSession {
    let petWindow: PetWindow
    let speechBubble: SpeechBubbleWindow
    let colorIndex: Int
    var lastStatus: ClaudeStatus
    var cwd: String
    var sessionStart: Date = Date()
    var workingSeconds: Int = 0
    var lastTool: String = ""
}

// MARK: - Time Tracker

class TimeTracker {
    private let key = "claudepet_today_minutes"
    private let dateKey = "claudepet_today_date"

    func todayTotalMinutes() -> Int {
        let saved = UserDefaults.standard.string(forKey: dateKey) ?? ""
        let today = dateString()
        if saved != today {
            // 날짜 바뀌면 리셋
            UserDefaults.standard.set(0, forKey: key)
            UserDefaults.standard.set(today, forKey: dateKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: key)
    }

    func addMinute() {
        let today = dateString()
        let saved = UserDefaults.standard.string(forKey: dateKey) ?? ""
        if saved != today {
            UserDefaults.standard.set(0, forKey: key)
            UserDefaults.standard.set(today, forKey: dateKey)
        }
        let current = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(current + 1, forKey: key)
    }

    private func dateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    func formatMinutes(_ mins: Int) -> String {
        if mins < 60 {
            return "\(mins)분"
        }
        let h = mins / 60
        let m = mins % 60
        return m > 0 ? "\(h)시간 \(m)분" : "\(h)시간"
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var sessions: [String: PetSession] = [:]
    var claudeMonitor: ClaudeMonitor!
    var statusItem: NSStatusItem!
    var randomSpeechTimer: Timer?
    var nextColorIndex: Int = 0
    let timeTracker = TimeTracker()
    let updateChecker = UpdateChecker()
    let tokenTracker = TokenTracker()
    var showTimerEnabled: Bool = true
    var desktopWasRunning: Bool = false
    var desktopStartTime: Date?
    var lastTokenMilestone: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        claudeMonitor = ClaudeMonitor()

        // 기본 Pet 항상 생성 (세션 없어도 살아있음)
        spawnDefaultPet()

        // 저장된 타이머 표시 설정 불러오기
        showTimerEnabled = UserDefaults.standard.object(forKey: "claudepet_show_timer") as? Bool ?? true

        // 첫 실행 시 Hook 설정 팝업
        HookSetup.checkAndPrompt()

        // 자동 업데이트 체크
        updateChecker.onResult = { [weak self] msg in
            if let session = self?.sessions.values.first {
                self?.showSpeech(msg, for: session)
            }
        }
        updateChecker.checkOnLaunch()

        startMonitoring()
        scheduleRandomSpeech()
        startTimeTracking()
    }

    private func spawnDefaultPet() {
        let color = PetColor.palette[0]
        let screen = NSScreen.main!
        let startX = screen.visibleFrame.midX - 32

        let petWindow = PetWindow(sessionId: "default", color: color, startX: startX)
        let speechBubble = SpeechBubbleWindow()
        petWindow.orderFront(nil)

        setupClickHandlers(for: "default", petWindow: petWindow)

        let session = PetSession(
            petWindow: petWindow,
            speechBubble: speechBubble,
            colorIndex: 0,
            lastStatus: .notRunning,
            cwd: ""
        )
        sessions["default"] = session

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if let s = self?.sessions["default"] {
                self?.showSpeech("안녕! 나는 Claude Pet이야!", for: s)
            }
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🐛"
        }
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Claude Pet v2.0", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        if sessions.isEmpty {
            menu.addItem(NSMenuItem(title: "세션 없음", action: nil, keyEquivalent: ""))
        } else {
            for (_, session) in sessions.sorted(by: { $0.key < $1.key }) {
                let dir = (session.cwd as NSString).lastPathComponent
                let statusIcon: String
                switch session.lastStatus {
                case .working: statusIcon = "🔵"
                case .waitingForPermission: statusIcon = "🟡"
                case .idle: statusIcon = "🟢"
                case .notRunning: statusIcon = "⚫"
                }
                let title = "\(statusIcon) \(dir.isEmpty ? "Claude" : dir)"
                menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func runUpdate() {
        if let session = sessions.values.first {
            showSpeech("업데이트 시작! 터미널을 확인해줘!", for: session)
        }
        updateChecker.updateAvailable = false
        updateChecker.runUpdate()
    }

    @objc private func toggleTimer() {
        showTimerEnabled = !showTimerEnabled
        UserDefaults.standard.set(showTimerEnabled, forKey: "claudepet_show_timer")
        for (_, session) in sessions {
            session.petWindow.petView.showTimer = showTimerEnabled
        }
    }

    @objc private func changeSkin(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let skinType = PetSkinType(rawValue: rawValue) else { return }

        // 모든 Pet에 적용
        for (_, session) in sessions {
            session.petWindow.petView.skin = skinType
        }

        // 저장
        UserDefaults.standard.set(skinType.rawValue, forKey: "claudepet_skin")

        let msg = skinType == .spring ? "봄이 왔어! 🌸" : "기본 스킨으로 돌아왔어!"
        if let session = sessions.values.first {
            showSpeech(msg, for: session)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Tool Name Mapping

    private func toolMessage(for tool: String) -> String {
        switch tool.lowercased() {
        case "bash": return "명령어 실행 중..."
        case "read": return "파일 읽는 중..."
        case "edit": return "코드 수정 중..."
        case "write": return "파일 작성 중..."
        case "grep": return "코드 검색 중..."
        case "glob": return "파일 찾는 중..."
        case "agent": return "에이전트 작업 중..."
        case "webcrawl", "webfetch": return "웹 검색 중..."
        case "websearch": return "웹 검색 중..."
        case "notebookedit": return "노트북 수정 중..."
        case let t where t.contains("task"): return "작업 관리 중..."
        case let t where t.contains("mcp"): return "플러그인 실행 중..."
        default: return "작업 중..."
        }
    }

    // MARK: - Time Tracking

    private var lastMinuteTrack: Int = 0

    private func startTimeTracking() {
        // 1초마다 세션 시간 업데이트
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateSessionTimes()
        }
    }

    private func updateSessionTimes() {
        for (id, session) in sessions {
            if id == "desktop" {
                // Desktop: 켜진 시점부터 계속 카운트
                if let start = desktopStartTime {
                    let secs = Int(Date().timeIntervalSince(start))
                    sessions[id]?.petWindow.petView.workingSeconds = secs
                    sessions[id]?.petWindow.petView.showTimer = showTimerEnabled
                }
                continue
            }

            // Code: 작업 중인 세션만 초 누적
            if session.lastStatus == .working {
                sessions[id]?.workingSeconds += 1

                let totalSecs = sessions[id]?.workingSeconds ?? 0
                if totalSecs / 60 > lastMinuteTrack {
                    lastMinuteTrack = totalSecs / 60
                    timeTracker.addMinute()
                }
            }

            let secs = sessions[id]?.workingSeconds ?? 0
            sessions[id]?.petWindow.petView.workingSeconds = secs
            sessions[id]?.petWindow.petView.showTimer = showTimerEnabled
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.syncSessions()
        }
    }

    private func syncSessions() {
        let liveInfos = claudeMonitor.checkSessions()
        let liveIds = Set(liveInfos.map { $0.sessionId })

        // 사라진 세션 제거 (단, "default"는 절대 제거하지 않음)
        let removedIds = Set(sessions.keys).subtracting(liveIds)
        for id in removedIds {
            if id == "default" || id == "desktop" { continue } // 기본/Desktop Pet은 유지

            if let session = sessions[id] {
                // 마지막 하나 남으면 제거하지 않고 default로 전환
                if sessions.count <= 1 {
                    sessions[id]?.lastStatus = .notRunning
                    session.petWindow.petView.claudeStatus = .notRunning
                    continue
                }

                showSpeech("바이바이~", for: session)
                let petWin = session.petWindow
                let bubbleWin = session.speechBubble
                sessions.removeValue(forKey: id)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    petWin.orderOut(nil)
                    bubbleWin.orderOut(nil)
                }
            }
        }

        // 새로운 세션 추가 / 기존 세션 업데이트
        for info in liveInfos {
            if let existing = sessions[info.sessionId] {
                // 상태 변경 감지
                if info.status != existing.lastStatus {
                    handleStatusChange(
                        from: existing.lastStatus,
                        to: info.status,
                        session: existing
                    )
                }
                sessions[info.sessionId]?.lastStatus = info.status
                sessions[info.sessionId]?.cwd = info.cwd
                existing.petWindow.petView.claudeStatus = info.status

                // 작업 중일 때 도구가 바뀌면 말풍선 업데이트
                if info.status == .working && info.tool != "none" && info.tool != existing.lastTool {
                    sessions[info.sessionId]?.lastTool = info.tool
                    showSpeech(toolMessage(for: info.tool), for: existing)
                }

                // 권한 대기 중엔 계속 점프 유지
                if info.status == .waitingForPermission {
                    existing.petWindow.petView.setState(.jumping)
                }
            } else {
                // "default" Pet이 세션 없이 살아있으면 → 첫 세션 연결
                if let defaultSession = sessions["default"], sessions.count == 1 {
                    // default Pet의 상태를 새 세션으로 업데이트
                    sessions.removeValue(forKey: "default")
                    sessions[info.sessionId] = defaultSession

                    setupClickHandlers(for: info.sessionId, petWindow: defaultSession.petWindow)

                    sessions[info.sessionId]?.lastStatus = info.status
                    sessions[info.sessionId]?.cwd = info.cwd
                    defaultSession.petWindow.petView.claudeStatus = info.status

                    let dir = (info.cwd as NSString).lastPathComponent
                    showSpeech("\(dir.isEmpty ? "세션" : dir) 연결됨!", for: defaultSession)
                } else {
                    // 추가 세션 → 새 Pet 스폰
                    spawnPet(for: info)
                }
            }
        }

        // 토큰 마일스톤 체크
        checkTokenMilestones()

        // Desktop 감지
        syncDesktop()

        rebuildStatusMenu()
    }

    private func checkTokenMilestones() {
        let today = tokenTracker.todayUsage()
        let totalK = today.totalTokens / 1000

        let milestones: [(Int, String)] = [
            (10, "오늘 10K 토큰 사용!"),
            (50, "오늘 50K 돌파!"),
            (100, "오늘 100K! 열심히 일하는 중!"),
            (200, "오늘 200K...많이 썼다!"),
            (500, "오늘 500K!! 대작업이었구나!"),
            (1000, "오늘 1M!!! 역대급이야!"),
        ]

        for (threshold, message) in milestones.reversed() {
            if totalK >= threshold && lastTokenMilestone < threshold {
                lastTokenMilestone = threshold
                if let session = sessions.values.first(where: { $0.petWindow.petView.petMode == .code }) ?? sessions.values.first {
                    showSpeech(message, for: session)
                }
                break
            }
        }

        // 자정에 리셋
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        if hour == 0 && minute == 0 {
            lastTokenMilestone = 0
        }
    }

    private func syncDesktop() {
        let isRunning = claudeMonitor.isDesktopRunning()
        let desktopId = "desktop"

        if isRunning && !desktopWasRunning {
            // Desktop 켜짐 → 펫 스폰
            desktopStartTime = Date()
            if sessions[desktopId] == nil {
                let color = PetColor.palette[0]
                let screen = NSScreen.main!
                let startX = screen.visibleFrame.midX + 60
                let petWindow = PetWindow(sessionId: desktopId, color: color, startX: startX)
                let speechBubble = SpeechBubbleWindow()
                petWindow.orderFront(nil)
                petWindow.petView.petMode = .desktop
                setupClickHandlers(for: desktopId, petWindow: petWindow)

                let session = PetSession(
                    petWindow: petWindow,
                    speechBubble: speechBubble,
                    colorIndex: 0,
                    lastStatus: .idle,
                    cwd: ""
                )
                sessions[desktopId] = session
                showSpeech("Claude Desktop 왔다! 반가워!", for: session)
            }
        } else if !isRunning && desktopWasRunning {
            // Desktop 꺼짐 → 반응
            if let session = sessions[desktopId] {
                let usedMins = Int(Date().timeIntervalSince(desktopStartTime ?? Date()) / 60)
                let usedSecs = Int(Date().timeIntervalSince(desktopStartTime ?? Date())) % 60
                let timeText = String(format: "%02d분%02d초", usedMins, usedSecs)
                showSpeech("\(timeText) 사용했어! 수고했어~", for: session)

                let petWin = session.petWindow
                let bubbleWin = session.speechBubble
                sessions.removeValue(forKey: desktopId)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    petWin.orderOut(nil)
                    bubbleWin.orderOut(nil)
                }
            }
            desktopStartTime = nil
        } else if isRunning, let session = sessions[desktopId], let start = desktopStartTime {
            // Desktop 실행 중 → 시간 업데이트 + 30분 알림
            let secs = Int(Date().timeIntervalSince(start))
            session.petWindow.petView.workingSeconds = secs
            session.petWindow.petView.showTimer = showTimerEnabled

            // 30분마다 알림
            let mins = secs / 60
            if mins > 0 && mins % 30 == 0 && secs % 60 < 3 {
                let messages = [
                    "\(mins)분 지났어!",
                    "\(mins)분이야! 스트레칭 어때?",
                    "벌써 \(mins)분! 물 한잔 마셔!",
                ]
                if let msg = messages.randomElement() {
                    showSpeech(msg, for: session)
                }
            }
        }

        desktopWasRunning = isRunning
    }

    // MARK: - Click Handler Setup

    private func setupClickHandlers(for sessionId: String, petWindow: PetWindow) {
        petWindow.petView.onClicked = { [weak self] in
            guard let session = self?.sessions[sessionId] else { return }
            self?.handlePetClicked(session: session)
        }
        petWindow.petView.onDoubleClicked = { [weak self] in
            guard let session = self?.sessions[sessionId] else { return }
            self?.handlePetDoubleClicked(session: session)
        }
        petWindow.petView.onRightClicked = { [weak self] event in
            guard let session = self?.sessions[sessionId] else { return }
            self?.handlePetRightClicked(event, sessionId: sessionId, session: session)
        }
    }

    // MARK: - Spawn / Remove

    private func spawnPet(for info: SessionInfo) {
        // 사용 중인 색상 제외하고 랜덤 선택
        let usedColors = Set(sessions.values.map { $0.colorIndex })
        let available = (1..<PetColor.palette.count).filter { !usedColors.contains($0) }
        let colorIndex = available.randomElement() ?? Int.random(in: 1..<PetColor.palette.count)

        let color = PetColor.palette[colorIndex]
        let petWindow = PetWindow(sessionId: info.sessionId, color: color)
        let speechBubble = SpeechBubbleWindow()

        petWindow.orderFront(nil)
        setupClickHandlers(for: info.sessionId, petWindow: petWindow)
        petWindow.petView.claudeStatus = info.status

        let session = PetSession(
            petWindow: petWindow,
            speechBubble: speechBubble,
            colorIndex: colorIndex,
            lastStatus: info.status,
            cwd: info.cwd
        )
        sessions[info.sessionId] = session

        let dir = (info.cwd as NSString).lastPathComponent
        let colorName = ["🟠", "🔵", "🟢", "🟣", "🩷", "🩵"][colorIndex]
        showSpeech("\(colorName) \(dir.isEmpty ? "새 세션" : dir) 시작!", for: session)
    }

    // MARK: - Status Change

    private func handleStatusChange(from old: ClaudeStatus, to new: ClaudeStatus, session: PetSession) {
        // 권한 대기에서 벗어나면 persistent 말풍선 닫기
        if old == .waitingForPermission && new != .waitingForPermission {
            session.speechBubble.forceDismiss()
        }

        switch new {
        case .working:
            if old != .working {
                showSpeech("작업 시작!", for: session)
                session.petWindow.petView.setState(.excited)
            }
        case .waitingForPermission:
            showSpeech("⚠️ 권한이 필요해! 확인해줘!", for: session, persistent: true)
            session.petWindow.petView.setState(.jumping)
        case .idle:
            if old == .working {
                showSpeech("작업 완료!", for: session)
                session.petWindow.petView.setState(.happy)
            }
        case .notRunning:
            session.petWindow.petView.setState(.idle)
        }
    }

    // MARK: - Click Interactions

    private func handlePetClicked(session: PetSession) {
        let dir = (session.cwd as NSString).lastPathComponent
        let clickMessages: [String]

        switch session.lastStatus {
        case .working:
            clickMessages = [
                "지금 \(dir)에서 열심히 일하는 중!",
                "잠깐만, 거의 다 됐어!",
                "Claude가 코드 작성 중~",
            ]
        case .waitingForPermission:
            clickMessages = [
                "권한 승인이 필요해! 터미널 확인해줘!",
                "나 좀 도와줘~ 권한이 필요해!",
            ]
        case .idle:
            clickMessages = [
                "\(dir) 대기 중~ 뭐 시킬 거야?",
                "나 건드리지 마~ 간지러워!",
                "놀아줄 거야?",
                "왜왜왜~ 뭐 필요해?",
            ]
        case .notRunning:
            clickMessages = [
                "Claude Code가 꺼져있어~",
                "나 혼자 심심해...",
            ]
        }

        if let msg = clickMessages.randomElement() {
            showSpeech(msg, for: session)
        }
        session.petWindow.petView.setState(.happy)
    }

    private func handlePetDoubleClicked(session: PetSession) {
        showSpeech("우왕! 신난다~!", for: session)
        session.petWindow.petView.setState(.jumping)
    }

    private func handlePetRightClicked(_ event: NSEvent, sessionId: String = "", session: PetSession) {
        let menu = NSMenu()
        let dir = (session.cwd as NSString).lastPathComponent

        let statusText: String
        switch session.lastStatus {
        case .working: statusText = "🔵 작업 중"
        case .waitingForPermission: statusText = "🟡 권한 대기"
        case .idle: statusText = "🟢 대기 중"
        case .notRunning: statusText = "⚫ 꺼짐"
        }
        menu.addItem(NSMenuItem(title: "\(dir.isEmpty ? "Claude" : dir) - \(statusText)", action: nil, keyEquivalent: ""))

        // 세션 시간
        let sessionSecs = Int(Date().timeIntervalSince(session.sessionStart))
        let workSecs = session.workingSeconds
        let sessionText = String(format: "%02d분%02d초", sessionSecs / 60, sessionSecs % 60)
        let workText = String(format: "%02d분%02d초", workSecs / 60, workSecs % 60)
        menu.addItem(NSMenuItem(title: "📊 세션 \(sessionText) (작업 \(workText))", action: nil, keyEquivalent: ""))

        // 전체 작업 시간
        let totalMins = timeTracker.todayTotalMinutes()
        menu.addItem(NSMenuItem(title: "📊 오늘 총 작업: \(timeTracker.formatMinutes(totalMins))", action: nil, keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // 토큰 사용량
        let sessionUsage = tokenTracker.usageForSession(sessionId)
        let todayUsage = tokenTracker.todayUsage()

        if sessionUsage.totalTokens > 0 {
            menu.addItem(NSMenuItem(title: "🪙 세션: \(TokenUsage.formatTokens(sessionUsage.totalTokens)) (입력 \(TokenUsage.formatTokens(sessionUsage.inputTokens + sessionUsage.cacheReadTokens)) / 출력 \(TokenUsage.formatTokens(sessionUsage.outputTokens)))", action: nil, keyEquivalent: ""))
        }
        if todayUsage.totalTokens > 0 {
            let cacheRate = todayUsage.cacheReadTokens > 0 ? Int(Double(todayUsage.cacheReadTokens) / Double(todayUsage.cacheReadTokens + todayUsage.cacheCreationTokens + todayUsage.inputTokens) * 100) : 0
            menu.addItem(NSMenuItem(title: "🪙 오늘 총: \(TokenUsage.formatTokens(todayUsage.totalTokens)) (캐시 \(cacheRate)%)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())

        // 시간 표시 토글
        let timerToggle = NSMenuItem(title: "작업시간 표시", action: #selector(toggleTimer), keyEquivalent: "")
        timerToggle.target = self
        timerToggle.state = showTimerEnabled ? .on : .off
        menu.addItem(timerToggle)

        // 스킨 서브메뉴
        let skinMenu = NSMenu()
        for skinType in PetSkinType.allCases {
            let item = NSMenuItem(title: skinType.rawValue, action: #selector(changeSkin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = skinType.rawValue
            if session.petWindow.petView.skin == skinType {
                item.state = .on
            }
            skinMenu.addItem(item)
        }
        let skinItem = NSMenuItem(title: "스킨", action: nil, keyEquivalent: "")
        skinItem.submenu = skinMenu
        menu.addItem(skinItem)

        menu.addItem(NSMenuItem.separator())

        if updateChecker.updateAvailable, let ver = updateChecker.latestVersion {
            let updateItem = NSMenuItem(title: "🎉 v\(ver) 업데이트!", action: #selector(runUpdate), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: session.petWindow.petView)
    }

    // MARK: - Speech

    private func showSpeech(_ text: String, for session: PetSession, persistent: Bool = false) {
        let petFrame = session.petWindow.frame
        let bubbleX = petFrame.midX
        let bubbleY = petFrame.maxY + 4
        session.speechBubble.show(text: text, at: NSPoint(x: bubbleX, y: bubbleY), persistent: persistent)
    }

    // MARK: - Random Speech

    private func scheduleRandomSpeech() {
        let interval = TimeInterval.random(in: 45...90)
        randomSpeechTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.triggerRandomSpeech()
            self?.scheduleRandomSpeech()
        }
    }

    private func triggerRandomSpeech() {
        guard !sessions.isEmpty else { return }
        // 랜덤 세션 하나 선택
        guard let (_, session) = sessions.randomElement() else { return }
        guard session.petWindow.isVisible else { return }

        let idleMessages = [
            "오늘 코딩 많이 했어?",
            "잠깐 스트레칭 하는 건 어때?",
            "커피 한잔 어때요~",
            "버그 없는 하루 되길!",
            "git commit 했어?",
            "오늘도 화이팅!",
            "난 여기서 지켜보고 있을게~",
            "세미콜론 빼먹지 않았지?",
            "난 Opus 4.6이야, 최고지!",
        ]

        let workingMessages = [
            "열심히 작업 중이야!",
            "잘 되고 있어!",
            "곧 끝날 거야!",
        ]

        let messages = session.lastStatus == .working ? workingMessages : idleMessages
        if let message = messages.randomElement() {
            showSpeech(message, for: session)
        }
    }
}
