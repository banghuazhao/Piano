import SwiftUI

struct PianoKeyView: View {
    let key: PianoKey
    let isPressed: Bool
    let showLabels: Bool
    let octaveNamesOnly: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        Group {
            if key.isBlack {
                BlackPianoKeyView(
                    key: key,
                    isPressed: isPressed,
                    showLabels: showLabels,
                    octaveNamesOnly: octaveNamesOnly
                )
            } else {
                WhitePianoKeyView(
                    key: key,
                    isPressed: isPressed,
                    showLabels: showLabels,
                    octaveNamesOnly: octaveNamesOnly
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.displayName) piano key")
        .accessibilityValue(isPressed ? "Pressed" : "Released")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onPress()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                onRelease()
            }
        }
    }
}

#Preview {
    HStack(spacing: 1) {
        PianoKeyView(
            key: PianoKey(note: .C, octave: 4),
            isPressed: false,
            showLabels: true,
            octaveNamesOnly: false,
            onPress: {},
            onRelease: {}
        )
        PianoKeyView(
            key: PianoKey(note: .D, octave: 4),
            isPressed: true,
            showLabels: true,
            octaveNamesOnly: false,
            onPress: {},
            onRelease: {}
        )
    }
    .frame(width: 110, height: 280)
    .padding()
    .background(PianoTheme.background)
}
