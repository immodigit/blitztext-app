import Foundation

/// Wohin das Popover beim Öffnen springen soll.
public enum PopoverDestination: Equatable {
    case workflow
    case fileTranscription
    case onboarding
    case main
    case unchanged
}

/// Reine Routing-Entscheidung fürs Popover — ohne UI/State, damit testbar.
public enum PopoverRouter {
    /// Priorität beim Öffnen:
    /// laufender Workflow › laufende/abgeschlossene Datei-Transkription ›
    /// Onboarding › zurück auf Haupt (wenn vorher auf transienter Seite) › unverändert.
    ///
    /// `onTransientPage` = aktuelle Seite ist Workflow, Onboarding oder Datei-Transkription
    /// (Seiten, die zurückgesetzt werden, wenn nichts mehr aktiv ist).
    public static func destinationOnPresent(
        workflowActive: Bool,
        fileTranscriptionActive: Bool,
        shouldShowOnboarding: Bool,
        onTransientPage: Bool
    ) -> PopoverDestination {
        if workflowActive { return .workflow }
        if fileTranscriptionActive { return .fileTranscription }
        if shouldShowOnboarding { return .onboarding }
        if onTransientPage { return .main }
        return .unchanged
    }
}
