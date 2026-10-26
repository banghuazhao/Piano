import SwiftUI

struct PianoKeyView: View {
    let key: PianoKey
    let isPressed: Bool
    var isTarget = false
    let showLabels: Bool
    let octaveNamesOnly: Bool
    let onPress: () -> Bool
    let onRelease: () -> Void
    @State private var accessibilityReleaseTask: Task<Void, Never>?

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
        .overlay {
            if isTarget {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(PianoTheme.brass, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.displayName) piano key")
        .accessibilityValue(isPressed ? "Pressed" : "Released")
        .accessibilityHint(isTarget ? "Next guided practice note" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard onPress() else { return }
            accessibilityReleaseTask?.cancel()
            accessibilityReleaseTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(180)) }
                catch { return }
                guard !Task.isCancelled else { return }
                accessibilityReleaseTask = nil
                onRelease()
            }
        }
        .onChange(of: isPressed) { _, pressed in
            if !pressed {
                accessibilityReleaseTask?.cancel()
                accessibilityReleaseTask = nil
            }
        }
        .onDisappear {
            if accessibilityReleaseTask != nil {
                accessibilityReleaseTask?.cancel()
                accessibilityReleaseTask = nil
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
            onPress: { true },
            onRelease: {}
        )
        PianoKeyView(
            key: PianoKey(note: .D, octave: 4),
            isPressed: true,
            showLabels: true,
            octaveNamesOnly: false,
            onPress: { true },
            onRelease: {}
        )
    }
    .frame(width: 110, height: 280)
    .padding()
    .background(PianoTheme.background)
}
