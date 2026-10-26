import SwiftUI

struct SettingsPianoVolumeControl: View {
    @Binding var volume: Double
    private var safeVolume: Double { volume.isFinite ? min(1, max(0, volume)) : 0.85 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2")
                    .font(.body)
                    .foregroundStyle(PianoTheme.brass)
                    .frame(width: 34, height: 34)
                    .background(PianoTheme.brass.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Piano volume")
                        .font(.body)
                        .foregroundStyle(PianoTheme.ivory)
                    Text("Balance the piano with other audio")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                }

                Spacer(minLength: 8)

                Text("\(Int((safeVolume * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(PianoTheme.brass)
            }

            Slider(value: Binding(get: { safeVolume }, set: { volume = $0 }), in: 0...1)
                .tint(PianoTheme.brass)
                .accessibilityLabel("Piano volume")
                .accessibilityValue("\(Int((safeVolume * 100).rounded())) percent")
        }
        .padding(.vertical, 16)
    }
}
