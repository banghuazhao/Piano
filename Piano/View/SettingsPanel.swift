//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct SettingsPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(PianoTheme.brass)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(PianoTheme.ivory)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 17)

            Divider().overlay(PianoTheme.divider)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 20)
        }
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [PianoTheme.panel, PianoTheme.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(PianoTheme.brass.opacity(0.16), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}
