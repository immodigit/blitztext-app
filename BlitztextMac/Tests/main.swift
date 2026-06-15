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

// MARK: - Ergebnis

print("Tests: \(passed) grün, \(failures) rot")
exit(failures == 0 ? 0 : 1)
