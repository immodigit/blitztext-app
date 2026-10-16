import SwiftUI
import BlitztextCore

/// Einstellungen für die Übergabe an einen Webhook (z. B. n8n → Wissensdatenbank).
/// URL und Token liegen im Keychain, nicht in der settings.json.
struct WebhookSettingsSection: View {
    @Bindable var appState: AppState

    private enum Field {
        case url
        case token
    }

    @State private var urlText = ""
    @State private var tokenText = ""
    @State private var urlProblem: String?
    @State private var savedField: Field?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Webhook (z. B. n8n)")

            Toggle("Ergebnisse an Webhook senden", isOn: $appState.webhookSettings.isEnabled)
                .toggleStyle(.switch)

            Text("Schickt das Transkript als JSON an deinen Workflow — etwa um es dort zu analysieren und in deiner Wissensdatenbank abzulegen.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appState.webhookSettings.isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Webhook-URL")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("https://n8n.example.de/webhook/…", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .focused($focusedField, equals: .url)
                        .onSubmit { saveURL() }

                    if let urlProblem {
                        hint(urlProblem, color: .red)
                    } else if let url = try? WebhookEndpoint.validate(urlText).get(),
                              WebhookEndpoint.isN8nTestURL(url) {
                        hint("Das ist eine n8n-Test-URL: Sie nimmt nur etwas an, solange der Editor auf ein Test-Event wartet. Für den Alltag die Produktions-URL (…/webhook/…) nehmen und den Workflow aktivieren.", color: .orange)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Token (optional)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    SecureField("Wert für Header Auth", text: $tokenText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .focused($focusedField, equals: .token)
                        .onSubmit { saveToken() }
                    Text("Wird als Header \(WebhookService.tokenHeader) mitgeschickt. In n8n am Webhook „Header Auth“ mit diesem Namen und Wert einstellen.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let savedField {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(savedField == .url ? "URL gespeichert" : "Token gespeichert")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Automatisch senden")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    ForEach(WebhookSource.allCases) { source in
                        Toggle(source.settingsTitle, isOn: sourceBinding(source))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                    }
                    Text("Nicht gewählte Sprachnachrichten kannst du nach dem Transkribieren einzeln mit „An Webhook senden“ übergeben.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if appState.appSettings.secureLocalModeEnabled {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Der sichere lokale Modus hält die Transkription auf dem Mac. Was du hier zum Senden auswählst, verlässt den Mac trotzdem — als Klartext an deinen Webhook.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.09)))
                }

                HStack(spacing: 8) {
                    Button("Testnachricht senden") {
                        saveURL()
                        saveToken()
                        guard urlProblem == nil else { return }
                        appState.sendWebhookTest()
                    }
                    .controlSize(.small)
                    .disabled(appState.webhookTestState == .sending)

                    deliveryLabel(appState.webhookTestState)
                }

                if appState.lastBackgroundWebhookState != .idle {
                    HStack(spacing: 4) {
                        Text("Letztes Diktat/Umformung:")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        deliveryLabel(appState.lastBackgroundWebhookState)
                    }
                }
            }
        }
        .onAppear {
            urlText = KeychainService.load(key: .webhookURL) ?? ""
            tokenText = KeychainService.load(key: .webhookToken) ?? ""
        }
        .onChange(of: focusedField) { oldValue, _ in
            // Wie beim API Key: beim Verlassen des Feldes speichern.
            if oldValue == .url { saveURL() }
            if oldValue == .token { saveToken() }
        }
    }

    private func sourceBinding(_ source: WebhookSource) -> Binding<Bool> {
        Binding(
            get: { appState.webhookSettings.sources.contains(source) },
            set: { isOn in
                if isOn {
                    appState.webhookSettings.sources.insert(source)
                } else {
                    appState.webhookSettings.sources.remove(source)
                }
            }
        )
    }

    private func saveURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (KeychainService.load(key: .webhookURL) ?? "") || urlProblem != nil else { return }
        if trimmed.isEmpty {
            KeychainService.delete(key: .webhookURL)
            urlProblem = nil
            return
        }
        switch WebhookEndpoint.validate(trimmed) {
        case .success(let url):
            do {
                try KeychainService.save(key: .webhookURL, value: url.absoluteString)
                urlText = url.absoluteString
                urlProblem = nil
                flashSaved(.url)
            } catch {
                urlProblem = error.localizedDescription
            }
        case .failure(let problem):
            urlProblem = problem.message
        }
    }

    private func saveToken() {
        let trimmed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (KeychainService.load(key: .webhookToken) ?? "") else { return }
        if trimmed.isEmpty {
            KeychainService.delete(key: .webhookToken)
            return
        }
        if (try? KeychainService.save(key: .webhookToken, value: trimmed)) != nil {
            flashSaved(.token)
        }
    }

    private func flashSaved(_ field: Field) {
        withAnimation(.easeInOut(duration: 0.2)) { savedField = field }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if savedField == field { savedField = nil }
            }
        }
    }

    private func hint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func deliveryLabel(_ state: WebhookDeliveryState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .sending:
            ProgressView().controlSize(.small)
        case .sent:
            Label("Angekommen", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
