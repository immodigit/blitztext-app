import SwiftUI
import Observation
import AppKit
import BlitztextCore
import UniformTypeIdentifiers

enum PopoverPage: Equatable {
    case main
    case onboarding
    case settings
    case workflow
    case fileTranscription
}

/// Zustand der Datei-Transkription (Sprachnachricht aus einer Datei, z. B. iPhone-Memo).
enum FileTranscriptionState: Equatable {
    case idle
    case running(fileName: String, progress: Double?)
    case done(text: String, fileName: String, savedToFile: Bool)
    case failed(String)
}

/// Ein Transkriptions-Auftrag in der Warteschlange.
struct FileTranscriptionJob {
    let url: URL
    let writeTextFile: Bool
}

@Observable
@MainActor
final class AppState {
    private static let pasteRetryInitialAttempts = 22
    private static let concealedPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    var activeWorkflow: (any Workflow)?
    var page: PopoverPage = .main
    var isPopoverShown = false
    var menuBarStatus: MenuBarStatus = .idle {
        didSet {
            guard oldValue != menuBarStatus else { return }
            onMenuBarStatusChange?(menuBarStatus)
        }
    }
    var accessibilityPermissionGranted = false
    var fileTranscriptionState: FileTranscriptionState = .idle
    private var fileTranscriptionTask: Task<Void, Never>?
    private var lastTranscriptionSourceURL: URL?
    private var fileTranscriptionQueue: [FileTranscriptionJob] = []
    private var fileTranscriptionWrittenOutputs: [URL] = []
    private var isProcessingFileTranscriptionQueue = false
    private var currentFileTranscriptionLabel = ""
    var localModelDownloadProgress: Double?
    var localModelDownloadStatusText: String?
    var localModelDownloadErrorText: String?
    var onMenuBarStatusChange: ((MenuBarStatus) -> Void)?
    private var activeLaunchSource: WorkflowLaunchSource = .manual
    private var activePasteTarget: PasteTarget?
    private var lastPopoverPasteTarget: PasteTarget?
    private var pasteboardRestoreItems: [NSPasteboardItem]?
    private var pasteboardRestoreChangeCount: Int?
    private var menuBarStatusResetTask: Task<Void, Never>?
    private var workflowCleanupTask: Task<Void, Never>?

    // Persisted settings
    var appSettings: AppSettings {
        didSet {
            saveSettings()
            prewarmLocalTranscriptionIfNeeded()
        }
    }
    var transcriptionSettings: TranscriptionSettings {
        didSet { saveSettings() }
    }
    var textImprovementSettings: TextImprovementSettings {
        didSet { saveSettings() }
    }
    var dampfAblassenSettings: DampfAblassenSettings {
        didSet { saveSettings() }
    }
    var emojiTextSettings: EmojiTextSettings {
        didSet { saveSettings() }
    }

    // Hotkeys
    let hotkeyService = HotkeyService()

    // Computed
    var isConfigured: Bool {
        KeychainService.isConfigured || !LocalTranscriptionService.installedModels().isEmpty
    }
    var shouldShowOnboarding: Bool {
        !isConfigured && !appSettings.hasSeenOnboarding
    }

    var currentPhase: WorkflowPhase {
        activeWorkflow?.phase ?? .idle
    }

    init() {
        self.appSettings = Self.loadAppSettings()
        self.transcriptionSettings = Self.loadTranscriptionSettings()
        self.textImprovementSettings = Self.loadTextImprovementSettings()
        self.dampfAblassenSettings = Self.loadDampfAblassenSettings()
        self.emojiTextSettings = Self.loadEmojiTextSettings()
        refreshAccessibilityPermission()
        autoSelectFastLocalModelIfNeeded()
        prewarmLocalTranscriptionIfNeeded()
    }

    // MARK: - Custom Display Names

    func displayName(for type: WorkflowType) -> String {
        switch type {
        case .textImprover:
            let name = textImprovementSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        case .dampfAblassen:
            let name = dampfAblassenSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        case .emojiText:
            let name = emojiTextSettings.customName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? type.displayName : name
        default:
            return type.displayName
        }
    }

