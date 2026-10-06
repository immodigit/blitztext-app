import Foundation

// Reine, testbare Logik der Sprechererkennung: Redebeiträge bilden,
// Platzhalter vergeben, Transkript formatieren, Zeitachse auswerten.
// Die Modelle (Diarisierung, Stimm-Fingerabdruck) liegen im App-Target.

/// Ein Zeitbereich in Sekunden.
public struct TimeSpan: Equatable, Codable, Hashable, Sendable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var duration: Double { end - start }
}

/// Abschnitt, in dem laut Diarisierung eine bestimmte Person spricht.
public struct SpeakerSpan: Equatable, Sendable {
    public let speaker: Int
    public let start: Double
    public let end: Double

    public init(speaker: Int, start: Double, end: Double) {
        self.speaker = speaker
        self.start = start
        self.end = end
    }
}

/// Ein Stück Transkript mit (möglicherweise fehlender) Sprecherzuordnung.
public struct AttributedPiece: Equatable, Sendable {
    public let speaker: Int?
    public let start: Double
    public let end: Double
    public let text: String

    public init(speaker: Int?, start: Double, end: Double, text: String) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Zusammenhängender Redebeitrag einer Person.
public struct SpeakerTurn: Equatable, Sendable {
    public let speaker: Int
    public let start: Double
    public let end: Double
    public let text: String

    public init(speaker: Int, start: Double, end: Double, text: String) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SpeakerTurns {
    /// Fasst aufeinanderfolgende Stücke derselben Person zu einem Beitrag zusammen.
    /// Stücke ohne Sprecher (Diarisierung unsicher) hängen am vorigen Beitrag,
    /// am Anfang am nächsten — so geht kein Text verloren und es entstehen
    /// keine Zeilen „Unbekannt: äh“.
    public static func merge(_ pieces: [AttributedPiece]) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        var pending: (start: Double, end: Double, text: String)?

        for piece in pieces {
            let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            guard let speaker = piece.speaker else {
                if let last = turns.last {
                    turns[turns.count - 1] = SpeakerTurn(
                        speaker: last.speaker,
                        start: last.start,
                        end: max(last.end, piece.end),
                        text: last.text + " " + text
                    )
                } else if let held = pending {
                    pending = (held.start, max(held.end, piece.end), held.text + " " + text)
                } else {
                    pending = (piece.start, piece.end, text)
                }
                continue
            }

            if let last = turns.last, last.speaker == speaker {
                turns[turns.count - 1] = SpeakerTurn(
                    speaker: speaker,
                    start: last.start,
                    end: max(last.end, piece.end),
                    text: last.text + " " + text
                )
            } else if let held = pending {
                turns.append(SpeakerTurn(
                    speaker: speaker,
                    start: min(held.start, piece.start),
                    end: max(held.end, piece.end),
                    text: held.text + " " + text
                ))
                pending = nil
            } else {
                turns.append(SpeakerTurn(speaker: speaker, start: piece.start, end: piece.end, text: text))
            }
        }
        return turns
    }
}

public enum SpeakerLabels {
    /// „Sprecher A“ … „Sprecher Z“, danach durchgezählt.
    public static func placeholder(forIndex index: Int) -> String {
        guard index >= 0, index < 26, let scalar = UnicodeScalar(65 + index) else {
            return "Sprecher \(index + 1)"
        }
        return "Sprecher \(Character(scalar))"
    }

