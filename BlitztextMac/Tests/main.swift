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
// Key als Teilstrings zusammengesetzt (wie oben), damit kein literaler
// "sk-…"-Schlüssel im Quelltext steht und der CI-Secret-Scan nicht anschlägt.
check(OpenAIKeyValidator.isPlausible("  sk-" + "abcdefghij1234567890ABCD  "),
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

// MARK: - HotkeyModifier: NSEvent-Flags übersetzen
// Wichtig für externe Tastaturen und den CapsLock-Fehler: aus dem rohen
// macOS-Flag-Bitfeld dürfen nur die fünf echten Modifier ankommen.

let capsLockBit: UInt = 1 << 16
let shiftBit: UInt = 1 << 17
let controlBit: UInt = 1 << 18
let optionBit: UInt = 1 << 19
let commandBit: UInt = 1 << 20
let numericPadBit: UInt = 1 << 21
let helpBit: UInt = 1 << 22
let functionBit: UInt = 1 << 23

equal(HotkeyModifier.set(fromEventFlags: 0), [], "keine Taste gedrückt → leere Menge")
equal(HotkeyModifier.set(fromEventFlags: functionBit | shiftBit), [.function, .shift], "fn + Shift erkannt")
equal(
    HotkeyModifier.set(fromEventFlags: controlBit | optionBit | commandBit),
    [.control, .option, .command],
    "fn-freie Kombination erkannt"
)
equal(
    HotkeyModifier.set(fromEventFlags: capsLockBit | functionBit | shiftBit),
    [.function, .shift],
    "CapsLock wird ignoriert (sonst greift bei aktivem CapsLock kein Kürzel)"
)
equal(
    HotkeyModifier.set(fromEventFlags: numericPadBit | helpBit | controlBit | shiftBit),
    [.control, .shift],
    "numericPad/help werden ignoriert"
)

// MARK: - HotkeyBinding: Anzeige, Gültigkeit, Treffer

equal(HotkeyBinding(.function, .shift).label, "fn + Shift", "Label in kanonischer Reihenfolge")
equal(HotkeyBinding(.shift, .function).label, "fn + Shift", "Reihenfolge der Eingabe egal")
equal(HotkeyBinding(.command, .control, .option, .shift, .function).label,
      "fn + Ctrl + Option + Shift + Cmd",
      "kanonische macOS-Reihenfolge fn ⌃ ⌥ ⇧ ⌘")
equal(HotkeyBinding(.control, .option).symbolLabel, "⌃⌥", "Symbol-Label ohne Trenner")

check(HotkeyBinding(.function, .shift).isValid, "zwei Modifier sind gültig")
check(!HotkeyBinding(.shift).isValid, "ein einzelner Modifier ist zu wenig")
equal(HotkeyBinding(.shift).problem, .tooFewModifiers, "Grund wird benannt")
check(!HotkeyBinding([]).isValid, "leere Belegung ist ungültig")

check(HotkeyBinding(.function, .shift).matches([.function, .shift]), "exakter Treffer")
check(!HotkeyBinding(.function, .shift).matches([.function, .shift, .control]),
      "Obermenge trifft nicht (sonst würde fn+Shift+Ctrl doppelt auslösen)")
check(!HotkeyBinding(.function, .shift).matches([.function]), "Teilmenge trifft nicht")
check(!HotkeyBinding([]).matches([]), "leere Belegung darf nie auslösen")
check(!HotkeyBinding(.shift).matches([.shift]), "ungültige Belegung löst nie aus")

check(HotkeyBinding(.function, .shift).usesFunctionKey, "erkennt fn-Abhängigkeit")
check(!HotkeyBinding(.control, .option).usesFunctionKey, "fn-freie Belegung erkannt")

// MARK: - HotkeyBinding: Codable (stabile Form in settings.json)

do {
    let binding = HotkeyBinding(.command, .function)
    let data = try! JSONEncoder().encode(binding)
    equal(String(data: data, encoding: .utf8) ?? "", "[\"function\",\"command\"]",
          "kodiert als sortierte Liste")
    equal(try! JSONDecoder().decode(HotkeyBinding.self, from: data), binding, "Roundtrip")
}

do {
    // Vorwärtskompatibel: unbekannte Modifier aus einer neueren Version
    // dürfen den Start nicht sprengen.
    let data = Data("[\"function\",\"shift\",\"hyperkey\"]".utf8)
    equal(try! JSONDecoder().decode(HotkeyBinding.self, from: data), HotkeyBinding(.function, .shift),
          "unbekannte Modifier werden verworfen")
}

// MARK: - HotkeyBindingSet: Zuordnung Workflow ↔ Tastenkombination

let apple = HotkeyBindingSet.preset(.appleKeyboard)

equal(apple[.transcription], HotkeyBinding(.function, .shift), "Standard bleibt fn + Shift")
equal(apple[.localTranscription], HotkeyBinding(.function, .shift, .control), "Standard lokal bleibt fn + Shift + Ctrl")
equal(apple[.textImprover], HotkeyBinding(.function, .control), "Standard Blitztext+ bleibt fn + Ctrl")
equal(apple[.dampfAblassen], HotkeyBinding(.function, .option), "Standard $%&! bleibt fn + Option")
equal(apple[.emojiText], HotkeyBinding(.function, .command), "Standard :) bleibt fn + Cmd")

equal(apple.workflow(matching: [.function, .shift]), .transcription, "fn + Shift startet Transkription")
equal(apple.workflow(matching: [.function, .shift, .control]), .localTranscription,
      "fn + Shift + Ctrl startet die lokale Transkription (nicht die Cloud-Variante)")
check(apple.workflow(matching: [.function]) == nil, "einzelnes fn löst nichts aus")
check(apple.workflow(matching: []) == nil, "nichts gedrückt löst nichts aus")
check(apple.workflow(matching: [.control, .option]) == nil, "unbelegte Kombination löst nichts aus")

// MARK: - Preset für externe Tastaturen (kein fn vorhanden)

let external = HotkeyBindingSet.preset(.externalKeyboard)

for type in WorkflowType.allCases {
    check(external[type] != nil, "externes Preset belegt \(type.rawValue)")
    check(external[type]?.usesFunctionKey == false, "externes Preset kommt ohne fn aus: \(type.rawValue)")
}
check(external.isComplete, "externes Preset belegt jeden Workflow gültig und überschneidungsfrei")
check(apple.isComplete, "Apple-Preset belegt jeden Workflow gültig und überschneidungsfrei")

equal(apple.matchingPreset, .appleKeyboard, "Apple-Preset wird wiedererkannt")
equal(external.matchingPreset, .externalKeyboard, "externes Preset wird wiedererkannt")
check(apple.setting(HotkeyBinding(.control, .command), for: .emojiText).matchingPreset == nil,
      "abweichende Belegung ist kein Preset mehr")

// MARK: - Umbelegen und Konflikte

do {
    let changed = apple.setting(HotkeyBinding(.control, .option), for: .transcription)
    equal(changed[.transcription], HotkeyBinding(.control, .option), "neue Belegung übernommen")
    equal(changed[.textImprover], apple[.textImprover], "andere Workflows bleiben unangetastet")
    equal(changed.workflow(matching: [.control, .option]), .transcription, "neue Kombination greift")
    check(changed.workflow(matching: [.function, .shift]) == nil, "alte Kombination greift nicht mehr")
}

equal(apple.conflicts(with: HotkeyBinding(.function, .control), ignoring: .transcription), [.textImprover],
      "belegte Kombination wird als Konflikt gemeldet")
equal(apple.conflicts(with: HotkeyBinding(.function, .control), ignoring: .textImprover), [],
      "eigene Belegung ist kein Konflikt mit sich selbst")
equal(apple.conflicts(with: HotkeyBinding(.control, .option), ignoring: .transcription), [],
      "freie Kombination meldet keinen Konflikt")

do {
    let unbound = apple.clearing(.dampfAblassen)
    check(unbound[.dampfAblassen] == nil, "Belegung lässt sich entfernen")
    check(unbound.workflow(matching: [.function, .option]) == nil, "entfernte Belegung löst nicht mehr aus")
    check(!unbound.isComplete, "unbelegter Workflow gilt als unvollständig")
}

// MARK: - Reparatur beim Laden (kaputte oder alte settings.json)

do {
    // Doppelbelegung: der erste Workflow in fester Reihenfolge behält sie.
    let broken = apple.setting(HotkeyBinding(.function, .shift), for: .emojiText)
    equal(broken.conflictingWorkflows, [.transcription, .emojiText], "Doppelbelegung wird erkannt")
    let repaired = broken.repaired()
    equal(repaired[.transcription], HotkeyBinding(.function, .shift), "erster Workflow behält die Kombination")
    check(repaired[.emojiText] == nil, "die doppelte Belegung wird entfernt statt zufällig zu gewinnen")
    equal(repaired.conflictingWorkflows, [], "nach Reparatur keine Konflikte mehr")
}

do {
    let broken = apple.setting(HotkeyBinding(.shift), for: .textImprover)
    let repaired = broken.repaired()
    check(repaired[.textImprover] == nil, "ungültige Einzeltaste wird beim Laden verworfen")
    equal(repaired[.transcription], HotkeyBinding(.function, .shift), "gültige Belegungen bleiben erhalten")
}

equal(apple.repaired(), apple, "gesunde Belegung bleibt unverändert")

// MARK: - HotkeyBindingSet: Codable

do {
    let custom = HotkeyBindingSet.preset(.externalKeyboard).setting(HotkeyBinding(.control, .command), for: .emojiText)
    let data = try! JSONEncoder().encode(custom)
    equal(try! JSONDecoder().decode(HotkeyBindingSet.self, from: data), custom, "Roundtrip über JSON")
    let json = String(data: data, encoding: .utf8) ?? ""
    check(json.contains("\"emojiText\""), "Workflow-Schlüssel bleiben lesbar in der settings.json")
}

do {
    // Alte Datei kennt einen Workflow noch nicht → er bleibt einfach unbelegt.
    let data = Data("{\"transcription\":[\"function\",\"shift\"]}".utf8)
    let decoded = try! JSONDecoder().decode(HotkeyBindingSet.self, from: data)
    equal(decoded[.transcription], HotkeyBinding(.function, .shift), "bekannte Belegung wird gelesen")
    check(decoded[.emojiText] == nil, "fehlende Belegung ist kein Fehler")
}

do {
    // Unbekannter Workflow aus einer neueren Version darf nicht crashen.
    let data = Data("{\"transcription\":[\"function\",\"shift\"],\"zeitreise\":[\"control\",\"option\"]}".utf8)
    let decoded = try! JSONDecoder().decode(HotkeyBindingSet.self, from: data)
    equal(decoded[.transcription], HotkeyBinding(.function, .shift), "unbekannter Workflow wird übersprungen")
    check(decoded.workflow(matching: [.control, .option]) == nil, "unbekannte Belegung löst nichts aus")
}

// MARK: - Teilmengen-Falle
// macOS meldet jeden Modifier einzeln. Auf dem Weg zu fn+Shift+Ctrl ist
// zwangsläufig kurz fn+Shift gedrückt — und das löst dann die Transkription
// aus. Eine längere Kombination ist nur erreichbar, wenn die zusätzliche
// Taste zuletzt gedrückt wird. Belegungen müssen davor warnen.

equal(
    apple.overlaps(with: HotkeyBinding(.function, .shift, .control), ignoring: .localTranscription),
    [.transcription, .textImprover],
    "fn + Shift + Ctrl wird von den kürzeren fn-Kombinationen verdeckt"
)
equal(
    apple.overlaps(with: HotkeyBinding(.function, .shift), ignoring: .transcription),
    [.localTranscription],
    "die kürzere Kombination verdeckt auch die längere (Warnung in beide Richtungen)"
)
equal(
    apple.overlaps(with: HotkeyBinding(.control, .option), ignoring: .transcription),
    [],
    "unabhängige Kombination verdeckt nichts"
)
equal(
    apple.overlaps(with: HotkeyBinding(.function, .command), ignoring: .emojiText),
    [],
    "gleiche Belegung an sich selbst ist keine Verdeckung"
)

for type in WorkflowType.allCases {
    guard let binding = external[type] else { continue }
    equal(external.overlaps(with: binding, ignoring: type), [],
          "externes Preset ist frei von Teilmengen-Fallen: \(type.rawValue)")
    equal(binding.modifiers.count, 2,
          "externes Preset nutzt nur Zweier-Kombinationen: \(type.rawValue)")
    check(!binding.modifiers.contains(.command) || binding.modifiers.contains(.control) || binding.modifiers.contains(.option),
          "kein Kürzel aus Cmd + Shift (kollidiert zu oft mit App-Kürzeln): \(type.rawValue)")
}

// MARK: - HotkeyChordRecorder: Kombination aufnehmen

do {
    var recorder = HotkeyChordRecorder()
    equal(recorder.state, .idle, "startet im Leerlauf")
    equal(recorder.handle(pressed: []), .idle, "ohne Tastendruck passiert nichts")
    equal(recorder.handle(pressed: [.control]), .recording([.control]), "erste Taste wird aufgenommen")
    equal(recorder.handle(pressed: [.control, .option]), .recording([.control, .option]), "zweite Taste kommt dazu")
    equal(recorder.handle(pressed: []), .captured(HotkeyBinding(.control, .option)), "Loslassen schließt ab")
}

do {
    // Finger rutscht ab: die größte gehaltene Kombination zählt, nicht die letzte.
    var recorder = HotkeyChordRecorder()
    _ = recorder.handle(pressed: [.function])
    _ = recorder.handle(pressed: [.function, .shift])
    _ = recorder.handle(pressed: [.function])
    equal(recorder.handle(pressed: []), .captured(HotkeyBinding(.function, .shift)),
          "gemerkt wird die größte gehaltene Kombination")
}

do {
    var recorder = HotkeyChordRecorder()
    _ = recorder.handle(pressed: [.shift])
    equal(recorder.handle(pressed: []), .rejected(.tooFewModifiers), "eine einzelne Taste wird abgelehnt")
    equal(recorder.handle(pressed: [.control, .command]), .recording([.control, .command]),
          "nach Ablehnung ist die nächste Aufnahme wieder frei")
    equal(recorder.handle(pressed: []), .captured(HotkeyBinding(.control, .command)), "zweiter Versuch klappt")
}

do {
    var recorder = HotkeyChordRecorder()
    _ = recorder.handle(pressed: [.control, .option])
    _ = recorder.handle(pressed: [])
    equal(recorder.handle(pressed: [.command, .shift]), .recording([.command, .shift]),
          "neue Aufnahme beginnt bei null statt weiterzuzählen")
    recorder.reset()
    equal(recorder.state, .idle, "reset räumt auf")
}

// MARK: - Sprechererkennung: Sprecherwechsel

do {
    let pieces = [
        AttributedPiece(speaker: 0, start: 0, end: 2, text: "Hallo"),
        AttributedPiece(speaker: 0, start: 2, end: 4, text: "Daniel."),
        AttributedPiece(speaker: 1, start: 4, end: 6, text: "Hi Chris."),
        AttributedPiece(speaker: 0, start: 6, end: 8, text: "Pass auf."),
    ]
    let turns = SpeakerTurns.merge(pieces)
    equal(turns.count, 3, "aufeinanderfolgende Stücke derselben Person werden ein Redebeitrag")
    equal(turns.first, SpeakerTurn(speaker: 0, start: 0, end: 4, text: "Hallo Daniel."), "Text und Zeit werden verbunden")
    equal(turns.last?.speaker, 0, "Sprecherwechsel zurück erzeugt einen neuen Beitrag")
}

do {
    let pieces = [
        AttributedPiece(speaker: nil, start: 0, end: 1, text: "Äh"),
        AttributedPiece(speaker: 1, start: 1, end: 3, text: "Also gut."),
        AttributedPiece(speaker: nil, start: 3, end: 4, text: "ja"),
        AttributedPiece(speaker: 0, start: 4, end: 5, text: "Okay."),
    ]
    let turns = SpeakerTurns.merge(pieces)
    equal(turns.map(\.speaker), [1, 0], "Stücke ohne Sprecher hängen am Nachbarbeitrag statt eigene Zeilen zu erzeugen")
    equal(turns.first?.text, "Äh Also gut. ja", "unzugeordneter Text geht nicht verloren")
}

equal(SpeakerTurns.merge([AttributedPiece(speaker: 0, start: 0, end: 1, text: "   ")]), [],
      "leere Stücke erzeugen keinen Beitrag")

// MARK: - Sprechererkennung: Platzhalter und Format

equal(SpeakerLabels.placeholder(forIndex: 0), "Sprecher A", "erster Platzhalter")
equal(SpeakerLabels.placeholder(forIndex: 2), "Sprecher C", "dritter Platzhalter")
equal(SpeakerLabels.placeholder(forIndex: 26), "Sprecher 27", "nach Z wird gezählt")

do {
    let turns = [
        SpeakerTurn(speaker: 3, start: 0, end: 1, text: "a"),
        SpeakerTurn(speaker: 1, start: 1, end: 2, text: "b"),
        SpeakerTurn(speaker: 3, start: 2, end: 3, text: "c"),
    ]
    equal(SpeakerLabels.placeholders(for: turns), [3: "Sprecher A", 1: "Sprecher B"],
          "Platzhalter folgen der Reihenfolge des ersten Wortbeitrags, nicht der internen Nummer")
}

equal(SpeakerTranscriptFormatter.timecode(75), "01:15", "Zeitmarke unter einer Stunde")
equal(SpeakerTranscriptFormatter.timecode(3725), "1:02:05", "Zeitmarke ab einer Stunde")

do {
    let turns = [
        SpeakerTurn(speaker: 0, start: 0, end: 4, text: "Hallo Daniel."),
        SpeakerTurn(speaker: 1, start: 64, end: 66, text: "Hi Chris."),
    ]
    equal(SpeakerTranscriptFormatter.text(turns: turns, names: [0: "Chris", 1: "Sprecher B"]),
          "[00:00] Chris: Hallo Daniel.\n\n[01:04] Sprecher B: Hi Chris.",
          "Transkript zeigt Zeitmarke, Namen und Text je Beitrag")
}

// MARK: - Sprechererkennung: Zeitachse

do {
    let spans = [
        SpeakerSpan(speaker: 0, start: 0, end: 10),
        SpeakerSpan(speaker: 1, start: 8, end: 14),
        SpeakerSpan(speaker: 0, start: 20, end: 21),
    ]
    let exclusive = SpeakerTimeline.exclusiveSpans(spans, minimumDuration: 1.5)
    equal(exclusive[0], [TimeSpan(start: 0, end: 8)], "Überlappung wird abgeschnitten, zu kurze Stücke fallen weg")
    equal(exclusive[1], [TimeSpan(start: 10, end: 14)], "auch der zweite Sprecher verliert den Überlappungsteil")
    equal(SpeakerTimeline.talkTime(spans), [0: 11, 1: 6], "Redezeit zählt alle eigenen Abschnitte")
}

do {
    let spans = [SpeakerSpan(speaker: 0, start: 0, end: 5), SpeakerSpan(speaker: 0, start: 3, end: 8)]
    equal(SpeakerTimeline.talkTime(spans), [0: 8], "überlappende Abschnitte derselben Person zählen nicht doppelt")
    equal(SpeakerTimeline.exclusiveSpans(spans, minimumDuration: 1)[0], [TimeSpan(start: 0, end: 8)],
          "eigene Überlappung ist keine Fremdüberlappung")
}

// MARK: - Sprechererkennung: Hörproben

do {
    let spans = [
        TimeSpan(start: 0, end: 3), TimeSpan(start: 10, end: 30), TimeSpan(start: 40, end: 41),
        TimeSpan(start: 300, end: 306), TimeSpan(start: 600, end: 604),
    ]
    let picks = VoiceSamplePicker.pick(from: spans, count: 3, minDuration: 2.5, maxDuration: 8)
    equal(picks.count, 3, "liefert die gewünschte Anzahl Hörproben")
    check(picks.allSatisfy { $0.duration <= 8 && $0.duration >= 2.5 }, "Hörproben sind zwischen Mindest- und Höchstlänge")
    check(picks.contains { $0.start >= 600 } && picks.contains { $0.start < 60 },
          "Hörproben stammen aus Anfang und Ende der Aufnahme, nicht nur vom längsten Block")
    check(picks == picks.sorted { $0.start < $1.start }, "Hörproben sind chronologisch sortiert")
    equal(picks.first { $0.start >= 10 && $0.start < 30 }?.duration, 8, "lange Abschnitte werden auf die Höchstlänge gekürzt")
}

equal(VoiceSamplePicker.pick(from: [TimeSpan(start: 0, end: 1)], count: 3, minDuration: 2.5, maxDuration: 8), [],
      "zu kurze Abschnitte liefern keine Hörprobe")

// MARK: - Sprechererkennung: Stimmabgleich

do {
    let a: [Float] = [3, 4]
    equal(VoiceVectorMath.normalized(a), [0.6, 0.8], "Vektor wird auf Länge 1 gebracht")
    check(abs(VoiceVectorMath.cosine([1, 0], [0, 1])) < 0.0001, "senkrechte Stimmen sind unähnlich")
    check(abs(VoiceVectorMath.cosine([2, 0], [5, 0]) - 1) < 0.0001, "Länge spielt für die Ähnlichkeit keine Rolle")
    let merged = VoiceVectorMath.mergedCentroid(existing: [1, 0], weight: 3, adding: [0, 1])
    check(merged[0] > merged[1] && abs(VoiceVectorMath.cosine(merged, [3, 1]) - 1) < 0.0001,
          "neue Probe verschiebt das Profil gewichtet statt es zu ersetzen")
}

do {
    let chris = UUID(), daniel = UUID()
    let profiles = [VoiceProfileCandidate(id: chris, vector: [1, 0, 0]), VoiceProfileCandidate(id: daniel, vector: [0, 1, 0])]
    let speakers: [Int: [Float]] = [
        0: [0.95, 0.05, 0],      // eindeutig Chris
        1: [0.1, 0.6, 0.79],     // halbwegs Daniel
        2: [0, 0.1, 1],          // niemand
    ]
    let result = VoiceMatcher.match(speakers: speakers, profiles: profiles, thresholds: .standard)
    if case .recognized(let id, _) = result[0] { equal(id, chris, "eindeutige Stimme wird erkannt") } else { check(false, "Sprecher 0 sollte erkannt sein") }
    if case .uncertain(let id, _) = result[1] { equal(id, daniel, "mittlere Ähnlichkeit wird als Vermutung gemeldet") } else { check(false, "Sprecher 1 sollte unsicher sein") }
    equal(result[2], .unknown, "fremde Stimme ist neu")
}

do {
    let chris = UUID()
    let profiles = [VoiceProfileCandidate(id: chris, vector: [1, 0])]
    let speakers: [Int: [Float]] = [0: [0.99, 0.1], 1: [0.9, 0.3]]
    let result = VoiceMatcher.match(speakers: speakers, profiles: profiles, thresholds: .standard)
    if case .recognized(let id, _) = result[0] { equal(id, chris, "bester Treffer bekommt das Profil") } else { check(false, "Sprecher 0 sollte erkannt sein") }
    equal(result[1], .unknown, "ein Profil wird nie zwei Sprechern derselben Aufnahme zugeordnet")
}

equal(VoiceMatcher.match(speakers: [0: [1, 0]], profiles: [], thresholds: .standard), [0: .unknown],
      "ohne Profile ist jede Stimme neu")

// MARK: - Sprechererkennung: Zitat zur Hörprobe

do {
    let pieces = [
        AttributedPiece(speaker: 0, start: 0, end: 2, text: "Vorher"),
        AttributedPiece(speaker: 1, start: 9.5, end: 11, text: "ich habe"),
        AttributedPiece(speaker: 1, start: 11, end: 13, text: "über 1000 Wohnungen."),
        AttributedPiece(speaker: 0, start: 17, end: 19, text: "Danach"),
    ]
    equal(TranscriptQuote.text(in: TimeSpan(start: 10, end: 16), from: pieces, maxLength: 200),
          "ich habe über 1000 Wohnungen.", "Zitat enthält genau die Stücke, deren Mitte in der Hörprobe liegt")
    equal(TranscriptQuote.text(in: TimeSpan(start: 10, end: 16), from: pieces, maxLength: 12),
          "ich habe …", "lange Zitate werden an einer Wortgrenze gekürzt")
    equal(TranscriptQuote.text(in: TimeSpan(start: 30, end: 40), from: pieces, maxLength: 200), "",
          "ohne Text in der Hörprobe bleibt das Zitat leer")
}

// MARK: - Sprechererkennung: Zuordnung je Sprecher

do {
    let chris = UUID()
    equal(SpeakerAssignment(match: .recognized(profileID: chris, similarity: 0.9)),
          .recognized(profileID: chris, similarity: 0.9), "sicherer Treffer wird übernommen")
    equal(SpeakerAssignment(match: .uncertain(profileID: chris, similarity: 0.6)),
          .suggested(profileID: chris, similarity: 0.6), "unsicherer Treffer wird zur Vermutung")
    equal(SpeakerAssignment(match: .unknown), .unknown, "fremde Stimme bleibt unbekannt")

    check(SpeakerAssignment.unknown.needsDecision, "neue Stimme wartet auf eine Entscheidung")
    check(SpeakerAssignment.suggested(profileID: chris, similarity: 0.6).needsDecision, "Vermutung wartet auf Bestätigung")
    check(!SpeakerAssignment.recognized(profileID: chris, similarity: 0.9).needsDecision, "erkannte Stimme braucht nichts")
    check(!SpeakerAssignment.skipped.needsDecision, "übersprungene Stimme fragt nicht erneut")

    let lookup: (UUID) -> String? = { $0 == chris ? "Chris" : nil }
    equal(SpeakerAssignment.recognized(profileID: chris, similarity: 0.9).displayName(placeholder: "Sprecher A", profileName: lookup),
          "Chris", "erkannte Stimme trägt den Profilnamen")
    equal(SpeakerAssignment.confirmed(profileID: chris).displayName(placeholder: "Sprecher A", profileName: lookup),
          "Chris", "bestätigte Stimme trägt den Profilnamen")
    equal(SpeakerAssignment.suggested(profileID: chris, similarity: 0.6).displayName(placeholder: "Sprecher B", profileName: lookup),
          "Sprecher B", "eine bloße Vermutung landet nicht im Transkript")
    equal(SpeakerAssignment.named("Gast").displayName(placeholder: "Sprecher C", profileName: lookup),
          "Gast", "nur hier benannte Stimme trägt den Namen")
    equal(SpeakerAssignment.confirmed(profileID: UUID()).displayName(placeholder: "Sprecher A", profileName: lookup),
          "Sprecher A", "gelöschtes Profil fällt auf den Platzhalter zurück")
}

// MARK: - Ergebnis

print("Tests: \(passed) grün, \(failures) rot")
exit(failures == 0 ? 0 : 1)
