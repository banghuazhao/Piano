//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(PianoTheme.brass)
                    .frame(width: 34, height: 34)
                    .background(PianoTheme.brass.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(PianoTheme.ivory)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(PianoTheme.brass)
        .padding(.vertical, 14)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
