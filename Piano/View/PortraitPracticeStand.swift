import SwiftUI

/// Uses the extra height of a portrait iPad as a calm music stand above the keys.
struct PortraitPracticeStand: View {
    let chordName: String
    let takeCount: Int
    let isRecording: Bool
    let onRecord: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PIANOFLOW  /  CONCERT GRAND")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(PianoTheme.brass)
                Spacer()
                Image(systemName: "waveform")
                    .foregroundStyle(PianoTheme.brass.opacity(0.7))
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 20)

            VStack(spacing: 13) {
                Text(isRecording ? "CAPTURING YOUR PERFORMANCE" : "YOUR MUSIC STAND")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(isRecording ? PianoTheme.recording : PianoTheme.brass)

                Text(chordName == "READY TO PLAY" ? "Make every note yours." : chordName)
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                    .foregroundStyle(PianoTheme.ivory)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityAddTraits(.updatesFrequently)

                Text("An expressive 88-key piano, ready whenever you are.")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 650)

            Spacer(minLength: 20)

            HStack(spacing: 14) {
                Button(isRecording ? "Finish recording" : "Record a take", systemImage: isRecording ? "stop.circle.fill" : "record.circle") {
                    onRecord()
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? PianoTheme.recording : PianoTheme.brass)
                .foregroundStyle(PianoTheme.background)

                Button("Saved performances (\(takeCount))", systemImage: "square.stack") {
                    onLibrary()
                }
                .buttonStyle(.bordered)
                .tint(PianoTheme.ivory)
            }
            .controlSize(.large)
            .frame(minHeight: 52)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [PianoTheme.panelRaised, PianoTheme.background, PianoTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PianoTheme.brass.opacity(0.5))
                .frame(height: 1)
        }
    }
}
