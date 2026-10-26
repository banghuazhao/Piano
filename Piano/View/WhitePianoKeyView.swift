import SwiftUI

struct WhitePianoKeyView: View {
    let key: PianoKey
    let isPressed: Bool
    let showLabels: Bool
    let octaveNamesOnly: Bool

    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 1,
            bottomLeadingRadius: 6,
            bottomTrailingRadius: 6,
            topTrailingRadius: 1
        )
        .fill(
            LinearGradient(
                colors: isPressed
                    ? [Color(hex: 0xD8D0C3FF), Color(hex: 0xE6DDD0FF), Color(hex: 0xC9BFAFFF)]
                    : [Color(hex: 0xFFFDF7FF), PianoTheme.ivory, Color(hex: 0xDDD4C5FF)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 1,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 6,
                topTrailingRadius: 1
            )
            .strokeBorder(Color(hex: 0xBEB4A5FF), lineWidth: 0.8)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.black.opacity(0.07))
                .frame(width: 2)
                .padding(.vertical, 2)
        }
        .overlay(alignment: .bottom) {
            if showLabels && (!octaveNamesOnly || key.note == .C) {
                Text(key.displayName)
                    .font(.system(size: min(labelSize, 16), weight: key.note == .C ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0x4C473FFF))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
            }
        }
        .shadow(color: .black.opacity(isPressed ? 0.08 : 0.24), radius: isPressed ? 1 : 3, x: 1, y: isPressed ? 1 : 3)
        .offset(y: isPressed ? 2 : 0)
    }
}
