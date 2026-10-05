import Foundation
import BlitztextCore

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
    case idle
    case running(String)
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum WorkflowLaunchSource: Equatable {
    case manual
    case hotkeyBackground

    var presentsWorkflowPage: Bool {
        switch self {
        case .manual:
            return true
        case .hotkeyBackground:
            return false
        }
    }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
    var type: WorkflowType { get }
    var phase: WorkflowPhase { get set }
    var isRecording: Bool { get }
    var audioLevel: Float { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }

    func start()
    func stop()
    func reset()
}

// MARK: - App Settings

struct AppSettings: Codable {
    /// Obergrenze für den lokalen Transkript-Verlauf.
    static let maxHistoryLimit = 20

    var hotkeyMode: HotkeyMode = .hold
    var hasSeenOnboarding: Bool = false
    var secureLocalModeEnabled: Bool = false
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName
    var hasAutoSelectedFastLocalModel: Bool = false
    /// Lokales Umform-Modell über Ollama (austauschbar, z. B. qwen2.5:3b, gemma3:4b).
    var ollamaModelName: String = "qwen2.5:7b"
    /// Wie viele der letzten Ergebnisse lokal aufbewahrt werden (0 = aus).
    var historyLimit: Int = 5
    /// Welche Tastenkombination welchen Workflow startet. Frei belegbar, weil
    /// viele externe Tastaturen keine nutzbare fn-Taste haben.
    var hotkeyBindings: HotkeyBindingSet = .default
    /// Erkennt in Sprachnachrichten-Dateien, wer was gesagt hat (nur lokaler Modus).
    var speakerRecognitionEnabled: Bool = true

    init(
        hotkeyMode: HotkeyMode = .hold,
        hasSeenOnboarding: Bool = false,
        secureLocalModeEnabled: Bool = false,
        selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName,
        hasAutoSelectedFastLocalModel: Bool = false,
        ollamaModelName: String = "qwen2.5:7b",
        historyLimit: Int = 5,
        hotkeyBindings: HotkeyBindingSet = .default,
        speakerRecognitionEnabled: Bool = true
    ) {
        self.hotkeyMode = hotkeyMode
        self.hasSeenOnboarding = hasSeenOnboarding
        self.secureLocalModeEnabled = secureLocalModeEnabled
        self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
        self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
        self.ollamaModelName = ollamaModelName
        self.historyLimit = historyLimit
        self.hotkeyBindings = hotkeyBindings
        self.speakerRecognitionEnabled = speakerRecognitionEnabled
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case secureLocalModeEnabled
        case selectedLocalTranscriptionModelName
        case hasAutoSelectedFastLocalModel
        case ollamaModelName
        case historyLimit
        case hotkeyBindings
        case speakerRecognitionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyMode = try container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode) ?? .hold
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        secureLocalModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled) ?? false
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.recommendedFastModelName
        hasAutoSelectedFastLocalModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAutoSelectedFastLocalModel
        ) ?? false
        ollamaModelName = try container.decodeIfPresent(String.self, forKey: .ollamaModelName) ?? "qwen2.5:7b"
        let decodedLimit = try container.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 5
        historyLimit = min(max(decodedLimit, 0), Self.maxHistoryLimit)
        // Ältere settings.json kennt das Feld nicht -> bisherige fn-Kürzel.
        // `repaired()` wirft ungültige oder doppelte Belegungen aus einer von
        // Hand bearbeiteten Datei raus, statt sie stumm wirken zu lassen.
        hotkeyBindings = (try container.decodeIfPresent(HotkeyBindingSet.self, forKey: .hotkeyBindings))?
            .repaired() ?? .default
        speakerRecognitionEnabled = try container.decodeIfPresent(Bool.self, forKey: .speakerRecognitionEnabled) ?? true
    }
}

// MARK: - Transcript History

/// Ein aufbewahrtes Ergebnis, damit ein in das falsche Feld getippter Text
/// nicht verloren geht. Bleibt rein lokal auf dem Gerät.
struct TranscriptHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let type: WorkflowType
    let date: Date

    init(id: UUID = UUID(), text: String, type: WorkflowType, date: Date) {
        self.id = id
        self.text = text
        self.type = type
        self.date = date
    }
}

enum TranscriptionBackend: String, Codable {
    case remote
    case local
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
    var language: String = "de"
}

struct DampfAblassenSettings: Codable {
    var systemPrompt: String = "Du erhältst ein emotional gesprochenes Transkript. Erkenne zuerst das eigentliche Ziel, Anliegen und den wahren Frust der Person. Formuliere daraus eine klare, respektvolle und wirksame Nachricht, mit der die Person ihr Ziel eher erreicht. Bewahre relevante Fakten, konkrete Probleme, Grenzen, Erwartungen und die nötige Dringlichkeit. Entferne Beleidigungen, Drohungen, Sarkasmus, Unterstellungen und unnötige Eskalation. Wenn mehrere Vorwürfe genannt werden, verdichte sie auf die entscheidenden Kernpunkte. Der Ton soll ruhig, menschlich, bestimmt und lösungsorientiert sein. Gib NUR die fertige Nachricht zurück."
    var customName: String = ""
}

struct EmojiTextSettings: Codable {
    var emojiDensity: EmojiDensity = .mittel
    var customName: String = ""

    enum EmojiDensity: String, Codable, CaseIterable, Identifiable {
        case wenig
        case mittel
        case viel

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .wenig: return "Wenig"
            case .mittel: return "Mittel"
            case .viel: return "Viel"
            }
        }
    }
}

struct TextImprovementSettings: Codable {
    var systemPrompt: String = ""
    var customTerms: [String] = []
    var context: String = ""
    var tone: TextTone = .neutral
    var customName: String = ""

    enum TextTone: String, Codable, CaseIterable, Identifiable {
        case formal
        case neutral
        case casual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .formal: return "Formell"
            case .neutral: return "Neutral"
            case .casual: return "Locker"
            }
        }
    }
}
