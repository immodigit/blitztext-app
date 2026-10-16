import AVFoundation
import BlitztextCore
import Foundation

enum WebhookError: LocalizedError {
    case endpoint(WebhookEndpoint.Problem)
    case rejected(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .endpoint(let problem): return problem.message
        case .rejected(let message): return message
        case .network(let message): return "Webhook nicht erreichbar: \(message)"
        }
    }
}

/// Schickt Ergebnisse als JSON an den Webhook des Nutzers (z. B. n8n).
/// Was dort passiert (Analyse, Ablage in der Wissensdatenbank), entscheidet der Workflow.
enum WebhookService {
    /// Header, den der n8n-Webhook per „Header Auth“ prüfen kann.
    static let tokenHeader = "X-Blitztext-Token"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static func send(_ payload: WebhookPayload) async throws {
        let url: URL
        switch WebhookEndpoint.validate(KeychainService.load(key: .webhookURL) ?? "") {
        case .success(let valid): url = valid
        case .failure(let problem): throw WebhookError.endpoint(problem)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Blitztext/\(appVersion)", forHTTPHeaderField: "User-Agent")
        if let token = KeychainService.load(key: .webhookToken) {
            request.setValue(token, forHTTPHeaderField: tokenHeader)
        }
        request.httpBody = try payload.encodedJSON()

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw WebhookError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw WebhookError.network("keine HTTP-Antwort")
        }
        if let problem = WebhookResponse.problem(forStatus: http.statusCode) {
            throw WebhookError.rejected(problem)
        }
    }
}

/// Liest Aufnahmezeit und Dauer aus den Audio-Metadaten. Dateisystem-Zeitstempel
/// taugen nicht: bei Exporten aus der Sprachmemo-App sind sie das Exportdatum.
enum AudioMetadataReader {
    static func read(from url: URL) async -> (recordedAt: Date?, durationSeconds: Double?) {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let seconds = duration.map(CMTimeGetSeconds).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }

        var recordedAt: Date?
        if let item = try? await asset.load(.creationDate) {
            recordedAt = try? await item.load(.dateValue)
        }
        return (recordedAt, seconds)
    }
}
