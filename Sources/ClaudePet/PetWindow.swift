import Cocoa

// MARK: - Pet Mode

enum PetMode {
    case code
    case desktop
}

// MARK: - Pet Skin

enum PetSkinType: String, CaseIterable {
    case basic = "기본"
    case spring = "봄 에디션 🌸"
    case summer = "여름 에디션 🍉"
    case autumn = "가을 에디션 🍁"
}

// MARK: - Petal Particle (봄 에디션용)

struct Petal {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var speed: CGFloat
    var swayPhase: CGFloat
    var rotation: CGFloat
    var alpha: CGFloat
}

// MARK: - Pet State

enum PetState {
    case idle
    case walkingLeft
    case walkingRight
    case jumping
    case happy
    case excited
}

// MARK: - Session Color

struct PetColor {
    let body: NSColor
    let bodyDark: NSColor
    let foot: NSColor

    static let palette: [PetColor] = [
        // Claude 오렌지 (기본)
        PetColor(
            body: NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1.0),
            bodyDark: NSColor(red: 0.72, green: 0.38, blue: 0.26, alpha: 1.0),
            foot: NSColor(red: 0.65, green: 0.33, blue: 0.22, alpha: 1.0)
        ),
        // 블루
        PetColor(
            body: NSColor(red: 0.38, green: 0.58, blue: 0.85, alpha: 1.0),
            bodyDark: NSColor(red: 0.28, green: 0.45, blue: 0.72, alpha: 1.0),
            foot: NSColor(red: 0.22, green: 0.38, blue: 0.62, alpha: 1.0)
        ),
        // 그린
        PetColor(
            body: NSColor(red: 0.40, green: 0.75, blue: 0.45, alpha: 1.0),
            bodyDark: NSColor(red: 0.30, green: 0.60, blue: 0.35, alpha: 1.0),
            foot: NSColor(red: 0.24, green: 0.50, blue: 0.28, alpha: 1.0)
        ),
        // 퍼플
        PetColor(
            body: NSColor(red: 0.65, green: 0.45, blue: 0.82, alpha: 1.0),
            bodyDark: NSColor(red: 0.52, green: 0.34, blue: 0.68, alpha: 1.0),
            foot: NSColor(red: 0.42, green: 0.28, blue: 0.58, alpha: 1.0)
        ),
        // 핑크
        PetColor(
            body: NSColor(red: 0.85, green: 0.42, blue: 0.58, alpha: 1.0),
            bodyDark: NSColor(red: 0.72, green: 0.32, blue: 0.46, alpha: 1.0),
            foot: NSColor(red: 0.60, green: 0.26, blue: 0.38, alpha: 1.0)
        ),
        // 틸
        PetColor(
            body: NSColor(red: 0.32, green: 0.72, blue: 0.70, alpha: 1.0),
            bodyDark: NSColor(red: 0.24, green: 0.58, blue: 0.56, alpha: 1.0),
            foot: NSColor(red: 0.18, green: 0.48, blue: 0.46, alpha: 1.0)
        ),
    ]
}

// MARK: - Pet Window

class PetWindow: NSWindow {
    let petView: PetView
    let sessionId: String

    init(sessionId: String, color: PetColor, startX: CGFloat? = nil) {
        self.sessionId = sessionId

        let screen = NSScreen.main!
        let visibleFrame = screen.visibleFrame
        let petSize = NSSize(width: 96, height: 64)

        let x = startX ?? CGFloat.random(in: visibleFrame.origin.x...(visibleFrame.maxX - petSize.width))
        let y = visibleFrame.origin.y

        let frame = NSRect(origin: NSPoint(x: x, y: y), size: petSize)

        petView = PetView(frame: NSRect(origin: .zero, size: petSize), color: color)

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = true
        self.contentView = petView

        petView.onPositionUpdate = { [weak self] dx in
            self?.movePet(dx: dx)
        }

        petView.startAnimating()
    }

    private func movePet(dx: CGFloat) {
        guard let screen = NSScreen.main else { return }
        var newFrame = self.frame
        newFrame.origin.x += dx

        let visibleFrame = screen.visibleFrame
        let minX = visibleFrame.origin.x
        let maxX = visibleFrame.origin.x + visibleFrame.width - newFrame.width

        if newFrame.origin.x <= minX {
            newFrame.origin.x = minX
            petView.setState(.walkingRight)
        } else if newFrame.origin.x >= maxX {
            newFrame.origin.x = maxX
            petView.setState(.walkingLeft)
        }

        newFrame.origin.y = visibleFrame.origin.y
        self.setFrame(newFrame, display: true)
    }
}

