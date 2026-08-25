import Foundation

// MARK: - Modifier

/// Die fünf Modifier, aus denen ein Blitztext-Kürzel besteht.
///
/// Bewusst nur Modifier und keine Buchstaben: Blitztext hört global mit
/// (`NSEvent.addGlobalMonitorForEvents`) und kann Tastendrücke dabei nicht
/// schlucken. Ein Buchstabe im Kürzel würde beim Aufnehmen mit in den Text
/// tippen. Modifier allein lösen in keiner App etwas aus.
public enum HotkeyModifier: String, CaseIterable, Codable, Sendable {
    case function
    case control
    case option
    case shift
    case command

    /// Beschriftung wie auf der Taste — landet 1:1 im Kürzel-Badge.
    public var displayName: String {
        switch self {
        case .function: return "fn"
        case .control: return "Ctrl"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Cmd"
        }
    }

    public var symbol: String {
        switch self {
        case .function: return "fn"
        case .control: return "\u{2303}"
        case .option: return "\u{2325}"
        case .shift: return "\u{21E7}"
        case .command: return "\u{2318}"
        }
    }

    /// Bit im Rohwert von `NSEvent.ModifierFlags`.
    var eventFlagBit: UInt {
        switch self {
        case .function: return 1 << 23
        case .control: return 1 << 18
        case .option: return 1 << 19
        case .shift: return 1 << 17
        case .command: return 1 << 20
        }
    }

    /// Übersetzt das rohe macOS-Flag-Bitfeld in die fünf relevanten Modifier.
    ///
    /// Filtert bewusst alles andere weg. `deviceIndependentFlagsMask` enthält
    /// auch CapsLock, numericPad und help — mit aktivem CapsLock hätte sonst
    /// kein einziges Kürzel mehr gegriffen.
    public static func set(fromEventFlags raw: UInt) -> Set<HotkeyModifier> {
        Set(allCases.filter { raw & $0.eventFlagBit != 0 })
    }
}

extension HotkeyModifier: Comparable {
    /// Kanonische macOS-Reihenfolge: fn ⌃ ⌥ ⇧ ⌘.
    private var order: Int {
        switch self {
        case .function: return 0
        case .control: return 1
        case .option: return 2
        case .shift: return 3
        case .command: return 4
        }
    }

    public static func < (lhs: HotkeyModifier, rhs: HotkeyModifier) -> Bool {
        lhs.order < rhs.order
    }
}

// MARK: - Binding

public enum HotkeyBindingProblem: Equatable, Sendable {
    /// Weniger als zwei Modifier. Ein einzelner Modifier (nur Shift, nur Cmd)
    /// wird beim normalen Tippen ständig gedrückt — die Aufnahme würde bei
    /// jedem Großbuchstaben starten.
    case tooFewModifiers
}

/// Eine Tastenkombination aus Modifiern, unabhängig von der Reihenfolge.
public struct HotkeyBinding: Hashable, Sendable {
    public static let minimumModifierCount = 2

    public let modifiers: Set<HotkeyModifier>

    public init(_ modifiers: Set<HotkeyModifier>) {
        self.modifiers = modifiers
    }

    public init(_ modifiers: HotkeyModifier...) {
        self.modifiers = Set(modifiers)
    }

    public var sortedModifiers: [HotkeyModifier] { modifiers.sorted() }

    /// „fn + Shift" — der Badge in der Menüleiste teilt am " + ".
    public var label: String {
        sortedModifiers.map(\.displayName).joined(separator: " + ")
    }

    public var symbolLabel: String {
        sortedModifiers.map(\.symbol).joined()
    }

    /// Braucht eine fn-Taste. Viele externe Tastaturen haben keine, oder ihr
    /// fn wird in der Tastatur-Firmware verarbeitet und erreicht macOS nie.
    public var usesFunctionKey: Bool { modifiers.contains(.function) }

    public var problem: HotkeyBindingProblem? {
        modifiers.count < Self.minimumModifierCount ? .tooFewModifiers : nil
    }

    public var isValid: Bool { problem == nil }

    /// Exakter Treffer: `fn + Shift` darf nicht auch bei `fn + Shift + Ctrl`
    /// auslösen, sonst wäre die dreitastige Kombination nicht erreichbar.
    /// Ungültige Belegungen lösen nie aus (sonst würde eine leere Belegung
    /// bei jedem Loslassen feuern).
    public func matches(_ pressed: Set<HotkeyModifier>) -> Bool {
        isValid && modifiers == pressed
    }
}

