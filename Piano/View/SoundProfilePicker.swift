import SwiftUI

@MainActor
struct SoundProfilePicker: View {
    @Binding private var selection: PianoSoundProfile
    @State private var store = PremiumStore.shared
    @State private var showingPremium = false
    @State private var requestedProfile: PianoSoundProfile?

    init(selection: Binding<PianoSoundProfile>) {
        _selection = selection
    }

    var body: some View {
        SettingsPanel(
            title: "Piano sound",
            subtitle: "Find a tone that fits your playing",
            symbol: "waveform"
        ) {
            ForEach(PianoSoundProfile.allCases) { profile in
                Button {
                    select(profile)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(for: profile))
                            .font(.title3)
                            .foregroundStyle(PianoTheme.brass)
                            .frame(width: 26)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(PianoTheme.ivory)

                            Text(profile.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(PianoTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if profile.isPremium && !store.isPremium {
                            Text("PREMIUM")
                                .font(.caption2.bold())
                                .tracking(0.8)
                                .foregroundStyle(PianoTheme.brass)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(PianoTheme.brass.opacity(0.12), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: profile))
                .accessibilityAddTraits(selection == profile ? .isSelected : [])

                if profile != PianoSoundProfile.allCases.last {
                    Divider().overlay(PianoTheme.divider)
                }
            }
        }
        .sheet(isPresented: $showingPremium, onDismiss: {
            if !store.isPremium { requestedProfile = nil }
        }) {
            PremiumView(feature: .pianoSounds)
        }
        .onChange(of: store.isPremium) { _, isPremium in
            if isPremium, let requestedProfile {
                selection = requestedProfile
                self.requestedProfile = nil
            } else if !isPremium && selection.isPremium {
                selection = .concert
            }
        }
        .task {
            guard !PianoRuntimeEnvironment.isUITesting else { return }
            await store.prepare()
        }
    }

    private func select(_ profile: PianoSoundProfile) {
        if profile.isPremium && !store.isPremium {
            requestedProfile = profile
            showingPremium = true
        } else {
            requestedProfile = nil
            selection = profile
        }
    }

    private func symbol(for profile: PianoSoundProfile) -> String {
        if selection == profile { return "checkmark.circle.fill" }
        if profile.isPremium && !store.isPremium { return "lock.circle" }
        return "circle"
    }

    private func accessibilityLabel(for profile: PianoSoundProfile) -> String {
        var label = "\(profile.title). \(profile.subtitle)."
        if profile.isPremium && !store.isPremium {
            label += " Premium purchase required."
        }
        return label
    }
}
