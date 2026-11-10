import SwiftUI
import BlitztextCore

struct MenuBarView: View {
    @Bindable var appState: AppState

    static let width: CGFloat = 380

    /// Damit die Versionszeile beim Überfahren erkennbar wird — sonst sieht
    /// niemand, dass sie anklickbar ist.
    @State private var isVersionHovered = false
    @State private var copiedLast = false

    var body: some View {
        VStack(spacing: 0) {
            switch appState.page {
            case .main:
                mainPage
            case .onboarding:
                onboardingPage
            case .settings:
                settingsPage
            case .workflow:
                workflowPage
            case .fileTranscription:
                fileTranscriptionPage
            case .improverTextBox:
                improverTextBoxPage
            case .history:
                historyPage
            }
        }
        .frame(width: Self.width)
        .background(BlitztextTheme.page)
        .tint(BlitztextTheme.accent)
        .animation(.easeInOut(duration: 0.2), value: appState.page)
    }

    // MARK: - Main Page

    /// Aufbau von oben nach unten: Marke, Hinweise nur wenn nötig, die eine
    /// Kern-Geste (Diktat), die Modi als ruhige Liste, das letzte Ergebnis.
    /// Technik (Modell, Schlüssel, Kürzel) wohnt in den Einstellungen.
    private var mainPage: some View {
        VStack(spacing: 0) {
            miniHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 14) {
                if !appState.isConfigured {
                    setupHero
                }

                if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                    NoticeRow(
                        icon: "externaldrive.badge.plus",
                        title: "Nach /Applications verschieben",
                        detail: "So startet Blitztext zuverl\u{00E4}ssig mit dem Mac und bekommt saubere Updates.",
                        tint: BlitztextTheme.warning,
                        actionTitle: "Pr\u{00FC}fen",
                        action: { appState.page = .settings }
                    )
                }

                if !appState.accessibilityPermissionGranted {
                    NoticeRow(
                        icon: "hand.raised.fill",
                        title: "Einf\u{00FC}gen braucht Bedienungshilfen",
                        detail: "Nach Updates kann macOS die Freigabe neu verlangen.",
                        actionTitle: "\u{00D6}ffnen",
                        action: { appState.requestAccessibilityPermission() }
                    )
                }

                if appState.isConfigured {
                    dictationCard
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Modi")
                    modeList
                        .card()
                }

                if appState.appSettings.historyLimit > 0, let entry = appState.transcriptHistory.first {
                    lastMessage(entry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            appFooter
        }
    }

    private var miniHeader: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            Text("Blitztext")
                .font(.ui(15, .bold))

            Spacer(minLength: 0)

            Button {
                appState.page = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.ui(13))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(BlitztextTheme.card))
                    .shadow(color: BlitztextTheme.cardShadow, radius: 2, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("Einstellungen")
            .accessibilityLabel("Einstellungen")
        }
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Einrichtung n\u{00F6}tig")
                .font(.ui(16, .bold))
            Text("Lade ein lokales Sprachmodell oder hinterlege deinen OpenAI API Key. Danach sprechen und einf\u{00FC}gen.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                appState.page = .settings
            } label: {
                Label("Einrichten", systemImage: "checklist")
            }
            .buttonStyle(.filledAction)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Diktat

    /// Der Diktat-Workflow, den das Hauptkürzel gerade auslöst.
    private var dictationType: WorkflowType { .transcription }