    func workflowSubtitle(for type: WorkflowType) -> String {
        switch type {
        case .transcription:
            if appSettings.secureLocalModeEnabled {
                let modelName = selectedLocalModelName
                return LocalTranscriptionService.isModelInstalled(modelName)
                    ? "Lokal: \(LocalTranscriptionModel.displayName(for: modelName))."
                    : "Lokales WhisperKit-Modell fehlt."
            }
            return "Online: Whisper über OpenAI."
        case .localTranscription:
            return "Nur lokal. Kein Server."
        case .textImprover, .dampfAblassen, .emojiText:
            if appSettings.secureLocalModeEnabled {
                return "Im lokalen Modus pausiert."
            }
            return type.subtitle
        }
    }

    var resolvedLocalModelName: String {
        LocalTranscriptionService.resolvedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelDisplayName: String {
        LocalTranscriptionModel.displayName(for: selectedLocalModelName)
    }

    var selectedLocalModelName: String {
        LocalTranscriptionService.normalizedModelName(appSettings.selectedLocalTranscriptionModelName)
    }

    var selectedLocalModelIsInstalled: Bool {
        LocalTranscriptionService.isModelInstalled(selectedLocalModelName)
    }

    var isDownloadingLocalModel: Bool {
        localModelDownloadProgress != nil
    }

    var localModelDownloadButtonTitle: String {
        selectedLocalModelIsInstalled
            ? "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) ist installiert"
            : "\(LocalTranscriptionModel.displayName(for: selectedLocalModelName)) installieren"
    }

    // MARK: - Workflow Management

    func startWorkflow(_ type: WorkflowType, source: WorkflowLaunchSource = .manual) {
        guard isWorkflowAvailable(type) else {
            if source == .manual {
                page = .settings
            }
            return
        }

        activeWorkflow?.stop()
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        activeLaunchSource = source
        activePasteTarget = capturePasteTarget(for: source)

        switch type {
        case .transcription:
            let workflow = TranscriptionWorkflow(
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: appSettings.secureLocalModeEnabled ? .local : .remote,
                localModelName: selectedLocalModelName
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .localTranscription:
            let workflow = TranscriptionWorkflow(
                type: .localTranscription,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language,
                backend: .local,
                localModelName: selectedLocalModelName
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .textImprover:
            let workflow = TextImprovementWorkflow(
                settings: textImprovementSettings,
                language: transcriptionSettings.language
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .dampfAblassen:
            let workflow = DampfAblassenWorkflow(
                settings: dampfAblassenSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()

        case .emojiText:
            let workflow = EmojiTextWorkflow(
                settings: emojiTextSettings,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language
            )
            configureWorkflowHandlers(workflow)
            activeWorkflow = workflow
            workflow.start()
        }

        page = source.presentsWorkflowPage ? .workflow : .main
    }

    func isWorkflowAvailable(_ type: WorkflowType) -> Bool {
        switch type {
        case .localTranscription:
            return selectedLocalModelIsInstalled
        case .transcription:
            return appSettings.secureLocalModeEnabled
                ? selectedLocalModelIsInstalled
                : KeychainService.isConfigured
        case .textImprover, .dampfAblassen, .emojiText:
            return !appSettings.secureLocalModeEnabled && KeychainService.isConfigured
        }
    }

    func stopCurrentWorkflow() {
        activeWorkflow?.stop()
    }

    func resetCurrentWorkflow() {
        activeWorkflow?.reset()
        activeWorkflow = nil
        activePasteTarget = nil
        activeLaunchSource = .manual
        menuBarStatusResetTask?.cancel()
        workflowCleanupTask?.cancel()
        menuBarStatus = .idle
        page = .main
    }

    // MARK: - Datei-Transkription (MVP)

    /// Öffnet einen Datei-Dialog und startet die Transkription der gewählten Audiodatei.
    func presentFileTranscription() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = "Transkribieren"
        panel.message = "Audio- oder Videodatei zum Transkribieren auswählen (Video erzeugt zusätzlich .srt-Untertitel)"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startFileTranscription(url: url)
    }

    /// Einstieg aus dem Finder ("Öffnen mit → Blitztext"). Transkribiert die
    /// Datei(en) nacheinander und legt je eine .txt neben das Original.
    func handleOpenedAudioFiles(_ urls: [URL]) {
        let mediaURLs = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .audio) || type.conforms(to: .movie)
        }
        guard !mediaURLs.isEmpty else { return }
        enqueueFileTranscriptions(mediaURLs.map { FileTranscriptionJob(url: $0, writeTextFile: true) })
    }

    /// Transkribiert eine über den Datei-Dialog gewählte Audiodatei (Ergebnis im Popover).
    func startFileTranscription(url: URL, writeTextFileOnFinish: Bool = false) {
        enqueueFileTranscriptions([FileTranscriptionJob(url: url, writeTextFile: writeTextFileOnFinish)])
    }

    /// Hängt Aufträge an die Warteschlange an und startet die Abarbeitung.
    /// Robust gegen jede Auslieferungsart von macOS (Sammel- oder Einzelaufrufe):
    /// neue Dateien brechen die laufende Transkription nicht ab, sondern reihen sich an.
    private func enqueueFileTranscriptions(_ jobs: [FileTranscriptionJob]) {
        guard !jobs.isEmpty else { return }
        fileTranscriptionQueue.append(contentsOf: jobs)
        page = .fileTranscription
        if !isProcessingFileTranscriptionQueue, let first = fileTranscriptionQueue.first {
            fileTranscriptionState = .running(fileName: first.url.lastPathComponent, progress: nil)
        }
        processFileTranscriptionQueue()
    }

    private func processFileTranscriptionQueue() {
        guard !isProcessingFileTranscriptionQueue else { return }
        isProcessingFileTranscriptionQueue = true

        fileTranscriptionTask = Task(priority: .userInitiated) {
            defer { isProcessingFileTranscriptionQueue = false }

            if let availabilityError = fileTranscriptionAvailabilityError() {
                fileTranscriptionQueue.removeAll()
                fileTranscriptionState = .failed(availabilityError)
                return
            }

            var succeeded = 0
            var failures: [String] = []

            while !fileTranscriptionQueue.isEmpty {
                if Task.isCancelled { return }
                let job = fileTranscriptionQueue.removeFirst()
                lastTranscriptionSourceURL = job.url

                let remaining = fileTranscriptionQueue.count
                let label = remaining > 0
                    ? "\(job.url.lastPathComponent) (noch \(remaining))"
                    : job.url.lastPathComponent
                currentFileTranscriptionLabel = label
                fileTranscriptionState = .running(fileName: label, progress: nil)

                do {
                    let result = try await transcribeAudioFile(at: job.url, reportProgress: true)
                    guard !result.text.isEmpty else {
                        failures.append("\(job.url.lastPathComponent): keine Sprache erkannt")
                        continue
                    }
                    if job.writeTextFile {
                        if let txt = writeOutputFile(result.text, forSource: job.url, ext: "txt") {
                            fileTranscriptionWrittenOutputs.append(txt)
                        }
                        // Untertitel mit Timestamps, sofern Segmente vorliegen (lokaler Modus).
                        if !result.cues.isEmpty,
                           let srt = writeOutputFile(SubtitleFormatter.srt(from: result.cues), forSource: job.url, ext: "srt") {
                            fileTranscriptionWrittenOutputs.append(srt)
                        }
                    }
                    succeeded += 1
                    fileTranscriptionState = .done(
                        text: result.text,
                        fileName: job.url.lastPathComponent,
                        savedToFile: job.writeTextFile
                    )
                } catch is CancellationError {
                    return
                } catch {
                    failures.append("\(job.url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            // Am Ende alle geschriebenen Dateien gesammelt im Finder zeigen.
            if !fileTranscriptionWrittenOutputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(fileTranscriptionWrittenOutputs)
                fileTranscriptionWrittenOutputs.removeAll()
            }

            // Fehler im Stapel sichtbar machen (statt sie hinter der letzten Datei zu verstecken).
            if let summary = TranscriptionBatchSummary.text(succeeded: succeeded, failures: failures) {
                fileTranscriptionState = succeeded == 0
                    ? .failed(summary)
                    : .done(text: summary, fileName: "Stapel-Bilanz", savedToFile: true)
            }
        }
    }

    /// Speichert das aktuell gezeigte Transkript als .txt neben der Quelldatei (In-App-Button).
    func saveTranscriptAsTextFile() {
        guard case let .done(text, _, _) = fileTranscriptionState,
              let source = lastTranscriptionSourceURL,
              let output = writeOutputFile(text, forSource: source, ext: "txt") else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }

    func resetFileTranscription() {
        fileTranscriptionTask?.cancel()
        fileTranscriptionTask = nil
        fileTranscriptionQueue.removeAll()
        fileTranscriptionWrittenOutputs.removeAll()
        isProcessingFileTranscriptionQueue = false
        fileTranscriptionState = .idle
        page = .main
    }

    /// Prüft, ob das aktuell gewählte Backend einsatzbereit ist.
    private func fileTranscriptionAvailabilityError() -> String? {
        if appSettings.secureLocalModeEnabled {
            return selectedLocalModelIsInstalled
                ? nil
                : "Kein lokales Modell installiert. Lade im Menü ein Modell oder schalte den lokalen Modus aus."
        }
        return KeychainService.isConfigured
            ? nil
            : "Kein OpenAI API Key hinterlegt. Trage ihn in den Einstellungen ein oder aktiviere den lokalen Modus."
    }

    /// Transkribiert eine Datei und liefert Text + Untertitel-Cues (Timestamps).
    /// Videos: erst Tonspur extrahieren (WhisperKit liest kein Video).
    /// Audio: auf Kopie arbeiten (Online-Pfad löscht die Eingabedatei).
    private func transcribeAudioFile(
        at url: URL,
        reportProgress: Bool = false
    ) async throws -> (text: String, cues: [SubtitleCue]) {
        let audioURL: URL
        if VideoAudioExtractor.isVideo(url) {
            fileTranscriptionState = .running(
                fileName: "\(currentFileTranscriptionLabel) – Tonspur wird extrahiert …",
                progress: nil
            )
            audioURL = try await VideoAudioExtractor.extractAudioToTemporaryFile(from: url)
        } else {
            let fileExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("blitztext-import-\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: url, to: tempURL)
            audioURL = tempURL
        }
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let text: String
        var cues: [SubtitleCue] = []
        if appSettings.secureLocalModeEnabled {
            // Fortschritt nebenläufig pollen (nur lokal — Online liefert keinen).
            let progressPoll: Task<Void, Never>? = reportProgress ? Task { @MainActor in
                while !Task.isCancelled {
                    let fraction = await LocalTranscriptionService.shared.currentProgressFraction()
                    applyFileTranscriptionProgress(fraction)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            } : nil
            defer { progressPoll?.cancel() }

            let result = try await LocalTranscriptionService.shared.transcribeWithSegments(
                audioURL: audioURL,
                language: transcriptionSettings.language,
                modelName: selectedLocalModelName
            )
            text = result.text
            cues = result.segments
                .map { (start: $0.start, end: $0.end, text: SubtitleFormatter.strippingTokens($0.text)) }
                .filter { !$0.text.isEmpty && $0.end > $0.start }
                .map { SubtitleCue(start: $0.start, end: $0.end, text: $0.text) }
        } else {
            text = try await TranscriptionService.transcribe(
                audioURL: audioURL,
                customTerms: textImprovementSettings.customTerms,
                language: transcriptionSettings.language
            )
        }
        return (TranscriptionQualityService.cleanedTranscript(text), cues)
    }

    /// Aktualisiert die Fortschrittsanzeige während der laufenden Datei-Transkription.
    private func applyFileTranscriptionProgress(_ fraction: Double) {
        guard case .running = fileTranscriptionState else { return }
        fileTranscriptionState = .running(
            fileName: currentFileTranscriptionLabel,
            progress: fraction > 0.001 ? min(fraction, 1.0) : nil
        )
    }

    /// Schreibt Inhalt als Datei mit gegebener Endung neben das Original;
    /// Fallback ~/Downloads. Überschreibt nichts — hängt bei Bedarf -1, -2 … an.
    @discardableResult
    private func writeOutputFile(_ content: String, forSource sourceURL: URL, ext: String) -> URL? {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }

        func uniqueURL(in directory: URL) -> URL {
            TranscriptFileNaming.uniqueURL(forBase: base, ext: ext, in: directory, fileExists: exists)
        }

        let primaryTarget = uniqueURL(in: sourceURL.deletingLastPathComponent())
        if (try? content.write(to: primaryTarget, atomically: true, encoding: .utf8)) != nil {
            return primaryTarget
        }

        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let fallback = uniqueURL(in: downloads)
            if (try? content.write(to: fallback, atomically: true, encoding: .utf8)) != nil {
                return fallback
            }
        }
        return nil
    }

    func enableSecureLocalMode() {
        appSettings.secureLocalModeEnabled = true
        if !selectedLocalModelIsInstalled {
            installSelectedLocalModel()
        }
    }

    func installSelectedLocalModel() {
        guard !isDownloadingLocalModel else { return }

        let modelName = selectedLocalModelName
        localModelDownloadProgress = 0
        localModelDownloadStatusText = "Download startet..."
        localModelDownloadErrorText = nil

        Task {
            do {
                let installedURL = try await LocalTranscriptionService.shared.downloadAndInstall(
                    modelName: modelName
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let clampedProgress = min(max(progress, 0), 1)
                        self.localModelDownloadProgress = clampedProgress
                        self.localModelDownloadStatusText = "Download \(Int(clampedProgress * 100)) %"
                    }
                }

                appSettings.selectedLocalTranscriptionModelName = installedURL.lastPathComponent
                appSettings.secureLocalModeEnabled = true
                localModelDownloadProgress = nil
                localModelDownloadStatusText = "\(LocalTranscriptionModel.displayName(for: modelName)) ist installiert."
                localModelDownloadErrorText = nil

                try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
            } catch {
                localModelDownloadProgress = nil
                localModelDownloadStatusText = nil
                localModelDownloadErrorText = error.localizedDescription
            }
        }
    }

    func copyToClipboard(_ text: String) {
        writeSensitiveTextToPasteboard(text)
    }

    // MARK: - Auto-Paste

    /// Copies the text, restores focus when needed, then simulates Cmd+V.
    /// The text intentionally remains on the clipboard as a fallback if paste is blocked.
    private func pasteAtCursor(_ text: String, target: PasteTarget? = nil) {
        writeSensitiveTextToPasteboard(text)

        if isPopoverShown {
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
        }

        let trusted = AccessibilityPermissionService.isTrusted(promptIfNeeded: true)
        accessibilityPermissionGranted = trusted
        guard trusted else {
            menuBarStatus = .error(activeWorkflow?.type)
            return
        }

        attemptPasteTrusted(
            target: target,
            attemptsRemaining: Self.pasteRetryInitialAttempts
        )
    }

    private func writeSensitiveTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Vorherigen Zwischenablage-Inhalt sichern, um ihn nach erfolgreichem
        // Einfügen wiederherzustellen (sonst geht die Nutzer-Zwischenablage verloren).
        pasteboardRestoreItems = snapshotPasteboardItems(pasteboard)

        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.concealedPasteboardType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: Self.concealedPasteboardType)
        pasteboardRestoreChangeCount = pasteboard.changeCount
    }

    /// Tiefe Kopie aller Zwischenablage-Einträge (alle Typen), damit sie nach
    /// dem Einfügen unverändert zurückgeschrieben werden können.
    private func snapshotPasteboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    /// Stellt die gesicherte Zwischenablage wieder her — aber nur, wenn das
    /// Einfügen wirklich lief und der Nutzer seither nichts Neues kopiert hat.
    private func scheduleClipboardRestore() {
        guard let items = pasteboardRestoreItems,
              let expectedChangeCount = pasteboardRestoreChangeCount else {
            return
        }
        // Snapshot konsumieren, damit Retries ihn nicht mehrfach auslösen.
        pasteboardRestoreItems = nil
        pasteboardRestoreChangeCount = nil

        // Kurz warten, bis die Ziel-App das Transkript per Cmd+V übernommen hat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let pasteboard = NSPasteboard.general
            // Nur wiederherstellen, wenn seit dem Transkript nichts kopiert wurde.
            guard pasteboard.changeCount == expectedChangeCount else { return }
            pasteboard.clearContents()
            if !items.isEmpty {
                pasteboard.writeObjects(items)
            }
        }
    }