    /// Platzhalter in der Reihenfolge, in der die Personen zum ersten Mal sprechen.
    public static func placeholders(for turns: [SpeakerTurn]) -> [Int: String] {
        var result: [Int: String] = [:]
        for turn in turns where result[turn.speaker] == nil {
            result[turn.speaker] = placeholder(forIndex: result.count)
        }
        return result
    }
}

public enum SpeakerTranscriptFormatter {
    /// `mm:ss`, ab einer Stunde `h:mm:ss`.
    public static func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    /// Transkript mit einer Zeile je Beitrag: `[mm:ss] Name: Text`.
    public static func text(turns: [SpeakerTurn], names: [Int: String]) -> String {
        let fallback = SpeakerLabels.placeholders(for: turns)
        return turns.map { turn in
            let name = names[turn.speaker] ?? fallback[turn.speaker] ?? "Unbekannt"
            return "[\(timecode(turn.start))] \(name): \(turn.text)"
        }
        .joined(separator: "\n\n")
    }
}

public enum SpeakerTimeline {
    /// Abschnitte je Person, in denen niemand sonst spricht — nur daraus lassen
    /// sich saubere Stimm-Fingerabdrücke und Hörproben gewinnen.
    public static func exclusiveSpans(_ spans: [SpeakerSpan], minimumDuration: Double) -> [Int: [TimeSpan]] {
        let speakers = Set(spans.map(\.speaker))
        var result: [Int: [TimeSpan]] = [:]
        for speaker in speakers {
            let own = union(spans.filter { $0.speaker == speaker }.map { TimeSpan(start: $0.start, end: $0.end) })
            let others = union(spans.filter { $0.speaker != speaker }.map { TimeSpan(start: $0.start, end: $0.end) })
            result[speaker] = subtract(others, from: own).filter { $0.duration >= minimumDuration }
        }
        return result
    }

    /// Gesamte Redezeit je Person (eigene Überlappungen zählen einfach).
    public static func talkTime(_ spans: [SpeakerSpan]) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for speaker in Set(spans.map(\.speaker)) {
            let own = union(spans.filter { $0.speaker == speaker }.map { TimeSpan(start: $0.start, end: $0.end) })
            result[speaker] = own.reduce(0) { $0 + $1.duration }
        }
        return result
    }

    static func union(_ spans: [TimeSpan]) -> [TimeSpan] {
        var merged: [TimeSpan] = []
        for span in spans.sorted(by: { $0.start < $1.start }) where span.duration > 0 {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1] = TimeSpan(start: last.start, end: max(last.end, span.end))
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// `base` minus `cuts`; beide Listen sind sortiert und überlappungsfrei.
    static func subtract(_ cuts: [TimeSpan], from base: [TimeSpan]) -> [TimeSpan] {
        var result: [TimeSpan] = []
        for span in base {
            var cursor = span.start
            for cut in cuts where cut.end > cursor && cut.start < span.end {
                if cut.start > cursor {
                    result.append(TimeSpan(start: cursor, end: cut.start))
                }
                cursor = max(cursor, cut.end)
            }
            if cursor < span.end {
                result.append(TimeSpan(start: cursor, end: span.end))
            }
        }
        return result
    }
}

public enum VoiceSamplePicker {
    /// Wählt Hörproben über die ganze Aufnahme verteilt: die Zeitachse wird in
    /// `count` Abschnitte geteilt, je Abschnitt gewinnt der längste Redeblock.
    /// Lange Blöcke werden mittig auf `maxDuration` gekürzt (die Ränder sind
    /// die Stellen, an denen die Diarisierung am ehesten danebenliegt).
    public static func pick(from spans: [TimeSpan], count: Int, minDuration: Double, maxDuration: Double) -> [TimeSpan] {
        let candidates = spans.filter { $0.duration >= minDuration }.sorted { $0.start < $1.start }
        guard count > 0, let first = candidates.first, let last = candidates.last else { return [] }

        let timelineStart = first.start
        let bucketLength = max((last.end - timelineStart) / Double(count), .leastNonzeroMagnitude)
        var chosen: [TimeSpan] = []

        for bucket in 0..<count {
            let lower = timelineStart + Double(bucket) * bucketLength
            let upper = bucket == count - 1 ? .infinity : lower + bucketLength
            if let best = candidates
                .filter({ $0.start >= lower && $0.start < upper && !chosen.contains($0) })
                .max(by: { $0.duration < $1.duration }) {
                chosen.append(best)
            }
        }

        for span in candidates.sorted(by: { $0.duration > $1.duration }) where chosen.count < count && !chosen.contains(span) {
            chosen.append(span)
        }

        return chosen
            .map { span in
                guard span.duration > maxDuration else { return span }
                let start = span.start + (span.duration - maxDuration) / 2
                return TimeSpan(start: start, end: start + maxDuration)
            }
            .sorted { $0.start < $1.start }
    }
}

/// Was in einer Hörprobe gesagt wird — hilft beim Wiedererkennen der Stimme.
public enum TranscriptQuote {
    public static func text(in span: TimeSpan, from pieces: [AttributedPiece], maxLength: Int) -> String {
        let joined = pieces
            .filter { piece in
                let middle = (piece.start + piece.end) / 2
                return middle >= span.start && middle <= span.end
            }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard joined.count > maxLength else { return joined }
        let prefix = joined.prefix(maxLength)
        let cut = prefix.lastIndex(where: { $0.isWhitespace }).map { prefix[..<$0] } ?? prefix
        return cut.trimmingCharacters(in: .whitespaces) + " …"
    }
}

/// Redeanteil einer Person (oder des Sammelsegments „Weitere“) fürs Diagramm.
public struct TalkShare: Equatable, Sendable {
    public let name: String
    public let seconds: Double
    public let percent: Int
    public let colorSlot: Int?