extension HotkeyBinding: Codable {
    /// Als sortierte Liste von Rohwerten — in der settings.json lesbar und stabil.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sortedModifiers.map(\.rawValue))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValues = try container.decode([String].self)
        // Unbekannte Modifier aus einer neueren Version überspringen statt
        // den Start mit einem Decoding-Fehler zu verlieren.
        self.init(Set(rawValues.compactMap(HotkeyModifier.init(rawValue:))))
    }
}

// MARK: - Presets

public enum HotkeyPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Apple-Tastatur (eingebaut oder Magic Keyboard) — alles über fn.
    case appleKeyboard
    /// Externe Tastatur ohne nutzbare fn-Taste.
    case externalKeyboard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleKeyboard: return "Apple-Tastatur"
        case .externalKeyboard: return "Externe Tastatur"
        }
    }

    public var explanation: String {
        switch self {
        case .appleKeyboard:
            return "Kürzel über die fn-Taste. Passt für die eingebaute Tastatur und das Magic Keyboard."
        case .externalKeyboard:
            return "Ganz ohne fn. Für Tastaturen, deren fn-Taste fehlt oder macOS nie erreicht."
        }
    }
}

// MARK: - Binding Set

/// Welche Kombination welchen Workflow startet.
///
/// Ein Workflow darf auch unbelegt sein (kein Eintrag) — dann ist er nur über
/// das Menü erreichbar.
public struct HotkeyBindingSet: Equatable, Sendable {
    private var storage: [WorkflowType: HotkeyBinding]

    public init(_ bindings: [WorkflowType: HotkeyBinding] = [:]) {
        self.storage = bindings
    }

    public subscript(type: WorkflowType) -> HotkeyBinding? { storage[type] }

    public var bindings: [WorkflowType: HotkeyBinding] { storage }

    // MARK: Treffer

    /// Der Workflow zur gedrückten Kombination — oder nil.
    public func workflow(matching pressed: Set<HotkeyModifier>) -> WorkflowType? {
        // Feste Reihenfolge über allCases, damit das Ergebnis auch bei einer
        // (reparierbaren) Doppelbelegung deterministisch bleibt.
        WorkflowType.allCases.first { storage[$0]?.matches(pressed) == true }
    }

    // MARK: Ändern

    public func setting(_ binding: HotkeyBinding, for type: WorkflowType) -> HotkeyBindingSet {
        var copy = self
        copy.storage[type] = binding
        return copy
    }

    public func clearing(_ type: WorkflowType) -> HotkeyBindingSet {
        var copy = self
        copy.storage[type] = nil
        return copy
    }

    // MARK: Prüfen

    /// Andere Workflows, die diese Kombination schon belegen.
    public func conflicts(with binding: HotkeyBinding, ignoring type: WorkflowType) -> [WorkflowType] {
        WorkflowType.allCases.filter { $0 != type && storage[$0] == binding }
    }

    /// Andere Workflows, deren Kombination in `binding` steckt oder umgekehrt.
    ///
    /// macOS meldet jeden Modifier einzeln: Auf dem Weg zu `fn + Shift + Ctrl`
    /// ist zwangsläufig kurz `fn + Shift` gedrückt — und das löst dann zuerst
    /// aus. Solche Belegungen sind nur erreichbar, wenn die zusätzliche Taste
    /// zuletzt gedrückt wird. Kein Fehler, aber die Einstellungen sollen davor
    /// warnen statt den Nutzer rätseln zu lassen.
    public func overlaps(with binding: HotkeyBinding, ignoring type: WorkflowType) -> [WorkflowType] {
        WorkflowType.allCases.filter { other in
            guard other != type, let existing = storage[other] else { return false }
            return existing.modifiers.isStrictSubset(of: binding.modifiers)
                || binding.modifiers.isStrictSubset(of: existing.modifiers)
        }
    }

