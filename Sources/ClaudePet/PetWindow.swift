import Cocoa

// MARK: - Pet Skin

enum PetSkinType: String, CaseIterable {
    case basic = "기본"
    case spring = "봄 에디션 🌸"
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

        // === 스킨 악세서리 ===
        if skin == .spring {
            drawSpringAccessory(centerX: centerX, headTopY: headY + headHeight, bounceY: bounceY)
            updateAndDrawPetals()
        }
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
