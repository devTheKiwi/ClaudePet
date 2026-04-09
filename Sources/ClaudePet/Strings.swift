import Foundation

/// 시스템 언어 감지 기반 한/영 자동 전환
struct L10n {
    static let isKorean: Bool = {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("ko")
    }()

    // MARK: - 인사

    static let greeting = isKorean ? "안녕! 나는 Claude Pet이야!" : "Hi! I'm Claude Pet!"

    // MARK: - 상태 변경

    static let workStarted = isKorean ? "작업 시작!" : "Work started!"
    static let workDone = isKorean ? "작업 완료!" : "Work done!"
    static let permissionNeeded = isKorean ? "⚠️ 권한이 필요해! 확인해줘!" : "⚠️ Permission needed! Check terminal!"
    static let sessionConnected = isKorean ? "연결됨!" : "Connected!"
    static let desktopHello = isKorean ? "Claude Desktop 왔다! 반가워!" : "Claude Desktop is here! Hi!"
    static let desktopBye: (String) -> String = { time in
        isKorean ? "\(time) 사용했어! 수고했어~" : "Used \(time)! Good work~"
    }
    static let bye = isKorean ? "바이바이~" : "Bye bye~"

    // MARK: - 도구별 알림

    static func toolMessage(for tool: String) -> String {
        switch tool.lowercased() {
        case "bash": return isKorean ? "명령어 실행 중..." : "Running command..."
        case "read": return isKorean ? "파일 읽는 중..." : "Reading file..."
        case "edit": return isKorean ? "코드 수정 중..." : "Editing code..."
        case "write": return isKorean ? "파일 작성 중..." : "Writing file..."
        case "grep": return isKorean ? "코드 검색 중..." : "Searching code..."
        case "glob": return isKorean ? "파일 찾는 중..." : "Finding files..."
        case "agent": return isKorean ? "에이전트 작업 중..." : "Agent working..."
        case "webcrawl", "webfetch", "websearch": return isKorean ? "웹 검색 중..." : "Searching web..."
        case "notebookedit": return isKorean ? "노트북 수정 중..." : "Editing notebook..."
        case let t where t.contains("task"): return isKorean ? "작업 관리 중..." : "Managing tasks..."
        case let t where t.contains("mcp"): return isKorean ? "플러그인 실행 중..." : "Running plugin..."
        default: return isKorean ? "작업 중..." : "Working..."
        }
    }

    // MARK: - 클릭 메시지

    static let clickWorking = isKorean
        ? ["지금 열심히 일하는 중!", "잠깐만, 거의 다 됐어!", "Claude가 코드 작성 중~"]
        : ["Working hard right now!", "Almost done, wait!", "Claude is coding~"]

    static let clickPermission = isKorean
        ? ["권한 승인이 필요해! 터미널 확인해줘!", "나 좀 도와줘~ 권한이 필요해!"]
        : ["Permission needed! Check terminal!", "Help me~ I need permission!"]

    static let clickIdle = isKorean
        ? ["뭐~ 심심해?", "나 건드리지 마~ 간지러워!", "놀아줄 거야?", "왜왜왜~ 뭐 필요해?"]
        : ["Bored?", "Don't poke me~ ticklish!", "Wanna play?", "What do you need?"]

    static let clickNotRunning = isKorean
        ? ["Claude Code가 꺼져있어~", "나 혼자 심심해..."]
        : ["Claude Code is off~", "I'm lonely..."]

    static let doubleClick = isKorean ? "우왕! 신난다~!" : "Woah! So fun~!"

    // MARK: - 랜덤 말걸기

    static let idleMessages = isKorean
        ? ["오늘 코딩 많이 했어?", "잠깐 스트레칭 하는 건 어때?", "커피 한잔 어때요~",
           "버그 없는 하루 되길!", "git commit 했어?", "오늘도 화이팅!",
           "난 여기서 지켜보고 있을게~", "세미콜론 빼먹지 않았지?"]
        : ["Done much coding today?", "How about a stretch?", "Coffee break?",
           "Bug-free day!", "Did you git commit?", "You got this!",
           "I'm watching over you~", "Didn't forget a semicolon?"]

