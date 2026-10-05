import Foundation

// Abgleich von Stimm-Fingerabdrücken (Embeddings) mit gespeicherten Profilen.
// Reine Vektor-Logik, damit sie ohne CoreML testbar ist.

public enum VoiceVectorMath {
    public static func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? vector.map { $0 / length } : vector
    }

    /// Kosinus-Ähnlichkeit (-1…1). Unterschiedlich lange Vektoren gelten als unähnlich.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return zip(normalized(a), normalized(b)).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// Mittelt eine neue Probe gewichtet ins Profil ein. `weight` = Anzahl der
    /// bisher eingeflossenen Proben — so kippt ein einzelner schlechter
    /// Mitschnitt kein über viele Gespräche gelerntes Profil.
    public static func mergedCentroid(existing: [Float], weight: Int, adding: [Float]) -> [Float] {
        guard existing.count == adding.count, weight > 0 else { return normalized(adding) }
        let old = normalized(existing), new = normalized(adding)
        let w = Float(weight)
        return normalized(zip(old, new).map { $0 * w + $1 })
    }
}

public struct VoiceProfileCandidate: Equatable, Sendable {
    public let id: UUID
    public let vector: [Float]

    public init(id: UUID, vector: [Float]) {
        self.id = id
        self.vector = vector
    }
}

public enum VoiceMatch: Equatable, Sendable {
    case recognized(profileID: UUID, similarity: Float)
    case uncertain(profileID: UUID, similarity: Float)
    case unknown
}

public struct VoiceMatchThresholds: Equatable, Sendable {
    public let recognized: Float
    public let uncertain: Float

    public init(recognized: Float, uncertain: Float) {
        self.recognized = recognized
        self.uncertain = uncertain
    }

    public static let standard = VoiceMatchThresholds(recognized: 0.70, uncertain: 0.50)
}

public enum VoiceMatcher {
    public static func match(
        speakers: [Int: [Float]],
        profiles: [VoiceProfileCandidate],
        thresholds: VoiceMatchThresholds
    ) -> [Int: VoiceMatch] {
        var result = Dictionary(uniqueKeysWithValues: speakers.keys.map { ($0, VoiceMatch.unknown) })

        // Alle Paare nach Ähnlichkeit, dann gierig vergeben: Ein Profil gehört
        // höchstens einem Sprecher derselben Aufnahme, und der ähnlichste gewinnt.
        let pairs = speakers.flatMap { speaker, vector in
            profiles.map { (speaker: speaker, profile: $0.id, similarity: VoiceVectorMath.cosine(vector, $0.vector)) }
        }
        .filter { $0.similarity >= thresholds.uncertain }
        .sorted { $0.similarity > $1.similarity }

        var usedSpeakers = Set<Int>(), usedProfiles = Set<UUID>()
        for pair in pairs where !usedSpeakers.contains(pair.speaker) && !usedProfiles.contains(pair.profile) {
            usedSpeakers.insert(pair.speaker)
            usedProfiles.insert(pair.profile)
            result[pair.speaker] = pair.similarity >= thresholds.recognized
                ? .recognized(profileID: pair.profile, similarity: pair.similarity)
                : .uncertain(profileID: pair.profile, similarity: pair.similarity)
        }
        return result
    }
}

/// Wem eine Stimme in einem Transkript zugeordnet ist — vom automatischen
/// Abgleich bis zur Entscheidung des Nutzers.
public enum SpeakerAssignment: Equatable, Sendable {
    case recognized(profileID: UUID, similarity: Float)
    case suggested(profileID: UUID, similarity: Float)
    case unknown
    case confirmed(profileID: UUID)
    case named(String)
    case skipped

    public init(match: VoiceMatch) {
        switch match {
        case let .recognized(profileID, similarity):
            self = .recognized(profileID: profileID, similarity: similarity)
        case let .uncertain(profileID, similarity):
            self = .suggested(profileID: profileID, similarity: similarity)
        case .unknown:
            self = .unknown
        }
    }

    /// Neue Stimme oder bloße Vermutung: hier soll der Nutzer gefragt werden.
    public var needsDecision: Bool {
        switch self {
        case .suggested, .unknown: return true
        case .recognized, .confirmed, .named, .skipped: return false
        }
    }

    /// Name im Transkript. Eine Vermutung zählt nicht — sonst stünde ein
    /// geratener Name im Protokoll, ohne dass ihn jemand bestätigt hat.
    public func displayName(placeholder: String, profileName: (UUID) -> String?) -> String {
        switch self {
        case let .recognized(profileID, _), let .confirmed(profileID):
            return profileName(profileID) ?? placeholder
        case let .named(name):
            return name
        case .suggested, .unknown, .skipped:
            return placeholder
        }
    }
}
