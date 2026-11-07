import SwiftUI
import BlitztextCore

// MARK: - Workflow Accent Color (eine Quelle für Zeilen, Popover und HUD)

extension WorkflowType {
    var color: Color {
        switch self {
        case .transcription: return .blue
        case .localTranscription: return .green
        case .textImprover: return .purple
        case .dampfAblassen: return .orange
        case .emojiText: return .cyan
        }
    }
}

struct WorkflowRowView: View {
    let type: WorkflowType
    let enabled: Bool
    var customName: String? = nil
    /// Nur gesetzt, wenn es etwas zu sagen gibt (z. B. warum die Zeile
    /// deaktiviert ist). Im Normalfall bleibt die Zeile bewusst ruhig.
    var subtitle: String? = nil
    /// Markiert, dass dieser Modus Text ins Netz schickt, obwohl der Rest
    /// lokal läuft. Nur die Abweichung wird gezeigt, nicht der Normalfall.
    var sendsOnline: Bool = false
    /// Beschriftung des Kürzels. Nil, wenn der Workflow unbelegt ist —
    /// dann bleibt der Badge weg statt eine tote Taste zu versprechen.
    var hotkeyLabel: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                // Icon in der Workflow-Farbe — gleiche Farbe wie im Status-HUD,
                // damit der Nutzer Aktion und Overlay sofort zuordnet.
                ModeIcon(icon: type.icon, tint: type.color, size: 34)
                    .opacity(enabled ? 1 : 0.45)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(customName ?? type.displayName)
                            .font(.ui(13.5, .semibold))
                            .foregroundStyle(enabled ? .primary : .tertiary)
                            .lineLimit(1)

                        if sendsOnline {
                            Image(systemName: "icloud")
                                .font(.ui(10, .semibold))
                                .foregroundStyle(BlitztextTheme.warning)
                                .help("Dieser Modus sendet den Text an OpenAI.")
                                .accessibilityLabel("sendet online")
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.ui(11.5))
                            .foregroundStyle(enabled ? .secondary : .tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 6)

                if let hotkeyLabel {
                    HotkeyBadge(label: hotkeyLabel, enabled: enabled)
                        .opacity(enabled ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered && enabled ? Color.primary.opacity(0.05) : Color.clear)
            )
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help("Startet \(customName ?? type.displayName)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Hotkey Badge

struct HotkeyBadge: View {
    let label: String
    let enabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(label.components(separatedBy: " + "), id: \.self) { key in
                Text(key)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(keyTextColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(keyBackgroundColor)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(keyStrokeColor, lineWidth: 0.8)
                    )
                    .shadow(color: keyShadowColor, radius: 1.2, y: 0.6)
            }
        }
    }

    private var keyTextColor: Color {
        guard enabled else {
            return colorScheme == .dark
                ? Color.white.opacity(0.34)
                : Color.black.opacity(0.26)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.84)
            : Color.black.opacity(0.72)
    }

    private var keyBackgroundColor: Color {
        guard enabled else {
            return colorScheme == .dark
                ? Color.white.opacity(0.05)
                : Color.black.opacity(0.035)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.09)
    }

    private var keyStrokeColor: Color {
        guard enabled else {
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.06)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.20)
            : Color.black.opacity(0.16)
    }

    private var keyShadowColor: Color {
        guard enabled else { return .clear }

        return colorScheme == .dark
            ? Color.black.opacity(0.10)
            : Color.black.opacity(0.06)
    }
}
