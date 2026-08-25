import Cocoa
import Observation
import BlitztextCore

enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case hold    // Tasten halten = aufnehmen, loslassen = stoppen
    case toggle  // Einmal drücken = starten, nochmal/Escape = stoppen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold: return "Halten"
        case .toggle: return "Drücken"
        }
    }

    var description: String {
        switch self {
        case .hold: return "Tasten halten zum Aufnehmen, loslassen zum Stoppen"
        case .toggle: return "Einmal drücken zum Starten, nochmal oder Escape zum Stoppen"
        }
    }
}

enum HotkeyEvent {
    case down(WorkflowType)  // Keys pressed
    case up(WorkflowType)    // Keys released (for hold mode)
    case cancel              // Escape pressed
}

@Observable
@MainActor
final class HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var activeCombo: WorkflowType?  // Which combo is currently held

    /// Welche Kombination welchen Workflow startet. Wird von `AppState` aus den
    /// Einstellungen gesetzt — die Zuordnungslogik selbst liegt testbar in
    /// `BlitztextCore`.
    var bindings: HotkeyBindingSet = .default

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    // Aufnahme einer neuen Kombination in den Einstellungen. Solange sie läuft,
    // startet kein Workflow — sonst würde das Belegen selbst mitaufnehmen.
    private var chordRecorder: HotkeyChordRecorder?
    private var onChordState: ((HotkeyChordRecorderState) -> Void)?

    var isRecordingChord: Bool { chordRecorder != nil }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlags(event)
            }
            return event
        }
        // Escape key monitor for toggle mode
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                if event.keyCode == 53 { // Escape
                    self?.handleEscape()
                }
            }
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
    }

    // MARK: - Kombination aufnehmen

    /// Nimmt die nächste gehaltene Modifier-Kombination auf. Der Handler wird
    /// bei jedem Zwischenstand gerufen, damit die Einstellungen live anzeigen
    /// können, was gerade gedrückt ist.
    func beginChordCapture(_ handler: @escaping (HotkeyChordRecorderState) -> Void) {
        // Eine laufende Aufnahme sauber beenden, damit kein up-Event fehlt.
        if let combo = activeCombo {
            activeCombo = nil
            onHotkeyEvent?(.up(combo))
        }
        chordRecorder = HotkeyChordRecorder()
        onChordState = handler
    }

    func endChordCapture() {
        chordRecorder = nil
        onChordState = nil
    }

    // MARK: - Auswertung

    private func handleFlags(_ event: NSEvent) {
        let pressed = HotkeyModifier.set(fromEventFlags: event.modifierFlags.rawValue)

        if var recorder = chordRecorder {
            let state = recorder.handle(pressed: pressed)
            chordRecorder = recorder
            onChordState?(state)
            return
        }

        if let combo = bindings.workflow(matching: pressed) {
            if activeCombo == nil {
                activeCombo = combo
                onHotkeyEvent?(.down(combo))
            }
            return
        }

        // Keys released -- fire up event
        if let combo = activeCombo {
            activeCombo = nil
            onHotkeyEvent?(.up(combo))
        }
    }

    private func handleEscape() {
        guard chordRecorder == nil else { return }
        activeCombo = nil
        onHotkeyEvent?(.cancel)
    }
}
