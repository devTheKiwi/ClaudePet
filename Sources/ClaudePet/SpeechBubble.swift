import Cocoa

class SpeechBubbleWindow: NSWindow {
    private let label: NSTextField
    private let bubbleView: SpeechBubbleView
    private var dismissTimer: Timer?

    init() {
        let size = NSSize(width: 240, height: 60)
        label = NSTextField(labelWithString: "")
        bubbleView = SpeechBubbleView(frame: NSRect(origin: .zero, size: size))

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // 말풍선 뷰 설정
        self.contentView = bubbleView

        // 텍스트 레이블
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false

        bubbleView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor, constant: -4),
        ])
    }

    func show(text: String, at point: NSPoint, persistent: Bool = false) {
        dismissTimer?.invalidate()

        label.stringValue = text

        // 텍스트 크기에 맞게 윈도우 리사이즈
        let maxWidth: CGFloat = 260
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - 24, height: 100),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        )

        let bubbleWidth = max(textSize.width + 32, 80)
        let bubbleHeight = max(textSize.height + 28, 44)

        let windowSize = NSSize(width: bubbleWidth, height: bubbleHeight + 10) // +10 for tail
        let windowOrigin = NSPoint(x: point.x - windowSize.width / 2, y: point.y)

        // 화면 경계 체크
        var finalOrigin = windowOrigin
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            if finalOrigin.x < visibleFrame.origin.x {
                finalOrigin.x = visibleFrame.origin.x
            }
            if finalOrigin.x + windowSize.width > visibleFrame.maxX {
                finalOrigin.x = visibleFrame.maxX - windowSize.width
            }
        }

        setFrame(NSRect(origin: finalOrigin, size: windowSize), display: true)
        bubbleView.frame = NSRect(origin: .zero, size: windowSize)
        bubbleView.needsDisplay = true

        // 페이드인
        self.alphaValue = 0
        self.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 1.0
        }

        // persistent가 아닌 경우만 자동 사라짐
        if !persistent {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }
    }

    func forceDismiss() {
        dismissTimer?.invalidate()
        dismiss()
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}

// MARK: - Speech Bubble View (말풍선 그리기)

class SpeechBubbleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        let tailHeight: CGFloat = 8
        let bubbleRect = NSRect(
            x: 2,
            y: tailHeight + 2,
            width: bounds.width - 4,
            height: bounds.height - tailHeight - 4
        )

        // 말풍선 배경 (그림자)
        let shadowColor = NSColor(white: 0, alpha: 0.12)
        shadowColor.setFill()
        let shadowPath = NSBezierPath(
            roundedRect: bubbleRect.offsetBy(dx: 0, dy: -1),
            xRadius: 12, yRadius: 12
        )
        shadowPath.fill()

        // 말풍선 배경 (흰색)
        NSColor.white.setFill()
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 12, yRadius: 12)
        bubblePath.fill()

        // 말풍선 테두리
        NSColor(white: 0.85, alpha: 1.0).setStroke()
        bubblePath.lineWidth = 1.0
        bubblePath.stroke()

        // 꼬리 (삼각형)
        let tailPath = NSBezierPath()
        let tailCenterX = bounds.midX
        tailPath.move(to: NSPoint(x: tailCenterX - 6, y: tailHeight + 2))
        tailPath.line(to: NSPoint(x: tailCenterX, y: 0))
        tailPath.line(to: NSPoint(x: tailCenterX + 6, y: tailHeight + 2))
        tailPath.close()

        NSColor.white.setFill()
        tailPath.fill()

        // 꼬리 테두리 (양쪽 선만)
        NSColor(white: 0.85, alpha: 1.0).setStroke()
        let tailStroke = NSBezierPath()
        tailStroke.move(to: NSPoint(x: tailCenterX - 6, y: tailHeight + 2))
        tailStroke.line(to: NSPoint(x: tailCenterX, y: 0))
        tailStroke.line(to: NSPoint(x: tailCenterX + 6, y: tailHeight + 2))
        tailStroke.lineWidth = 1.0
        tailStroke.stroke()
    }
}
