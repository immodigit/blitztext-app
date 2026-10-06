import SwiftUI
import AppKit
import Charts
import BlitztextCore

// MARK: - Redeanteile

/// Ring mit dem Redeanteil je Person, daneben die Legende mit genauen Werten —
/// die Zuordnung hängt so nie an der Farbe allein.
struct TalkShareChart: View {
    let shares: [TalkShare]

    /// Die einzigen vier Farben der Standardpalette, die im Ring (jedes Segment
    /// kann an jedes grenzen) in Hell und Dunkel alle Paarprüfungen bestehen.
    static let palette: [Color] = [
        dynamic(light: 0x2A78D6, dark: 0x3987E5),   // Blau
        dynamic(light: 0xEDA100, dark: 0xC98500),   // Gelb
        dynamic(light: 0xE87BA4, dark: 0xD55181),   // Magenta
        dynamic(light: 0x008300, dark: 0x008300),   // Grün
    ]
    private static let neutral = dynamic(light: 0x9B9A94, dark: 0x6F6E69)

    var body: some View {
        if shares.count >= 2 {
            HStack(alignment: .center, spacing: 14) {
                Chart(Array(shares.enumerated()), id: \.offset) { _, share in
                    SectorMark(
                        angle: .value("Redezeit", share.seconds),
                        innerRadius: .ratio(0.58),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(color(for: share))
                }
                .chartLegend(.hidden)
                .frame(width: 76, height: 76)
                .accessibilityLabel("Redeanteile")
                .accessibilityValue(shares.map { "\($0.name) \($0.percent) Prozent" }.joined(separator: ", "))

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { _, share in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color(for: share))
                                .frame(width: 8, height: 8)
                            Text(share.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text("\(share.percent) %")
                                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                            Text(SpeakerTranscriptFormatter.timecode(share.seconds))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(for share: TalkShare) -> Color {
        guard let slot = share.colorSlot, slot < Self.palette.count else { return Self.neutral }
        return Self.palette[slot]
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
