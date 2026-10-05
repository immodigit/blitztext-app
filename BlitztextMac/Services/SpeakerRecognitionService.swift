import Foundation
import AVFoundation
import CoreML
import WhisperKit
import SpeakerKit
import BlitztextCore

/// Ergebnis der Sprecheranalyse einer Datei. Enthält bewusst keine
/// WhisperKit-/SpeakerKit-Typen, damit AppState und UI nur Blitztext-Typen sehen.
struct SpeakerAnalysis: Sendable {
    struct Sample: Sendable, Equatable {
        let span: TimeSpan
        let clipURL: URL
        let quote: String
    }

    struct Speaker: Sendable {
        let key: Int
        let talkTime: Double
        /// Stimm-Fingerabdruck; nil, wenn die Person zu wenig allein gesprochen hat.
        let vector: [Float]?
        let samples: [Sample]
    }

    let turns: [SpeakerTurn]
    /// Relevante Sprecher in der Reihenfolge ihres ersten Wortbeitrags.
    /// Leer, wenn nur eine Person spricht — dann gibt es nichts zuzuordnen.
    let speakers: [Speaker]
}

/// Lokale Sprechererkennung: wer spricht wann (SpeakerKit/Pyannote) und
/// wessen Stimme ist das (Stimm-Fingerabdruck aus dem Pyannote-Embedder).
///
/// SpeakerKit liefert nur anonyme Cluster („Speaker 0/1“) und gibt die
/// Embeddings nicht nach außen. Für Stimmprofile über mehrere Aufnahmen hinweg
/// rufen wir deshalb dasselbe Embedder-Modell direkt über CoreML auf — so liegen
/// Profile und Diarisierung im selben Stimmraum, ohne das Paket zu forken.
actor SpeakerRecognitionService {
    static let shared = SpeakerRecognitionService()

    /// Version des Stimmraums. Ändert sich das Embedder-Modell, passen alte
    /// Profile nicht mehr — sie werden dann nicht mehr zum Abgleich genutzt.
    static let embedderIdentifier = "pyannote-v3/W8A16"

    /// Personen mit weniger Redezeit sind meist Fehlcluster (Räuspern, Hintergrund)
    /// und werden dem Nachbarbeitrag zugeschlagen statt eigene Zeilen zu bekommen.
    static let minimumTalkTime: Double = 8
    /// So viel eindeutige Sprache braucht ein belastbarer Fingerabdruck.
    static let minimumVoiceprintSpeech: Double = 4

    private var speakerKit: SpeakerKit?
    private var embedder: VoiceEmbedder?

    // MARK: - Modelle

    /// True, wenn die Modelle schon lokal liegen (dann kein Netzwerk nötig).
    nonisolated static var isModelInstalled: Bool {
        installedModelFolder() != nil
    }

    /// Ordner mit den vollständig geladenen SpeakerKit-Modellen, falls vorhanden.
    nonisolated static func installedModelFolder() -> URL? {
        let base = AppSupportPaths.speakerKitModelsDirectoryURL
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator where url.lastPathComponent == "speaker_segmenter" {
            let root = url.deletingLastPathComponent()
            let required = ["SpeakerSegmenter.mlmodelc", "SpeakerEmbedder.mlmodelc",
                            "SpeakerEmbedderPreprocessor.mlmodelc", "PldaProjector.mlmodelc"]
            let found = Set(
                (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
                    .compactMap { ($0 as? URL)?.lastPathComponent }) ?? []
            )
            if required.allSatisfy(found.contains) {
                return root
            }
        }
        return nil
    }

    /// Lädt die Modelle (~11 MB) einmalig neben die Whisper-Modelle. Nur auf
    /// ausdrücklichen Wunsch — im lokalen Modus geht sonst nichts ins Netz.
    func downloadModels(progress: @escaping @Sendable (Double) -> Void) async throws {
        if Self.isModelInstalled {
            progress(1)
            return
        }
        try FileManager.default.createDirectory(
            at: AppSupportPaths.speakerKitModelsDirectoryURL,
            withIntermediateDirectories: true
        )
        // Diarizer direkt erzeugen statt über SpeakerKit(config): dessen Init
        // lädt bei download: true sofort und ohne Fortschrittsmeldung.
        let diarizer = SpeakerKitDiarizer.pyannote(config: PyannoteConfig(
            downloadBase: AppSupportPaths.speakerKitModelsDirectoryURL.path,
            download: true,
            load: false,
            verbose: false,
            logLevel: .error
        ))
        // Über den Basistyp aufrufen: SpeakerKitDiarizer hat zwei gleichlautende
        // Überladungen (mit/ohne @Sendable), die beide hierhin weiterreichen.
        let manager: ModelManager = diarizer
        try await manager.downloadModels { update in
            let fraction = update.fractionCompleted
            progress(fraction.isFinite ? fraction : 0)
        }
        guard Self.isModelInstalled else {
            throw SpeakerRecognitionError.downloadIncomplete
        }
        progress(1)
    }

    private func loadedSpeakerKit() async throws -> SpeakerKit {
        if let speakerKit { return speakerKit }
        guard let folder = Self.installedModelFolder() else {
            throw SpeakerRecognitionError.modelMissing
        }
        let kit = try await SpeakerKit(PyannoteConfig(
            modelFolder: folder.path,
            download: false,
            load: true,
            verbose: false,
            logLevel: .error
        ))
        speakerKit = kit
        return kit
    }

    private func loadedEmbedder() async throws -> VoiceEmbedder {
        if let embedder { return embedder }
        guard let folder = Self.installedModelFolder(),
              let directory = VoiceEmbedder.modelDirectory(in: folder) else {
            throw SpeakerRecognitionError.modelMissing
        }
        let loaded = try await VoiceEmbedder(modelDirectory: directory)
        embedder = loaded
        return loaded
    }

    /// Gibt den Speicher frei (z. B. nach einem Stapel).
    func unload() async {
        await speakerKit?.unloadModels()
        speakerKit = nil
        embedder = nil
    }

    // MARK: - Analyse

    /// Ordnet ein Transkript (mit Wort-Zeitstempeln) Sprechern zu und berechnet
    /// je Sprecher Fingerabdruck und Hörproben. Hörproben landen als WAV in
    /// `clipsDirectory`.
    func analyze(
        audio: [Float],
        transcription: [TranscriptionResult],
        clipsDirectory: URL
    ) async throws -> SpeakerAnalysis {
        let kit = try await loadedSpeakerKit()
        let diarization = try await kit.diarize(audioArray: audio, options: PyannoteDiarizationOptions())

        let spans = diarization.segments.compactMap { segment -> SpeakerSpan? in
            guard let id = segment.speaker.speakerId else { return nil }
            return SpeakerSpan(speaker: id, start: Double(segment.startTime), end: Double(segment.endTime))
        }
        let talkTime = SpeakerTimeline.talkTime(spans)
        let relevant = Set(talkTime.filter { $0.value >= Self.minimumTalkTime }.keys)

        let pieces = diarization.addSpeakerInfo(to: transcription).flatMap { $0 }.map { segment in
            AttributedPiece(
                speaker: segment.speaker.speakerId.flatMap { relevant.contains($0) ? $0 : nil },
                start: Double(segment.startTime),
                end: Double(segment.endTime),
                text: SubtitleFormatter.strippingTokens(segment.text)
            )
        }

        let turns = SpeakerTurns.merge(pieces).compactMap { turn -> SpeakerTurn? in
            let cleaned = TranscriptionQualityService.cleanedTranscript(turn.text)
            guard !cleaned.isEmpty else { return nil }
            return SpeakerTurn(speaker: turn.speaker, start: turn.start, end: turn.end, text: cleaned)
        }

        var order: [Int] = []
        for turn in turns where !order.contains(turn.speaker) {
            order.append(turn.speaker)
        }
        guard order.count >= 2 else {
            return SpeakerAnalysis(turns: turns, speakers: [])
        }

        try FileManager.default.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        let exclusive = SpeakerTimeline.exclusiveSpans(spans, minimumDuration: 1.0)
        let embedder = try await loadedEmbedder()

        var speakers: [SpeakerAnalysis.Speaker] = []
        for key in order {
            try Task.checkCancellation()
            let ownSpans = exclusive[key] ?? []
            let vector = try embedder.voiceprint(audio: audio, spans: ownSpans, minimumSpeech: Self.minimumVoiceprintSpeech)

            // Doppelt so viele Kandidaten ziehen und die mit erkanntem Text
            // bevorzugen: Eine Hörprobe ohne Zitat hilft beim Zuordnen kaum.
            let candidates = VoiceSamplePicker.pick(from: ownSpans, count: 6, minDuration: 2.5, maxDuration: 8)
                .map { (span: $0, quote: TranscriptQuote.text(in: $0, from: pieces, maxLength: 140)) }
            let chosen = (candidates.filter { !$0.quote.isEmpty } + candidates.filter { $0.quote.isEmpty })
                .prefix(3)
                .sorted { $0.span.start < $1.span.start }

            let samples = chosen.enumerated().compactMap { index, candidate -> SpeakerAnalysis.Sample? in
                let url = clipsDirectory.appendingPathComponent("speaker-\(key)-\(index).wav")
                guard (try? VoiceClipWriter.write(audio: audio, span: candidate.span, to: url)) != nil else { return nil }
                return SpeakerAnalysis.Sample(span: candidate.span, clipURL: url, quote: candidate.quote)
            }

            speakers.append(SpeakerAnalysis.Speaker(
                key: key,
                talkTime: talkTime[key] ?? 0,
                vector: vector,
                samples: samples
            ))
        }

        return SpeakerAnalysis(turns: turns, speakers: speakers)
    }
}

