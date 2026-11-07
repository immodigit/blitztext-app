import SwiftUI
import AppKit

// Ruhige Oberfläche: helle Seite, weiße Karten (nachts dunkle Flächen),
// die Akzentfarbe nur für Aktionen und Auswahl. Bewusst nur Systemschrift
// und eigene Farben — keine Marken-Tokens aus dem Original-Projekt.

enum BlitztextTheme {
    static let accent = dynamic(light: 0x3346D3, dark: 0x8C9BFF)
    /// Text und Symbole auf gefülltem Akzent.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0F1116)
    /// Tonale Flächen (Knöpfe, Auswahl): Akzent in geringer Stärke.
    static let tonal = dynamic(light: 0x3346D3, dark: 0x8C9BFF).opacity(0.13)
    static let onTonal = dynamic(light: 0x1F2FB0, dark: 0xDCE1FF)

    static let ready = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    /// Seite hinter den Karten.
    static let page = dynamic(light: 0xF3F3F6, dark: 0x1C1D22)
    /// Karten und gruppierte Zeilen.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2A2B32)
    /// Flächen innerhalb einer Karte (Felder, Tasten).
    static let inset = dynamic(light: 0xF3F3F6, dark: 0x35363E)

    static let cardShadow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .clear
            : NSColor(srgbRed: 0.05, green: 0.07, blue: 0.11, alpha: 0.07)
    })
    static let cardEdge = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : .clear
    })

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension Font {
    /// Systemschrift in fester Größe (der Mac kennt kein Dynamic Type).
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Karten

private struct CardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(BlitztextTheme.card)
                    .shadow(color: BlitztextTheme.cardShadow, radius: 3, x: 0, y: 1)
            }
            .overlay {
                shape.strokeBorder(BlitztextTheme.cardEdge, lineWidth: 1)
            }
            .clipShape(shape)
    }
}

extension View {
    /// Eine Karte auf der Seite.
    func card(cornerRadius: CGFloat = 14) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Bausteine

/// Abschnittstitel über einer Karte: neutral, damit der Akzent bei den Aktionen bleibt.
struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.ui(12, .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 2)
    }
}

/// Kompakter Hinweis mit Symbol, Text und optionaler Aktion.
struct NoticeRow: View {
    let icon: String
    let title: String
    var detail: String?
    var tint: Color = BlitztextTheme.accent
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.ui(12, .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ui(12, .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.tonalAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.10)))
    }
}

/// Kopf für Unterseiten: runder Zurück-Knopf, Titel mittig, optional rechts etwas.
struct PageHeader<Trailing: View>: View {
    let title: String
    var icon: String? = nil
    var iconTint: Color = .secondary
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.ui(12, .semibold))
                        .foregroundStyle(iconTint)
                }
                Text(title)
                    .font(.ui(14, .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 70)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(BlitztextTheme.card))
                        .shadow(color: BlitztextTheme.cardShadow, radius: 2, y: 1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Zur\u{00FC}ck")
                .accessibilityLabel("Zur\u{00FC}ck")

                Spacer()

                trailing
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, icon: String? = nil, iconTint: Color = .secondary, onBack: @escaping () -> Void) {
        self.init(title: title, icon: icon, iconTint: iconTint, onBack: onBack, trailing: { EmptyView() })
    }
}

/// Symbol einer Funktion im Kreis ihrer Farbe.
struct ModeIcon: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .font(.ui(size * 0.42, .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

/// Sprechblase: rund, nur die Ecke unten links spitz — wie eine Nachricht.
struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: r,
            bottomLeadingRadius: r * 0.22,
            bottomTrailingRadius: r,
            topTrailingRadius: r,
            style: .continuous
        )
        .path(in: rect)
    }
}

// MARK: - Knöpfe

/// Ohne Fläche, nur ein weiches Drücken. Bleibt ohne Innenabstand, weil die
/// Einstellungen und Unterseiten ihn so verwenden.
struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Tonale Kapsel für Nebenaktionen, gefüllte Kapsel für die eine Hauptaktion.
struct CapsuleActionButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration, filled: filled)
    }

    private struct CapsuleBody: View {
        let configuration: ButtonStyleConfiguration
        let filled: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.ui(12, .semibold))
                .foregroundStyle(filled ? BlitztextTheme.onAccent : BlitztextTheme.onTonal)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(filled ? BlitztextTheme.accent : BlitztextTheme.tonal)
                    Capsule().fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                }
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}

extension ButtonStyle where Self == SubtleButtonStyle {
    static var subtle: SubtleButtonStyle { SubtleButtonStyle() }
}

extension ButtonStyle where Self == CapsuleActionButtonStyle {
    static var tonalAction: CapsuleActionButtonStyle { CapsuleActionButtonStyle(filled: false) }
    static var filledAction: CapsuleActionButtonStyle { CapsuleActionButtonStyle(filled: true) }
}
