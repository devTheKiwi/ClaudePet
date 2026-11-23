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
    var creditedMinutes: Int = 0   // 일별 작업시간에 이미 적립한 분 (세션별 독립 카운트)
    var lastTool: String = ""
    var info: SessionInfo? = nil   // 훅이 남긴 최신 값 (더블클릭으로 세션 창 찾기)
}

/// 쉬느라 숨은 감자 (쉬는 펫 숨기기). 그 세션이 다시 일하면 색·작업시간·모여 있기 순서를 이어 쓴다
struct RestingPet {
    let colorIndex: Int
    let sessionStart: Date
    let workingSeconds: Int
    let creditedMinutes: Int
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
            return L10n.isKorean ? "\(mins)분" : "\(mins)m"
        }
        let h = mins / 60
        let m = mins % 60
        if L10n.isKorean {
            return m > 0 ? "\(h)시간 \(m)분" : "\(h)시간"
        }
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var sessions: [String: PetSession] = [:]
    var restingPets: [String: RestingPet] = [:]   // 상태 파일이 없어지면(세션 끝) 잊는다
    var claudeMonitor: ClaudeMonitor!
    var statusItem: NSStatusItem!
    var randomSpeechTimer: Timer?
    let caretLocator = CaretLocator()
    var nextColorIndex: Int = 0
    let timeTracker = TimeTracker()
    let updateChecker = UpdateChecker()
    let tokenTracker = TokenTracker()
    let stateExport = StateExport()
    var showTimerEnabled: Bool = true
    var desktopWasRunning: Bool = false
    var desktopStartTime: Date?
    var lastTokenMilestone: Int = 0
    var lastMilestoneDate: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        claudeMonitor = ClaudeMonitor()

        // 기본 Pet 항상 생성 (세션 없어도 살아있음)
        spawnDefaultPet()

        // 저장된 타이머 표시 설정 불러오기
        showTimerEnabled = UserDefaults.standard.object(forKey: "claudepet_show_timer") as? Bool ?? true

        // 첫 실행 시 Hook 설정 팝업
        HookSetup.checkAndPrompt()

        // Hook 자동 복구 시 재시작 안내
        if HookSetup.needsClaudeRestart {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                if let session = self?.sessions.values.first {
                    let msg = L10n.isKorean ? "Hook 복구됨! Claude Code를 재시작해주세요!" : "Hooks repaired! Please restart Claude Code!"
                    self?.showSpeech(msg, for: session)
                }
            }
        }

        // 자동 업데이트 체크
        updateChecker.onResult = { [weak self] msg in
            if let session = self?.sessions.values.first {
                self?.showSpeech(msg, for: session)
            }
        }
        // 릴리스 노트의 펫 멘트(업데이트 소식)는 놓치지 않게 10초
        updateChecker.onNews = { [weak self] msg in
            if let session = self?.sessions.values.first {
                self?.showSpeech(msg, for: session, duration: 10)
            }
        }
        updateChecker.checkOnLaunch()
        // 6시간마다 재확인 — 앱을 계속 켜둬도 새 버전을 알 수 있게 (최신이면 조용히)
        Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.updateChecker.checkPeriodic()
        }
        // 맥 잠금해제(깨어남)·앱 활성화 시 즉시 재확인 — 6시간 안 기다림 (쿨다운은 checkPeriodic 내부)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateChecker.checkPeriodic() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateChecker.checkPeriodic() }

        startMonitoring()
        scheduleRandomSpeech()
        startTimeTracking()
    }

    private func spawnDefaultPet() {
        let color = PetColor.palette[0]
        let screen = PetPlacement.screen ?? NSScreen.main!
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
                self?.showSpeech(L10n.greeting, for: s)
            }
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // 번들에 펫 모양 아이콘이 있으면 그걸 쓰고, 없으면(swift run 등) 예전처럼 🐛
            if let icon = Bundle.main.image(forResource: "MenuBarIcon") {
                icon.isTemplate = true   // 밝은·어두운 메뉴바에 맞춰 시스템이 색을 입힌다
                button.image = icon
                button.imagePosition = .imageLeading
            } else {
                button.title = "🐛"
            }
        }
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        // 메뉴바 아이콘 배지: 업데이트 있으면 🎉 (메뉴 안 열어도 항상 보임)
        let bug = statusItem.button?.image == nil ? "🐛" : ""
        statusItem.button?.title = bug + (updateChecker.updateAvailable ? "🎉" : "")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Claude Pet v\(updateChecker.currentVersion)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        if sessions.isEmpty {
            menu.addItem(NSMenuItem(title: L10n.isKorean ? "세션 없음" : "No sessions", action: nil, keyEquivalent: ""))
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
        // 투명 모드에선 클릭이 펫을 통과해 우클릭이 어려우니,
        // 세션별 정보만 빼고 우클릭 메뉴 항목을 메뉴바에도 둔다
        menu.addItem(todayWorkItem())
        if let tokens = todayTokensItem() { menu.addItem(tokens) }
        menu.addItem(NSMenuItem.separator())
        settingsMenuItems().forEach { menu.addItem($0) }
        menu.addItem(NSMenuItem.separator())

        // 업데이트 있으면 메뉴바 메뉴에도 실행 항목 노출 (배지 보고 아이콘 눌렀을 때 헤매지 않게)
        if updateChecker.updateAvailable, let ver = updateChecker.latestVersion {
            let updateItem = NSMenuItem(title: "🎉 v\(ver) \(L10n.menuUpdate)", action: #selector(runUpdate), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        }

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func runUpdate() {
        if let session = sessions.values.first {
            showSpeech(L10n.updateStarted, for: session)
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
        rebuildStatusMenu()
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
        rebuildStatusMenu()

        let msg = L10n.skinChanged(skinType)
        if let session = sessions.values.first {
            showSpeech(msg, for: session)
        }
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        // "system"이면 키 제거(자동 감지로 복귀), 아니면 "ko"/"en" 저장
        if value == "system" {
            UserDefaults.standard.removeObject(forKey: "claudepet_language")
        } else {
            UserDefaults.standard.set(value, forKey: "claudepet_language")
        }
        // 메뉴/말풍선은 접근 시점에 L10n을 다시 읽으므로 즉시 반영됨
        rebuildStatusMenu()
        if let session = sessions.values.first {
            showSpeech(L10n.languageChanged, for: session)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Shared Menu Items (우클릭 메뉴 · 메뉴바 메뉴 공용)

    private func todayWorkItem() -> NSMenuItem {
        let totalMins = timeTracker.todayTotalMinutes()
        return NSMenuItem(title: L10n.menuTodayWork(timeTracker.formatMinutes(totalMins)), action: nil, keyEquivalent: "")
    }

    /// 오늘 토큰 합계 — todayUsage 는 캐시값이라 메뉴바 메뉴를 2초마다 다시 만들어도 가볍다
    private func todayTokensItem() -> NSMenuItem? {
        let todayUsage = tokenTracker.todayUsage()
        guard todayUsage.totalTokens > 0 else { return nil }
        let cacheRate = todayUsage.cacheReadTokens > 0 ? Int(Double(todayUsage.cacheReadTokens) / Double(todayUsage.cacheReadTokens + todayUsage.cacheCreationTokens + todayUsage.inputTokens) * 100) : 0
        let todayLabel = L10n.isKorean ? "🪙 오늘 총" : "🪙 Today"
        return NSMenuItem(title: "\(todayLabel): \(TokenUsage.formatTokens(todayUsage.totalTokens)) (cache \(cacheRate)%)", action: nil, keyEquivalent: "")
    }

    /// 작업시간 표시 · 스킨 · 언어 · 펫 배치 · 쉬는 펫 숨기기
    private func settingsMenuItems() -> [NSMenuItem] {
        let timerToggle = NSMenuItem(title: L10n.menuWorkTime, action: #selector(toggleTimer), keyEquivalent: "")
        timerToggle.target = self
        timerToggle.state = showTimerEnabled ? .on : .off

        // 스킨은 모든 펫이 같이 쓰고 claudepet_skin 에 저장된다
        let currentSkin = UserDefaults.standard.string(forKey: "claudepet_skin").flatMap(PetSkinType.init(rawValue:)) ?? .basic
        let skinMenu = NSMenu()
        for skinType in PetSkinType.allCases {
            let displayName: String
            switch skinType {
            case .basic: displayName = L10n.skinBasic
            case .spring: displayName = L10n.skinSpring
            case .summer: displayName = L10n.skinSummer
            case .autumn: displayName = L10n.skinAutumn
            }
            let item = NSMenuItem(title: displayName, action: #selector(changeSkin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = skinType.rawValue
            item.state = currentSkin == skinType ? .on : .off
            skinMenu.addItem(item)
        }
        let skinItem = NSMenuItem(title: L10n.menuSkin, action: nil, keyEquivalent: "")
        skinItem.submenu = skinMenu

        let langMenu = NSMenu()
        let currentLang = UserDefaults.standard.string(forKey: "claudepet_language") ?? "system"
        let langOptions: [(value: String, name: String)] = [
            ("system", L10n.langSystem),
            ("ko", L10n.langKorean),
            ("en", L10n.langEnglish),
        ]
        for opt in langOptions {
            let item = NSMenuItem(title: opt.name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.value
            if currentLang == opt.value { item.state = .on }
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: L10n.menuLanguage, action: nil, keyEquivalent: "")
        langItem.submenu = langMenu

        return [timerToggle, skinItem, langItem, placementMenuItem(), idleHideMenuItem()]
    }

    // MARK: - Idle Hide

    /// "쉬는 펫 숨기기": 쉬는 세션 감자를 몇 분 뒤 화면에서 뺄지. 상태 파일은 두므로 다시 일하면 돌아온다
    private func idleHideMenuItem() -> NSMenuItem {
        let menu = NSMenu()
        let current = ClaudeMonitor.idleHideMinutes
        for minutes in ClaudeMonitor.idleHideOptions {
            let title = L10n.idleHideOption(minutes, isDefault: minutes == ClaudeMonitor.defaultIdleHideMinutes)
            let item = NSMenuItem(title: title, action: #selector(changeIdleHide(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.state = current == minutes ? .on : .off
            menu.addItem(item)
        }
        let item = NSMenuItem(title: L10n.menuIdleHide, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func changeIdleHide(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        ClaudeMonitor.idleHideMinutes = minutes
        syncSessions()   // 다음 확인(2초)을 기다리지 않고 바로 숨기거나 다시 꺼낸다
    }

    // MARK: - Pet Placement

    /// 우클릭 메뉴와 메뉴바 메뉴에 같이 붙이는 "펫 배치" 서브메뉴
    private func placementMenuItem() -> NSMenuItem {
        let menu = NSMenu()

        // 모니터가 여러 대일 때만 화면 선택
        if NSScreen.screens.count > 1 {
            let screenMenu = NSMenu()
            let current = PetPlacement.screenChoice
            var options: [(value: String, name: String)] = [("dock", L10n.screenDock), ("follow", L10n.screenFollow)]
            options += NSScreen.screens.map { (PetPlacement.displayID(of: $0), $0.localizedName) }
            for (index, opt) in options.enumerated() {
                if index == 2 { screenMenu.addItem(NSMenuItem.separator()) }
                let item = NSMenuItem(title: opt.name, action: #selector(changePetScreen(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = opt.value
                item.state = current == opt.value ? .on : .off
                screenMenu.addItem(item)
            }
            let screenItem = NSMenuItem(title: L10n.menuPetScreen, action: nil, keyEquivalent: "")
            screenItem.submenu = screenMenu
            menu.addItem(screenItem)
        }

        let toggles: [(title: String, on: Bool, action: Selector)] = [
            (L10n.menuHoverFade, PetPlacement.hoverFade, #selector(toggleHoverFade)),
            (L10n.menuCaretFade, PetPlacement.caretFade, #selector(toggleCaretFade)),
            (L10n.menuGather, PetPlacement.gather, #selector(toggleGather)),
        ]
        for toggle in toggles {
            let item = NSMenuItem(title: toggle.title, action: toggle.action, keyEquivalent: "")
            item.target = self
            item.state = toggle.on ? .on : .off
            menu.addItem(item)
        }

        let item = NSMenuItem(title: L10n.menuPlacement, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func changePetScreen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        PetPlacement.screenChoice = value
        applyPlacement()
    }

    @objc private func toggleHoverFade() {
        PetPlacement.hoverFade.toggle()
        updateHoverFade()
        rebuildStatusMenu()
    }

    @objc private func toggleCaretFade() {
        PetPlacement.caretFade.toggle()
        // 권한 안내 창은 이 기능을 켤 때만 띄운다. 허용하지 않아도 마우스 기준 동작은 그대로다
        if PetPlacement.caretFade && !CaretLocator.isTrusted {
            CaretLocator.requestPermission()
        }
        updateHoverFade()
        rebuildStatusMenu()
    }

    @objc private func toggleGather() {
        PetPlacement.gather.toggle()
        updateGatherHomes()
        rebuildStatusMenu()
    }

    /// 화면 설정이 바뀌면 다음 걸음을 기다리지 않고 바로 옮긴다
    private func applyPlacement() {
        for (_, session) in sessions {
            session.petWindow.snapToFloor()
        }
        updateGatherHomes()
        rebuildStatusMenu()
    }

    /// 커서가 펫(말풍선 포함) 근처에 오면 반투명 + 클릭 통과. ⌥ 를 누르고 있으면 평소처럼 잡힌다.
    /// "글 쓰는 자리에서 투명해지기"가 켜져 있으면 글자 커서가 있는 줄을 가린 펫도 똑같이 투명해진다.
    private func updateHoverFade() {
        caretLocator.tick(enabled: PetPlacement.caretFade)
        // 클릭·드래그 도중엔 상태를 바꾸지 않음 (⌥ 드래그 중 손 떼도 끊기지 않게)
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let enabled = PetPlacement.hoverFade
        let mouse = NSEvent.mouseLocation
        let holdingOption = NSEvent.modifierFlags.contains(.option)

        for (_, session) in sessions {
            var zone = session.petWindow.frame
            if session.speechBubble.isVisible {
                zone = zone.union(session.speechBubble.frame)
            }
            let nearMouse = enabled && zone.insetBy(dx: -20, dy: -20).contains(mouse)
            let overCaret = caretLocator.zone.map { zone.insetBy(dx: 0, dy: -4).intersects($0) } ?? false
            let faded = !holdingOption && (nearMouse || overCaret)
            session.petWindow.hoverFaded = faded
            session.speechBubble.hoverFaded = faded
        }
    }

    /// 모여 있기: 펫이 gatherMinimum 마리 이상이면 펫 화면 오른쪽 아래 구석에 오래된 순서로 줄 세운다.
    /// 간격 72pt — 몸통(40pt)이 옆 펫 창(96pt)에 안 겹쳐서 클릭이 엉뚱한 펫으로 안 간다.
    /// 권한 요청이 온 펫은 줄 앞(왼쪽)으로 나와서 점프한다.
    private func updateGatherHomes() {
        let pets = sessions.values.sorted { $0.sessionStart < $1.sessionStart }
        guard PetPlacement.gather, pets.count >= PetPlacement.gatherMinimum,
              let visibleFrame = PetPlacement.screen?.visibleFrame else {
            for pet in pets { pet.petWindow.homeX = nil }
            return
        }

        let spacing: CGFloat = 72
        let lineRight = visibleFrame.maxX - 96 - 8
        let lineLeft = lineRight - CGFloat(pets.count - 1) * spacing
        var slot = 0
        var front = 0
        for pet in pets {
            if pet.lastStatus == .waitingForPermission {
                pet.petWindow.homeX = max(visibleFrame.minX, lineLeft - 96 - CGFloat(front) * 96)
                front += 1
            } else {
                pet.petWindow.homeX = lineRight - CGFloat(slot) * spacing
                slot += 1
            }
        }
    }

    // MARK: - Model Message

    private func modelMessage() -> String {
        // 활성 세션에서 모델명 가져오기
        for (id, _) in sessions {
            if id == "default" || id == "desktop" { continue }
            if let model = tokenTracker.modelForSession(id) {
                let name = formatModelName(model)
                return L10n.modelReactions(name).randomElement() ?? "I'm \(name)!"
            }
        }
        return L10n.modelReactions("Claude").randomElement() ?? "I'm Claude!"
    }

    private func formatModelName(_ model: String) -> String {
        // "claude-opus-4-6" → "Opus 4.6"
        // "claude-sonnet-4-6" → "Sonnet 4.6"
        let parts = model.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        if parts.count >= 3 {
            let name = String(parts[0]).capitalized
            return "\(name) \(parts[1]).\(parts[2])"
        }
        return model.replacingOccurrences(of: "claude-", with: "").capitalized
    }

    // MARK: - Tool Name Mapping

    private func toolMessage(for tool: String) -> String {
        return L10n.toolMessage(for: tool)
    }

    // MARK: - Time Tracking

    private func startTimeTracking() {
        // 1초마다 세션 시간 업데이트 + Dock 이 보이는 화면 기억 (자동 숨김 대응)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateSessionTimes()
            PetPlacement.refreshDockScreen()
        }
        // 15fps로 말풍선 위치 추적 + 커서 근처 펫 반투명
        Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.updateBubblePositions()
            self?.updateHoverFade()
        }
    }

    private func updateBubblePositions() {
        for (_, session) in sessions {
            guard session.speechBubble.isVisible else { continue }
            let petFrame = session.petWindow.frame
            let bubbleX = petFrame.midX
            let bubbleY = petFrame.maxY + 4
            session.speechBubble.updatePosition(to: NSPoint(x: bubbleX, y: bubbleY))
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

                // 세션별로 자기 작업 분을 독립 적립 (전역 워터마크 폐기 — 순차·자정 과소집계 버그 수정)
                let workedMinutes = (sessions[id]?.workingSeconds ?? 0) / 60
                if workedMinutes > (sessions[id]?.creditedMinutes ?? 0) {
                    sessions[id]?.creditedMinutes = workedMinutes
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

                showSpeech(L10n.bye, for: session)
                let petWin = session.petWindow
                let bubbleWin = session.speechBubble
                // 쉬느라 숨는 거면 다시 나올 때 색·작업시간을 이어 쓴다 (세션이 끝난 거면 바로 아래에서 잊는다)
                restingPets[id] = RestingPet(colorIndex: session.colorIndex, sessionStart: session.sessionStart,
                                             workingSeconds: session.workingSeconds, creditedMinutes: session.creditedMinutes)
                sessions.removeValue(forKey: id)
                // 인사 말풍선을 잠깐 보인 뒤 땅속으로 들어가고, 다 들어가면 창을 닫는다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    bubbleWin.orderOut(nil)
                    petWin.petView.playExit { petWin.orderOut(nil) }
                }
            }
        }
        // 상태 파일이 없어진 세션(끝났거나 2시간 지나 정리됨)은 잊는다
        restingPets = restingPets.filter { claudeMonitor.sessionsOnDisk.contains($0.key) }

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
                sessions[info.sessionId]?.info = info
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
                    sessions[info.sessionId]?.info = info
                    defaultSession.petWindow.petView.claudeStatus = info.status

                    let dir = (info.cwd as NSString).lastPathComponent
                    showSpeech("\(dir.isEmpty ? L10n.sessionConnected : dir + " " + L10n.sessionConnected)", for: defaultSession)
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

        // 모여 있기 자리 (세션 수·권한 요청 상태가 바뀌면 줄을 다시 세움)
        updateGatherHomes()

        rebuildStatusMenu()

        // 펫과 같은 세션 상태를 ~/.claudepet/state.json 으로 내보낸다 (쓰기는 백그라운드, 실패해도 무시)
        stateExport.update(
            pets: sessions.map { StateExport.Pet(id: $0.key, status: $0.value.lastStatus, info: $0.value.info) },
            todayMinutes: timeTracker.todayTotalMinutes()
        )
    }

    private func checkTokenMilestones() {
        let today = tokenTracker.todayUsage()
        let totalK = today.totalTokens / 1000

        let milestones = L10n.tokenMilestones

        for (threshold, message) in milestones.reversed() {
            if totalK >= threshold && lastTokenMilestone < threshold {
                lastTokenMilestone = threshold
                if let session = sessions.values.first(where: { $0.petWindow.petView.petMode == .code }) ?? sessions.values.first {
                    showSpeech(message, for: session)
                }
                break
            }
        }

        // 날짜 바뀌면 리셋 (자정, 슬립 복귀 등 안전)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: Date())
        if lastMilestoneDate != todayStr {
            lastTokenMilestone = 0
            lastMilestoneDate = todayStr
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
                let screen = PetPlacement.screen ?? NSScreen.main!
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
                showSpeech(L10n.desktopHello, for: session)
            }
        } else if !isRunning && desktopWasRunning {
            // Desktop 꺼짐 → 반응
            if let session = sessions[desktopId] {
                let usedMins = Int(Date().timeIntervalSince(desktopStartTime ?? Date()) / 60)
                let usedSecs = Int(Date().timeIntervalSince(desktopStartTime ?? Date())) % 60
                let timeText = String(format: "%02d:%02d", usedMins, usedSecs)
                showSpeech(L10n.desktopBye(timeText), for: session)

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
                if let msg = L10n.desktopTimeAlert(mins).randomElement() {
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
            self?.jumpToSession(sessionId)
        }
        petWindow.petView.onRightClicked = { [weak self] event in
            guard let session = self?.sessions[sessionId] else { return }
            self?.handlePetRightClicked(event, sessionId: sessionId, session: session)
        }
    }

    // MARK: - Spawn / Remove

    private func spawnPet(for info: SessionInfo) {
        // 쉬느라 숨었던 감자면 원래 색을 다시 쓴다 (그새 다른 감자가 그 색을 쓰고 있으면 새로 고른다).
        // 새로 고를 땐 사용 중인 색, 되도록 숨은 감자 색도 빼고 랜덤
        let resting = restingPets.removeValue(forKey: info.sessionId)
        let usedColors = Set(sessions.values.map { $0.colorIndex })
        let restingColors = Set(restingPets.values.map { $0.colorIndex })
        let allColors = Array(1..<PetColor.palette.count)
        let colorIndex: Int
        if let resting, !usedColors.contains(resting.colorIndex) {
            colorIndex = resting.colorIndex
        } else {
            colorIndex = allColors.filter { !usedColors.contains($0) && !restingColors.contains($0) }.randomElement()
                ?? allColors.filter { !usedColors.contains($0) }.randomElement()
                ?? Int.random(in: 1..<PetColor.palette.count)
        }

        let color = PetColor.palette[colorIndex]
        // 새 감자는 메인 감자(데스크톱 펫, 없으면 기본 펫) 바로 옆 땅에서 태어난다. 메인이 기뻐 뛰고,
        // 새 감자는 거기서 싹을 틔운 뒤 자기 자리로 걸어간다(모여 있기 모드면 자리로, 아니면 자유롭게).
        let mother = sessions["desktop"] ?? sessions["default"]
        var birthX: CGFloat?
        if let m = mother?.petWindow, m.isVisible {
            let vf = (PetPlacement.screen ?? NSScreen.main!).visibleFrame
            let side: CGFloat = m.frame.midX > vf.midX ? -1 : 1  // 화면 가운데 쪽으로
            birthX = min(max(m.frame.minX + side * 56, vf.minX), vf.maxX - m.frame.width)
            mother?.petWindow.petView.setState(.happy)
        }
        let petWindow = PetWindow(sessionId: info.sessionId, color: color, startX: birthX)
        let speechBubble = SpeechBubbleWindow()

        petWindow.orderFront(nil)
        petWindow.petView.playEnter()  // 싹이 돋고 감자가 솟아오르기
        setupClickHandlers(for: info.sessionId, petWindow: petWindow)
        petWindow.petView.claudeStatus = info.status

        var session = PetSession(
            petWindow: petWindow,
            speechBubble: speechBubble,
            colorIndex: colorIndex,
            lastStatus: info.status,
            cwd: info.cwd,
            info: info
        )
        if let resting {
            // 작업시간 뱃지·오늘 적립한 분·모여 있기 순서를 숨기 전 그대로 이어 간다
            session.sessionStart = resting.sessionStart
            session.workingSeconds = resting.workingSeconds
            session.creditedMinutes = resting.creditedMinutes
            petWindow.petView.workingSeconds = resting.workingSeconds
            petWindow.petView.showTimer = showTimerEnabled
        }
        sessions[info.sessionId] = session

        let dir = (info.cwd as NSString).lastPathComponent
        showSpeech(L10n.sessionConnected.isEmpty ? dir : "\(dir.isEmpty ? L10n.sessionConnected : dir + " " + L10n.sessionConnected)", for: session)
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
                showSpeech(L10n.workStarted, for: session)
                session.petWindow.petView.setState(.excited)
            }
        case .waitingForPermission:
            showSpeech(L10n.permissionNeeded, for: session, persistent: true)
            session.petWindow.petView.setState(.jumping)
        case .idle:
            if old == .working {
                showSpeech(L10n.workDone, for: session)
                session.petWindow.petView.setState(.happy)
            }
        case .notRunning:
            session.petWindow.petView.setState(.idle)
        }
    }

    // MARK: - Click Interactions

    private func handlePetClicked(session: PetSession) {
        let clickMessages: [String]

        switch session.lastStatus {
        case .working:
            clickMessages = L10n.clickWorking
        case .waitingForPermission:
            clickMessages = L10n.clickPermission
        case .idle:
            clickMessages = L10n.clickIdle
        case .notRunning:
            clickMessages = L10n.clickNotRunning
        }

        if let msg = clickMessages.randomElement() {
            showSpeech(msg, for: session)
        }
        session.petWindow.petView.setState(.happy)
    }

    private func handlePetDoubleClicked(session: PetSession) {
        showSpeech(L10n.doubleClick, for: session)
        session.petWindow.petView.setState(.jumping)
    }

    // MARK: - 세션 창으로 가기 (더블클릭 · 우클릭 메뉴)

    private var isJumping = false   // 이동 중엔 다시 누르지 않게 (터미널 제어 허용 창이 떠 있는 동안 등)

    private func jumpToSession(_ sessionId: String) {
        guard !isJumping, let session = sessions[sessionId] else { return }
        // 세션 없는 기본 펫은 갈 곳이 없으니 예전 더블클릭 반응("신난다~")
        guard sessionId != "default" else {
            handlePetDoubleClicked(session: session)
            return
        }
        isJumping = true
        session.petWindow.petView.setState(.jumping)

        SessionJump.go(sessionId: sessionId, info: session.info) { [weak self] outcome in
            guard let self = self else { return }
            self.isJumping = false
            guard let session = self.sessions[sessionId] else { return }
            switch outcome {
            case .jumped: break
            case .appOnly: self.showSpeech(L10n.jumpAppOnly, for: session)
            case .needsPermission: self.showSpeech(L10n.jumpNeedsPermission, for: session, duration: 8)
            case .closed: self.showSpeech(L10n.jumpClosed, for: session)
            case .oldHook: self.showSpeech(L10n.jumpOldHook, for: session, duration: 6)
            case .notFound: self.showSpeech(L10n.jumpNotFound, for: session)
            }
        }
    }

    @objc private func jumpMenuClicked(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? String else { return }
        jumpToSession(sessionId)
    }

    private func handlePetRightClicked(_ event: NSEvent, sessionId: String = "", session: PetSession) {
        let menu = NSMenu()
        let dir = (session.cwd as NSString).lastPathComponent

        let statusText: String
        switch session.lastStatus {
        case .working: statusText = L10n.menuWorking
        case .waitingForPermission: statusText = L10n.menuPermission
        case .idle: statusText = L10n.menuIdle
        case .notRunning: statusText = L10n.menuOff
        }
        menu.addItem(NSMenuItem(title: "\(dir.isEmpty ? "Claude" : dir) - \(statusText)", action: nil, keyEquivalent: ""))

        // 세션 창으로 가기 (세션 없는 기본 펫은 갈 곳이 없어 뺀다)
        if sessionId != "default" {
            let jumpItem = NSMenuItem(
                title: sessionId == "desktop" ? L10n.menuOpenDesktop : L10n.menuJump,
                action: #selector(jumpMenuClicked(_:)),
                keyEquivalent: ""
            )
            jumpItem.target = self
            jumpItem.representedObject = sessionId
            menu.addItem(jumpItem)
        }

        // 세션 시간
        let sessionSecs = Int(Date().timeIntervalSince(session.sessionStart))
        let workSecs = session.workingSeconds
        let sessionText = String(format: "%02d:%02d", sessionSecs / 60, sessionSecs % 60)
        let workText = String(format: "%02d:%02d", workSecs / 60, workSecs % 60)
        let sessionLabel = L10n.isKorean ? "📊 세션 \(sessionText) (작업 \(workText))" : "📊 Session \(sessionText) (Work \(workText))"
        menu.addItem(NSMenuItem(title: sessionLabel, action: nil, keyEquivalent: ""))

        // 전체 작업 시간
        menu.addItem(todayWorkItem())

        menu.addItem(NSMenuItem.separator())

        // 토큰 사용량
        let sessionUsage = tokenTracker.usageForSession(sessionId)

        if sessionUsage.totalTokens > 0 {
            let inLabel = L10n.isKorean ? "입력" : "In"
            let outLabel = L10n.isKorean ? "출력" : "Out"
            menu.addItem(NSMenuItem(title: "🪙 \(L10n.isKorean ? "세션" : "Session"): \(TokenUsage.formatTokens(sessionUsage.totalTokens)) (\(inLabel) \(TokenUsage.formatTokens(sessionUsage.inputTokens + sessionUsage.cacheReadTokens)) / \(outLabel) \(TokenUsage.formatTokens(sessionUsage.outputTokens)))", action: nil, keyEquivalent: ""))
        }
        if let tokens = todayTokensItem() { menu.addItem(tokens) }

        menu.addItem(NSMenuItem.separator())

        // 작업시간 표시 · 스킨 · 언어 · 펫 배치 (메뉴바 메뉴와 같은 항목)
        settingsMenuItems().forEach { menu.addItem($0) }

        menu.addItem(NSMenuItem.separator())

        if updateChecker.updateAvailable, let ver = updateChecker.latestVersion {
            let updateItem = NSMenuItem(title: "🎉 v\(ver) \(L10n.menuUpdate)", action: #selector(runUpdate), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: session.petWindow.petView)
    }

    // MARK: - Speech

    private func showSpeech(_ text: String, for session: PetSession, persistent: Bool = false, duration: TimeInterval = 4.0) {
        let petFrame = session.petWindow.frame
        let bubbleX = petFrame.midX
        let bubbleY = petFrame.maxY + 4
        session.speechBubble.show(text: text, at: NSPoint(x: bubbleX, y: bubbleY), persistent: persistent, duration: duration)
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

        if session.lastStatus == .working {
            if let message = L10n.workingMessages.randomElement() {
                showSpeech(message, for: session)
            }
            return
        }

        // idle: 기본 멘트 + 모델 멘트 + (스킨에 따라) 에디션 멘트를 가중치 있게 섞기
        var pool = L10n.idleMessages + [modelMessage()]
        switch session.petWindow.petView.skin {
        case .summer: pool += L10n.summerMessages + L10n.summerMessages   // 여름 멘트 자주
        case .spring: pool += L10n.springMessages + L10n.springMessages   // 봄 멘트 자주
        case .autumn: pool += L10n.autumnMessages + L10n.autumnMessages   // 가을 멘트 자주
        case .basic: break
        }
        if let message = pool.randomElement() {
            showSpeech(message, for: session)
        }
    }
}