    /// Die Kern-Geste in einem Satz, dazu wo transkribiert wird.
    private var dictationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    appState.startWorkflow(dictationType)
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.ui(20, .semibold))
                        .foregroundStyle(BlitztextTheme.onAccent)
                        .frame(width: 52, height: 52)
                        .background(SpeechBubbleShape().fill(BlitztextTheme.accent))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!appState.isWorkflowAvailable(dictationType))
                .help("Diktat jetzt starten")
                .accessibilityLabel("Aufnahme starten")

                VStack(alignment: .leading, spacing: 3) {
                    Text(dictationTitle)
                        .font(.ui(14, .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Der Text landet direkt am Cursor.")
                        .font(.ui(11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("Lokal auf diesem Mac")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Toggle("", isOn: Binding(
                    get: { appState.appSettings.secureLocalModeEnabled },
                    set: { newValue in
                        if newValue {
                            appState.enableSecureLocalMode()
                        } else {
                            appState.appSettings.secureLocalModeEnabled = false
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(appState.isDownloadingLocalModel)
            }

            if let progress = appState.localModelDownloadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                    Text(appState.localModelDownloadStatusText ?? "Modell wird geladen \u{2026}")
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText = appState.localModelDownloadErrorText {
                NoticeRow(icon: "xmark.circle.fill", title: errorText, tint: BlitztextTheme.danger)
            }

            Button {
                appState.page = .settings
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.ui(10.5, .semibold))
                        .foregroundStyle(statusTint)
                        .padding(.top, 1.5)
                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.ui(11.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Modell und Zugang in den Einstellungen verwalten")
        }
        .padding(16)
        .card()
    }

    private var dictationTitle: String {
        guard let hotkey = appState.hotkeyLabel(for: dictationType) else {
            return "Mikrofon antippen und sprechen"
        }
        switch appState.appSettings.hotkeyMode {
        case .hold: return "\(hotkey) halten und sprechen"
        case .toggle: return "\(hotkey) dr\u{00FC}cken und sprechen"
        }
    }

    private var statusNeedsAttention: Bool {
        appState.appSettings.secureLocalModeEnabled
            && !appState.selectedLocalModelIsInstalled
            && !appState.isDownloadingLocalModel
    }

    private var statusIcon: String {
        if statusNeedsAttention { return "exclamationmark.triangle.fill" }
        return appState.appSettings.secureLocalModeEnabled ? "lock.fill" : "network"
    }

    private var statusTint: Color {
        if statusNeedsAttention { return BlitztextTheme.warning }
        return appState.appSettings.secureLocalModeEnabled ? BlitztextTheme.ready : BlitztextTheme.accent
    }

    /// Ehrlicher Geltungsbereich: was bleibt auf dem Mac, was geht raus?
    private var statusText: String {
        guard appState.appSettings.secureLocalModeEnabled else {
            return "Sprache und Modi laufen online \u{00FC}ber OpenAI."
        }
        if appState.isDownloadingLocalModel {
            return appState.localModelDownloadStatusText ?? "Modell wird geladen \u{2026}"
        }
        if !appState.selectedLocalModelIsInstalled {
            return "\(appState.selectedLocalModelDisplayName) fehlt noch. In den Einstellungen laden."
        }
        if appState.improverRewriteIsLocal {
            return "\(appState.selectedLocalModelDisplayName). Sprache und Modi bleiben auf diesem Mac."
        }
        if appState.improverBoxAvailable {
            return "\(appState.selectedLocalModelDisplayName). Sprache bleibt auf diesem Mac, Modi senden an OpenAI."
        }
        return "\(appState.selectedLocalModelDisplayName). Sprache bleibt auf diesem Mac."
    }

    // MARK: Modi

    /// Der Diktat-Workflow steht schon groß oben; die Liste zeigt die Umformer.
    private var listedModes: [WorkflowType] {
        WorkflowType.mainMenuCases.filter { $0 != dictationType }
    }

    private var modeList: some View {
        let modes = listedModes
        return VStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element) { index, type in
                if index > 0 {
                    Divider().opacity(0.5).padding(.leading, 62).padding(.trailing, 12)
                }
                let enabled = isImprover(type)
                    ? appState.improverBoxAvailable
                    : appState.isWorkflowAvailable(type)
                WorkflowRowView(
                    type: type,
                    enabled: enabled,
                    customName: appState.displayName(for: type),
                    // Untertitel nur, wenn es ein Problem zu erklären gibt —
                    // im Normalzustand bleiben die Zeilen ruhig.
                    subtitle: enabled ? nil : appState.workflowSubtitle(for: type),
                    sendsOnline: enabled && rowSendsOnline(type),
                    hotkeyLabel: appState.hotkeyLabel(for: type)
                ) {
                    if isImprover(type) {
                        appState.openImproverBox(type: type)
                    } else {
                        appState.startWorkflow(type)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func isImprover(_ type: WorkflowType) -> Bool {
        type == .textImprover || type == .dampfAblassen || type == .emojiText
    }

    /// Nur Abweichungen markieren: Im lokalen Modus fällt auf, wenn ein Modus
    /// doch ins Netz geht. Im Online-Modus gilt das ohnehin für alles.
    private func rowSendsOnline(_ type: WorkflowType) -> Bool {
        guard appState.appSettings.secureLocalModeEnabled else { return false }
        switch type {
        case .textImprover, .dampfAblassen, .emojiText:
            return !appState.improverRewriteIsLocal
        case .transcription, .localTranscription:
            return false
        }
    }

    // MARK: Letztes Ergebnis

    /// Das letzte Ergebnis als gesendete Nachricht. Ein Klick kopiert es,
    /// eine Sprachnachricht öffnet ihr Ergebnisfenster.
    private func lastMessage(_ entry: TranscriptHistoryEntry) -> some View {
        let isVoiceMessage = entry.tapAction == .openVoiceMessage
        return VStack(alignment: .trailing, spacing: 5) {
            Button {
                switch entry.tapAction {
                case .openVoiceMessage:
                    appState.openVoiceMessageFromHistory(entry)
                case .copyText:
                    appState.copyHistoryEntry(entry)
                    withAnimation(.easeOut(duration: 0.15)) { copiedLast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(.easeOut(duration: 0.15)) { copiedLast = false }
                    }
                }
            } label: {
                Text(entry.text)
                    .font(.ui(12.5))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16, bottomLeadingRadius: 16,
                            bottomTrailingRadius: 4, topTrailingRadius: 16,
                            style: .continuous
                        )
                        .fill(BlitztextTheme.accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help(isVoiceMessage ? "Sprachnachricht \u{00F6}ffnen" : "Kopieren")
            .accessibilityLabel("Letzter Text: \(entry.text)")

            Group {
                if copiedLast {
                    Label("Kopiert", systemImage: "checkmark")
                        .foregroundStyle(BlitztextTheme.ready)
                } else {
                    Label(
                        "\(isVoiceMessage ? "Sprachnachricht" : appState.displayName(for: entry.type)), \(Self.relativeTime(entry.date))",
                        systemImage: isVoiceMessage ? "waveform" : "doc.on.doc"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .font(.ui(11))
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 40)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .full
        return formatter
    }()

    static func relativeTime(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "gerade eben" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - History Page

    private var historyPage: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Verlauf", onBack: { appState.page = .main }) {
                if !appState.transcriptHistory.isEmpty {
                    Button("Leeren") {
                        appState.clearHistory()
                        appState.page = .main
                    }
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .buttonStyle(SubtleButtonStyle())
                }
            }

            ScrollView {
                HistorySection(appState: appState)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - File Transcription Page

    private var fileTranscriptionPage: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Sprachnachricht",
                icon: "waveform",
                iconTint: BlitztextTheme.accent,
                onBack: { appState.resetFileTranscription() }
            )

            FileTranscriptionContentView(appState: appState)

            Spacer(minLength: 0)

            appFooter
        }
    }

    private var improverTextBoxPage: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: appState.displayName(for: appState.improverType),
                icon: appState.improverType.icon,
                iconTint: appState.improverType.color,
                onBack: { appState.resetImproverBox() }
            )

            ImproverTextBoxContent(appState: appState)

            Spacer(minLength: 0)

            appFooter
        }
    }

    // MARK: - Onboarding

    private var onboardingPage: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Willkommen bei Blitztext")
                    .font(.ui(14, .semibold))

                Spacer()

                Button("Sp\u{00E4}ter") {
                    appState.page = .main
                }
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .buttonStyle(SubtleButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Einmal einrichten, dann direkt loslegen.")
                        .font(.ui(14, .semibold))
                    Text("Lokales Sprachmodell laden oder eigenen OpenAI API Key eintragen. Danach sprechen und einf\u{00FC}gen.")
                        .font(.ui(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                    NoticeRow(
                        icon: "arrow.down.app",
                        title: "Lege Blitztext zuerst nach /Applications.",
                        detail: "Das h\u{00E4}lt Anmeldestart, Updates und das Entfernen sauber auf einer App-Kopie.",
                        tint: BlitztextTheme.warning
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    onboardingStep(number: "1", title: "Sprachmodell oder Key", detail: "In den Einstellungen ein lokales Modell laden oder deinen OpenAI API Key speichern.")
                    onboardingStep(number: "2", title: "Berechtigungen erlauben", detail: "Mikrofon und Bedienungshilfen f\u{00FC}r das Einf\u{00FC}gen freigeben.")
                    onboardingStep(number: "3", title: "Kürzel halten und sprechen", detail: "Der Text landet direkt im aktiven Textfeld.")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                Button {
                    appState.page = .settings
                } label: {
                    Label("Jetzt einrichten", systemImage: "checklist")
                }
                .buttonStyle(.filledAction)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Spacer(minLength: 0)

            appFooter
        }
    }

    private func onboardingStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.ui(11, .semibold))
                .foregroundStyle(BlitztextTheme.onTonal)
                .frame(width: 20, height: 20)
                .background(Circle().fill(BlitztextTheme.tonal))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ui(12, .semibold))
                Text(detail)
                    .font(.ui(11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Settings Page

    private var settingsPage: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Einstellungen", onBack: { appState.page = .main }) {
                settingsQuickAction
            }

            Divider().opacity(0.5)

            SettingsContentView(appState: appState)

            Spacer(minLength: 0)

            appFooter
        }
    }

    @ViewBuilder
    private var settingsQuickAction: some View {
        if !appState.accessibilityPermissionGranted {
            Button {
                appState.requestAccessibilityPermission()
            } label: {
                Label("Rechte", systemImage: "hand.raised")
            }
            .buttonStyle(.tonalAction)
        }
    }

    // MARK: - Workflow Page

    private var workflowPage: some View {
        VStack(spacing: 0) {
            if let workflow = appState.activeWorkflow {
                PageHeader(
                    title: appState.displayName(for: workflow.type),
                    icon: workflow.type.icon,
                    iconTint: workflow.type.color,
                    onBack: { appState.resetCurrentWorkflow() }
                )

                // Ein gemeinsamer Aufnahme-/Verarbeitungs-View für alle Workflows.
                WorkflowActiveView(workflow: workflow)

                Spacer(minLength: 0)

                appFooter
            }
        }
    }

    // MARK: - Footer

    private var appFooter: some View {
        HStack(spacing: 6) {
            // Führt zur Release-Übersicht, nicht auf die Repo-Startseite: Wer
            // auf die eigene Versionsnummer klickt, will wissen, ob es eine
            // neuere gibt — und was sich geändert hat.
            Link(destination: Self.releasesURL) {
                Text(appVersionLabel)
                    .font(.ui(11))
                    .foregroundStyle(isVersionHovered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .underline(isVersionHovered)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isVersionHovered = hovering
                }
            }
            .help("Alle Versionen und \u{00C4}nderungen auf GitHub ansehen")

            Spacer(minLength: 4)

            if appState.page == .main {
                if appState.isConfigured {
                    Button {
                        appState.presentFileTranscription()
                    } label: {
                        Label("Sprachnachricht", systemImage: "waveform.badge.plus")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.tonalAction)
                    .help("Sprachmemo, WhatsApp-Sprachnachricht oder Video transkribieren. Dateien gehen auch per Rechtsklick im Finder.")
                }

                if appState.appSettings.historyLimit > 0 && !appState.transcriptHistory.isEmpty {
                    Button {
                        appState.page = .history
                    } label: {
                        Label("Verlauf", systemImage: "clock")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.tonalAction)
                }
            }

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .font(.ui(12))
            .foregroundStyle(.secondary)
            .fixedSize()
            .buttonStyle(SubtleButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Divider().opacity(0.6)
        }
    }

    private static let releasesURL = URL(string: "https://github.com/immodigit/blitztext-app/releases")!

    private var appVersionLabel: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return "v\(version)"
        }
        return "Blitztext"
    }
}

// MARK: - History Section

/// Die letzten Ergebnisse. Ein Tippen kopiert den Text in die Zwischenablage —
/// Rettung, falls er ins falsche Feld ging; eine Sprachnachricht öffnet ihr
/// Ergebnisfenster.
struct HistorySection: View {
    @Bindable var appState: AppState
    @State private var copiedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(appState.transcriptHistory.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().opacity(0.5).padding(.leading, 40).padding(.trailing, 12)
                }
                row(for: entry)
            }
        }
        .padding(.vertical, 4)
        .card()
    }

    private func row(for entry: TranscriptHistoryEntry) -> some View {
        let isCopied = copiedID == entry.id
        let isVoiceMessage = entry.tapAction == .openVoiceMessage
        return Button {
            switch entry.tapAction {
            case .openVoiceMessage:
                appState.openVoiceMessageFromHistory(entry)
            case .copyText:
                appState.copyHistoryEntry(entry)
                withAnimation(.easeInOut(duration: 0.2)) { copiedID = entry.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isCopied ? "checkmark" : (isVoiceMessage ? "waveform" : entry.type.icon))
                    .font(.ui(11, .semibold))
                    .foregroundStyle(isCopied ? Color.green : (isVoiceMessage ? BlitztextTheme.accent : entry.type.color))
                    .frame(width: 18)
                    .padding(.top, 1)

                Text(entry.text)
                    .font(.ui(12))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(isCopied ? "Kopiert" : MenuBarView.relativeTime(entry.date))
                    .font(.ui(10.5))
                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.voiceMessage.map { "Sprachnachricht \u{00F6}ffnen: \($0.fileName)" } ?? "Kopieren")
    }
}

// MARK: - Workflow Active View (gemeinsam für alle Workflows)

/// Ein View für Aufnahme, Verarbeitung, Ergebnis und Fehler — identisches
/// Verhalten für alle Workflows, Wellenform in der jeweiligen Workflow-Farbe.
/// Ersetzt die vier zuvor kopierten, fast identischen ActiveViews.
struct WorkflowActiveView: View {
    let workflow: any Workflow

    var body: some View {
        VStack(spacing: 0) {
            switch workflow.phase {
            case .idle, .running:
                if workflow.isRecording {
                    recordingView
                } else {
                    processingStateView
                }

            case .done(let text):
                autoPasteView(text: text)

            case .error(let msg):
                errorView(message: msg) {
                    workflow.reset()
                    workflow.start()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var runningMessage: String {
        if case .running(let message) = workflow.phase, !message.isEmpty {
            return message
        }
        return "Wird verarbeitet \u{2026}"
    }

    private var recordingView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 20)

            WaveformView(
                audioLevel: workflow.audioLevel,
                isRecording: true,
                accentColor: workflow.type.color
            )
            .frame(height: 44)
            .padding(.horizontal, 24)

            // Monochromer Stopp-Knopf
            Button {
                workflow.stop()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.primary.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)

            Text("Ich h\u{00F6}re zu \u{2026} Klicke zum Stoppen.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 8)
        }
    }

    private var processingStateView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 24)
            ProgressView()
                .scaleEffect(0.7)
                .controlSize(.small)
            Text(runningMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 24)
        }
    }
}

// MARK: - Shared Result / Error Views

private func autoPasteView(text: String) -> some View {
    VStack(spacing: 12) {
        Spacer().frame(height: 20)

        ZStack {
            Circle()
                .fill(Color.green.opacity(0.1))
                .frame(width: 44, height: 44)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.green)
        }

        Text("Eingef\u{00FC}gt")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)

        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

        Spacer().frame(height: 12)
    }
}

// MARK: - File Transcription Content

struct ImproverTextBoxContent: View {
    @Bindable var appState: AppState
    @State private var copied = false

    private var isBusy: Bool {
        switch appState.improverBoxPhase {
        case .transcribing, .improving: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $appState.improverInputText)
                .font(.system(size: 12))
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                .overlay(alignment: .topLeading) {
                    if appState.improverInputText.isEmpty {
                        Text("Text eingeben — oder \u{201E}Diktieren\u{201C} antippen und sprechen.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(isBusy)

            HStack(spacing: 8) {
                Button {
                    appState.toggleImproverDictation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.improverIsRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(appState.improverIsRecording ? "Stopp" : "Diktieren")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(appState.improverIsRecording ? .red : .blue)
                }
                .buttonStyle(SubtleButtonStyle())
                .disabled(isBusy)

                Spacer()

                Button {
                    appState.improveImproverText()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10, weight: .bold))
                        Text("Umformen")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                }
                .buttonStyle(SubtleButtonStyle())
                .disabled(isBusy || appState.improverIsRecording
                    || appState.improverInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            switch appState.improverBoxPhase {
            case .recording:
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill").font(.system(size: 10)).foregroundStyle(.red)
                    Text("Aufnahme läuft – \u{201E}Stopp\u{201C} zum Beenden.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            case .transcribing:
                busyLine("Wird transkribiert \u{2026}")
            case .improving:
                busyLine("Text wird umgeformt \u{2026}")
            case .failed(let message):
                Text(message).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .result(let text):
                resultSection(text: text)
            case .idle:
                EmptyView()
            }

            Text(appState.improverRewriteIsLocal
                ? "Umformen läuft lokal auf dem Gerät — kein Netzwerk."
                : "\u{201E}Umformen\u{201C} sendet den Text an OpenAI. Das Diktieren bleibt im lokalen Modus auf dem Gerät.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func busyLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.6).controlSize(.small)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func resultSection(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ergebnis")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple.opacity(0.12), lineWidth: 0.5))

            HStack(spacing: 8) {
                Button {
                    appState.pasteImproverResult()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc").font(.system(size: 10, weight: .bold))
                        Text("Einfügen")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.blue)
                }
                .buttonStyle(SubtleButtonStyle())

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .bold))
                        Text(copied ? "Kopiert" : "Kopieren")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(copied ? .green : .blue)
                }
                .buttonStyle(SubtleButtonStyle())

                Spacer()

                Button("Als Eingabe") {
                    appState.useImproverResultAsInput()
                }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .buttonStyle(SubtleButtonStyle())
            }
        }
    }
}

