import SwiftUI

@MainActor
struct PremiumView: View {
    @State private var store = PremiumStore.shared
    @State private var feedbackMessage = ""
    @State private var showingFeedback = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "pianokeys")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(PianoTheme.brass)
                            .accessibilityHidden(true)

                        Text("Your piano, without limits")
                            .font(.largeTitle.bold())
                            .foregroundStyle(PianoTheme.ivory)

                        Text("Make every practice session uninterrupted and shape the sound to suit the room.")
                            .font(.body)
                            .foregroundStyle(PianoTheme.secondary)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        benefit("Play without ads", symbol: "sparkles", detail: "An uninterrupted instrument every time you return.")
                        benefit("Warm Studio", symbol: "waveform", detail: "A close, mellow piano with rounded lows.")
                        benefit("Bright Hall", symbol: "music.note.house", detail: "A clear, spacious piano for expressive playing.")
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 22))

                    if store.isPremium {
                        Label("Premium is active", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(PianoTheme.brass)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    } else {
                        purchaseControls
                    }

                    Button {
                        Task { await restore() }
                    } label: {
                        if store.isRestoring {
                            ProgressView("Restoring purchases")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        } else {
                            Text("Restore purchases")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                    .disabled(store.isRestoring || store.isPurchasing)
                    .buttonStyle(.plain)
                    .foregroundStyle(PianoTheme.secondary)
                    .accessibilityHint("Checks your App Store account for a previous Premium purchase")

                    Text("One purchase. No subscription. Your existing piano, metronome, and recording tools stay free.")
                        .font(.footnote)
                        .foregroundStyle(PianoTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .background(PianoTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .alert("PianoFlow Premium", isPresented: $showingFeedback) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(feedbackMessage)
            }
        }
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .task {
            await store.prepare()
            await store.loadProduct()
        }
    }

    @ViewBuilder
    private var purchaseControls: some View {
        if let price = store.localizedPrice {
            Button {
                Task { await purchase() }
            } label: {
                if store.isPurchasing {
                    ProgressView("Completing purchase")
                        .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    Text("Unlock Premium · \(price)")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
            }
            .disabled(store.isPurchasing || store.isRestoring)
            .buttonStyle(.borderedProminent)
            .tint(PianoTheme.brass)
            .foregroundStyle(PianoTheme.background)
            .accessibilityHint("A one-time purchase through the App Store")
        } else if store.isLoadingProduct {
            ProgressView("Checking availability")
                .frame(maxWidth: .infinity, minHeight: 56)
        } else {
            VStack(spacing: 10) {
                Text(store.productLoadError ?? "Checking Premium availability")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .multilineTextAlignment(.center)

                Button("Try again") {
                    Task { await store.loadProduct() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func benefit(_ title: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(PianoTheme.brass)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PianoTheme.ivory)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
            }
        }
    }

    private func purchase() async {
        switch await store.purchase() {
        case .purchased:
            showFeedback("Premium is ready. Enjoy ad-free playing and the new sound profiles.")
        case .pending:
            showFeedback("Your purchase is pending approval. Premium will unlock automatically when the App Store confirms it.")
        case .cancelled:
            break
        case .unavailable:
            showFeedback(store.productLoadError ?? "Premium is temporarily unavailable. Please try again later.")
        case .unverified:
            showFeedback("The App Store could not verify this purchase. No Premium access was granted.")
        case .failed(let message):
            showFeedback("The purchase could not be completed. \(message)")
        }
    }

    private func restore() async {
        switch await store.restorePurchases() {
        case .restored:
            showFeedback("Your Premium purchase has been restored.")
        case .notFound:
            showFeedback("No Premium purchase was found for this App Store account.")
        case .failed(let message):
            showFeedback("Purchases could not be restored. \(message)")
        }
    }

    private func showFeedback(_ message: String) {
        feedbackMessage = message
        showingFeedback = true
    }
}
