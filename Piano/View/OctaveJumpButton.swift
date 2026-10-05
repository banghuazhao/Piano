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
                .foregroundStyle(isSelected ? PianoTheme.background : PianoTheme.ivory)
                .frame(minWidth: 44, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? PianoTheme.brass : PianoTheme.panelRaised)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(isSelected ? PianoTheme.brass : PianoTheme.divider, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to octave \(octave)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