    static let workingMessages = isKorean
        ? ["열심히 작업 중이야!", "잘 되고 있어!", "곧 끝날 거야!"]
        : ["Working hard!", "Going well!", "Almost done!"]

    // MARK: - 모델 멘트

    static func modelReactions(_ name: String) -> [String] {
        return isKorean
            ? ["난 \(name)이야, 최고지!", "난 \(name)! 멋지지?", "난 \(name), 잘 부탁해!",
               "\(name) 등장! 반가워~", "난 \(name)이야, 믿고 맡겨!"]
            : ["I'm \(name), the best!", "I'm \(name)! Cool right?", "I'm \(name), nice to meet you!",
               "\(name) is here!", "I'm \(name), trust me!"]
    }

    // MARK: - 토큰 마일스톤

    static let tokenMilestones: [(Int, String)] = isKorean
        ? [(10, "오늘 10K 토큰 사용!"), (50, "오늘 50K 돌파!"),
           (100, "오늘 100K! 열심히 일하는 중!"), (200, "오늘 200K...많이 썼다!"),
           (500, "오늘 500K!! 대작업이었구나!"), (1000, "오늘 1M!!! 역대급이야!")]
        : [(10, "10K tokens today!"), (50, "50K reached!"),
           (100, "100K! Working hard!"), (200, "200K... that's a lot!"),
           (500, "500K!! Big project!"), (1000, "1M!!! That's legendary!")]

    // MARK: - Desktop 시간 알림

    static func desktopTimeAlert(_ mins: Int) -> [String] {
        return isKorean
            ? ["\(mins)분 지났어!", "\(mins)분이야! 스트레칭 어때?", "벌써 \(mins)분! 물 한잔 마셔!"]
            : ["\(mins) min passed!", "\(mins) min! How about a stretch?", "\(mins) min already! Drink some water!"]
    }

    // MARK: - 스킨

    static let skinBasic = isKorean ? "기본" : "Basic"
    static let skinSpring = isKorean ? "봄 에디션 🌸" : "Spring 🌸"
    static let skinChanged: (Bool) -> String = { isSpring in
        isSpring
            ? (isKorean ? "봄이 왔어! 🌸" : "Spring is here! 🌸")
            : (isKorean ? "기본 스킨으로 돌아왔어!" : "Back to default skin!")
    }

    // MARK: - 우클릭 메뉴

    static let menuWorking = isKorean ? "🔵 작업 중" : "🔵 Working"
    static let menuPermission = isKorean ? "🟡 권한 대기" : "🟡 Permission"
    static let menuIdle = isKorean ? "🟢 대기 중" : "🟢 Idle"
    static let menuOff = isKorean ? "⚫ 꺼짐" : "⚫ Off"
    static let menuWorkTime = isKorean ? "작업시간 표시" : "Show work time"
    static let menuSkin = isKorean ? "스킨" : "Skins"
    static let menuUpdate = isKorean ? "업데이트!" : "Update!"
    static let menuQuit = isKorean ? "종료" : "Quit"
    static let menuTodayWork: (String) -> String = { time in
        isKorean ? "📊 오늘 총 작업: \(time)" : "📊 Today: \(time)"
    }

    // MARK: - 업데이트

    static let updateAvailable: (String) -> String = { ver in
        isKorean ? "새 버전 v\(ver) 나왔어! 우클릭→업데이트!" : "New v\(ver) available! Right-click→Update!"
    }
    static let updateLatest: (String) -> String = { ver in
        isKorean ? "최신 버전이에요! (v\(ver))" : "You're up to date! (v\(ver))"
    }
    static let updateStarted = isKorean ? "업데이트 시작! 터미널을 확인해줘!" : "Updating! Check terminal!"
    static let updateChecking = isKorean ? "업데이트 확인 중..." : "Checking updates..."
}
