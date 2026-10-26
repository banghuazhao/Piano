//
// Created by Banghua Zhao on 12/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//
import SwiftUI

@MainActor
struct SettingsView: View {
    var midi: MIDIInputService = MIDIInputService()
    @AppStorage("showKeyDisplayNames") private var showKeyDisplayNames = true
    @AppStorage("showFirstKeyNameForOctavesOnly") private var showFirstKeyNameForOctavesOnly = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = false
    @AppStorage("keyWidth") private var keyWidth = 50.0
    @AppStorage("masterVolume") private var masterVolume = 0.85
    @AppStorage("soundProfile") private var soundProfileRaw = PianoSoundProfile.concert.rawValue
    @ObservedObject private var privacy = AdPrivacyManager.shared

    @Environment(\.dismiss) private var dismiss
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsHeaderView()

                    PremiumSettingsSection()

                    SoundProfilePicker(selection: Binding(
                        get: { PianoSoundProfile(rawValue: soundProfileRaw) ?? .concert },
                        set: { soundProfileRaw = $0.rawValue }
                    ))

                    MIDISettingsSection(midi: midi)

                    SettingsPanel(title: "Keyboard", subtitle: "Make every note easy to find", symbol: "pianokeys") {
                        SettingsToggleRow(
                            title: "Key labels",
                            subtitle: "Show note names on the keys",
                            symbol: "textformat",
                            isOn: $showKeyDisplayNames
                        )

                        if showKeyDisplayNames {
                            Divider().overlay(PianoTheme.divider)
                            SettingsToggleRow(
                                title: "Octave labels only",
                                subtitle: "Keep only the first note of each octave labeled",
                                symbol: "number",
                                isOn: $showFirstKeyNameForOctavesOnly
                            )
                        }

                        Divider().overlay(PianoTheme.divider)
                        SettingsKeyWidthControl(keyWidth: $keyWidth)
                    }

                    SettingsPanel(title: "Playing feel", subtitle: "Shape your sound and touch", symbol: "hand.tap") {
                        SettingsToggleRow(
                            title: "Touch feedback",
                            subtitle: "Feel a gentle response with each note",
                            symbol: "waveform.path",
                            isOn: $hapticsEnabled
                        )

                        Divider().overlay(PianoTheme.divider)
                        SettingsPianoVolumeControl(volume: $masterVolume)
                    }

                    if privacy.privacyOptionsRequired {
                        SettingsPanel(title: "Privacy", subtitle: "Manage your ad privacy choices", symbol: "hand.raised") {
                            Button {
                                privacy.presentPrivacyOptions()
                            } label: {
                                Label("Privacy choices", systemImage: "slider.horizontal.3")
                                    .font(.body)
                                    .foregroundStyle(PianoTheme.ivory)
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Review and change your advertising privacy choices")
                        }
                    }

                    Button("Restore default settings", systemImage: "arrow.counterclockwise") {
                        showingResetConfirmation = true
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(PianoTheme.secondary)
                    .accessibilityHint("Resets key labels, key width, touch feedback, piano sound, and piano volume")
                }
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .background(PianoTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .pianoNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PIANO SETTINGS")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(PianoTheme.secondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                        .bold()
                }
            }
            .confirmationDialog(
                "Restore default settings?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore Defaults", role: .destructive, action: restoreDefaults)
            } message: {
                Text("Your keyboard preferences will return to their original values.")
            }
        }
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    private func restoreDefaults() {
        showKeyDisplayNames = true
        showFirstKeyNameForOctavesOnly = false
        hapticsEnabled = false
        keyWidth = 50
        masterVolume = 0.85
        soundProfileRaw = PianoSoundProfile.concert.rawValue
    }
}

#Preview {
    SettingsView()
}
