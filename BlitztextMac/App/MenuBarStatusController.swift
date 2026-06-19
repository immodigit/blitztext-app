import AppKit

enum MenuBarStatus: Equatable {
    case idle
    case recording(WorkflowType)
    case processing(WorkflowType)
    case success(WorkflowType?)
    case error(WorkflowType?)
}

@MainActor
final class MenuBarStatusController {
    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var currentStatus: MenuBarStatus = .idle

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        renderCurrentStatus()
    }

    func update(to status: MenuBarStatus) {
        currentStatus = status
        animationFrame = 0
        configureAnimationIfNeeded()
        renderCurrentStatus()
    }

    private func configureAnimationIfNeeded() {
        stopAnimation()

        switch currentStatus {
        case .recording:
            startAnimation(interval: 0.12)
        case .processing:
            startAnimation(interval: 0.18)
        default:
            break
        }
    }

    private func startAnimation(interval: TimeInterval) {
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick() {
        animationFrame = (animationFrame + 1) % 4
        renderCurrentStatus()
    }

    private func renderCurrentStatus() {
        guard let button else { return }
        button.image = MenuBarStatusIconRenderer.makeImage(for: currentStatus, frame: animationFrame)
        button.image?.isTemplate = true
        button.toolTip = tooltip(for: currentStatus)
    }

    private func tooltip(for status: MenuBarStatus) -> String {
        switch status {
        case .idle:
            return "Blitztext ist bereit"
        case .recording(let type):
            return "\(type.displayName): Aufnahme läuft"
        case .processing(let type):
            return "\(type.displayName): Verarbeitung läuft"
        case .success(let type):
            if let type {
                return "\(type.displayName): Fertig"
            }
            return "Blitztext: Fertig"
        case .error(let type):
            if let type {
                return "\(type.displayName): Fehler"
            }
            return "Blitztext: Fehler"
        }
    }

    deinit {
        animationTimer?.invalidate()
    }
}

private enum MenuBarStatusIconRenderer {
    static func makeImage(for status: MenuBarStatus, frame: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            drawBaseIcon(in: bounds, status: status, frame: frame)

            switch status {
            case .recording(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .recording
                )
            case .processing(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .processing
                )
            case .success:
                drawBadge(systemName: "checkmark", in: bounds, fillOpacity: 1.0)
            case .error:
                drawBadge(systemName: "exclamationmark", in: bounds, fillOpacity: 1.0)
            default:
                break
            }

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }

    private enum ActivityPhase {
        case recording
        case processing
    }

    private static func drawBaseIcon(in bounds: CGRect, status: MenuBarStatus, frame: Int) {
        // Blitz-Glyphe (Template, einfarbig). Normalisierte Punkte (y nach oben).
        let pts: [(CGFloat, CGFloat)] = [
            (0.56, 0.95), (0.30, 0.50), (0.48, 0.50),
            (0.44, 0.05), (0.70, 0.52), (0.52, 0.52),
        ]
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX + pts[0].0 * bounds.width,
                              y: bounds.minY + pts[0].1 * bounds.height))
        for p in pts.dropFirst() {
            path.line(to: NSPoint(x: bounds.minX + p.0 * bounds.width,
                                  y: bounds.minY + p.1 * bounds.height))
        }
        path.close()
        NSColor.black.withAlphaComponent(boltAlpha(for: status, frame: frame)).setFill()
        path.fill()
    }

    /// Volldeckend in Ruhe; sanftes Pulsieren während Aufnahme/Verarbeitung.
    private static func boltAlpha(for status: MenuBarStatus, frame: Int) -> CGFloat {
        switch status {
        case .recording, .processing:
            let pulse: [CGFloat] = [1.0, 0.78, 0.55, 0.78]
            return pulse[frame % pulse.count]
        default:
            return 1.0
        }
    }

    private static func drawActivityBadge(
        type: WorkflowType,
        systemName: String,
        in bounds: CGRect,
        frame: Int,
        phase: ActivityPhase
    ) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgeOpacity: CGFloat
        let haloOpacity: CGFloat

        switch phase {
        case .recording:
            let values: [CGFloat]
            switch type {
            case .transcription, .localTranscription:
                values = [0.74, 1.0, 0.82, 0.92]
            case .textImprover:
                values = [0.66, 0.84, 1.0, 0.8]
            case .dampfAblassen:
                values = [1.0, 0.76, 0.94, 0.68]
            case .emojiText:
                values = [0.8, 0.92, 0.7, 1.0]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.14 + (CGFloat(frame % 4) * 0.04)
        case .processing:
            let values: [CGFloat]
            switch type {
            case .transcription, .localTranscription:
                values = [0.58, 0.72, 0.9, 0.72]
            case .textImprover:
                values = [0.48, 0.68, 0.92, 0.84]
            case .dampfAblassen:
                values = [0.84, 0.62, 0.9, 0.56]
            case .emojiText:
                values = [0.54, 0.76, 0.88, 0.68]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.12 + (CGFloat((frame + 2) % 4) * 0.03)
        }

        let haloInset = phase == .recording ? -0.8 : -0.45
        let haloRect = badgeRect.insetBy(dx: haloInset, dy: haloInset)
        let haloPath = NSBezierPath(ovalIn: haloRect)
        NSColor.black.withAlphaComponent(haloOpacity).setStroke()
        haloPath.lineWidth = phase == .recording ? 0.9 : 0.75
        haloPath.stroke()

        drawBadge(systemName: systemName, in: bounds, fillOpacity: badgeOpacity)

        if phase == .processing {
            drawProcessingDot(around: badgeRect, frame: frame)
        }
    }

    private static func drawBadge(systemName: String, in bounds: CGRect, fillOpacity: CGFloat) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.black.withAlphaComponent(fillOpacity).setFill()
        badgePath.fill()

        guard let symbol = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        ) else {
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 5.5, weight: .bold)
        let configuredSymbol = symbol.withSymbolConfiguration(config) ?? symbol
        let symbolRect = badgeRect.insetBy(dx: 1.2, dy: 1.2)
        configuredSymbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .destinationOut,
            fraction: 1.0
        )
    }

    private static func drawProcessingDot(around badgeRect: CGRect, frame: Int) {
        let orbitPoints: [CGPoint] = [
            CGPoint(x: badgeRect.midX, y: badgeRect.maxY + 0.35),
            CGPoint(x: badgeRect.maxX + 0.35, y: badgeRect.midY),
            CGPoint(x: badgeRect.midX, y: badgeRect.minY - 0.35),
            CGPoint(x: badgeRect.minX - 0.35, y: badgeRect.midY),
        ]
        let point = orbitPoints[frame % orbitPoints.count]
        let dotRect = CGRect(x: point.x - 0.85, y: point.y - 0.85, width: 1.7, height: 1.7)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor.black.withAlphaComponent(0.92).setFill()
        dotPath.fill()
    }

    private static func badgeSymbol(for type: WorkflowType) -> String {
        switch type {
        case .transcription:
            return "mic.fill"
        case .localTranscription:
            return "lock.shield.fill"
        case .textImprover:
            return "text.alignleft"
        case .dampfAblassen:
            return "flame.fill"
        case .emojiText:
            return "face.smiling"
        }
    }

}
