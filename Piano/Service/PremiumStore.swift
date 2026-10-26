import Observation
import StoreKit

enum PremiumPurchaseOutcome {
    case purchased
    case pending
    case cancelled
    case unavailable
    case unverified
    case failed(String)
}

enum PremiumRestoreOutcome {
    case restored
    case notFound
    case failed(String)
}

@MainActor
@Observable
final class PremiumStore {
    static let shared = PremiumStore()
    static let productID = "com.appsbay.PianoFlow.premium"

    private(set) var isPremium = false
    private(set) var hasDeterminedEntitlement = false
    private(set) var product: Product?
    private(set) var isLoadingProduct = false
    private(set) var productLoadError: String?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false

    var localizedPrice: String? { product?.displayPrice }

    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var entitlementRevision = 0

    init() {}

    deinit {
        preparationTask?.cancel()
        transactionUpdatesTask?.cancel()
    }

    func prepare() async {
        // A foreground entitlement refresh can finish before app startup's
        // prepare call. Keep the transaction listener alive in either order.
        listenForTransactionUpdates()
        if hasDeterminedEntitlement { return }
        if let preparationTask {
            await preparationTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.refreshEntitlements()
        }
        preparationTask = task
        await task.value
        preparationTask = nil
    }

    func refreshEntitlements() async {
        let revisionAtStart = entitlementRevision
        var hasVerifiedPurchase = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            hasVerifiedPurchase = true
        }

        // A purchase or revocation may arrive while this sequence is suspended.
        guard !Task.isCancelled, revisionAtStart == entitlementRevision else { return }
        isPremium = hasVerifiedPurchase
        hasDeterminedEntitlement = true
    }

    func loadProduct() async {
        guard product == nil, !isLoadingProduct else { return }
        isLoadingProduct = true
        productLoadError = nil
        defer { isLoadingProduct = false }

        do {
            product = try await Product.products(for: [Self.productID])
                .first { $0.id == Self.productID && $0.type == .nonConsumable }
            if product == nil {
                productLoadError = "Premium is not available in this storefront yet."
            }
        } catch {
            productLoadError = "Premium could not be loaded. Check your connection and try again."
        }
    }

    func purchase() async -> PremiumPurchaseOutcome {
        await prepare()
        if isPremium { return .purchased }
        guard !isPurchasing else { return .pending }
        if product == nil { await loadProduct() }
        guard let product else { return .unavailable }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else { return .unverified }
                guard transaction.productID == Self.productID,
                      transaction.revocationDate == nil else { return .unverified }

                // Grant access from the signed transaction, then acknowledge delivery.
                entitlementRevision += 1
                isPremium = true
                hasDeterminedEntitlement = true
                await transaction.finish()
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed("The App Store returned an unknown purchase state.")
            }
        } catch StoreKitError.userCancelled {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func restorePurchases() async -> PremiumRestoreOutcome {
        await prepare()
        guard !isRestoring else { return .failed("A restore is already in progress.") }
        isRestoring = true
        defer { isRestoring = false }

        do {
            // This can show an App Store sign-in prompt, so only call it on a tap.
            try await AppStore.sync()
            await refreshEntitlements()
            return isPremium ? .restored : .notFound
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func listenForTransactionUpdates() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.productID else { continue }

                // StoreKit sends refunds and purchases made on another device here.
                self.entitlementRevision += 1
                self.isPremium = transaction.revocationDate == nil
                self.hasDeterminedEntitlement = true
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }
}