    public var conflictingWorkflows: Set<WorkflowType> {
        var seen: [HotkeyBinding: [WorkflowType]] = [:]
        for type in WorkflowType.allCases {
            guard let binding = storage[type] else { continue }
            seen[binding, default: []].append(type)
        }
        return Set(seen.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    public var invalidWorkflows: Set<WorkflowType> {
        Set(WorkflowType.allCases.filter { type in
            guard let binding = storage[type] else { return false }
            return !binding.isValid
        })
    }

    /// Jeder Workflow hat eine gültige, eindeutige Kombination.
    public var isComplete: Bool {
        WorkflowType.allCases.allSatisfy { storage[$0]?.isValid == true }
            && conflictingWorkflows.isEmpty
    }

    /// Räumt eine kaputte oder von Hand bearbeitete Belegung auf:
    /// ungültige Einträge und Doppelbelegungen fliegen raus. Bei einer
    /// Doppelbelegung behält der in `WorkflowType.allCases` frühere Workflow
    /// die Kombination — nicht der Zufall der Dictionary-Reihenfolge.
    public func repaired() -> HotkeyBindingSet {
        var result: [WorkflowType: HotkeyBinding] = [:]
        var taken: Set<HotkeyBinding> = []
        for type in WorkflowType.allCases {
            guard let binding = storage[type], binding.isValid, !taken.contains(binding) else { continue }
            result[type] = binding
            taken.insert(binding)
        }
        return HotkeyBindingSet(result)
    }

    // MARK: Presets

    public static func preset(_ preset: HotkeyPreset) -> HotkeyBindingSet {
        switch preset {
        case .appleKeyboard:
            return HotkeyBindingSet([
                .transcription: HotkeyBinding(.function, .shift),
                .localTranscription: HotkeyBinding(.function, .shift, .control),
                .textImprover: HotkeyBinding(.function, .control),
                .dampfAblassen: HotkeyBinding(.function, .option),
                .emojiText: HotkeyBinding(.function, .command),
            ])
        case .externalKeyboard:
            // Bewusst nur Zweier-Kombinationen: Eine Dreier-Kombination wäre
            // hier nicht sicher erreichbar, weil ihre Teilmenge zuerst auslöst
            // (siehe `overlaps(with:ignoring:)`). Cmd + Shift bleibt frei — das
            // steckt in zu vielen App-Kürzeln. Die meistgenutzte Aktion bekommt
            // die Kombination, die am seltensten aus Versehen entsteht.
            return HotkeyBindingSet([
                .transcription: HotkeyBinding(.control, .option),
                .localTranscription: HotkeyBinding(.control, .shift),
                .textImprover: HotkeyBinding(.option, .shift),
                .dampfAblassen: HotkeyBinding(.control, .command),
                .emojiText: HotkeyBinding(.option, .command),
            ])
        }
    }

    public static let `default` = HotkeyBindingSet.preset(.appleKeyboard)

    /// Welches Preset gerade genau eingestellt ist — für die Auswahl in den
    /// Einstellungen. Nil, sobald der Nutzer etwas Eigenes belegt hat.
    public var matchingPreset: HotkeyPreset? {
        HotkeyPreset.allCases.first { Self.preset($0) == self }
    }
}

extension HotkeyBindingSet: Codable {
    /// Als `{"transcription": ["function","shift"], …}` — in der settings.json
    /// von Hand lesbar und änderbar.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var raw: [String: HotkeyBinding] = [:]
        for (type, binding) in storage {
            raw[type.rawValue] = binding
        }
        try container.encode(raw)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode([String: HotkeyBinding].self)
        var result: [WorkflowType: HotkeyBinding] = [:]
        for (key, binding) in raw {
            // Unbekannte Workflows aus einer neueren Version überspringen.
            guard let type = WorkflowType(rawValue: key) else { continue }
            result[type] = binding
        }
        self.init(result)
    }
}

// MARK: - Chord Recorder

public enum HotkeyChordRecorderState: Equatable, Sendable {
    case idle
    case recording(Set<HotkeyModifier>)
    case captured(HotkeyBinding)
    case rejected(HotkeyBindingProblem)
}

/// Nimmt eine neue Kombination auf: Tasten halten, loslassen, fertig.
///
/// Gemerkt wird die größte gehaltene Kombination, nicht die zuletzt gesehene —
/// sonst würde ein abrutschender Finger beim Loslassen die Kombination kürzen.
public struct HotkeyChordRecorder: Sendable {
    public private(set) var state: HotkeyChordRecorderState = .idle
    private var accumulated: Set<HotkeyModifier> = []

    public init() {}

    @discardableResult
    public mutating func handle(pressed: Set<HotkeyModifier>) -> HotkeyChordRecorderState {
        if pressed.isEmpty {
            guard !accumulated.isEmpty else {
                state = .idle
                return state
            }
            let binding = HotkeyBinding(accumulated)
            accumulated = []
            state = binding.isValid ? .captured(binding) : .rejected(binding.problem ?? .tooFewModifiers)
            return state
        }

        if case .captured = state { accumulated = [] }
        if case .rejected = state { accumulated = [] }

        accumulated.formUnion(pressed)
        state = .recording(accumulated)
        return state
    }

    public mutating func reset() {
        accumulated = []
        state = .idle
    }
}
