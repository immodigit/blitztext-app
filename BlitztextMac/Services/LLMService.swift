import Foundation
import BlitztextCore

enum LLMError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenAI API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Verbindungsproblem: \(msg)"
        case .apiError(let msg):
            return "Fehler von OpenAI: \(msg)"
        case .noContent:
            return "Keine Antwort erhalten. Bitte nochmal versuchen."
        }
    }
}

enum RewriteModel: String {
    case fastEdit = "gpt-4o-mini"
    case rageMode = "gpt-4o"
}

private struct OpenAIChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?
}

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}

enum LLMService {
    private static let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    /// Austauschbares lokales Umform-Backend.
    enum LocalRewriteEngine: Equatable {
        case none                  // Cloud (OpenAI)
        case apple                 // Apples on-device Modell (macOS 26+)
        case ollama(model: String) // Lokaler Ollama-Dienst, frei wählbares Modell
    }

    static func improve(
        text: String,
        settings: TextImprovementSettings,
        model: RewriteModel = .fastEdit,
        localEngine: LocalRewriteEngine = .none
    ) async throws -> String {
        // Eigennamen-Liste nur an die Cloud (GPT setzt sie korrekt nur bei Vorkommen ein).
        // Lokale Modelle neigen dazu, die Begriffe fälschlich einzubauen — daher dort weglassen.
        try await run(
            text: text,
            systemPrompt: buildSystemPrompt(settings: settings, includeTerms: localEngine == .none),
            model: model,
            temperature: 0.3,
            localEngine: localEngine
        )
    }

    static func dampfAblassen(
        text: String,
        systemPrompt: String,
        model: RewriteModel = .rageMode,
        localEngine: LocalRewriteEngine = .none
    ) async throws -> String {
        try await run(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: 0.4,
            localEngine: localEngine
        )
    }

    static func addEmojis(
        text: String,
        settings: EmojiTextSettings,
        model: RewriteModel = .fastEdit,
        localEngine: LocalRewriteEngine = .none
    ) async throws -> String {
        try await run(
            text: text,
            systemPrompt: buildEmojiSystemPrompt(density: settings.emojiDensity),
            model: model,
            temperature: 0.3,
            localEngine: localEngine
        )
    }

    /// Wählt das Backend. Bei einem lokal gewählten Lauf wird bewusst NICHT
    /// still auf die Cloud zurückgefallen — sonst würde das lokale Versprechen
    /// unbemerkt gebrochen (ein Fehler wird durchgereicht).
    private static func run(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double,
        localEngine: LocalRewriteEngine
    ) async throws -> String {
        switch localEngine {
        case .apple:
            if AppleFoundationRewriter.isAvailable, #available(macOS 26.0, *) {
                let output = try await AppleFoundationRewriter.rewrite(text: text, instructions: systemPrompt)
                return LocalRewriteSanitizer.clean(output)
            }
        case .ollama(let ollamaModel):
            let output = try await OllamaRewriteService.rewrite(text: text, instructions: systemPrompt, model: ollamaModel)
            return LocalRewriteSanitizer.clean(output)
        case .none:
            break
        }
        return try await complete(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: temperature
        )
    }

    private static func complete(
        text: String,
        systemPrompt: String,
        model: RewriteModel,
        temperature: Double
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: .openAIAPIKey) else {
            throw LLMError.notConfigured
        }

        let payload = OpenAIChatRequest(
            model: model.rawValue,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text),
            ],
            temperature: temperature
        )

        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Keine gültige Antwort")
        }

        guard httpResponse.statusCode == 200 else {
            throw LLMError.apiError(openAIErrorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = result.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noContent
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func openAIErrorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error?.message
    }

    private static func buildEmojiSystemPrompt(density: EmojiTextSettings.EmojiDensity) -> String {
        let densityInstruction: String
        switch density {
        case .wenig:
            densityInstruction = "Setze nur vereinzelt Emojis ein, maximal 1-2 pro Absatz."
        case .mittel:
            densityInstruction = "Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze."
        case .viel:
            densityInstruction = "Setze grosszuegig Emojis ein, gerne mehrere pro Satz."
        }

        return "Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, aber fuege passende Emojis ein. \(densityInstruction) Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. Gib NUR den Text mit Emojis zurueck, keine Erklaerungen."
    }

    /// Schreibweise-Hilfe: NUR korrigieren, falls ein Begriff vorkommt — niemals hinzufügen.
    private static func termsHint(_ terms: [String]) -> String {
        guard !terms.isEmpty else { return "" }
        return "\n\nSchreibweise: Falls — und nur falls — eines dieser Wörter im Text vorkommt, schreibe es exakt so. Füge KEINES davon von dir aus hinzu, wenn es nicht im Text steht: \(terms.joined(separator: ", "))"
    }

    /// Strikte Ausgabe: nur der fertige Text, kein Drumherum.
    private static let strictOutputRule =
        "\n\nGib AUSSCHLIESSLICH den fertigen Text aus. Keine Einleitung, keine Erklärung, keine Hinweise oder Anmerkungen davor oder danach, keine Markdown-Formatierung (** _ #), keine Trennlinien (---), keine Platzhalter wie [Dein Name]."

    private static func buildSystemPrompt(settings: TextImprovementSettings, includeTerms: Bool = true) -> String {
        let terms = includeTerms ? settings.customTerms : []
        if !settings.systemPrompt.isEmpty {
            return settings.systemPrompt + termsHint(terms) + strictOutputRule
        }

        var prompt = """
        Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
        - Korrigiere Rechtschreibung und Grammatik
        - Verbessere die Formulierung und den Lesefluss
        - Behalte die ursprüngliche Bedeutung und die Sprache bei
        - Behalte die Anrede bei (aus „du" wird kein „Sie" und umgekehrt)
        - Verdrehe die Aussage nicht und erfinde keine zusätzlichen Fakten
        """

        switch settings.tone {
        case .formal:
            prompt += "\n- Verwende einen formellen, professionellen Ton"
        case .neutral:
            prompt += "\n- Verwende einen neutralen, klaren Ton"
        case .casual:
            prompt += "\n- Verwende einen lockeren, natürlichen Ton"
        }

        if !settings.context.isEmpty {
            prompt += "\n\nKontext: \(settings.context)"
        }

        return prompt + termsHint(terms) + strictOutputRule
    }
}
