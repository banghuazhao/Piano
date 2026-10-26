import SwiftUI

/// Native control chrome on iOS 26, with an opaque accessible fallback.
private struct PianoControlSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(.regular.tint(tint).interactive(interactive),
                                in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(PianoTheme.panelRaised)
                        .overlay {
                            if let tint {
                                RoundedRectangle(cornerRadius: cornerRadius).fill(tint.opacity(0.18))
                            }
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(contrast == .increased ? PianoTheme.ivory : (tint ?? PianoTheme.divider),
                                      lineWidth: contrast == .increased ? 2 : 1)
                }
        }
    }
}

extension View {
    func pianoControlSurface(cornerRadius: CGFloat = 16, tint: Color? = nil,
                             interactive: Bool = false) -> some View {
        modifier(PianoControlSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    @ViewBuilder
    func pianoGlassContainer(spacing: CGFloat = 3) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Let the system draw Liquid Glass navigation bars on modern releases.
    @ViewBuilder
    func pianoNavigationChrome() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.toolbarBackground(PianoTheme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    func pianoPopoverSurface() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background(PianoTheme.panel)
                .presentationBackground(PianoTheme.panel)
        }
    }
}
