import Foundation

// MARK: - Workflow Types

/// Die Aktionen, die Blitztext auslösen kann.
///
/// Liegt bewusst in `BlitztextCore` (Foundation-only): Die Tastenbelegung
/// (`HotkeyBindingSet`) ordnet Kombinationen diesen Typen zu und ist damit
/// ohne Xcode/AppKit testbar.
public enum WorkflowType: String, CaseIterable, Identifiable, Codable, Sendable {
    case transcription
    case localTranscription
    case textImprover
    case dampfAblassen
    case emojiText

    public var id: String { rawValue }

    public static var mainMenuCases: [WorkflowType] {
        allCases.filter { $0 != .localTranscription }
    }

    public var displayName: String {
        switch self {
        case .transcription: return "Blitztext"
        case .localTranscription: return "Blitztext Lokal"
        case .textImprover: return "Blitztext+"
        case .dampfAblassen: return "Blitztext $%&!"
        case .emojiText: return "Blitztext :)"
        }
    }

    public var icon: String {
        switch self {
        case .transcription: return "mic.fill"
        case .localTranscription: return "lock.shield.fill"
        case .textImprover: return "text.badge.checkmark"
        case .dampfAblassen: return "flame.fill"
        case .emojiText: return "face.smiling"
        }
    }

    public var subtitle: String {
        switch self {
        case .transcription: return "Sprache rein. Text raus."
        case .localTranscription: return "Nur lokal. Kein Server."
        case .textImprover: return "Geschrieben sprechen."
        case .dampfAblassen: return "Frust rein. Entspannt raus."
        case .emojiText: return "Text rein. Emojis dazu."
        }
    }

    public var accentColor: String {
        switch self {
        case .transcription: return "blue"
        case .localTranscription: return "green"
        case .textImprover: return "purple"
        case .dampfAblassen: return "orange"
        case .emojiText: return "cyan"
        }
    }
}
