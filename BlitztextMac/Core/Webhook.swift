import Foundation

// MARK: - Quellen

/// Welche Art Ergebnis an den Webhook gehen darf. Der Nutzer wählt pro Quelle —
/// eine Sprachnachricht gehört in die Wissensdatenbank, ein schnelles Diktat
/// in ein Chatfenster meist nicht.
public enum WebhookSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case voiceMessage
    case dictation
    case rewrite

    public var id: String { rawValue }

    public init(workflow: WorkflowType) {
        switch workflow {
        case .transcription, .localTranscription: self = .dictation
        case .textImprover, .dampfAblassen, .emojiText: self = .rewrite
        }
    }

    /// Einzahl, wie sie in der Nutzlast steht.
    public var label: String {
        switch self {
        case .voiceMessage: return "Sprachnachricht"
        case .dictation: return "Diktat"
        case .rewrite: return "Umformung"
        }
    }

    /// Beschriftung des Schalters in den Einstellungen.
    public var settingsTitle: String {
        switch self {
        case .voiceMessage: return "Sprachnachrichten"
        case .dictation: return "Diktate (Blitztext, Lokal)"
        case .rewrite: return "Umformungen (Blitztext+, $%&!, :))"
        }
    }
}

// MARK: - Einstellungen

/// Ob und wofür der Webhook benutzt wird. Ziel-URL und Token liegen nicht hier,
/// sondern im Keychain — eine n8n-Webhook-URL ist selbst ein Geheimnis.
public struct WebhookSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var sources: Set<WebhookSource>

    public static let `default` = WebhookSettings(isEnabled: false, sources: [.voiceMessage])

    public init(isEnabled: Bool, sources: Set<WebhookSource>) {
        self.isEnabled = isEnabled
        self.sources = sources
    }

    public func sendsAutomatically(_ source: WebhookSource) -> Bool {
        isEnabled && sources.contains(source)
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        // Als Strings lesen: eine Quelle aus einer neueren Version darf nicht crashen.
        if let raw = try container.decodeIfPresent([String].self, forKey: .sources) {
            sources = Set(raw.compactMap(WebhookSource.init(rawValue:)))
        } else {
            sources = Self.default.sources
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        // Sortiert, damit die settings.json bei jedem Speichern gleich aussieht.
        try container.encode(sources.map(\.rawValue).sorted(), forKey: .sources)
    }
}

// MARK: - Ziel-URL

public enum WebhookEndpoint {
    public enum Problem: Error, Equatable, Sendable {
        case empty
        case malformed
        case insecure

        public var message: String {
            switch self {
            case .empty: return "Keine Webhook-URL hinterlegt."
            case .malformed: return "Das ist keine gültige Webhook-URL (https://…)."
            case .insecure: return "Unverschlüsseltes http ist nur für diesen Mac (localhost) erlaubt. Bitte https verwenden."
            }
        }
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Transkripte sind vertraulich: über das Netz nur verschlüsselt.
    public static func validate(_ raw: String) -> Result<URL, Problem> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              let url = components.url else {
            return .failure(.malformed)
        }
        switch scheme {
        case "https":
            return .success(url)
        case "http":
            return loopbackHosts.contains(host) ? .success(url) : .failure(.insecure)
        default:
            return .failure(.malformed)
        }
    }

    /// n8n-Test-URLs nehmen nur Anfragen an, solange der Editor „Listen for test event“ zeigt.
    public static func isN8nTestURL(_ url: URL) -> Bool {
        url.path.contains("/webhook-test/")
    }
}

// MARK: - Antwort

public enum WebhookResponse {
    /// Verständliche Fehlermeldung zum HTTP-Status — `nil` bei Erfolg.
    public static func problem(forStatus status: Int) -> String? {
        switch status {
        case 200..<300:
            return nil
        case 401, 403:
            return "Zugriff verweigert (HTTP \(status)). Token in Blitztext und im n8n-Webhook prüfen."
        case 404:
            return "Webhook nicht gefunden (HTTP 404). Ist der n8n-Workflow aktiv? Test-URLs funktionieren nur, solange der Editor lauscht."
        case 500..<600:
            return "Der Workflow ist mit einem Fehler abgebrochen (HTTP \(status))."
        default:
            return "Unerwartete Antwort vom Webhook (HTTP \(status))."
        }
    }
}

// MARK: - Nutzlast

public enum WebhookTranscriptionEngine: String, Codable, Sendable {
    case local
    case openAI = "openai"
}

/// Was Blitztext an den Webhook schickt. Feldnamen sind ein Vertrag mit den
/// Workflows der Nutzer — nur ergänzen, nie umbenennen; sonst `schema` hochzählen.
public struct WebhookPayload: Encodable, Sendable {
    public static let schemaVersion = "blitztext.transcript.v1"

    public struct Segment: Encodable, Equatable, Sendable {
        public let start: Double
        public let end: Double
        public let text: String
    }

    public struct AppInfo: Encodable, Equatable, Sendable {
        public let name: String
        public let version: String
    }

    public let schema: String
    public let id: String
    public let source: WebhookSource
    public let sourceLabel: String
    public let workflow: WorkflowType?
    public let createdAt: Date
    public let text: String
    public let language: String
    public let transcription: WebhookTranscriptionEngine
    public let fileName: String?
    /// Aufnahmezeitpunkt aus den Audio-Metadaten — nie aus dem Dateisystem
    /// (das ist bei Exporten das Exportdatum).
    public let recordedAt: Date?
    public let durationSeconds: Double?
    public let segments: [Segment]?
    public let app: AppInfo
    public let isTest: Bool

    public init(
        id: UUID = UUID(),
        source: WebhookSource,
        workflow: WorkflowType?,
        createdAt: Date = Date(),
        text: String,
        language: String,
        transcription: WebhookTranscriptionEngine,
        fileName: String?,
        recordedAt: Date?,
        durationSeconds: Double?,
        segments: [SubtitleCue],
        appVersion: String,
        isTest: Bool = false
    ) {
        self.schema = Self.schemaVersion
        self.id = id.uuidString
        self.source = source
        self.sourceLabel = source.label
        self.workflow = workflow
        self.createdAt = createdAt
        self.text = text
        self.language = language
        self.transcription = transcription
        self.fileName = fileName
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.segments = segments.isEmpty ? nil : segments.map { Segment(start: $0.start, end: $0.end, text: $0.text) }
        self.app = AppInfo(name: "Blitztext", version: appVersion)
        self.isTest = isTest
    }

    /// Testnachricht aus den Einstellungen — der Workflow kann sie an `isTest` erkennen und verwerfen.
    public static func test(appVersion: String) -> WebhookPayload {
        WebhookPayload(
            source: .voiceMessage,
            workflow: nil,
            text: "Testnachricht von Blitztext. Wenn du das in n8n siehst, kommt der Webhook an.",
            language: "de",
            transcription: .local,
            fileName: "blitztext-test.m4a",
            recordedAt: nil,
            durationSeconds: nil,
            segments: [],
            appVersion: appVersion,
            isTest: true
        )
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