    public init(name: String, seconds: Double, percent: Int, colorSlot: Int?) {
        self.name = name
        self.seconds = seconds
        self.percent = percent
        self.colorSlot = colorSlot
    }
}

public enum TalkShareCalculator {
    /// `entries` in der Reihenfolge des ersten Wortbeitrags. Gleiche Namen werden
    /// addiert (aufgespaltene Cluster derselben Person). Die `maxColored` Personen
    /// mit der meisten Redezeit bekommen eine Farbe — vergeben nach erstem
    /// Wortbeitrag, damit die Farbe an der Person hängt und nicht am Rang.
    /// Mehr als eine übrige Person wird zu „Weitere (n)“ zusammengefasst.
    public static func shares(_ entries: [(name: String, seconds: Double)], maxColored: Int) -> [TalkShare] {
        var order: [String] = []
        var seconds: [String: Double] = [:]
        for entry in entries where entry.seconds > 0 {
            if seconds[entry.name] == nil { order.append(entry.name) }
            seconds[entry.name, default: 0] += entry.seconds
        }
        let total = seconds.values.reduce(0, +)
        guard total > 0 else { return [] }

        let ranked = order.sorted { (seconds[$0] ?? 0) > (seconds[$1] ?? 0) }
        let colored = Array(ranked.prefix(maxColored))
        let rest = Array(ranked.dropFirst(maxColored))
        let slots = order.filter(colored.contains).enumerated()
            .reduce(into: [String: Int]()) { $0[$1.element] = $1.offset }

        var slices: [(name: String, seconds: Double, slot: Int?)] = colored.map { ($0, seconds[$0] ?? 0, slots[$0]) }
        if rest.count == 1, let only = rest.first {
            slices.append((only, seconds[only] ?? 0, nil))
        } else if rest.count > 1 {
            slices.append(("Weitere (\(rest.count))", rest.reduce(0) { $0 + (seconds[$1] ?? 0) }, nil))
        }

        // Größter-Rest-Verfahren: gerundete Prozente ergeben zusammen genau 100.
        let exact = slices.map { $0.seconds / total * 100 }
        var percents = exact.map { Int($0.rounded(.down)) }
        let missing = 100 - percents.reduce(0, +)
        for index in exact.indices.sorted(by: { exact[$0] - Double(percents[$0]) > exact[$1] - Double(percents[$1]) }).prefix(missing) {
            percents[index] += 1
        }

        return slices.enumerated().map { index, slice in
            TalkShare(name: slice.name, seconds: slice.seconds, percent: percents[index], colorSlot: slice.slot)
        }
    }
}
