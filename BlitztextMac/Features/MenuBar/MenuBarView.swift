import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

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
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.2), value: appState.page)
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("Blitztext")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        appState.page = .settings
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gear")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.00001)) // hit target
                                )
                                .contentShape(Rectangle())

                            if !appState.accessibilityPermissionGranted {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                    .offset(x: -4, y: 4)
                            }
                        }
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Status area
                if appState.isConfigured {
                    configuredHeader
                } else {
                    unconfiguredHeader
                }
            }
            .padding(.bottom, 16)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            )

            if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                installHintBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }

            // Die Aktionen kommen zuerst — Konfiguration rückt nach unten
            // bzw. in die Einstellungen.
            VStack(spacing: 0) {
                ForEach(WorkflowType.mainMenuCases) { type in
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
                        dataMode: rowDataMode(for: type)
                    ) {
                        if isImprover(type) {
                            appState.openImproverBox(type: type)
                        } else {
                            appState.startWorkflow(type)
                        }
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 2)

            if !appState.accessibilityPermissionGranted {
                accessibilityHintBanner
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            transcriptionModeRow
                .padding(.horizontal, 16)
                .padding(.top, 4)

            if appState.isConfigured {
                fileTranscriptionEntry
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            if appState.appSettings.historyLimit > 0 && !appState.transcriptHistory.isEmpty {
                HistorySection(appState: appState)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            appFooter
                .padding(.top, 2)
        }
    }

    /// Bewusst schlank: eine Zeile statt Karte — die Funktion ist sekundär
    /// gegenüber den Diktier-Workflows.
    private var fileTranscriptionEntry: some View {
        Button {
            appState.presentFileTranscription()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 20)

                Text("Sprachnachricht transkribieren")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.035))
            )
        }
        .buttonStyle(SubtleButtonStyle())
    }

    // MARK: - File Transcription Page

    private var fileTranscriptionPage: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    appState.resetFileTranscription()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Zur\u{00FC}ck")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(SubtleButtonStyle())

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                    Text("Sprachnachricht")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer()
                Color.clear.frame(width: 58, height: 18)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            FileTranscriptionContentView(appState: appState)

            Spacer(minLength: 0)

            appFooter
        }
    }

    private var improverTextBoxPage: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    appState.resetImproverBox()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Zur\u{00FC}ck")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(SubtleButtonStyle())

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: appState.improverType.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(appState.improverType.color)
                    Text(appState.displayName(for: appState.improverType))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer()
                Color.clear.frame(width: 58, height: 18)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ImproverTextBoxContent(appState: appState)

            Spacer(minLength: 0)

            appFooter
        }
    }

    private func isImprover(_ type: WorkflowType) -> Bool {
        type == .textImprover || type == .dampfAblassen || type == .emojiText
    }

    private func rowDataMode(for type: WorkflowType) -> WorkflowRowView.DataMode {
        switch type {
        case .textImprover, .dampfAblassen, .emojiText:
            return appState.improverRewriteIsLocal ? .local : .cloud
        case .localTranscription:
            return .local
        case .transcription:
            return appState.appSettings.secureLocalModeEnabled ? .local : .cloud
        }
    }

    /// Kompakte Modus-Zeile: zeigt, WO transkribiert wird, und schaltet um.
    /// Modell-Auswahl und Download wohnen in den Einstellungen — hier gibt es
    /// nur den Status und einen direkten Absprung dorthin.
    private var transcriptionModeRow: some View {
        let localOn = appState.appSettings.secureLocalModeEnabled

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: localOn ? "lock.shield.fill" : "network")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(localOn ? .green : .blue)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(localOn ? "Transkription: lokal auf dem Gerät" : "Transkription: online (OpenAI)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)

                    if localOn {
                        Button {
                            appState.page = .settings
                        } label: {
                            HStack(spacing: 3) {
                                if !appState.selectedLocalModelIsInstalled && !appState.isDownloadingLocalModel {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(.orange)
                                }
                                Text(modeRowDetail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Modell in den Einstellungen verwalten")
                    }
                }

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
                    Text(appState.localModelDownloadStatusText ?? "Modell wird geladen ...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText = appState.localModelDownloadErrorText {
                Text(errorText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var modeRowDetail: String {
        if appState.isDownloadingLocalModel {
            return appState.localModelDownloadStatusText ?? "Modell wird geladen ..."
        }
        if !appState.selectedLocalModelIsInstalled {
            return "Modell fehlt — in den Einstellungen laden"
        }
        // Ehrlicher Geltungsbereich: was bleibt lokal, was geht raus?
        if appState.improverRewriteIsLocal {
            return "\(appState.selectedLocalModelDisplayName) · alles bleibt auf dem Gerät"
        }
        if appState.improverBoxAvailable {
            return "\(appState.selectedLocalModelDisplayName) · Umformer senden an OpenAI"
        }
        return appState.selectedLocalModelDisplayName
    }

    private var accessibilityHintBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("Einfügen braucht Bedienungshilfen.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Nach Updates kann macOS die Freigabe neu verlangen.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Öffnen") {
                appState.requestAccessibilityPermission()
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(SubtleButtonStyle())
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var configuredHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("Bereit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            // Die Kern-Geste in einem Satz — sichtbar, ohne Handbuch.
            Text(usageHint)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
    }

    private var usageHint: String {
        switch appState.appSettings.hotkeyMode {
        case .hold:
            return "Kürzel halten, sprechen, loslassen — der Text landet im aktiven Textfeld."
        case .toggle:
            return "Kürzel drücken, sprechen, nochmal drücken — der Text landet im aktiven Textfeld."
        }
    }

    private var installHintBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("Für sauberen Anmeldestart nach /Applications verschieben.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Sonst entstehen leichter doppelte Login-Items oder uneinheitliche Updates.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Prüfen") {
                appState.page = .settings
            }
            .font(.system(size: 10.5, weight: .medium))
            .buttonStyle(SubtleButtonStyle())
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var onboardingPage: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Willkommen bei Blitztext")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Später") {
                    appState.page = .main
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(SubtleButtonStyle())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.5)
            )

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 42, height: 42)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Einmal einrichten, dann direkt loslegen.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Eigenen OpenAI API Key eintragen. Danach sprechen und einfügen.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                        onboardingInstallCard
                    }

                    onboardingStep(number: "1", title: "OpenAI Key speichern", detail: "Öffne die Einstellungen und trage deinen eigenen OpenAI API Key ein.")
                    onboardingStep(number: "2", title: "Berechtigungen erlauben", detail: "Mikrofon und Bedienungshilfen für das Einfügen freigeben.")
                    onboardingStep(number: "3", title: "Workflow wählen", detail: "Blitztext oder einen der Verbesserer-Workflows direkt aus der Menüleiste starten.")
                }

                HStack(spacing: 8) {
                    Button {
                        appState.page = .settings
                    } label: {
                        Text("Jetzt einrichten")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
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

                    Text("Du findest alles später im Zahnrad.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Spacer(minLength: 0)

            appFooter
        }
    }

    private var unconfiguredHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "key.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 4) {
                Text("Einrichtung n\u{00F6}tig")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("\u{00D6}ffne die Einstellungen und hinterlege deine Zugangsdaten, um loszulegen.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            Button {
                appState.page = .settings
            } label: {
                Text("Einstellungen \u{00F6}ffnen")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 7)
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
        }
    }

    private func onboardingStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var onboardingInstallCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text("Lege Blitztext zuerst nach /Applications.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Das hält Anmeldestart, spätere Updates und das Entfernen sauber auf einer einzigen App-Kopie.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Settings Page

    private var settingsPage: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button {
                    appState.page = .main
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Zur\u{00FC}ck")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(SubtleButtonStyle())

                Spacer()

                Text("Einstellungen")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()
                settingsQuickAction
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

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
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Rechte")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.orange)
            }
            .buttonStyle(SubtleButtonStyle())
        } else {
            Color.clear.frame(width: 58, height: 18)
        }
    }

    // MARK: - Workflow Page

    private var workflowPage: some View {
        VStack(spacing: 0) {
            if let workflow = appState.activeWorkflow {
                // Header bar
                HStack {
                    Button {
                        appState.resetCurrentWorkflow()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Zur\u{00FC}ck")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(SubtleButtonStyle())

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: workflow.type.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(workflow.type.color)
                        Text(appState.displayName(for: workflow.type))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // Ein gemeinsamer Aufnahme-/Verarbeitungs-View für alle Workflows.
                WorkflowActiveView(workflow: workflow)

                Spacer(minLength: 0)

                appFooter
            }
        }
    }

    private var appFooter: some View {
        HStack {
            Text(appVersionLabel)
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            Spacer()

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.quaternary)
            .buttonStyle(SubtleButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var appVersionLabel: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return "Blitztext \(version)"
        }
        return "Blitztext"
    }
}

// MARK: - History Section

/// Zeigt die letzten Ergebnisse direkt auf der Hauptseite. Ein Tippen kopiert
/// den Text in die Zwischenablage — Rettung, falls er ins falsche Feld ging.
struct HistorySection: View {
    @Bindable var appState: AppState
    @State private var copiedID: UUID?

    /// Im Menü nur die obersten paar zeigen, damit es kompakt bleibt.
    private static let maxVisible = 4

    private var visibleEntries: [TranscriptHistoryEntry] {
        Array(appState.transcriptHistory.prefix(Self.maxVisible))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ZULETZT")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Leeren") {
                    appState.clearHistory()
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .buttonStyle(SubtleButtonStyle())
            }

            VStack(spacing: 4) {
                ForEach(visibleEntries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    private func row(for entry: TranscriptHistoryEntry) -> some View {
        let isCopied = copiedID == entry.id
        return Button {
            appState.copyHistoryEntry(entry)
            withAnimation(.easeInOut(duration: 0.2)) { copiedID = entry.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if copiedID == entry.id { copiedID = nil }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCopied ? "checkmark" : entry.type.icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isCopied ? Color.green : entry.type.color)
                    .frame(width: 16)

                Text(entry.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Text(isCopied ? "Kopiert" : relativeTime(entry.date))
                    .font(.system(size: 9.5))
                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.035))
            )
        }
        .buttonStyle(SubtleButtonStyle())
        .help("Kopieren: \(entry.text)")
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "gerade" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return "\(days) d"
    }
}

// MARK: - Subtle Button Style

struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
        VStack(alignment: .leading, spacing: 10) {
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

            ScrollView {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
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

                if savedToFile {
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
