import SwiftUI

struct OctaveJumpButton: View {
    let octave: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("C\(octave)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(PianoTheme.ivory)
                .frame(minWidth: 44, minHeight: 44)
                .pianoControlSurface(cornerRadius: 9, tint: isSelected ? PianoTheme.brass : nil, interactive: true)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule().fill(PianoTheme.ivory).frame(width: 16, height: 2).padding(.bottom, 5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to octave \(octave)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
