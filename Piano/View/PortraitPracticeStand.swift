import SwiftUI

/// Uses a tall piano canvas as a music stand above the keys.
struct PortraitPracticeStand: View {
    let chordName: String
    let takeCount: Int
    let isRecording: Bool
    var soundTitle = "Concert Grand"
    let onRecord: () -> Void
    let onLibrary: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let stackedActions = geometry.size.width < 500 || dynamicTypeSize.isAccessibilitySize
            let needsScrolling = stackedActions || geometry.size.height < 360

            Group {
                if needsScrolling {
                    ScrollView {
                        content(stackedActions: stackedActions, usesSpacers: false)
                            .padding(stackedActions ? 20 : 24)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    content(stackedActions: false, usesSpacers: true)
                        .padding(32)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [PianoTheme.panelRaised, PianoTheme.background, PianoTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(PianoTheme.brass.opacity(0.5)).frame(height: 1)
        }
    }

    private func content(stackedActions: Bool, usesSpacers: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("PIANOFLOW  /  \(soundTitle.uppercased())")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(PianoTheme.brass)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "waveform")
                    .foregroundStyle(PianoTheme.brass.opacity(0.7))
                    .accessibilityHidden(true)
            }

            if usesSpacers {
                Spacer(minLength: 20)
            } else {
                Color.clear.frame(height: 24)
            }

            VStack(spacing: 13) {
                Text(isRecording ? "CAPTURING YOUR PERFORMANCE" : "YOUR MUSIC STAND")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(isRecording ? PianoTheme.recording : PianoTheme.brass)

                Text(chordName == "READY TO PLAY" ? "Make every note yours." : chordName)
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                    .foregroundStyle(PianoTheme.ivory)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(stackedActions ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)

                Text("An expressive 88-key piano, ready whenever you are.")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 650)

            if usesSpacers {
                Spacer(minLength: 20)
            } else {
                Color.clear.frame(height: 24)
            }

            Group {
                if stackedActions {
                    VStack(spacing: 14) { actions }
                } else {
                    HStack(spacing: 14) { actions }
                }
            }
            .controlSize(.large)
            .frame(minHeight: 52)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var actions: some View {
        Button(isRecording ? "Finish recording" : "Record a take",
               systemImage: isRecording ? "stop.circle.fill" : "record.circle", action: onRecord)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? PianoTheme.recording : PianoTheme.brass)
            .foregroundStyle(PianoTheme.background)
        Button("Saved performances (\(takeCount))", systemImage: "square.stack", action: onLibrary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.bordered)
            .tint(PianoTheme.ivory)
    }
}
