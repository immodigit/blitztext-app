import AVFoundation
import UniformTypeIdentifiers

/// Extrahiert die Tonspur aus einem Video in eine temporäre m4a-Datei,
/// damit WhisperKit (das nur Audio liest) Videos transkribieren kann.
enum VideoAudioExtractor {
    /// True, wenn die Datei ein Video-Container ist (mp4, mov, …).
    static func isVideo(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie)) ?? false
    }

    /// Exportiert nur die Audiospur als m4a in den Temp-Ordner und liefert den Pfad.
    static func extractAudioToTemporaryFile(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitztext-audio-\(UUID().uuidString).m4a")

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(
                domain: "Blitztext",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Die Tonspur dieses Videos konnte nicht vorbereitet werden."]
            )
        }
        export.outputURL = outputURL
        export.outputFileType = .m4a

        await withCheckedContinuation { continuation in
            export.exportAsynchronously { continuation.resume() }
        }

        guard export.status == .completed else {
            throw export.error ?? NSError(
                domain: "Blitztext",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Audio-Extraktion aus dem Video ist fehlgeschlagen."]
            )
        }
        return outputURL
    }
}