struct FileTranscriptionContentView: View {
    @Bindable var appState: AppState
    @State private var copied = false
    @State private var savedTxt = false
    @State private var showingNote = false

    var body: some View {
        VStack(spacing: 0) {
            switch appState.fileTranscriptionState {
            case .idle:
                idleView

            case .running(let fileName, let progress):
                VStack(spacing: 12) {
                    Spacer().frame(height: 24)
                    if let progress {
                        VStack(spacing: 6) {
                            ProgressView(value: progress)
                                .frame(maxWidth: .infinity)
                            Text("\(Int(progress * 100)) %")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                    }
                    Text("Transkribiere \u{201E}\(fileName)\u{201C} \u{2026}")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(progress == nil
                        ? "Modell wird vorbereitet \u{2026}"
                        : "Lange Aufnahmen k\u{00F6}nnen etwas dauern.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer().frame(height: 24)
                }

            case .done(let text, let fileName, let savedToFile):
                resultView(text: text, fileName: fileName, savedToFile: savedToFile)

            case .failed(let message):
                errorView(message: message) {
                    appState.presentFileTranscription()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 20)
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
            Text("Audiodatei w\u{00E4}hlen")
                .font(.system(size: 13, weight: .semibold))
            Button("Datei ausw\u{00E4}hlen") {
                appState.presentFileTranscription()
            }
            .buttonStyle(SubtleButtonStyle())
            Spacer().frame(height: 12)
        }
    }

    private func resultView(text: String, fileName: String, savedToFile: Bool) -> some View {
        let review = appState.speakerReview
        let shownText = showingNote ? (noteText ?? "") : text

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text(fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 12)

            if appState.speakerReviewQueue.count > 1, let index = appState.speakerReviewQueueIndex {
                speakerReviewBatchBar(index: index, total: appState.speakerReviewQueue.count)
            }

            if let batchNotice = appState.fileBatchNotice {
                Text(batchNotice)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.speakerModelMissingForLastTranscription {
                SpeakerModelOfferView(appState: appState)
            }

            if let notice = appState.speakerRecognitionNotice {
                Text(notice)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let review {
                ScrollView {
                    SpeakerReviewSection(appState: appState, review: review)
                }
                .frame(maxHeight: review.pendingSpeakers.isEmpty ? 150 : 330)
                .fixedSize(horizontal: false, vertical: true)

                Picker("", selection: $showingNote) {
                    Text("Transkript").tag(false)
                    Text("Gesprächsnotiz").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if showingNote {
                noteView
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: review == nil ? 220 : 180)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
            }

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(shownText, forType: .string)
                    withAnimation(.easeInOut(duration: 0.2)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation(.easeInOut(duration: 0.2)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                        Text(copied ? "Kopiert" : "Kopieren")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(copied ? .green : .blue)
                }
                .buttonStyle(SubtleButtonStyle())
                .disabled(shownText.isEmpty)

                if showingNote {
                    EmptyView()
                } else if savedToFile {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(".txt gespeichert")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                } else {
                    Button {
                        appState.saveTranscriptAsTextFile()
                        withAnimation(.easeInOut(duration: 0.2)) { savedTxt = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation(.easeInOut(duration: 0.2)) { savedTxt = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: savedTxt ? "checkmark" : "arrow.down.doc")
                                .font(.system(size: 10, weight: .bold))
                            Text(savedTxt ? "Gespeichert" : "Als .txt")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(savedTxt ? .green : .blue)
                    }
                    .buttonStyle(SubtleButtonStyle())
                }

                Spacer()

                Button("Weitere Datei") {
                    appState.presentFileTranscription()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(SubtleButtonStyle())
            }

            if appState.webhookSettings.isEnabled,
               appState.lastVoiceMessagePayload != nil || appState.fileWebhookState != .idle {
                WebhookDeliveryRow(
                    state: appState.fileWebhookState,
                    canSend: appState.lastVoiceMessagePayload != nil,
                    send: appState.sendVoiceMessageToWebhook
                )
            }
        }
        .onChange(of: appState.speakerReview == nil) { _, noReview in
            if noReview { showingNote = false }
        }
    }

    /// Stapel: jede Aufnahme mit offenen Stimmen einzeln zuordnen.
    private func speakerReviewBatchBar(index: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                showingNote = false
                appState.showPreviousSpeakerReview()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(SubtleButtonStyle())
            .disabled(!appState.canShowPreviousSpeakerReview)
            .help("Vorherige Aufnahme")

            VStack(alignment: .leading, spacing: 1) {
                Text("Aufnahme \(index + 1) von \(total)")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("Stimmen je Aufnahme zuordnen. Benannte Stimmen erkennt Blitztext in den nächsten wieder.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                showingNote = false
                appState.showNextSpeakerReview()
            } label: {
                HStack(spacing: 3) {
                    Text("Nächste")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)
            }
            .buttonStyle(SubtleButtonStyle())
            .disabled(!appState.canShowNextSpeakerReview)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
    }

    private var noteText: String? {
        if case let .done(note) = appState.conversationNote { return note }
        return nil
    }

    @ViewBuilder
    private var noteView: some View {
        switch appState.conversationNote {
        case .idle:
            VStack(spacing: 8) {
                Text("Fasst zusammen, was jede Person gesagt hat, plus Vereinbarungen und nächste Schritte.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let review = appState.speakerReview, !review.pendingSpeakers.isEmpty {
                    Text("Tipp: Erst die offenen Stimmen benennen — sonst steht „Sprecher B“ in der Notiz.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Gesprächsnotiz erstellen") {
                    appState.createConversationNote()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)
                .buttonStyle(SubtleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

        case .running:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Notiz wird erstellt …")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

        case let .done(note):
            ScrollView {
                Text(note)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

        case let .failed(message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Nochmal versuchen") {
                    appState.createConversationNote()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(SubtleButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

private func errorView(message: String, onRetry: @escaping () -> Void) -> some View {
    VStack(spacing: 10) {
        Spacer().frame(height: 16)

        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.1))
                .frame(width: 40, height: 40)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
        }

        Text(message)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)

        Button(action: onRetry) {
            Text("Nochmal versuchen")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
        .buttonStyle(SubtleButtonStyle())

        Spacer().frame(height: 4)
    }
}

/// Übergabe der Sprachnachricht an den Webhook: Knopf, Fortschritt oder Ergebnis.
private struct WebhookDeliveryRow: View {
    let state: WebhookDeliveryState
    let canSend: Bool
    let send: () -> Void

    var body: some View {
        switch state {
        case .idle:
            if canSend {
                Button(action: send) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 10, weight: .bold))
                        Text("An Webhook senden")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(SubtleButtonStyle())
            }

        case .sending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Wird an den Webhook gesendet …")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

        case .sent:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("An den Webhook übergeben")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.green)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if canSend {
                    Button("Erneut senden", action: send)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                        .buttonStyle(SubtleButtonStyle())
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.09)))
        }
    }
}
