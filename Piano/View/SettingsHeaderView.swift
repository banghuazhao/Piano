//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct SettingsHeaderView: View {
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [PianoTheme.panel, PianoTheme.background],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(PianoTheme.brass.opacity(0.35), lineWidth: 1)
                    }

                Image(systemName: "pianokeys")
                    .font(.title)
                    .foregroundStyle(PianoTheme.brass)
                    .accessibilityHidden(true)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text("Make it yours")
                    .font(.title2.bold())
                    .foregroundStyle(PianoTheme.ivory)

                Text("Fine-tune your keyboard for every session.")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
