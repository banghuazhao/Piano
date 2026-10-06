import SwiftUI

@MainActor
struct PremiumSettingsSection: View {
    @State private var store = PremiumStore.shared
    @State private var showingPremium = false

    var body: some View {
        SettingsPanel(
            title: "PianoFlow Premium",
            subtitle: store.isPremium ? "Your upgrade is active" : "More sound, uninterrupted practice",
            symbol: "sparkles"
        ) {
            Button {
                showingPremium = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isPremium ? "Premium active" : "Explore Premium")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(PianoTheme.ivory)

                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(PianoTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: store.isPremium ? "checkmark.seal.fill" : "chevron.right")
                        .foregroundStyle(PianoTheme.brass)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(store.isPremium
                ? "View your Premium benefits and restore purchases"
                : "View the one-time purchase and Premium benefits")
        }
        .sheet(isPresented: $showingPremium) {
            PremiumView()
        }
        .task {
            await store.prepare()
            await store.loadProduct()
        }
    }

    private var detail: String {
        if store.isPremium { return "Ad-free playing and every piano sound" }
        if let price = store.localizedPrice { return "One-time purchase · \(price)" }
        return "Ad-free playing and two more piano sounds"
    }
}