    func prepareForPopoverPresentation() {
        lastPopoverPasteTarget = captureCurrentFrontmostApp()

        let onTransientPage = page == .workflow || page == .onboarding || page == .fileTranscription
        let destination = PopoverRouter.destinationOnPresent(
            workflowActive: activeWorkflow?.phase.isActive ?? false,
            fileTranscriptionActive: fileTranscriptionState != .idle,
            shouldShowOnboarding: shouldShowOnboarding,
            onTransientPage: onTransientPage
        )

        switch destination {
        case .workflow:
            page = .workflow
        case .fileTranscription:
            page = .fileTranscription
        case .onboarding:
            page = .onboarding
            markOnboardingSeen()
        case .main:
            page = .main
        case .unchanged:
            break
        }
    }

    func markOnboardingSeen() {
        guard !appSettings.hasSeenOnboarding else { return }
        appSettings.hasSeenOnboarding = true
    }

    // MARK: - API Key Status

    func apiKeyDisplayValue(for key: KeychainKey) -> String {
        guard let value = KeychainService.load(key: key), !value.isEmpty else {
            return ""
        }
        if value.count > 8 {
            return String(value.prefix(4)) + " \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
        }
        return "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"
    }

    func hasValue(for key: KeychainKey) -> Bool {
        guard let value = KeychainService.load(key: key) else { return false }
        return !value.isEmpty
    }

