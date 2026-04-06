import Cocoa

// MARK: - Per-session Pet Data

struct PetSession {
    let petWindow: PetWindow
    let speechBubble: SpeechBubbleWindow
    let colorIndex: Int
    var lastStatus: ClaudeStatus
    var cwd: String
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var sessions: [String: PetSession] = [:]
    var claudeMonitor: ClaudeMonitor!
    var statusItem: NSStatusItem!
    var randomSpeechTimer: Timer?
    var nextColorIndex: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        claudeMonitor = ClaudeMonitor()
        startMonitoring()
        scheduleRandomSpeech()
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

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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

        // 사라진 세션 제거
        let removedIds = Set(sessions.keys).subtracting(liveIds)
        for id in removedIds {
            if let session = sessions[id] {
                showSpeech("바이바이~", for: session)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    session.petWindow.orderOut(nil)
                    session.speechBubble.orderOut(nil)
                }
                sessions.removeValue(forKey: id)
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

                // 권한 대기 중엔 계속 점프 유지
                if info.status == .waitingForPermission {
                    existing.petWindow.petView.setState(.jumping)
                }
            } else {
                // 새 세션 → 새 Pet 스폰!
                spawnPet(for: info)
            }
        }

        rebuildStatusMenu()
    }

    // MARK: - Spawn / Remove

    private func spawnPet(for info: SessionInfo) {
        let colorIndex = nextColorIndex % PetColor.palette.count
        nextColorIndex += 1

        let color = PetColor.palette[colorIndex]
        let petWindow = PetWindow(sessionId: info.sessionId, color: color)
        let speechBubble = SpeechBubbleWindow()

        petWindow.orderFront(nil)

        // 클릭 이벤트 연결
        petWindow.petView.onClicked = { [weak self] in
            guard let session = self?.sessions[info.sessionId] else { return }
            self?.handlePetClicked(session: session)
        }
        petWindow.petView.onDoubleClicked = { [weak self] in
            guard let session = self?.sessions[info.sessionId] else { return }
            self?.handlePetDoubleClicked(session: session)
        }
        petWindow.petView.onRightClicked = { [weak self] event in
            guard let session = self?.sessions[info.sessionId] else { return }
            self?.handlePetRightClicked(event, session: session)
        }

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

    private func handlePetRightClicked(_ event: NSEvent, session: PetSession) {
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
