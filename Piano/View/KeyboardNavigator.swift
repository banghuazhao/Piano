import SwiftUI

struct KeyboardNavigator: View {
    @Binding var position: Double
    let octaves: [Int]
    let currentOctave: Int?
    let onOctave: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                  Text("RANGE")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(PianoTheme.secondary)

                Text("A0")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(PianoTheme.secondary)
                }

                Slider(value: $position, in: 0...1)
                    .tint(PianoTheme.brass)
                    .accessibilityLabel("Keyboard range")
                    .accessibilityValue("Octave \(currentOctave ?? 4)")

                if !dynamicTypeSize.isAccessibilitySize {
                  Text("C8")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(PianoTheme.secondary)
                }

                if geometry.size.width >= 650 && !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 4) {
                        ForEach(octaves, id: \.self) { octave in
                            OctaveJumpButton(
                                octave: octave,
                                isSelected: currentOctave == octave,
                                action: { onOctave(octave) }
                            )
                        }
                    }
                } else {
                    Menu {
                        ForEach(octaves, id: \.self) { octave in
                            Button("C\(octave)") { onOctave(octave) }
                        }
                    } label: {
                        Label("C\(currentOctave ?? 4)", systemImage: "chevron.down")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(PianoTheme.ivory)
                            .frame(minWidth: 72, minHeight: 44)
                            .pianoControlSurface(cornerRadius: 9, interactive: true)
                    }
                    .accessibilityLabel("Choose octave")
                }
            }
            .pianoGlassContainer()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 56)
        .background(PianoTheme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(PianoTheme.divider).frame(height: 1)
        }
    }
}
