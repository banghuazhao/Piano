//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct SettingsKeyWidthControl: View {
    @Binding var keyWidth: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.and.right")
                    .font(.body)
                    .foregroundStyle(PianoTheme.brass)
                    .frame(width: 34, height: 34)
                    .background(PianoTheme.brass.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Key width")
                        .font(.body)
                        .foregroundStyle(PianoTheme.ivory)
                    Text("Choose a comfortable touch target")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                }

                Spacer(minLength: 8)

                Text("\(Int(keyWidth)) pt")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(PianoTheme.brass)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PianoTheme.brass.opacity(0.11), in: Capsule())
                    .accessibilityHidden(true)
            }

            Slider(value: $keyWidth, in: 30...90, step: 5)
                .tint(PianoTheme.brass)
                .accessibilityLabel("Key width")
                .accessibilityValue("\(Int(keyWidth)) points")

            HStack {
                Text("NARROW")
                Spacer()
                Text("WIDE")
            }
            .font(.caption.bold())
            .tracking(1)
            .foregroundStyle(PianoTheme.secondary)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 16)
    }
}