    // MARK: - Settings Persistence

    private static let settingsURL: URL = {
        try? AppSupportPaths.ensureAppSupportDirectoryExists()
        return AppSupportPaths.settingsURL
    }()

    private func saveSettings() {
        let container = SettingsContainer(
            app: appSettings,
            transcription: transcriptionSettings,
            textImprovement: textImprovementSettings,
            dampfAblassen: dampfAblassenSettings,
            emojiText: emojiTextSettings
        )
        if let data = try? JSONEncoder().encode(container) {
            try? data.write(to: Self.settingsURL)
        }
    }

    private static func loadAppSettings() -> AppSettings {
        loadContainer()?.app ?? AppSettings()
    }

    private static func loadTranscriptionSettings() -> TranscriptionSettings {
        loadContainer()?.transcription ?? TranscriptionSettings()
    }

    private static func loadTextImprovementSettings() -> TextImprovementSettings {
        loadContainer()?.textImprovement ?? TextImprovementSettings()
    }

    private static func loadDampfAblassenSettings() -> DampfAblassenSettings {
        loadContainer()?.dampfAblassen ?? DampfAblassenSettings()
    }

    private static func loadEmojiTextSettings() -> EmojiTextSettings {
        loadContainer()?.emojiText ?? EmojiTextSettings()
    }