enum SpeakerRecognitionError: LocalizedError {
    case modelMissing
    case downloadIncomplete

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "Das Modell für die Sprechererkennung ist noch nicht geladen (Einstellungen → Stimmen)."
        case .downloadIncomplete:
            return "Der Download der Sprechererkennung ist unvollständig. Bitte erneut versuchen."
        }
    }
}

// MARK: - Stimm-Fingerabdruck

/// Ruft das Pyannote-Embedder-Modell (WeSpeaker) direkt auf: 30 s Audio rein,
/// je Maskenzeile ein 256-dimensionaler Fingerabdruck raus.
final class VoiceEmbedder: @unchecked Sendable {
    private static let chunkSamples = 480_000   // 30 s bei 16 kHz
    private static let maskFrames = 1767
    private static let maskRows = 64
    private static let maxChunks = 3

    private let preprocessor: MLModel
    private let embedder: MLModel

    static func modelDirectory(in root: URL) -> URL? {
        let candidate = root
            .appendingPathComponent("speaker_embedder", isDirectory: true)
            .appendingPathComponent("pyannote-v3", isDirectory: true)
            .appendingPathComponent("W8A16", isDirectory: true)
        let exists = FileManager.default.fileExists(
            atPath: candidate.appendingPathComponent("SpeakerEmbedder.mlmodelc").path
        )
        return exists ? candidate : nil
    }

