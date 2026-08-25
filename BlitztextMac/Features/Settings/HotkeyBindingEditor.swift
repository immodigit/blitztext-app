import SwiftUI
import BlitztextCore

/// Belegt die Kürzel neu. Grund: `fn` gibt es auf vielen externen Tastaturen
/// nicht — dort wird sie in der Tastatur-Firmware verarbeitet und erreicht
/// macOS nie. Ohne Umbelegen wäre die App an so einer Tastatur tot.
struct HotkeyBindingEditor: View {
    let appState: AppState

    @State private var capturing: WorkflowType?
    @State private var livePreview: Set<HotkeyModifier> = []
    @State private var notice: Notice?

    private struct Notice: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private var bindings: HotkeyBindingSet { appState.appSettings.hotkeyBindings }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetPicker

            VStack(spacing: 2) {
                ForEach(WorkflowType.allCases) { type in
                    row(for: type)
                }
            }

            if let notice {
                Text(notice.text)
                    .font(.system(size: 10))
                    .foregroundStyle(notice.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
            } else if usesFunctionKey {
                Text("Die fn-Taste gibt es nicht auf jeder externen Tastatur — bei manchen erreicht sie macOS gar nicht. Falls die Kürzel dort nicht reagieren: „Externe Tastatur\u{201C} wählen oder einzeln neu belegen.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            stopCapture()
        }
    }

    private var usesFunctionKey: Bool {
        WorkflowType.allCases.contains { bindings[$0]?.usesFunctionKey == true }
    }

    // MARK: - Presets

    private var presetPicker: some View {
        let active = bindings.matchingPreset

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(HotkeyPreset.allCases) { preset in
                    Button {
                        stopCapture()
                        appState.applyHotkeyPreset(preset)
                        notice = Notice(text: "\(preset.displayName): \(preset.explanation)", isError: false)
                    } label: {
                        Text(preset.displayName)
                            .font(.system(size: 11, weight: active == preset ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(active == preset ? .accentColor : nil)
                }
            }

            if active == nil {
                Text("Eigene Belegung")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Zeile pro Workflow

    @ViewBuilder
    private func row(for type: WorkflowType) -> some View {
        let isCapturing = capturing == type

        HStack(spacing: 8) {
            Text(appState.displayName(for: type))
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 6)

            if isCapturing {
                Text(livePreview.isEmpty
                     ? "Tasten halten\u{2026}"
                     : HotkeyBinding(livePreview).label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)

                Button("Abbrechen") { stopCapture() }
                    .controlSize(.mini)
                    .font(.system(size: 10))
            } else {
                if let shadowed = shadowHint(for: type) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .help(shadowed)
                }

                Text(bindings[type]?.label ?? "Nicht belegt")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(bindings[type] == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)

                Button("\u{00C4}ndern") { startCapture(for: type) }
                    .controlSize(.mini)
                    .font(.system(size: 10))

                Button {
                    stopCapture()
                    appState.clearHotkey(for: type)
                    notice = Notice(
                        text: "\(appState.displayName(for: type)) ist jetzt nur noch über das Menü erreichbar.",
                        isError: false
                    )
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .disabled(bindings[type] == nil)
                .help("Kürzel entfernen")
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Aufnahme

    private func startCapture(for type: WorkflowType) {
        capturing = type
        livePreview = []
        notice = Notice(text: "Halte die gewünschte Tastenkombination und lass sie wieder los. Mindestens zwei Tasten aus fn, Ctrl, Option, Shift, Cmd.", isError: false)

        appState.hotkeyService.beginChordCapture { state in
            switch state {
            case .idle:
                livePreview = []
            case .recording(let modifiers):
                livePreview = modifiers
            case .captured(let binding):
                apply(binding, to: type)
            case .rejected(.tooFewModifiers):
                stopCapture()
                notice = Notice(
                    text: "Zu wenig Tasten. Eine einzelne Taste wie Shift wird beim Tippen ständig gedrückt — nimm mindestens zwei.",
                    isError: true
                )
            }
        }
    }

    private func apply(_ binding: HotkeyBinding, to type: WorkflowType) {
        let conflicts = appState.assignHotkey(binding, to: type)
        stopCapture()

        guard conflicts.isEmpty else {
            let names = conflicts.map { appState.displayName(for: $0) }.joined(separator: ", ")
            notice = Notice(
                text: "\(binding.label) ist schon von \(names) belegt. Erst dort ändern oder entfernen.",
                isError: true
            )
            return
        }

        if let hint = shadowHint(for: type) {
            notice = Notice(text: "\(binding.label) gesetzt. \(hint)", isError: false)
        } else {
            notice = Notice(text: "\(appState.displayName(for: type)): \(binding.label)", isError: false)
        }
    }

    /// Warnt, wenn sich zwei Kürzel Tasten teilen. Das kürzere löst beim
    /// Drücken zuerst aus — das längere ist nur erreichbar, wenn die
    /// zusätzliche Taste zuletzt dazukommt.
    private func shadowHint(for type: WorkflowType) -> String? {
        guard let binding = bindings[type] else { return nil }
        let others = bindings.overlaps(with: binding, ignoring: type)
        guard !others.isEmpty else { return nil }
        let names = others.map { appState.displayName(for: $0) }.joined(separator: ", ")
        return "Teilt sich Tasten mit \(names): die gemeinsamen Tasten zuerst halten, die zusätzliche zuletzt drücken."
    }

    private func stopCapture() {
        appState.hotkeyService.endChordCapture()
        capturing = nil
        livePreview = []
    }
}
