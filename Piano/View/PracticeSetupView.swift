import SwiftUI

@MainActor
struct PracticeSetupView: View {
    let exercise: PracticeExercise
    let onStart: (PracticeExercise, PracticeOptions) -> Void
    @State private var mode: PracticeMode = .wait
    @State private var hand: PracticeHand
    @State private var bpm: Int
    @State private var countInBars = 1
    @State private var tempoStep = 5
    @State private var targetBPM: Int
    @AppStorage("practiceShowScore") private var showScore = true

    init(exercise: PracticeExercise, onStart: @escaping (PracticeExercise, PracticeOptions) -> Void) {
        self.exercise = exercise
        self.onStart = onStart
        _hand = State(initialValue: exercise.availableHands.first ?? .both)
        _bpm = State(initialValue: max(40, exercise.suggestedBPM - 20))
        _targetBPM = State(initialValue: exercise.suggestedBPM)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(PianoTheme.ivory)
                    Text(exercise.detail)
                        .foregroundStyle(PianoTheme.secondary)
                    Label("\(exercise.steps.count) steps · \(exercise.beatsPerBar)/\(exercise.beatUnit)", systemImage: "music.note.list")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.brass)
                }

                section("HOW TO PRACTICE") {
                    Picker("Practice mode", selection: $mode) {
                        Text("At your pace").tag(PracticeMode.wait)
                        Text("Rhythm coach").tag(PracticeMode.rhythm)
                    }
                    .pickerStyle(.segmented)
                    Text(mode == .wait
                         ? "The music waits for the right notes. Release repeated notes before replaying them."
                         : "Start after the count-in and keep time with the click. Feedback measures when you strike each note; note lengths are shown in the score.")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("HANDS & SCORE") {
                    if exercise.availableHands.count > 1 {
                        Picker("Hand to practice", selection: $hand) {
                            ForEach(exercise.availableHands) { hand in
                                Text(hand.title).tag(hand)
                            }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Label(hand.title, systemImage: "hand.raised")
                    }
                    Toggle("Show sheet music", isOn: $showScore)
                    Text("Practice a hand separately, then bring both parts together.")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                }

                if mode == .rhythm {
                    section("TEMPO") {
                        Stepper("Start: \(bpm) BPM", value: $bpm, in: 40...240, step: 5)
                            .monospacedDigit()
                            .onChange(of: bpm) { _, value in targetBPM = max(targetBPM, value) }
                        Picker("Count-in", selection: $countInBars) {
                            Text("None").tag(0)
                            Text("1 bar").tag(1)
                            Text("2 bars").tag(2)
                        }
                        .pickerStyle(.segmented)
                        Divider().overlay(PianoTheme.divider)
                        Stepper("Goal: \(targetBPM) BPM", value: $targetBPM, in: bpm...240, step: 5)
                            .monospacedDigit()
                        Picker("Increase after a good pass", selection: $tempoStep) {
                            Text("Off").tag(0)
                            Text("+5 BPM").tag(5)
                            Text("+10 BPM").tag(10)
                        }
                        .pickerStyle(.segmented)
                        Text("Reach 80% pitch and timing accuracy to unlock the next tempo. You choose when to start the next pass.")
                            .font(.subheadline)
                            .foregroundStyle(PianoTheme.secondary)
                    }
                }

                PracticeScoreView(exercise: exercise, currentBeat: 0, hand: hand)
                    .frame(height: hand == .both ? 220 : 155)

                Button {
                    onStart(exercise, PracticeOptions(mode: mode, bpm: bpm,
                        countInBars: countInBars, hand: hand,
                        tempoStep: tempoStep, targetBPM: targetBPM))
                } label: {
                    Label("Start practice", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("practice.start")
                .tint(PianoTheme.brass)
                .foregroundStyle(PianoTheme.background)
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(PianoTheme.background.ignoresSafeArea())
        .accessibilityIdentifier("practice.setup.scroll")
        .navigationTitle("Practice setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(PianoTheme.brass)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .foregroundStyle(PianoTheme.ivory)
        .padding(18)
        .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}
