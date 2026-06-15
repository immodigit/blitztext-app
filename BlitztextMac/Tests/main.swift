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

// MARK: - Ergebnis

print("Tests: \(passed) grün, \(failures) rot")
exit(failures == 0 ? 0 : 1)
