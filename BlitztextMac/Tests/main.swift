import Foundation
import BlitztextCore

// Schlanker Plain-Swift-Test-Runner (läuft ohne Xcode/XCTest, nur Command Line Tools).
// Ausführen mit:  swift run BlitztextCoreTests
// Exit-Code 0 = alle Tests grün, 1 = mindestens ein Fehler.

var failures = 0
var passed = 0

func check(_ condition: Bool, _ name: String) {
    if condition {
        passed += 1
    } else {
        failures += 1
        FileHandle.standardError.write(Data("✗ FAIL: \(name)\n".utf8))
    }
}

func equal<T: Equatable>(_ a: T, _ b: T, _ name: String) {
    check(a == b, "\(name) (\(a) != \(b))")
}

// MARK: - OpenAIKeyValidator

check(OpenAIKeyValidator.isPlausible("sk-" + String(repeating: "a", count: 25)),
      "akzeptiert plausiblen Key")
check(OpenAIKeyValidator.isPlausible("  sk-abcdefghij1234567890ABCD  "),
      "trimmt umgebende Leerzeichen")
check(!OpenAIKeyValidator.isPlausible(""), "lehnt leer ab")
check(!OpenAIKeyValidator.isPlausible("hallo welt"), "lehnt beliebigen Text ab")
check(!OpenAIKeyValidator.isPlausible("sk-abc"), "lehnt zu kurzen Key ab")
check(!OpenAIKeyValidator.isPlausible("pk-abcdefghij1234567890ABCD"), "lehnt falschen Prefix ab")

// MARK: - TranscriptFileNaming

let dir = URL(fileURLWithPath: "/tmp/memos")

equal(
    TranscriptFileNaming.uniqueURL(forBase: "Aufnahme 232", in: dir, fileExists: { _ in false }).lastPathComponent,
    "Aufnahme 232.txt",
    "nutzt schlichten Namen wenn frei"
)

do {
    let taken: Set<String> = ["/tmp/memos/Aufnahme 232.txt"]
    equal(
        TranscriptFileNaming.uniqueURL(forBase: "Aufnahme 232", in: dir, fileExists: { taken.contains($0.path) }).lastPathComponent,
        "Aufnahme 232-1.txt",
        "hängt Suffix bei einfacher Kollision an"
    )
}

do {
    let taken: Set<String> = ["/tmp/memos/memo.txt", "/tmp/memos/memo-1.txt", "/tmp/memos/memo-2.txt"]
    equal(
        TranscriptFileNaming.uniqueURL(forBase: "memo", in: dir, fileExists: { taken.contains($0.path) }).lastPathComponent,
        "memo-3.txt",
        "zählt durch mehrere Kollisionen hoch"
    )
}

do {
    let taken: Set<String> = ["/tmp/memos/a.txt"]
    let url = TranscriptFileNaming.uniqueURL(forBase: "a", in: dir, fileExists: { taken.contains($0.path) })
    check(!taken.contains(url.path), "überschreibt nie eine existierende Datei")
}

equal(
    TranscriptFileNaming.uniqueURL(forBase: "IMG_1119", ext: "srt", in: dir, fileExists: { _ in false }).lastPathComponent,
    "IMG_1119.srt",
    "respektiert die Datei-Endung (.srt)"
)

// MARK: - PopoverRouter (Feature 1: Fortschritt beim Wiederöffnen sehen)

equal(
    PopoverRouter.destinationOnPresent(workflowActive: true, fileTranscriptionActive: true, shouldShowOnboarding: true, onTransientPage: true),
    .workflow,
    "laufender Workflow hat Vorrang"
)
equal(
    PopoverRouter.destinationOnPresent(workflowActive: false, fileTranscriptionActive: true, shouldShowOnboarding: true, onTransientPage: true),
    .fileTranscription,
    "laufende Datei-Transkription wird beim Öffnen wieder gezeigt"
)
equal(
    PopoverRouter.destinationOnPresent(workflowActive: false, fileTranscriptionActive: false, shouldShowOnboarding: true, onTransientPage: true),
    .onboarding,
    "Onboarding wenn nötig"
)
equal(
    PopoverRouter.destinationOnPresent(workflowActive: false, fileTranscriptionActive: false, shouldShowOnboarding: false, onTransientPage: true),
    .main,
    "von transienter Seite zurück auf Haupt"
)
equal(
    PopoverRouter.destinationOnPresent(workflowActive: false, fileTranscriptionActive: false, shouldShowOnboarding: false, onTransientPage: false),
    .unchanged,
    "sonst Seite unverändert lassen"
)

