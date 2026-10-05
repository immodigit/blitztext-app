import SwiftUI
import BlitztextCore

/// Sprecherliste unter dem Transkript: erkannte Stimmen kompakt, neue und
/// unsichere Stimmen als Karte mit Hörproben und Namensfeld.
struct SpeakerReviewSection: View {
    @Bindable var appState: AppState
    let review: SpeakerReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text("\(review.speakers.count) Personen erkannt")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                if !review.pendingSpeakers.isEmpty {
                    Text("\(review.pendingSpeakers.count) offen")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }

            ForEach(review.speakers) { speaker in
                if speaker.assignment.needsDecision {
                    PendingSpeakerCard(appState: appState, speaker: speaker)
                } else {
                    SpeakerSummaryRow(appState: appState, speaker: speaker)
                }
            }
        }
    }
}

// MARK: - Erkannte / entschiedene Stimme

private struct SpeakerSummaryRow: View {
    @Bindable var appState: AppState
    let speaker: SpeakerReview.Speaker

    var body: some View {
        HStack(spacing: 8) {
            if let sample = speaker.samples.first {
                SamplePlayButton(url: sample.clipURL)
            } else {
                Color.clear.frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 11.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(isSkipped ? "Benennen" : "Ändern") {
                appState.reconsiderSpeaker(speaker.id)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)
            .buttonStyle(SubtleButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
    }

    private var isSkipped: Bool { speaker.assignment == .skipped }

    private var name: String {
        speaker.assignment.displayName(placeholder: speaker.placeholder) {
            appState.voiceProfiles.profile($0)?.name
        }
    }

    private var detail: String {
        let talk = "\(SpeakerTranscriptFormatter.timecode(speaker.talkTime)) Redezeit"
        switch speaker.assignment {
        case let .recognized(_, similarity):
            return "Erkannt · \(Int((similarity * 100).rounded())) % · \(talk)"
        case .confirmed:
            return "Zugeordnet · \(talk)"
        case .named:
            return "Nur in diesem Transkript benannt · \(talk)"
        case .skipped:
            return "Nicht benannt · \(talk)"
        case .suggested, .unknown:
            return talk
        }
    }
}

// MARK: - Neue oder unsichere Stimme

private struct PendingSpeakerCard: View {
    @Bindable var appState: AppState
    let speaker: SpeakerReview.Speaker
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: suggestion == nil ? "person.badge.plus" : "questionmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("\(speaker.placeholder) · \(SpeakerTranscriptFormatter.timecode(speaker.talkTime)) Redezeit")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if speaker.samples.isEmpty {
                Text("Keine Hörprobe — die Person spricht kaum allein.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(speaker.samples) { sample in
                        SampleRow(sample: sample)
                    }
                }
            }

            if let suggestion {
                Button {
                    appState.assignSpeaker(speaker.id, to: suggestion.id)
                } label: {
                    Text("Ja, das ist \(suggestion.name)")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.blue.opacity(0.12)))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(SubtleButtonStyle())
            }

            HStack(spacing: 6) {
                TextField(suggestion == nil ? "Wer ist das?" : "Jemand anderes …", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(save)

                Button("Speichern", action: save)
                    .font(.system(size: 12, weight: .medium))
                    .disabled(trimmedName.isEmpty)
                    .buttonStyle(SubtleButtonStyle())
                    .foregroundStyle(trimmedName.isEmpty ? Color.secondary : Color.blue)
            }

            HStack(spacing: 10) {
                if !otherProfiles.isEmpty {
                    Menu {
                        ForEach(otherProfiles) { profile in
                            Button(profile.name) {
                                appState.assignSpeaker(speaker.id, to: profile.id)
                            }
                        }
                    } label: {
                        Text("Bekannte Person …")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Spacer()

                Button("Überspringen") {
                    appState.skipSpeaker(speaker.id)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(SubtleButtonStyle())
            }

            Text(speaker.canLearnVoice
                ? "Speichern legt ein lokales Stimmprofil an, damit die Stimme künftig erkannt wird. Bei anderen Personen nur mit deren Einverständnis."
                : "Zu wenig Sprache für ein Stimmprofil — der Name gilt nur für dieses Transkript.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestion: VoiceProfile? {
        guard case let .suggested(profileID, _) = speaker.assignment else { return nil }
        return appState.voiceProfiles.profile(profileID)
    }

    private var title: String {
        guard case let .suggested(_, similarity) = speaker.assignment, let suggestion else {
            return "Neue Stimme erkannt"
        }
        return "Klingt wie \(suggestion.name) (\(Int((similarity * 100).rounded())) %)"
    }

    private var otherProfiles: [VoiceProfile] {
        appState.voiceProfiles.profiles
            .filter { $0.id != suggestion?.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        appState.nameSpeaker(speaker.id, as: trimmedName)
        name = ""
    }
}

// MARK: - Hörproben

private struct SampleRow: View {
    let sample: SpeakerReview.Sample

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            SamplePlayButton(url: sample.clipURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(SpeakerTranscriptFormatter.timecode(sample.span.start))
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(sample.quote.isEmpty ? "(ohne erkannten Text)" : "„\(sample.quote)“")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SamplePlayButton: View {
    let url: URL
    private var player: VoiceSamplePlayer { .shared }

    var body: some View {
        let isPlaying = player.playingURL == url
        Button {
            player.toggle(url)
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(isPlaying ? Color.orange : Color.blue))
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Hörprobe stoppen" : "Hörprobe abspielen")
    }
}

// MARK: - Modell fehlt

/// Angebot in der Ergebnisansicht, wenn ohne Sprecher transkribiert wurde,
/// weil das Modell fehlt. Geladen wird nur auf Klick.
struct SpeakerModelOfferView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text(appState.speakerModelInstalled ? "Sprechererkennung ist geladen" : "Wer hat was gesagt?")
                    .font(.system(size: 11.5, weight: .semibold))
            }

            if appState.speakerModelInstalled {
                Text("Transkribiere die Datei neu, um die Sprecher zu sehen.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Button("Neu transkribieren") {
                    appState.retranscribeLastFile()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)
                .buttonStyle(SubtleButtonStyle())
            } else {
                SpeakerModelDownloadControl(appState: appState)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
    }
}

/// Knopf bzw. Fortschritt für den einmaligen Download der Sprechererkennung.
struct SpeakerModelDownloadControl: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let progress = appState.speakerModelDownloadProgress {
                ProgressView(value: progress)
                Text("Lädt \(Int(progress * 100)) % …")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("Erkennt in Sprachnachrichten, wer spricht. Einmaliger Download (ca. 11 MB), danach komplett lokal.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sprechererkennung laden") {
                    appState.installSpeakerRecognitionModel()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)
                .buttonStyle(SubtleButtonStyle())
            }
            if let error = appState.speakerModelDownloadErrorText {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