    init(modelDirectory: URL) async throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        preprocessor = try await MLModel.load(
            contentsOf: modelDirectory.appendingPathComponent("SpeakerEmbedderPreprocessor.mlmodelc"),
            configuration: configuration
        )
        embedder = try await MLModel.load(
            contentsOf: modelDirectory.appendingPathComponent("SpeakerEmbedder.mlmodelc"),
            configuration: configuration
        )
    }

    /// Fingerabdruck aus den Abschnitten, in denen nur diese Person spricht.
    /// Bis zu drei 30-s-Fenster über die Aufnahme verteilt, gemittelt.
    func voiceprint(audio: [Float], spans: [TimeSpan], minimumSpeech: Double) throws -> [Float]? {
        var speech: [Float] = []
        for span in spans {
            let lower = max(0, Int(span.start * 16_000))
            let upper = min(audio.count, Int(span.end * 16_000))
            if upper > lower { speech.append(contentsOf: audio[lower..<upper]) }
        }
        guard Double(speech.count) / 16_000 >= minimumSpeech else { return nil }

        let windows = min(Self.maxChunks, Int((Double(speech.count) / Double(Self.chunkSamples)).rounded(.up)))
        let lastStart = max(0, speech.count - Self.chunkSamples)
        var sum = [Float](repeating: 0, count: 0)

        for index in 0..<windows {
            let start = windows == 1 ? 0 : lastStart * index / (windows - 1)
            let window = Array(speech[start..<min(speech.count, start + Self.chunkSamples)])
            let vector = VoiceVectorMath.normalized(try embedding(of: window))
            sum = sum.isEmpty ? vector : zip(sum, vector).map { $0 + $1 }
        }
        return VoiceVectorMath.normalized(sum)
    }

    private func embedding(of samples: [Float]) throws -> [Float] {
        // Float32-Eingaben; CoreML wandelt in das Float16 des Modells. Den Swift-Typ
        // Float16 gibt es auf Intel-Macs nicht — der Universal-Build bräche sonst.
        let waveform = try MLMultiArray(shape: [1, NSNumber(value: Self.chunkSamples)], dataType: .float32)
        let wavePointer = waveform.dataPointer.bindMemory(to: Float.self, capacity: Self.chunkSamples)
        for index in 0..<Self.chunkSamples {
            wavePointer[index] = index < samples.count ? samples[index] : 0
        }

        let features = try preprocessor.prediction(from: MLDictionaryFeatureProvider(dictionary: ["waveforms": waveform]))
        guard let preprocessed = features.featureValue(for: "preprocessor_output_1")?.multiArrayValue else {
            throw SpeakerKitError.invalidModelOutput("Stimm-Vorverarbeitung lieferte keine Merkmale")
        }

        // Maske: Zeile 0 markiert die Frames mit echter Sprache, Rest bleibt leer.
        let maskCount = Self.maskRows * Self.maskFrames
        let mask = try MLMultiArray(
            shape: [1, NSNumber(value: Self.maskRows), NSNumber(value: Self.maskFrames)],
            dataType: .float32
        )
        let maskPointer = mask.dataPointer.bindMemory(to: Float.self, capacity: maskCount)
        for index in 0..<maskCount { maskPointer[index] = 0 }
        let validFrames = min(Self.maskFrames, samples.count * Self.maskFrames / Self.chunkSamples)
        for frame in 0..<validFrames { maskPointer[frame] = 1 }

        let output = try embedder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "preprocessor_output_1": preprocessed,
            "speaker_masks": mask,
        ]))
        guard let embeddings = output.featureValue(for: "speaker_embeddings")?.multiArrayValue else {
            throw SpeakerKitError.invalidModelOutput("Stimm-Modell lieferte keinen Fingerabdruck")
        }
        let size = embeddings.shape[2].intValue
        return (0..<size).map { embeddings[[0, 0, NSNumber(value: $0)]].floatValue }
    }
}

// MARK: - Hörproben

enum VoiceClipWriter {
    /// Schreibt einen Ausschnitt als 16-kHz-WAV, auf angenehme Lautstärke
    /// normalisiert (Telefonmitschnitte sind oft sehr leise).
    static func write(audio: [Float], span: TimeSpan, to url: URL) throws {
        let lower = max(0, Int(span.start * 16_000))
        let upper = min(audio.count, Int(span.end * 16_000))
        guard upper > lower else { return }

        var clip = Array(audio[lower..<upper])
        let peak = clip.map(abs).max() ?? 0
        if peak > 0.0001 {
            let gain = min(0.9 / peak, 8)
            clip = clip.map { $0 * gain }
        }

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(clip.count)),
              let channel = buffer.floatChannelData?[0] else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(clip.count)
        clip.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: clip.count)
        }

        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}