// MARK: - SubtitleFormatter (Untertitel/SRT aus Timestamps)

equal(SubtitleFormatter.srtTimecode(0), "00:00:00,000", "Timecode 0")
equal(SubtitleFormatter.srtTimecode(4.5), "00:00:04,500", "Timecode 4,5 s")
equal(SubtitleFormatter.srtTimecode(65.25), "00:01:05,250", "Timecode 65,25 s")
equal(SubtitleFormatter.srtTimecode(3661.007), "01:01:01,007", "Timecode > 1 h")
equal(SubtitleFormatter.srtTimecode(-3), "00:00:00,000", "negativ → 0 (kein Absturz)")

equal(SubtitleFormatter.srt(from: []), "", "leere Cue-Liste → leerer String")

equal(
    SubtitleFormatter.srt(from: [SubtitleCue(start: 0, end: 2, text: "Hallo")]),
    "1\n00:00:00,000 --> 00:00:02,000\nHallo\n",
    "eine Cue korrekt formatiert"
)

equal(
    SubtitleFormatter.srt(from: [
        SubtitleCue(start: 0, end: 2, text: "Hallo"),
        SubtitleCue(start: 2, end: 4.5, text: "Welt"),
    ]),
    "1\n00:00:00,000 --> 00:00:02,000\nHallo\n\n2\n00:00:02,000 --> 00:00:04,500\nWelt\n",
    "zwei Cues nummeriert + Leerzeile dazwischen"
)

// MARK: - WhisperKit-Spezial-Tokens aus Untertiteln entfernen

equal(
    SubtitleFormatter.strippingTokens("<|startoftranscript|><|de|><|transcribe|><|0.00|> irgendwie geht.<|3.68|>"),
    "irgendwie geht.",
    "entfernt alle <|…|>-Tokens und trimmt"
)
equal(SubtitleFormatter.strippingTokens("Nee."), "Nee.", "lässt token-freien Text unverändert")
equal(SubtitleFormatter.strippingTokens("<|5.06|> Macht aber nicht.<|6.06|>"), "Macht aber nicht.", "entfernt umschließende Zeit-Tokens")
equal(SubtitleFormatter.strippingTokens(""), "", "leer bleibt leer")

// MARK: - TranscriptionBatchSummary (Fix 3: Stapel-Fehler sichtbar machen)

check(TranscriptionBatchSummary.text(succeeded: 8, failures: []) == nil,
      "ohne Fehler keine Bilanz")
equal(
    TranscriptionBatchSummary.text(succeeded: 7, failures: ["IMG_1.mov: keine Sprache erkannt"]) ?? "",
    "7 erfolgreich, 1 fehlgeschlagen:\n• IMG_1.mov: keine Sprache erkannt",
    "eine fehlgeschlagene Datei"
)
equal(
    TranscriptionBatchSummary.text(succeeded: 0, failures: ["a", "b"]) ?? "",
    "0 erfolgreich, 2 fehlgeschlagen:\n• a\n• b",
    "alle fehlgeschlagen, mehrere Einträge"
)

// MARK: - LocalRewriteSanitizer (Vorreden kleiner lokaler Modelle entfernen)

equal(
    LocalRewriteSanitizer.clean("Hier ist der verbesserte Text:\n\nEs gibt mehrere Fragen, die ich ansprechen muss."),
    "Es gibt mehrere Fragen, die ich ansprechen muss.",
    "entfernt deutsche Einleitung"
)
equal(
    LocalRewriteSanitizer.clean("Here is the improved text: Hello world"),
    "Hello world",
    "entfernt englische Einleitung"
)
equal(
    LocalRewriteSanitizer.clean("Hier ist die verbesserte Version:\nText"),
    "Text",
    "Variante 'verbesserte Version'"
)
equal(
    LocalRewriteSanitizer.clean("Es gibt mehrere Fragen."),
    "Es gibt mehrere Fragen.",
    "Text ohne Vorrede bleibt unverändert"
)
equal(
    LocalRewriteSanitizer.clean("\u{201E}Nur ein Satz.\u{201C}"),
    "Nur ein Satz.",
    "umschließende Anführungszeichen weg"
)
equal(
    LocalRewriteSanitizer.clean("Hier ist mein Plan und so weiter."),
    "Hier ist mein Plan und so weiter.",
    "ohne Doppelpunkt keine Fehl-Kürzung"
)

// MARK: - Ergebnis

print("Tests: \(passed) grün, \(failures) rot")
exit(failures == 0 ? 0 : 1)
