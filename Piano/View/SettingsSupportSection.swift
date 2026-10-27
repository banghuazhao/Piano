import SwiftUI

@MainActor
struct SettingsSupportSection: View {
    @Environment(\.openURL) private var openURL
    @State private var showingEmailFallback = false

    var body: some View {
        SettingsPanel(
            title: "Support & privacy",
            subtitle: "Helpful links and app details",
            symbol: "questionmark.circle"
        ) {
            Link(destination: AppSupportInformation.privacyPolicyURL) {
                HStack(spacing: 12) {
                    Label("Privacy policy", systemImage: "hand.raised")
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(PianoTheme.brass)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(PianoTheme.ivory)
            .accessibilityHint("Opens the PianoFlow privacy policy in your browser")
            .accessibilityIdentifier("settings.privacyPolicy")

            Divider().overlay(PianoTheme.divider)

            Button(action: openSupportEmail) {
                HStack(spacing: 12) {
                    Label("Contact support", systemImage: "envelope")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(PianoTheme.brass)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(PianoTheme.ivory)
            .accessibilityHint("Opens a mail draft addressed to PianoFlow support")
            .accessibilityIdentifier("settings.contactSupport")

            Divider().overlay(PianoTheme.divider)

            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App version")
                        .foregroundStyle(PianoTheme.ivory)
                    Text(AppSupportInformation.versionText())
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(PianoTheme.ivory)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.vertical, 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("App version, \(AppSupportInformation.versionText())")
            .accessibilityIdentifier("settings.appVersion")
        }
        .font(.body)
        .sheet(isPresented: $showingEmailFallback) {
            fallbackSheet
        }
    }

    private var fallbackSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("No mail app is available")
                        .font(.title3.bold())
                        .foregroundStyle(PianoTheme.ivory)
                    Text("You can contact PianoFlow support from any mail app at:")
                        .foregroundStyle(PianoTheme.secondary)
                    Text(AppSupportInformation.supportEmail)
                        .font(.body.monospaced())
                        .foregroundStyle(PianoTheme.ivory)
                        .textSelection(.enabled)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("settings.supportEmail")
                    Text("Include \(AppSupportInformation.versionText()) if you are reporting a problem.")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(PianoTheme.background.ignoresSafeArea())
            .navigationTitle("Contact support")
            .navigationBarTitleDisplayMode(.inline)
            .pianoNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingEmailFallback = false }
                }
            }
        }
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .pianoUITestTextSize()
    }

    private func openSupportEmail() {
        guard let url = AppSupportInformation.supportEmailURL() else {
            showingEmailFallback = true
            return
        }
        openURL(url) { accepted in
            guard !accepted else { return }
            Task { @MainActor in showingEmailFallback = true }
        }
    }
}
