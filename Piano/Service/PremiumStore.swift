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
    @ObservationIgnored private var productLoadTask: Task<Void, Never>?
    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var hasStartedTransactionUpdates = false
    @ObservationIgnored private var transactionUpdateStartupWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var entitlementRevision = 0
    @ObservationIgnored private let productsForSale: @MainActor () async throws -> [Product]

    init(productsForSale: @escaping @MainActor () async throws -> [Product] = {
        try await Product.products(for: [PremiumStore.productID])
    }) {
        self.productsForSale = productsForSale
    }

    deinit {
        preparationTask?.cancel()
        productLoadTask?.cancel()
        transactionUpdatesTask?.cancel()
    }

    /// Start before the first view task so StoreKit can deliver transactions
    /// that were completed outside the app or left unfinished at launch.
    func startObservingTransactions() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            var iterator = Transaction.updates.makeAsyncIterator()
            self?.markTransactionUpdatesStarted()
            while let result = await iterator.next() {
                guard let self else { return }
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.productID else { continue }

                self.entitlementRevision += 1
                self.isPremium = transaction.revocationDate == nil
                self.hasDeterminedEntitlement = true
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    private func markTransactionUpdatesStarted() {
        hasStartedTransactionUpdates = true
        transactionUpdateStartupWaiters.forEach { $0.resume() }
        transactionUpdateStartupWaiters.removeAll()
    }

    private func waitForTransactionUpdatesStart() async {
        guard !hasStartedTransactionUpdates else { return }
        await withCheckedContinuation { transactionUpdateStartupWaiters.append($0) }
    }

    func prepare() async {
        // A foreground entitlement refresh can finish before app startup's
        // prepare call. Keep the transaction listener alive in either order.
        startObservingTransactions()
        await waitForTransactionUpdatesStart()
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
        guard product == nil else { return }
        if let productLoadTask {
            await productLoadTask.value
            return
        }
        isLoadingProduct = true
        productLoadError = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                self.product = try await self.productsForSale()
                    .first { $0.id == Self.productID && $0.type == .nonConsumable }
                if self.product == nil {
                    self.productLoadError = "Premium is not available in this storefront yet."
                }
            } catch {
                self.productLoadError = "Premium could not be loaded. Check your connection and try again."
            }
            self.isLoadingProduct = false
            self.productLoadTask = nil
        }
        productLoadTask = task
        await task.value
    }

    func purchase() async -> PremiumPurchaseOutcome {
        guard !isPurchasing else { return .failed("A purchase is already in progress.") }
        guard !isRestoring else { return .failed("Wait for the restore to finish before purchasing.") }
        isPurchasing = true
        defer { isPurchasing = false }

        await prepare()
        if isPremium { return .purchased }
        if product == nil { await loadProduct() }
        if isPremium { return .purchased }
        guard let product else { return .unavailable }

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
        guard !isRestoring else { return .failed("A restore is already in progress.") }
        guard !isPurchasing else { return .failed("Wait for the purchase to finish before restoring.") }
        isRestoring = true
        defer { isRestoring = false }

        await prepare()

        do {
            // This can show an App Store sign-in prompt, so only call it on a tap.
            try await AppStore.sync()
            await refreshEntitlements()
            return isPremium ? .restored : .notFound
        } catch {
            return .failed(error.localizedDescription)
        }
    }

}
