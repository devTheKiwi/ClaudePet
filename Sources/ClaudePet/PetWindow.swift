import Cocoa

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
        let petSize = NSSize(width: 64, height: 64)

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

    // 세션별 색상
    private let bodyColor: NSColor
    private let bodyDarkColor: NSColor
    private let footColor: NSColor
    private let eyeWhite = NSColor.white
    private let pupilColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)

    init(frame: NSRect, color: PetColor) {
        self.bodyColor = color.body
        self.bodyDarkColor = color.bodyDark
        self.footColor = color.foot
        super.init(frame: frame)
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
    }

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
