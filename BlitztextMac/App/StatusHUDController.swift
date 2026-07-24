import AppKit
import SwiftUI
import OSLog

private let hudLogger = Logger(subsystem: "app.blitztext.mac", category: "StatusHUD")

/// Zeigt während Aufnahme und Verarbeitung ein festes Status-Overlay
/// unten mittig über dem Dock — immer an derselben Stelle, damit der Nutzer
/// weiß, wohin er schauen muss ("jetzt höre ich zu" → "jetzt transkribiere ich").
///
/// Ersetzt das frühere, am Text-Cursor klebende Overlay, das je nach App an
/// wechselnden Positionen auftauchte.
@MainActor
final class StatusHUDController {
    private static let hudSize = NSSize(width: 220, height: 56)
    /// Abstand über dem Dock (bzw. über der unteren Bildschirmkante).
    private static let bottomMargin: CGFloat = 20

    private let appState: AppState
    private let model = StatusHUDModel()
    private var panel: NSPanel?
    private var levelTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
    }

    func update(to status: MenuBarStatus) {
        hudLogger.debug("HUD status → \(String(describing: status), privacy: .public)")
        switch status {
        case .recording(let type):
            model.phase = .recording(type)
            showPanel()
            startLevelUpdates()
        case .processing(let type):
            model.phase = .processing(type)
            showPanel()
            stopLevelUpdates()
        case .idle, .success, .error:
            hidePanel()
        }
    }

    // MARK: - Panel

    private func showPanel() {
        if panel == nil {
            let panel = makePanel()
            self.panel = panel
        }
        position(panel!)
        panel!.orderFrontRegardless()
    }

    private func hidePanel() {
        stopLevelUpdates()
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.hudSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hostingView = NSHostingView(rootView: StatusHUDView(model: model))
        hostingView.frame = NSRect(origin: .zero, size: Self.hudSize)
        panel.contentView = hostingView
        return panel
    }

    /// Immer unten mittig auf dem Hauptbildschirm — `visibleFrame` schließt Dock
    /// und Menüleiste aus, sodass das Overlay stabil knapp über dem Dock sitzt.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + Self.bottomMargin
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Pegel-Aktualisierung

    /// Kopiert den Mikrofon-Pegel ~30×/s in das Model, damit die Wellenform
    /// live reagiert — unabhängig von SwiftUI-Observation über Existentials.
    private func startLevelUpdates() {
        guard levelTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.model.audioLevel = self.appState.liveAudioLevel
            }
        }
        // .common: Pegel fließt auch während Event-Tracking weiter ins Overlay.
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
        model.audioLevel = 0
    }

    deinit {
        levelTimer?.invalidate()
    }
}

// MARK: - Model

@MainActor
@Observable
final class StatusHUDModel {
    enum Phase: Equatable {
        case recording(WorkflowType)
        case processing(WorkflowType)
    }

    var phase: Phase = .recording(.transcription)
    var audioLevel: Float = 0
}

// MARK: - View

private struct StatusHUDView: View {
    let model: StatusHUDModel

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .recording(let type):
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(type.color)
            WaveformView(
                audioLevel: model.audioLevel,
                isRecording: true,
                accentColor: type.color,
                barCount: 22
            )
            .frame(width: 97)
            Text("Ich höre zu \u{2026}")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize()

        case .processing(let type):
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
            Text(processingLabel(type))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize()
        }
    }

    private func processingLabel(_ type: WorkflowType) -> String {
        switch type {
        case .transcription, .localTranscription:
            return "Transkribiert \u{2026}"
        case .textImprover:
            return "Formt um \u{2026}"
        case .dampfAblassen:
            return "Beruhigt \u{2026}"
        case .emojiText:
            return "Setzt Emojis \u{2026}"
        }
    }

}
