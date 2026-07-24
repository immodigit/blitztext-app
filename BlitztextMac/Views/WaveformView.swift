import SwiftUI
import Combine

/// Manages waveform bar levels and an internal display timer.
/// Lives as a reference type so the Timer closure always reads fresh state.
@MainActor
final class WaveformState: ObservableObject {
    @Published var levels: [CGFloat]

    /// The current audio level fed from the parent -- updated on every
    /// SwiftUI body evaluation so the timer always has the latest value.
    var currentAudioLevel: Float = 0

    private let barCount: Int
    private var phase: Double = 0
    private var timer: Timer?

    init(barCount: Int = 40) {
        self.barCount = barCount
        self.levels = Array(repeating: 0.03, count: barCount)
    }

    func startTimer() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        // .common: Wellenform läuft auch weiter, wenn macOS im Event-Tracking ist.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        levels = Array(repeating: 0.03, count: barCount)
        phase = 0
    }

    private func tick() {
        phase += 0.22
        let base = CGFloat(currentAudioLevel)
        levels.removeFirst()
        // Ausschlag skaliert mit der Lautstärke: beim Sprechen tanzen die Balken
        // deutlich, in Sprechpausen bleibt die Linie ruhig statt zu zappeln.
        let jitter = CGFloat.random(in: -0.22...0.22) * base
        let breathe = sin(phase) * (0.02 + base * 0.08)
        let newLevel = max(0.03, min(1.0, base + jitter + breathe))
        levels.append(newLevel)
    }

    deinit {
        timer?.invalidate()
    }
}

struct WaveformView: View {
    var audioLevel: Float
    var isRecording: Bool
    var accentColor: Color = .primary
    var barCount: Int = 40

    @StateObject private var state: WaveformState

    init(audioLevel: Float, isRecording: Bool, accentColor: Color = .primary, barCount: Int = 40) {
        self.audioLevel = audioLevel
        self.isRecording = isRecording
        self.accentColor = accentColor
        self.barCount = barCount
        _state = StateObject(wrappedValue: WaveformState(barCount: barCount))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(state.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(barColor(for: level))
                    .frame(width: 2.5, height: max(2, level * 40))
            }
        }
        .frame(height: 40)
        .onChange(of: audioLevel) { _, newLevel in
            state.currentAudioLevel = newLevel
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                state.currentAudioLevel = audioLevel
                state.startTimer()
            } else {
                state.stopTimer()
                withAnimation(.easeOut(duration: 0.4)) {
                    state.reset()
                }
            }
        }
        .onAppear {
            state.currentAudioLevel = audioLevel
            if isRecording {
                state.startTimer()
            }
        }
        .onDisappear {
            state.stopTimer()
        }
    }

    private func barColor(for level: CGFloat) -> Color {
        let opacity = 0.25 + Double(level) * 0.75
        return accentColor.opacity(opacity)
    }
}
