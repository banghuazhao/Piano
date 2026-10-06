import SwiftUI

@MainActor
struct PracticeSessionPanel: View {
    let session: PracticeSession
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("practiceShowScore") private var showScore = true

    var body: some View {
        if let exercise = session.exercise {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if verticalSizeClass != .compact {
                            Text(exercise.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(PianoTheme.ivory)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        Label(statusMessage, systemImage: session.isCountingIn ? "metronome" : feedbackSymbol)
                            .font(.subheadline)
                            .foregroundStyle(feedbackColor)
                            .lineLimit(verticalSizeClass == .compact ? 1 : 2)
                            .minimumScaleFactor(0.75)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Spacer(minLength: 6)

                    Text("\(session.completedSteps) / \(session.totalSteps)")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(PianoTheme.brass)
                        .accessibilityLabel("\(session.completedSteps) of \(session.totalSteps) steps completed")

                    if session.isActive {
                        Button(session.isPaused ? "Resume practice" : "Pause practice",
                               systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                            if session.isPaused { session.resume() } else { session.pause() }
                        }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                    }

                    Menu {
                        Toggle("Sheet music", isOn: $showScore)
                        Button("Restart exercise", systemImage: "arrow.counterclockwise") { session.restart() }
                    } label: {
                        Label("Practice options", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                            .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                    }

                    Button("Exit practice", systemImage: "xmark") {
                        session.stop()
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                    .accessibilityHint("Closes guided practice")
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(PianoTheme.ivory)

                if let result = session.lastCompletedResult,
                   let timing = result.onsetTimingAccuracyPercent {
                    HStack {
                        Text("Pitch \(result.accuracyPercent)% · Timing \(timing)% · \(result.missedNotes) missed")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PianoTheme.secondary)
                        Spacer(minLength: 8)
                        if session.canIncreaseTempo, let next = session.suggestedNextBPM {
                            Button("Next: \(next) BPM", systemImage: "arrow.up.right") {
                                _ = session.increaseTempo()
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(PianoTheme.brass)
                            .frame(minHeight: 44)
                        }
                    }
                }

                ProgressView(value: session.progressFraction)
                    .tint(PianoTheme.brass)
                    .accessibilityLabel("Exercise progress")
                    .accessibilityValue("\(session.completedSteps) of \(session.totalSteps) steps")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, verticalSizeClass == .compact ? 6 : 10)
            .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(PianoTheme.brass.opacity(0.34), lineWidth: 1)
            }
        }
    }

    private var statusMessage: String {
        if session.isCountingIn, let exercise = session.exercise {
            return session.countInBeat > 0
                ? "Count-in · \(session.countInBeat) of \(exercise.beatsPerBar)"
                : "Count-in · get ready"
        }
        return session.feedbackMessage
    }

    private var feedbackSymbol: String {
        switch session.feedbackTone {
        case .neutral: "hand.point.up.left"
        case .correct: "checkmark.circle.fill"
        case .tryAgain: "arrow.uturn.backward.circle.fill"
        case .completed: "star.fill"
        }
    }

    private var feedbackColor: Color {
        switch session.feedbackTone {
        case .neutral: PianoTheme.secondary
        case .correct, .completed: PianoTheme.brass
        case .tryAgain: PianoTheme.recording
        }
    }
}

#Preview {
    let session = PracticeSession()
    session.start(PracticeCatalog.all[0])
    return PracticeSessionPanel(session: session)
        .padding()
        .background(PianoTheme.background)
}