    private static func loadContainer() -> SettingsContainer? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(SettingsContainer.self, from: data)
    }

    func refreshAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.currentStatus()
    }

    func requestAccessibilityPermission() {
        accessibilityPermissionGranted = AccessibilityPermissionService.requestPermissionPrompt()
        AccessibilityPermissionService.openSystemSettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refreshAccessibilityPermission()
        }
    }

    private func autoSelectFastLocalModelIfNeeded() {
        guard !appSettings.hasAutoSelectedFastLocalModel,
              LocalTranscriptionService.shouldAutoSelectRecommendedFastModel(
                currentModelName: appSettings.selectedLocalTranscriptionModelName
              ) else {
            return
        }

        appSettings.selectedLocalTranscriptionModelName = LocalTranscriptionService.recommendedFastModelName
        appSettings.hasAutoSelectedFastLocalModel = true
    }

    private func prewarmLocalTranscriptionIfNeeded() {
        guard appSettings.secureLocalModeEnabled,
              LocalTranscriptionService.isModelInstalled(resolvedLocalModelName) else {
            return
        }

        let modelName = resolvedLocalModelName
        Task.detached(priority: .utility) {
            try? await LocalTranscriptionService.shared.prepare(modelName: modelName)
        }
    }

    private func handleWorkflowOutput(_ text: String) {
        pasteAtCursor(text, target: activePasteTarget)
        if activeLaunchSource == .hotkeyBackground {
            page = .main
        }
        scheduleWorkflowCleanup(after: 1.05)
    }

    private func configureWorkflowHandlers<T: Workflow>(_ workflow: T) {
        workflow.onOutput = { [weak self] text in
            self?.handleWorkflowOutput(text)
        }
        workflow.onPhaseChange = { [weak self, weak workflow] phase in
            guard let self, let workflow else { return }
            self.handleWorkflowPhaseChange(phase, workflow: workflow)
        }
    }

    private func handleWorkflowPhaseChange(_ phase: WorkflowPhase, workflow: any Workflow) {
        menuBarStatusResetTask?.cancel()

        switch phase {
        case .idle:
            if activeWorkflow == nil {
                menuBarStatus = .idle
            }

        case .running:
            menuBarStatus = workflow.isRecording
                ? .recording(workflow.type)
                : .processing(workflow.type)

        case .done:
            menuBarStatus = .success(workflow.type)

        case .error:
            menuBarStatus = .error(workflow.type)
            if activeLaunchSource == .hotkeyBackground {
                activeWorkflow = nil
                activePasteTarget = nil
                page = .main
            }
            scheduleMenuBarStatusReset(after: 1.6)
        }
    }

    private func scheduleWorkflowCleanup(after delay: TimeInterval) {
        guard let workflow = activeWorkflow else { return }

        workflowCleanupTask?.cancel()
        let workflowID = ObjectIdentifier(workflow)

        workflowCleanupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, let activeWorkflow = self.activeWorkflow else { return }
            guard ObjectIdentifier(activeWorkflow) == workflowID else { return }

            activeWorkflow.reset()
            self.activeWorkflow = nil
            self.activePasteTarget = nil
            self.activeLaunchSource = .manual
            if !self.isPopoverShown {
                self.page = .main
            }
            self.menuBarStatus = .idle
        }
    }

    private func scheduleMenuBarStatusReset(after delay: TimeInterval) {
        menuBarStatusResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            if self.activeWorkflow == nil || !(self.activeWorkflow?.phase.isActive ?? false) {
                self.menuBarStatus = .idle
            }
        }
    }

    private func capturePasteTarget(for source: WorkflowLaunchSource) -> PasteTarget? {
        switch source {
        case .manual:
            return lastPopoverPasteTarget
        case .hotkeyBackground:
            return captureCurrentFrontmostApp()
        }
    }

    private func attemptPasteTrusted(
        target: PasteTarget?,
        attemptsRemaining: Int
    ) {
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if let target {
            if frontmostPid == target.processIdentifier {
                performPaste()
                return
            }

            target.application.activate(options: [])
        } else {
            return
        }

        guard attemptsRemaining > 0 else {
            return
        }

        let delay: TimeInterval
        switch attemptsRemaining {
        case 16...:
            delay = 0.015
        case 8...15:
            delay = 0.025
        default:
            delay = 0.04
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attemptPasteTrusted(
                target: target,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private func performPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Einfügen lief — vorherige Zwischenablage wiederherstellen.
        scheduleClipboardRestore()
    }

    private func captureCurrentFrontmostApp() -> PasteTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let ownPid = NSRunningApplication.current.processIdentifier
        guard app.processIdentifier != ownPid else { return nil }

        return PasteTarget(
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            application: app
        )
    }
}

private struct SettingsContainer: Codable {
    var app: AppSettings?
    var transcription: TranscriptionSettings
    var textImprovement: TextImprovementSettings
    var dampfAblassen: DampfAblassenSettings?
    var emojiText: EmojiTextSettings?
}

// MARK: - Notification for Popover Dismissal

extension Notification.Name {
    static let dismissPopover = Notification.Name("dismissPopover")
}

private struct PasteTarget {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let application: NSRunningApplication
}