// MARK: - Pet View

class PetView: NSView {
    private var state: PetState = .idle
    private var animationFrame: Int = 0
    private var animationTimer: Timer?
    private var behaviorTimer: Timer?
    private var stateTimer: Timer?
    private let speed: CGFloat = 1.5

    var claudeStatus: ClaudeStatus = .notRunning
    var onPositionUpdate: ((CGFloat) -> Void)?
    var onClicked: (() -> Void)?
    var onDoubleClicked: (() -> Void)?
    var onRightClicked: ((NSEvent) -> Void)?
    var petMode: PetMode = .code
    var skin: PetSkinType = .basic {
        didSet { needsDisplay = true }
    }
    var workingSeconds: Int = 0
    var showTimer: Bool = true

    // 세션별 색상
    private let bodyColor: NSColor
    private let bodyDarkColor: NSColor
    private let footColor: NSColor
    private let eyeWhite = NSColor.white
    private let pupilColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)

    // 봄 에디션 파티클
    private var petals: [Petal] = []
    private let maxPetals = 8

    // 여름 에디션 파티클 (떠오르는 비눗방울)
    private var bubbles: [Petal] = []
    private let maxBubbles = 8

    // 가을 에디션 파티클 (떨어지는 낙엽)
    private var leaves: [Petal] = []
    private let maxLeaves = 8

    init(frame: NSRect, color: PetColor) {
        self.bodyColor = color.body
        self.bodyDarkColor = color.bodyDark
        self.footColor = color.foot
        super.init(frame: frame)
        // 저장된 스킨 불러오기
        if let saved = UserDefaults.standard.string(forKey: "claudepet_skin"),
           let skinType = PetSkinType(rawValue: saved) {
            self.skin = skinType
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClicked?()
        } else {
            onClicked?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClicked?(event)
    }

    func startAnimating() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        scheduleBehavior()
    }

    func setState(_ newState: PetState) {
        state = newState
        stateTimer?.invalidate()

        switch newState {
        case .jumping, .happy, .excited:
            stateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.scheduleBehavior()
            }
        default:
            break
        }
    }

    private func scheduleBehavior() {
        behaviorTimer?.invalidate()
        let delay = TimeInterval.random(in: 2.0...5.0)
        behaviorTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.pickRandomBehavior()
        }
    }

    private func pickRandomBehavior() {
        let roll = Int.random(in: 0...10)
        if roll < 4 {
            state = .idle
        } else if roll < 7 {
            state = .walkingRight
        } else {
            state = .walkingLeft
        }

        let duration = TimeInterval.random(in: 3.0...8.0)
        behaviorTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.pickRandomBehavior()
        }
    }

    private func tick() {
        animationFrame += 1

        switch state {
        case .walkingLeft:
            onPositionUpdate?(-speed)
        case .walkingRight:
            onPositionUpdate?(speed)
        default:
            break
        }

        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        let centerX = bounds.midX
        let baseY: CGFloat = 4

        let bounceY: CGFloat
        let footOffset: CGFloat

        switch state {
        case .idle:
            bounceY = sin(Double(animationFrame) * 0.2) * 2
            footOffset = 0
        case .walkingLeft, .walkingRight:
            bounceY = abs(sin(Double(animationFrame) * 0.3)) * 3
            footOffset = sin(Double(animationFrame) * 0.6) * 3
        case .jumping:
            let jumpPhase = Double(animationFrame % 30) / 30.0
            bounceY = sin(jumpPhase * .pi) * 15
            footOffset = 0
        case .happy:
            bounceY = abs(sin(Double(animationFrame) * 0.4)) * 5
            footOffset = sin(Double(animationFrame) * 0.8) * 2
        case .excited:
            bounceY = sin(Double(animationFrame) * 0.5) * 3
            footOffset = cos(Double(animationFrame) * 0.5) * 2
        }

        let bodyY = baseY + 10 + bounceY

        // === 발 ===
        footColor.setFill()
        let leftFootX = centerX - 14 + footOffset
        let rightFootX = centerX + 6 - footOffset
        let footY = baseY + bounceY

        NSBezierPath(roundedRect: NSRect(x: leftFootX, y: footY, width: 8, height: 10), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: rightFootX, y: footY, width: 8, height: 10), xRadius: 3, yRadius: 3).fill()

        // === 여름: 튜브 뒤쪽 (몸 뒤로 감김) ===
        if skin == .summer {
            drawSummerTubeBack(centerX: centerX, bodyY: bodyY)
        }

        // === 가을: 목도리 뒤쪽 (목 뒤로 감김) ===
        if skin == .autumn {
            drawAutumnScarfBack(centerX: centerX, bodyY: bodyY)
        }

        // === 몸통 ===
        bodyColor.setFill()
        let bodyWidth: CGFloat = 40
        let bodyHeight: CGFloat = 30
        let bodyX = centerX - bodyWidth / 2

        NSBezierPath(roundedRect: NSRect(x: bodyX, y: bodyY, width: bodyWidth, height: bodyHeight), xRadius: 14, yRadius: 12).fill()

        // === 머리 ===
        let headWidth: CGFloat = 32
        let headHeight: CGFloat = 18
        let headX = centerX - headWidth / 2
        let headY = bodyY + bodyHeight - 14

        NSBezierPath(roundedRect: NSRect(x: headX, y: headY, width: headWidth, height: headHeight), xRadius: 12, yRadius: 10).fill()

        // === 눈 ===
        let eyeY = bodyY + bodyHeight - 6
        let leftEyeX = centerX - 9
        let rightEyeX = centerX + 3

        eyeWhite.setFill()
        NSBezierPath(ovalIn: NSRect(x: leftEyeX, y: eyeY, width: 7, height: 8)).fill()
        NSBezierPath(ovalIn: NSRect(x: rightEyeX, y: eyeY, width: 7, height: 8)).fill()

        // 동공
        pupilColor.setFill()
        var pupilDx: CGFloat = 0
        switch state {
        case .walkingLeft: pupilDx = -1.5
        case .walkingRight: pupilDx = 1.5
        default: pupilDx = sin(Double(animationFrame) * 0.1) * 1
        }

        NSBezierPath(ovalIn: NSRect(x: leftEyeX + 2 + pupilDx, y: eyeY + 2.5, width: 3.5, height: 3.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: rightEyeX + 2 + pupilDx, y: eyeY + 2.5, width: 3.5, height: 3.5)).fill()

        // === 작업 중 이펙트 ===
        if claudeStatus == .working {
            drawWorkingEffect(centerX: centerX, topY: bodyY + bodyHeight + headHeight - 10)
        }

        // === 시간 뱃지 (왼쪽 대각선) ===
        if showTimer && workingSeconds > 0 {
            drawTimeBadge(bodyX: bodyX, headTopY: headY + headHeight, bounceY: bounceY)
        }

        // === Desktop 모드: 커피잔 ===
        if petMode == .desktop {
            drawCoffee(centerX: centerX, bodyY: bodyY, bounceY: bounceY)
        }

        // === 스킨 악세서리 ===
        if skin == .spring {
            drawSpringAccessory(centerX: centerX, headTopY: headY + headHeight, bounceY: bounceY)
            updateAndDrawPetals()
        }
        if skin == .summer {
            drawSummerAccessory(centerX: centerX, bodyY: bodyY, headTopY: headY + headHeight)
            updateAndDrawBubbles()
        }
        if skin == .autumn {
            drawAutumnAccessory(centerX: centerX, bodyY: bodyY, headTopY: headY + headHeight)
            updateAndDrawLeaves()
        }
    }

    // MARK: - Autumn Skin

    private let mapleColor     = NSColor(red: 0.753, green: 0.263, blue: 0.165, alpha: 1)
    private let mapleDarkColor = NSColor(red: 0.549, green: 0.173, blue: 0.110, alpha: 1)
    private let leafStemColor  = NSColor(red: 0.471, green: 0.306, blue: 0.173, alpha: 1)
    private let scarfColorA    = NSColor(red: 0.698, green: 0.243, blue: 0.173, alpha: 1)
    private let scarfColorB    = NSColor(red: 0.871, green: 0.776, blue: 0.620, alpha: 1)
    private let autumnLeafColors: [NSColor] = [
        NSColor(red: 0.753, green: 0.263, blue: 0.165, alpha: 1),   // 단풍 빨강
        NSColor(red: 0.839, green: 0.471, blue: 0.173, alpha: 1),   // 주황
        NSColor(red: 0.878, green: 0.706, blue: 0.243, alpha: 1),   // 은행 노랑
        NSColor(red: 0.588, green: 0.376, blue: 0.196, alpha: 1),   // 갈참
    ]

    /// 단풍잎 한 장. 골 반경을 얕게(0.55~) 두고 같은 색 stroke 를 덧대야
    /// 96x64 크기에서 뾰족한 별이 아니라 잎으로 읽힌다.
    private func drawMapleLeaf(cx: CGFloat, cy: CGFloat, s: CGFloat, tilt: CGFloat) {
        let pts: [(CGFloat, CGFloat)] = [
            (8, 0.66), (26, 0.56), (44, 0.90), (67, 0.55), (90, 1.00),
            (113, 0.55), (136, 0.90), (154, 0.56), (172, 0.66),
        ]
        NSGraphicsContext.saveGraphicsState()
        let xf = NSAffineTransform()
        xf.translateX(by: cx, yBy: cy)
        xf.rotate(byRadians: tilt)
        xf.concat()

        // 잎자루 — 길면 눈(headTopY-10 ~ -2)까지 내려와 '꽂힌' 모양이 된다
        leafStemColor.setStroke()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 0, y: 0))
        stem.line(to: NSPoint(x: -0.8, y: -s * 0.30))
        stem.lineWidth = 1.3
        stem.lineCapStyle = .round
        stem.stroke()

        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: 0, y: s * 0.06))
        for (deg, r) in pts {
            let a = deg * .pi / 180
            leaf.line(to: NSPoint(x: cos(a) * r * s, y: sin(a) * r * s))
        }
        leaf.close()
        leaf.lineJoinStyle = .round
        leaf.lineCapStyle = .round
        mapleColor.setFill()
        leaf.fill()
        mapleColor.setStroke()
        leaf.lineWidth = 2.6
        leaf.stroke()
        mapleDarkColor.setStroke()
        leaf.lineWidth = 0.8
        leaf.stroke()

        // 잎맥
        NSColor(red: 1.0, green: 0.91, blue: 0.84, alpha: 0.55).setStroke()
        for deg in [CGFloat(44), CGFloat(90), CGFloat(136)] {
            let a = deg * .pi / 180
            let vein = NSBezierPath()
            vein.move(to: NSPoint(x: 0, y: s * 0.12))
            vein.line(to: NSPoint(x: cos(a) * s * 0.58, y: sin(a) * s * 0.58))
            vein.lineWidth = 0.8
            vein.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // 목도리 중심 y — 목이 없는 체형이라 얼굴이 아니라 머리 아래 어깨선에 걸쳐야 '두른' 것으로 읽힌다
    private func autumnScarfY(bodyY: CGFloat) -> CGFloat { bodyY + 13 }

    /// 줄무늬 목도리 한 장 (호출 측 클립으로 앞/뒤 절반만 보이게)
    private func drawAutumnScarfBand(centerX: CGFloat, bodyY: CGFloat) {
        let sy = autumnScarfY(bodyY: bodyY)
        let outerW: CGFloat = 40, outerH: CGFloat = 11
        let panels = 9
        let pw = outerW / CGFloat(panels)
        let oval = NSRect(x: centerX - outerW / 2, y: sy - outerH / 2, width: outerW, height: outerH)

        // 세로 패널로 니트 줄무늬 (파라솔 캐노피와 같은 트릭)
        for i in 0..<panels {
            NSGraphicsContext.saveGraphicsState()
            let sx = centerX - outerW / 2 + CGFloat(i) * pw
            NSBezierPath(rect: NSRect(x: sx, y: sy - outerH, width: pw + 0.5, height: outerH * 2)).addClip()
            (i % 2 == 0 ? scarfColorA : scarfColorB).setFill()
            NSBezierPath(ovalIn: oval).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(white: 0.0, alpha: 0.14).setStroke()
        let edge = NSBezierPath(ovalIn: oval)
        edge.lineWidth = 0.8
        edge.stroke()
    }

    /// 목도리 뒤쪽(위 절반) — 몸통 그리기 전에 호출
    private func drawAutumnScarfBack(centerX: CGFloat, bodyY: CGFloat) {
        let sy = autumnScarfY(bodyY: bodyY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: sy, width: bounds.width, height: bounds.height - sy)).addClip()
        drawAutumnScarfBand(centerX: centerX, bodyY: bodyY)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawAutumnAccessory(centerX: CGFloat, bodyY: CGFloat, headTopY: CGFloat) {
        // === 목도리 앞쪽(아래 절반) — 머리 그린 뒤라 '두른' 느낌 ===
        let sy = autumnScarfY(bodyY: bodyY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: sy)).addClip()
        drawAutumnScarfBand(centerX: centerX, bodyY: bodyY)
        NSGraphicsContext.restoreGraphicsState()

        // === 늘어진 꼬리 (걸음에 맞춰 흔들림) ===
        let sway = sin(CGFloat(animationFrame) * 0.16) * 1.6
        let tw: CGFloat = 6.5, tlen: CGFloat = 10
        NSGraphicsContext.saveGraphicsState()
        let tailXF = NSAffineTransform()
        tailXF.translateX(by: centerX + 10 + sway * 0.4, yBy: sy - 1)
        tailXF.rotate(byRadians: sway * 0.045)
        tailXF.concat()
        for i in 0..<4 {
            (i % 2 == 0 ? scarfColorA : scarfColorB).setFill()
            NSBezierPath(roundedRect: NSRect(x: -tw / 2, y: -CGFloat(i + 1) * (tlen / 4),
                                             width: tw, height: tlen / 4 + 0.4),
                         xRadius: 1.2, yRadius: 1.2).fill()
        }
        scarfColorB.setStroke()
        for f in [CGFloat(-1), CGFloat(0), CGFloat(1)] {
            let fringe = NSBezierPath()
            fringe.move(to: NSPoint(x: f * 2.2, y: -tlen))
            fringe.line(to: NSPoint(x: f * 2.2 + sway * 0.25, y: -tlen - 3))
            fringe.lineWidth = 1
            fringe.lineCapStyle = .round
            fringe.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // === 단풍잎 (머리 위로 띄움) ===
        let tilt = sin(CGFloat(animationFrame) * 0.09) * 0.10 - 0.30
        drawMapleLeaf(cx: centerX + 8.5, cy: headTopY + 2.5, s: 9.5, tilt: tilt)
    }

    private func updateAndDrawLeaves() {
        // 새 낙엽 추가
        if leaves.count < maxLeaves && animationFrame % 11 == 0 {
            leaves.append(Petal(
                x: CGFloat.random(in: -10...bounds.width + 10),
                y: bounds.height + 6,
                size: CGFloat.random(in: 3.0...5.4),
                speed: CGFloat.random(in: 0.30...0.75),
                swayPhase: CGFloat.random(in: 0...(2 * .pi)),
                rotation: CGFloat.random(in: 0...(2 * .pi)),
                alpha: CGFloat.random(in: 0.55...0.95)
            ))
        }

        var active: [Petal] = []
        for var leaf in leaves {
            leaf.y -= leaf.speed
            leaf.x += sin(leaf.swayPhase + leaf.y * 0.06) * 0.85
            leaf.rotation += 0.04 + leaf.speed * 0.06

            if leaf.y > -10 {
                // 색은 Petal 구조체를 건드리지 않으려고 swayPhase 에서 뽑는다
                let idx = Int(leaf.swayPhase * 100) % autumnLeafColors.count
                // cos(rotation) 으로 가로 폭을 줄여 뒤집히며 떨어지는 느낌
                let flip = abs(cos(leaf.rotation))
                let w = leaf.size * (0.35 + flip * 0.65)
                let h = leaf.size * 0.78

                NSGraphicsContext.saveGraphicsState()
                let leafXF = NSAffineTransform()
                leafXF.translateX(by: leaf.x, yBy: leaf.y)
                leafXF.rotate(byRadians: sin(leaf.swayPhase + leaf.y * 0.05) * 0.5)
                leafXF.concat()
                autumnLeafColors[idx].withAlphaComponent(leaf.alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: -w / 2, y: -h / 2, width: w, height: h)).fill()
                NSColor(red: 0.27, green: 0.16, blue: 0.08, alpha: 0.35).setStroke()
                let vein = NSBezierPath()
                vein.move(to: NSPoint(x: -w / 2, y: 0))
                vein.line(to: NSPoint(x: w / 2, y: 0))
                vein.lineWidth = 0.5
                vein.stroke()
                NSGraphicsContext.restoreGraphicsState()

                active.append(leaf)
            }
        }
        leaves = active
    }

    // MARK: - Time Badge

    private func drawTimeBadge(bodyX: CGFloat, headTopY: CGFloat, bounceY: CGFloat) {
        let totalMins = workingSeconds / 60
        let secs = workingSeconds % 60
        let timeText = String(format: "%02d:%02d", totalMins, secs)

        let font = NSFont.systemFont(ofSize: 8, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0.35, alpha: 1.0),
        ]
        let textSize = (timeText as NSString).size(withAttributes: attrs)

        let badgeWidth = textSize.width + 8
        let badgeHeight = textSize.height + 4
        let badgeX = bodyX - badgeWidth + 10
        let badgeY = headTopY + bounceY - 2

        // 뱃지 배경
        let bgColor = skin == .spring
            ? NSColor(red: 1.0, green: 0.93, blue: 0.95, alpha: 0.9)
            : NSColor(white: 0.95, alpha: 0.9)
        bgColor.setFill()
        let badge = NSBezierPath(roundedRect: NSRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight), xRadius: 5, yRadius: 5)
        badge.fill()

        // 뱃지 테두리
        let borderColor = skin == .spring
            ? NSColor(red: 0.9, green: 0.75, blue: 0.8, alpha: 0.7)
            : NSColor(white: 0.8, alpha: 0.7)
        borderColor.setStroke()
        badge.lineWidth = 0.5
        badge.stroke()

        // 텍스트
        (timeText as NSString).draw(at: NSPoint(x: badgeX + 4, y: badgeY + 2), withAttributes: attrs)
    }

    // MARK: - Coffee (Desktop Mode)

    private func drawCoffee(centerX: CGFloat, bodyY: CGFloat, bounceY: CGFloat) {
        let cupX = centerX + 16
        let cupY = bodyY + 6

        // 컵 몸통 (갈색)
        NSColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0).setFill()
        let cup = NSBezierPath(roundedRect: NSRect(x: cupX, y: cupY, width: 9, height: 10), xRadius: 2, yRadius: 2)
        cup.fill()

        // 컵 안쪽 커피 (진한 갈색)
        NSColor(red: 0.35, green: 0.20, blue: 0.10, alpha: 1.0).setFill()
        NSBezierPath(roundedRect: NSRect(x: cupX + 1.5, y: cupY + 6, width: 6, height: 3), xRadius: 1, yRadius: 1).fill()

        // 컵 손잡이
        NSColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0).setStroke()
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: cupX + 9, y: cupY + 7))
        handle.curve(to: NSPoint(x: cupX + 9, y: cupY + 3),
                     controlPoint1: NSPoint(x: cupX + 13, y: cupY + 7),
                     controlPoint2: NSPoint(x: cupX + 13, y: cupY + 3))
        handle.lineWidth = 1.5
        handle.stroke()

        // 김 (흰색 웨이브, 애니메이션)
        let steamAlpha: CGFloat = 0.6
        NSColor(white: 1.0, alpha: steamAlpha).setStroke()
        for i in 0..<2 {
            let steam = NSBezierPath()
            let sx = cupX + 3 + CGFloat(i) * 4
            let sy = cupY + 11
            let phase = Double(animationFrame) * 0.12 + Double(i) * 1.5
            steam.move(to: NSPoint(x: sx, y: sy))
            steam.curve(to: NSPoint(x: sx + sin(phase) * 2, y: sy + 7),
                       controlPoint1: NSPoint(x: sx + sin(phase) * 3, y: sy + 2),
                       controlPoint2: NSPoint(x: sx - sin(phase) * 3, y: sy + 5))
            steam.lineWidth = 1.0
            steam.stroke()
        }
    }

    // MARK: - Spring Skin

    private func drawSpringAccessory(centerX: CGFloat, headTopY: CGFloat, bounceY: CGFloat) {
        let flowerX = centerX + 8
        let flowerY = headTopY + 6

        // 꽃잎 5장 (분홍)
        let petalColor = NSColor(red: 1.0, green: 0.7, blue: 0.78, alpha: 0.95)
        petalColor.setFill()
        let petalSize: CGFloat = 4.5
        for i in 0..<5 {
            let angle = (Double(i) * 72.0 + Double(animationFrame) * 0.5) * .pi / 180.0
            let px = flowerX + cos(angle) * 3.5 - petalSize / 2
            let py = flowerY + sin(angle) * 3.5 - petalSize / 2
            NSBezierPath(ovalIn: NSRect(x: px, y: py, width: petalSize, height: petalSize)).fill()
        }

        // 꽃 중심 (노랑)
        NSColor(red: 1.0, green: 0.9, blue: 0.4, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: NSRect(x: flowerX - 2.5, y: flowerY - 2.5, width: 5, height: 5)).fill()

        // 줄기 (초록)
        NSColor(red: 0.4, green: 0.7, blue: 0.35, alpha: 1.0).setStroke()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: flowerX, y: flowerY - 3))
        stem.line(to: NSPoint(x: flowerX + 1, y: flowerY - 8))
        stem.lineWidth = 1.5
        stem.stroke()
    }

    private func updateAndDrawPetals() {
        // 새 꽃잎 추가
        if petals.count < maxPetals && animationFrame % 12 == 0 {
            petals.append(Petal(
                x: CGFloat.random(in: -10...bounds.width + 10),
                y: bounds.height + 5,
                size: CGFloat.random(in: 2.5...4.5),
                speed: CGFloat.random(in: 0.3...0.8),
                swayPhase: CGFloat.random(in: 0...(2 * .pi)),
                rotation: CGFloat.random(in: 0...(2 * .pi)),
                alpha: CGFloat.random(in: 0.5...0.9)
            ))
        }

        // 꽃잎 업데이트 및 그리기
        var activePetals: [Petal] = []
        for var petal in petals {
            petal.y -= petal.speed
            petal.x += sin(petal.swayPhase + petal.y * 0.05) * 0.5
            petal.rotation += 0.03

            if petal.y > -10 {
                // 그리기
                let pink = NSColor(red: 1.0, green: 0.75, blue: 0.82, alpha: petal.alpha)
                pink.setFill()
                let px = petal.x + sin(Double(petal.rotation)) * 1.5
                NSBezierPath(ovalIn: NSRect(x: px, y: petal.y, width: petal.size, height: petal.size * 0.7)).fill()
                activePetals.append(petal)
            }
        }
        petals = activePetals
    }

    // MARK: - Summer Skin

    // 튜브 중심 y (배 위치)
    private func summerRingY(bodyY: CGFloat) -> CGFloat { bodyY + 8 }

    /// 알록달록 도넛 튜브 한 장 (호출 측 클립으로 앞/뒤 절반만 보이게)
    private func drawSummerTube(centerX: CGFloat, bodyY: CGFloat) {
        let ringY = summerRingY(bodyY: bodyY)
        let outerW: CGFloat = 56, outerH: CGFloat = 26
        let innerW: CGFloat = 30, innerH: CGFloat = 12
        let donut = NSBezierPath()
        donut.appendOval(in: NSRect(x: centerX - outerW / 2, y: ringY - outerH / 2, width: outerW, height: outerH))
        donut.appendOval(in: NSRect(x: centerX - innerW / 2, y: ringY - innerH / 2, width: innerW, height: innerH))
        donut.windingRule = .evenOdd

        // 알록달록 8조각 — radial 웨지로 클립해 도넛을 색칠
        let colors: [NSColor] = [
            NSColor(red: 0.96, green: 0.30, blue: 0.33, alpha: 1),   // 빨강
            NSColor(red: 1.00, green: 0.82, blue: 0.25, alpha: 1),   // 노랑
            NSColor(red: 0.30, green: 0.72, blue: 0.95, alpha: 1),   // 파랑
            NSColor(white: 1.0, alpha: 1),                           // 흰
        ]
        for i in 0..<8 {
            NSGraphicsContext.saveGraphicsState()
            let wedge = NSBezierPath()
            wedge.move(to: NSPoint(x: centerX, y: ringY))
            wedge.appendArc(withCenter: NSPoint(x: centerX, y: ringY), radius: outerW,
                            startAngle: CGFloat(i) * 45, endAngle: CGFloat(i + 1) * 45)
            wedge.close()
            wedge.addClip()
            colors[i % colors.count].setFill()
            donut.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        // 안쪽 구멍 음영(입체감)
        NSColor(white: 0.0, alpha: 0.12).setStroke()
        let hole = NSBezierPath(ovalIn: NSRect(x: centerX - innerW / 2, y: ringY - innerH / 2, width: innerW, height: innerH))
        hole.lineWidth = 1
        hole.stroke()
    }

    /// 튜브 뒤쪽(위 절반) — 몸통 그리기 전에 호출해 몸 뒤로 감기게 함
    private func drawSummerTubeBack(centerX: CGFloat, bodyY: CGFloat) {
        let ringY = summerRingY(bodyY: bodyY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: ringY, width: bounds.width, height: bounds.height - ringY)).addClip()
        drawSummerTube(centerX: centerX, bodyY: bodyY)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSummerAccessory(centerX: CGFloat, bodyY: CGFloat, headTopY: CGFloat) {
        // === 튜브 앞쪽(아래 절반) — 몸통 앞으로 (배에 두른 느낌) ===
        let ringY = summerRingY(bodyY: bodyY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: ringY)).addClip()
        drawSummerTube(centerX: centerX, bodyY: bodyY)
        NSGraphicsContext.restoreGraphicsState()

        // === 비치 파라솔 (머리 위 — 알록달록 캐노피 + 막대) ===
        let pX = centerX + 5
        let rimY = headTopY + 6          // 캐노피 밑단
        let domeH: CGFloat = 6           // 캐노피 높이
        let halfW: CGFloat = 10          // 캐노피 반폭

        // 막대 (머리 → 캐노피)
        NSColor(red: 0.50, green: 0.40, blue: 0.36, alpha: 1.0).setStroke()
        let pole = NSBezierPath()
        pole.move(to: NSPoint(x: pX, y: headTopY))
        pole.line(to: NSPoint(x: pX, y: rimY))
        pole.lineWidth = 1.5
        pole.stroke()

        // 캐노피 = 위 절반 타원을 세로 패널로 색칠 (튜브와 같은 알록달록)
        let dome = NSRect(x: pX - halfW, y: rimY - domeH, width: halfW * 2, height: domeH * 2)
        let canopyColors: [NSColor] = [
            NSColor(red: 0.96, green: 0.30, blue: 0.33, alpha: 1),
            NSColor(red: 1.00, green: 0.82, blue: 0.25, alpha: 1),
            NSColor(red: 0.30, green: 0.72, blue: 0.95, alpha: 1),
            NSColor(white: 1.0, alpha: 1),
        ]
        let panels = 4
        let panelW = halfW * 2 / CGFloat(panels)
        for i in 0..<panels {
            NSGraphicsContext.saveGraphicsState()
            let sx = pX - halfW + CGFloat(i) * panelW
            NSBezierPath(rect: NSRect(x: sx, y: rimY, width: panelW + 0.5, height: domeH + 1)).addClip()
            canopyColors[i % canopyColors.count].setFill()
            NSBezierPath(ovalIn: dome).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        // 밑단 라인 + 꼭지
        NSColor(white: 0.0, alpha: 0.15).setStroke()
        let rimLine = NSBezierPath()
        rimLine.move(to: NSPoint(x: pX - halfW, y: rimY))
        rimLine.line(to: NSPoint(x: pX + halfW, y: rimY))
        rimLine.lineWidth = 0.8
        rimLine.stroke()
        NSColor(red: 0.96, green: 0.30, blue: 0.33, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: pX - 1.3, y: rimY + domeH - 1, width: 2.6, height: 2.6)).fill()
    }

    private func updateAndDrawBubbles() {
        // 아래에서 위로 떠오르는 비눗방울
        if bubbles.count < maxBubbles && animationFrame % 14 == 0 {
            bubbles.append(Petal(
                x: CGFloat.random(in: 8...max(9, bounds.width - 8)),
                y: -4,
                size: CGFloat.random(in: 2.5...5.0),
                speed: CGFloat.random(in: 0.4...0.9),
                swayPhase: CGFloat.random(in: 0...(2 * .pi)),
                rotation: 0,
                alpha: CGFloat.random(in: 0.35...0.7)
            ))
        }

        var active: [Petal] = []
        for var b in bubbles {
            b.y += b.speed
            b.x += sin(b.swayPhase + b.y * 0.05) * 0.4
            if b.y < bounds.height + 6 {
                let s = b.size
                NSColor(red: 0.60, green: 0.85, blue: 1.0, alpha: b.alpha * 0.35).setFill()   // 속(연한 물색)
                NSBezierPath(ovalIn: NSRect(x: b.x, y: b.y, width: s, height: s)).fill()
                NSColor(red: 0.72, green: 0.90, blue: 1.0, alpha: b.alpha).setStroke()         // 테두리
                let ring = NSBezierPath(ovalIn: NSRect(x: b.x, y: b.y, width: s, height: s))
                ring.lineWidth = 0.8
                ring.stroke()
                NSColor(white: 1.0, alpha: b.alpha).setFill()                                  // 반짝
                NSBezierPath(ovalIn: NSRect(x: b.x + s * 0.2, y: b.y + s * 0.55, width: s * 0.25, height: s * 0.25)).fill()
                active.append(b)
            }
        }
        bubbles = active
    }

    // MARK: - Effects

    private func drawWorkingEffect(centerX: CGFloat, topY: CGFloat) {
        let sparkleColor = NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.8)
        sparkleColor.setFill()

        let phase = Double(animationFrame) * 0.15
        for i in 0..<3 {
            let angle = phase + Double(i) * (2.0 * .pi / 3.0)
            let radius: CGFloat = 6
            let x = centerX + cos(angle) * radius - 1.5
            let y = topY + 8 + sin(angle) * radius - 1.5
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 3, height: 3)).fill()
        }
    }
}
