import Foundation
import BlitztextCore

/// Sprecher einer transkribierten Aufnahme samt Zuordnung zu Stimmprofilen.
/// Der Nutzer entscheidet über neue und unsichere Stimmen; das Transkript
/// wird danach mit den Namen neu geschrieben.
struct SpeakerReview: Equatable {
    struct Sample: Equatable, Identifiable {
        let clipURL: URL
        let span: TimeSpan
        let quote: String

        var id: URL { clipURL }
    }

    struct Speaker: Equatable, Identifiable {
        /// Cluster-Nummer aus der Diarisierung.
        let id: Int
        let placeholder: String
        let talkTime: Double
        /// Stimm-Fingerabdruck; nil bei zu wenig eindeutiger Sprache.
        let vector: [Float]?
        let samples: [Sample]
        var assignment: SpeakerAssignment

        var canLearnVoice: Bool { vector != nil }
    }

    let sourceFileName: String
    let turns: [SpeakerTurn]
    var speakers: [Speaker]
    /// Temporärer Ordner der Hörproben dieser Aufnahme.
    let clipsDirectory: URL
    /// Bereits geschriebene .txt — wird nach jeder Benennung aktualisiert.
    var textFileURL: URL?

    init(analysis: SpeakerAnalysis, profiles: [VoiceProfileCandidate], sourceFileName: String, clipsDirectory: URL) {
        let placeholders = SpeakerLabels.placeholders(for: analysis.turns)
        let vectors = analysis.speakers.reduce(into: [Int: [Float]]()) { result, speaker in
            if let vector = speaker.vector { result[speaker.key] = vector }
        }
        let matches = VoiceMatcher.match(speakers: vectors, profiles: profiles, thresholds: .standard)

        self.sourceFileName = sourceFileName
        self.turns = analysis.turns
        self.clipsDirectory = clipsDirectory
        self.speakers = analysis.speakers.map { speaker in
            Speaker(
                id: speaker.key,
                placeholder: placeholders[speaker.key] ?? SpeakerLabels.placeholder(forIndex: 0),
                talkTime: speaker.talkTime,
                vector: speaker.vector,
                samples: speaker.samples.map { Sample(clipURL: $0.clipURL, span: $0.span, quote: $0.quote) },
                assignment: SpeakerAssignment(match: matches[speaker.key] ?? .unknown)
            )
        }
    }

    var pendingSpeakers: [Speaker] {
        speakers.filter { $0.assignment.needsDecision }
    }

    func speaker(_ id: Int) -> Speaker? {
        speakers.first { $0.id == id }
    }

    mutating func update(_ id: Int, to assignment: SpeakerAssignment) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[index].assignment = assignment
    }

    /// Redeanteile je Person mit den aktuellen Namen (fürs Kreisdiagramm).
    func talkShares(profileName: (UUID) -> String?, maxColored: Int) -> [TalkShare] {
        let entries = speakers.map { speaker in
            (name: speaker.assignment.displayName(placeholder: speaker.placeholder, profileName: profileName),
             seconds: speaker.talkTime)
        }
        return TalkShareCalculator.shares(entries, maxColored: maxColored)
    }

    /// Transkript mit den aktuellen Namen. Ordnet der Nutzer zwei Cluster
    /// derselben Person zu (die Diarisierung hat sie aufgespalten), werden
    /// deren aufeinanderfolgende Beiträge wieder zu einem zusammengeführt.
    func transcript(profileName: (UUID) -> String?) -> String {
        var names: [Int: String] = [:]
        for speaker in speakers {
            names[speaker.id] = speaker.assignment.displayName(placeholder: speaker.placeholder, profileName: profileName)
        }

        var canonicalKey: [String: Int] = [:]
        let pieces = turns.map { turn -> AttributedPiece in
            let name = names[turn.speaker] ?? "Unbekannt"
            let key = canonicalKey[name] ?? turn.speaker
            canonicalKey[name] = key
            return AttributedPiece(speaker: key, start: turn.start, end: turn.end, text: turn.text)
        }
        let mergedNames = canonicalKey.reduce(into: [Int: String]()) { $0[$1.value] = $1.key }
        return SpeakerTranscriptFormatter.text(turns: SpeakerTurns.merge(pieces), names: mergedNames)
    }
}

/// Zustand der Gesprächsnotiz (Zusammenfassung je Person).
enum ConversationNotePhase: Equatable {
    case idle
    case running
    case done(String)
    case failed(String)
}
