import Foundation
import AVFoundation
import Observation
import BlitztextCore

/// Eine benannte Stimme: Fingerabdruck plus eine kurze Hörprobe zum Nachprüfen.
struct VoiceProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var vector: [Float]
    /// Wie viele bestätigte Aufnahmen in den Fingerabdruck eingeflossen sind.
    var sampleCount: Int
    let createdAt: Date
    var updatedAt: Date
    /// Stimmraum, in dem der Fingerabdruck berechnet wurde.
    var embedderID: String
}

/// Lokale Ablage der Stimmprofile unter Application Support/Blitztext/voices.
/// Bleibt auf dem Gerät; „Sauber Entfernen“ löscht sie mit dem App-Ordner.
@Observable
@MainActor
final class VoiceProfileStore {
    static let shared = VoiceProfileStore()

    /// Obergrenze für das Gewicht des bisherigen Profils beim Nachlernen:
    /// neue Aufnahmen sollen ein altes Profil noch bewegen können.
    private static let maxLearningWeight = 20

    private(set) var profiles: [VoiceProfile] = []
    private let directory: URL

    private var indexURL: URL { directory.appendingPathComponent("profiles.json") }

    init(directory: URL = AppSupportPaths.voiceProfilesDirectoryURL) {
        self.directory = directory
        load()
    }

    /// Profile, die mit dem aktuellen Stimm-Modell vergleichbar sind.
    var matchingCandidates: [VoiceProfileCandidate] {
        profiles
            .filter { $0.embedderID == SpeakerRecognitionService.embedderIdentifier }
            .map { VoiceProfileCandidate(id: $0.id, vector: $0.vector) }
    }

    func profile(_ id: UUID) -> VoiceProfile? {
        profiles.first { $0.id == id }
    }

    func profile(named name: String) -> VoiceProfile? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return profiles.first { $0.name.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    func sampleURL(for id: UUID) -> URL? {
        let url = directory.appendingPathComponent("\(id.uuidString).wav")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func create(name: String, vector: [Float], sampleClip: URL?) -> VoiceProfile {
        let now = Date()
        let profile = VoiceProfile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            vector: VoiceVectorMath.normalized(vector),
            sampleCount: 1,
            createdAt: now,
            updatedAt: now,
            embedderID: SpeakerRecognitionService.embedderIdentifier
        )
        profiles.append(profile)
        storeSample(sampleClip, for: profile.id)
        save()
        return profile
    }

    /// Lernt eine bestätigte Aufnahme in ein bestehendes Profil ein.
    func learn(_ id: UUID, vector: [Float], sampleClip: URL?) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = profiles[index]
        if profile.embedderID == SpeakerRecognitionService.embedderIdentifier {
            profile.vector = VoiceVectorMath.mergedCentroid(
                existing: profile.vector,
                weight: min(profile.sampleCount, Self.maxLearningWeight),
                adding: vector
            )
            profile.sampleCount += 1
        } else {
            // Altes Modell: Fingerabdruck neu aufsetzen statt Äpfel mit Birnen zu mitteln.
            profile.vector = VoiceVectorMath.normalized(vector)
            profile.sampleCount = 1
            profile.embedderID = SpeakerRecognitionService.embedderIdentifier
        }
        profile.updatedAt = Date()
        profiles[index] = profile
        if sampleURL(for: id) == nil {
            storeSample(sampleClip, for: id)
        }
        save()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed
        profiles[index].updatedAt = Date()
        save()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id.uuidString).wav"))
        save()
    }

    func deleteAll() {
        profiles.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Persistenz

    private func storeSample(_ clip: URL?, for id: UUID) {
        guard let clip else { return }
        let target = directory.appendingPathComponent("\(id.uuidString).wav")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: clip, to: target)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([VoiceProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profiles).write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Blitztext: Stimmprofile konnten nicht gespeichert werden: \(error.localizedDescription)")
        }
    }
}

/// Spielt Hörproben ab. Ein zweiter Klick auf dieselbe Probe stoppt sie.
@Observable
@MainActor
final class VoiceSamplePlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = VoiceSamplePlayer()

    private(set) var playingURL: URL?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        guard let next = try? AVAudioPlayer(contentsOf: url) else { return }
        next.delegate = self
        next.play()
        player = next
        playingURL = url
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            // Nur zurücksetzen, wenn nicht inzwischen eine andere Probe läuft.
            guard let current = self.player, ObjectIdentifier(current) == finished else { return }
            self.player = nil
            self.playingURL = nil
        }
    }
}
