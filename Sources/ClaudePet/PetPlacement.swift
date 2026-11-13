import Cocoa

/// 펫이 어디서 어떻게 지낼지 — 우클릭/메뉴바 메뉴의 "펫 배치"에서 바꾸고 UserDefaults 에 저장한다.
/// (세션을 여러 개 띄우면 펫들이 화면 아래 창 내용을 가리던 문제 대응)
enum PetPlacement {
    private static let defaults = UserDefaults.standard

    /// 펫이 지낼 화면: "dock"(Dock 있는 화면, 기본) · "follow"(키보드 포커스 화면 따라가기 — 예전 동작) · 디스플레이 ID
    static var screenChoice: String {
        get { defaults.string(forKey: "claudepet_pet_screen") ?? "dock" }
        set { defaults.set(newValue, forKey: "claudepet_pet_screen") }
    }

    /// 커서가 다가가면 반투명 + 클릭 통과 (⌥ 를 누르고 있으면 평소처럼 잡힘)
    static var hoverFade: Bool {
        get { defaults.bool(forKey: "claudepet_hover_fade") }
        set { defaults.set(newValue, forKey: "claudepet_hover_fade") }
    }

    /// 펫이 gatherMinimum 마리 이상이면 화면 오른쪽 아래 구석에 줄지어 모여 있기
    static var gather: Bool {
        get { defaults.bool(forKey: "claudepet_gather") }
        set { defaults.set(newValue, forKey: "claudepet_gather") }
    }
    static let gatherMinimum = 3

    /// 지금 설정 기준으로 펫이 지낼 화면
    static var screen: NSScreen? {
        switch screenChoice {
        case "follow": return NSScreen.main
        case "dock": return dockScreen
        case let id: return NSScreen.screens.first { displayID(of: $0) == id } ?? dockScreen
        }
    }

    /// Dock 이 있는 화면. Dock 이 보이면 그 화면, 자동 숨김이면 마지막으로 Dock 이 보였던 화면, 그것도 없으면 메인 화면.
    static var dockScreen: NSScreen? {
        if let screen = insetDockScreen { return screen }
        if let id = lastDockScreenID, let screen = NSScreen.screens.first(where: { displayID(of: $0) == id }) {
            return screen
        }
        return NSScreen.screens.first
    }

    /// 1초마다 호출 — Dock 이 보이면 그 화면을 기억해 둔다.
    /// Dock 이 보이면 visibleFrame 만으로 알 수 있고, 자동 숨김일 때만 창 목록을 조회한다 (1회 1ms 안팎).
    static func refreshDockScreen() {
        let seen = insetDockScreen ?? (screenChoice == "dock" ? screenShowingDockWindow() : nil)
        guard let screen = seen else { return }
        let id = displayID(of: screen)
        if lastDockScreenID != id { lastDockScreenID = id }
    }

    /// 마지막으로 Dock 이 보였던 화면 (디스플레이 ID)
    private static var lastDockScreenID: String? {
        get { defaults.string(forKey: "claudepet_last_dock_screen") }
        set { defaults.set(newValue, forKey: "claudepet_last_dock_screen") }
    }

    /// Dock 이 자리를 차지해 visibleFrame 이 아래·옆으로 줄어든 화면 — 자동 숨김이면 줄어들지 않아서 없다
    private static var insetDockScreen: NSScreen? {
        NSScreen.screens.first { s in
            s.visibleFrame.minY - s.frame.minY > 8
                || s.visibleFrame.minX - s.frame.minX > 8
                || s.frame.maxX - s.visibleFrame.maxX > 8
        }
    }

    /// Dock 레벨 창이 떠 있는 화면 — 자동 숨김이면 Dock 이 튀어나와 있는 동안에만 창이 있다
    private static func screenShowingDockWindow() -> NSScreen? {
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let dock = windows.first(where: {
                  ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == dockLevel
              }),
              let boundsDict = dock[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayBounds(number.uint32Value).contains(center)
        }
    }

    static func displayID(of screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "\(number.uint32Value)"
        }
        return screen.localizedName
    }
}
