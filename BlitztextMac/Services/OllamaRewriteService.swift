import Foundation

/// Lokale Textumformung über einen laufenden Ollama-Dienst (localhost:11434).
/// Das Modell ist frei wählbar (qwen, gemma, llama …) — also austauschbar.
enum OllamaRewriteService {
    static let baseURL = URL(string: "http://localhost:11434")!

    struct ProbeResult {
        let reachable: Bool
        let models: [String]
    }

    /// Prüft, ob der Dienst läuft und welche Modelle installiert sind.
    static func probe() async -> ProbeResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return ProbeResult(reachable: false, models: [])
            }
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            return ProbeResult(reachable: true, models: decoded.models.map(\.name))
        } catch {
            return ProbeResult(reachable: false, models: [])
        }
    }

    /// Formt Text lokal um. `instructions` ist der System-Prompt.
    static func rewrite(text: String, instructions: String, model: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        let body = ChatRequest(
            model: model,
            stream: false,
            messages: [
                .init(role: "system", content: instructions),
                .init(role: "user", content: text),
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.message("Ungültige Antwort vom lokalen Modell.")
        }
        guard http.statusCode == 200 else {
            throw OllamaError.message("Lokales Modell „\(model)“ antwortete mit Status \(http.statusCode). Läuft Ollama und ist das Modell geladen?")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw OllamaError.message("Leere Antwort vom lokalen Modell.")
        }
        return content
    }

    enum OllamaError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case let .message(text) = self { return text }
            return nil
        }
    }

    // MARK: - DTOs

    private struct TagsResponse: Decodable {
        let models: [Model]
        struct Model: Decodable { let name: String }
    }

    private struct ChatRequest: Encodable {
        let model: String
        let stream: Bool
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct ChatResponse: Decodable {
        let message: Message
        struct Message: Decodable { let content: String }
    }
}
