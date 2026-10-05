import SwiftUI

struct BlackPianoKeyView: View {
    let key: PianoKey
    let isPressed: Bool
    let showLabels: Bool
    let octaveNamesOnly: Bool

    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: isPressed
                            ? [Color(hex: 0x222325FF), Color(hex: 0x101113FF), Color(hex: 0x29292BFF)]
                            : [Color(hex: 0x424245FF), Color(hex: 0x171719FF), Color(hex: 0x09090AFF)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.04), .black.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.11))
                        .frame(width: 2)
                        .padding(.leading, 3)
                        .padding(.vertical, 4)
                }
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: 0x303033FF))
                        .frame(height: 7)
                        .padding(.horizontal, 2)
                        .padding(.bottom, 2)
                }
                .overlay(alignment: .bottom) {
                    if showLabels && !octaveNamesOnly {
                        Text(key.displayName)
                            .font(.system(size: labelSize, weight: .medium, design: .rounded))
                            .foregroundStyle(PianoTheme.ivory.opacity(0.87))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .padding(.bottom, 15)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: isPressed ? 2 : 5, x: 1, y: isPressed ? 2 : 5)
                .frame(height: geometry.size.height * 0.62)
                .offset(y: isPressed ? 2 : 0)
        }
    }
}
