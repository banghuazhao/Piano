import SwiftUI

@MainActor
struct PracticeTempoView: View {
    let session: PracticeSession
    @State private var bpm: Int
    @Environment(\.dismiss) private var dismiss

    init(session: PracticeSession) {
        self.session = session
        _bpm = State(initialValue: session.currentBPM)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Rhythm coach tempo", systemImage: "metronome")
                    .font(.headline)
                Text("The session is paused. Changing tempo starts a new pass with your count-in.")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                Stepper("\(bpm) BPM", value: $bpm, in: 40...240, step: 5)
                    .font(.title3.bold().monospacedDigit())
                Slider(value: Binding(get: { Double(bpm) }, set: { bpm = Int($0.rounded()) }), in: 40...240, step: 1)
                    .accessibilityLabel("Practice tempo")
                    .accessibilityValue("\(bpm) beats per minute")
                Button("Restart at \(bpm) BPM") {
                    if let exercise = session.exercise {
                        session.start(exercise, options: PracticeOptions(mode: .rhythm, bpm: bpm,
                            countInBars: session.options.countInBars, hand: session.options.hand,
                            tempoStep: session.options.tempoStep, targetBPM: max(bpm, session.targetBPM)))
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(PianoTheme.brass)
                .foregroundStyle(PianoTheme.background)
                .frame(minHeight: 44)
                Button("Resume at \(session.currentBPM) BPM") {
                    session.resume()
                    dismiss()
                }
                    .frame(minHeight: 44)
            }
            .padding(20)
        }
        .frame(width: 320)
        .frame(maxHeight: 340)
        .pianoPopoverSurface()
        .foregroundStyle(PianoTheme.ivory)
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationCompactAdaptation(.sheet)
    }
}
