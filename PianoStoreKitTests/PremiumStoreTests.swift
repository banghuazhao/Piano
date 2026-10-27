import StoreKit
import StoreKitTest
import XCTest
@testable import Piano

/// StoreKit test sessions share one environment; keep this suite serial.
final class PremiumStoreTests: XCTestCase {
    @MainActor
    func testPrepareObservesTransactionsAfterEarlyEntitlementRefresh() async throws {
        let session = try makeSession()
        session.clearTransactions()
        let store = PremiumStore()
        await store.refreshEntitlements()
        XCTAssertTrue(store.hasDeterminedEntitlement)
        store.startObservingTransactions()
        store.startObservingTransactions()
        await store.prepare()

        _ = try await session.buyProduct(identifier: PremiumStore.productID)
        await waitForObservedEntitlement(true, in: store)
        let transaction = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == PremiumStore.productID
        })
        try session.refundTransaction(identifier: transaction.identifier)
        await waitForObservedEntitlement(false, in: store)
    }

    @MainActor
    func testPurchaseUnlocksPremiumAndRefundRevokesIt() async throws {
        let session = try makeSession()
        session.clearTransactions()
        let store = PremiumStore.shared
        await store.prepare()
        await waitForEntitlement(false, in: store)

        await store.loadProduct()
        XCTAssertNotNil(store.localizedPrice, "The StoreKit product should supply a localized price")
        let result = await store.purchase()
        guard case .purchased = result else {
            return XCTFail("Expected a verified purchase, received \(String(describing: result))")
        }
        await waitForEntitlement(true, in: store)

        let transaction = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == PremiumStore.productID }
        )
        try session.refundTransaction(identifier: transaction.identifier)
        await waitForEntitlement(false, in: store)
    }

    @MainActor
    func testRestoreFindsPurchaseMadeOutsideApp() async throws {
        let session = try makeSession()
        session.clearTransactions()
        let store = PremiumStore.shared
        await store.prepare()
        await waitForEntitlement(false, in: store)

        _ = try await session.buyProduct(identifier: PremiumStore.productID)
        let result = await store.restorePurchases()
        guard case .restored = result else {
            return XCTFail("Expected restore to find the verified purchase, received \(String(describing: result))")
        }
        await waitForEntitlement(true, in: store)
    }

    @MainActor
    func testAskToBuyStaysLockedUntilApproval() async throws {
        let session = try makeSession()
        session.clearTransactions()
        session.askToBuyEnabled = true
        let store = PremiumStore.shared
        await store.prepare()
        await waitForEntitlement(false, in: store)

        let result = await store.purchase()
        guard case .pending = result else {
            return XCTFail("Expected an Ask to Buy purchase to be pending, received \(String(describing: result))")
        }
        XCTAssertFalse(store.isPremium, "Pending transactions must not unlock Premium")

        let transaction = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == PremiumStore.productID }
        )
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        await waitForEntitlement(true, in: store)
    }

    @MainActor
    func testSimulatedPurchaseFailureLeavesPremiumLocked() async throws {
        let session = try makeSession()
        session.clearTransactions()
        let store = PremiumStore.shared
        await store.prepare()
        await waitForEntitlement(false, in: store)

        // A failed StoreKit request must not grant an entitlement. Canceling
        // the purchase sheet is covered manually because it returns a distinct
        // PurchaseResult.userCancelled value.
        try await session.setSimulatedError(.generic(.unknown), forAPI: .purchase)
        let result = await store.purchase()
        guard case .failed = result else {
            return XCTFail("Expected a failed purchase, received \(String(describing: result))")
        }
        XCTAssertFalse(store.isPremium)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    @MainActor
    func testConcurrentProductLoadAndPurchaseShareOneRequest() async throws {
        let session = try makeSession()
        session.clearTransactions()
        let gate = ProductLoadGate()
        let store = PremiumStore(productsForSale: {
            await gate.waitUntilReleased()
            return try await Product.products(for: [PremiumStore.productID])
        })
        await store.prepare()
        XCTAssertFalse(store.isPremium)

        let initialLoad = Task { await store.loadProduct() }
        await gate.waitUntilStarted()
        XCTAssertTrue(store.isLoadingProduct)

        let purchaseTask = Task { await store.purchase() }
        for _ in 0..<100 {
            if store.isPurchasing { break }
            await Task.yield()
        }
        guard store.isPurchasing else {
            gate.release()
            await initialLoad.value
            _ = await purchaseTask.value
            return XCTFail("Purchase should claim the operation before waiting for StoreKit")
        }

        let duplicatePurchase = await store.purchase()
        let overlappingRestore = await store.restorePurchases()

        gate.release()
        await initialLoad.value
        let result = await purchaseTask.value
        guard case .failed = duplicatePurchase else {
            return XCTFail("A second purchase must not start while the first is in progress")
        }
        guard case .failed = overlappingRestore else {
            return XCTFail("Restore must not start while a purchase is in progress")
        }
        guard case .purchased = result else {
            return XCTFail("A purchase sharing a product load should succeed, received \(String(describing: result))")
        }
        XCTAssertEqual(gate.callCount, 1, "Concurrent callers should share one product request")
        XCTAssertNotNil(store.localizedPrice)
        XCTAssertTrue(store.isPremium)
    }

    @MainActor
    func testVerifiedPremiumTransactionControlsAdvancedRecordingTools() async throws {
        let session = try makeSession()
        session.clearTransactions()
        let store = PremiumStore()
        await store.prepare()
        await waitForEntitlement(false, in: store)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PianoFlowPremiumGate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let studio = PerformanceStudio(
            libraryURL: directory.appendingPathComponent("performances.json"),
            hasPremiumAccess: { store.isPremium }
        )
        let take = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 0.6,
            events: [
                PerformanceEvent(note: 60, time: 0.05, isNoteOn: true, velocity: 80),
                PerformanceEvent(note: 60, time: 0.35, isNoteOn: false)
            ]
        )
        XCTAssertTrue(take.isValid)
        let advanced = PerformancePlaybackOptions(rate: 1.5)

        studio.play(take, options: advanced, noteOn: { _, _ in },
                    noteOff: { _ in }, sustain: { _ in })
        XCTAssertNil(studio.playingTakeID, "Free users must not start speed-controlled playback")
        XCTAssertNil(studio.saveExcerpt(of: take, from: 0, to: 0.5),
                     "Free users must not save a selected section")
        XCTAssertTrue(studio.takes.isEmpty)

        let purchase = await store.purchase()
        guard case .purchased = purchase else {
            return XCTFail("Expected verified Premium purchase, received \(String(describing: purchase))")
        }
        await waitForEntitlement(true, in: store)
        studio.lastError = nil
        studio.play(take, options: advanced, noteOn: { _, _ in },
                    noteOff: { _ in }, sustain: { _ in })
        XCTAssertEqual(studio.playingTakeID, take.id,
                       "Verified Premium should permit advanced playback")
        studio.stopPlayback()
        let savedSection = studio.saveExcerpt(of: take, from: 0, to: 0.5)
        XCTAssertNotNil(savedSection, "Verified Premium should permit section saving")
        XCTAssertEqual(studio.takes.count, 1)

        let transaction = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == PremiumStore.productID
        })
        try session.refundTransaction(identifier: transaction.identifier)
        await waitForEntitlement(false, in: store)
        studio.lastError = nil
        studio.play(take, options: advanced, noteOn: { _, _ in },
                    noteOff: { _ in }, sustain: { _ in })
        XCTAssertNil(studio.playingTakeID, "Refund must relock advanced playback")
        XCTAssertNil(studio.saveExcerpt(of: take, from: 0, to: 0.5),
                     "Refund must relock new section saves")
        XCTAssertEqual(studio.takes.count, 1,
                       "Refund must not remove a section saved while Premium was active")
    }

    private func makeSession() throws -> SKTestSession {
        let configuration = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "PianoFlow", withExtension: "storekit"),
            "The local StoreKit configuration must be copied into the test bundle"
        )
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        return session
    }

    @MainActor
    private func waitForEntitlement(_ expected: Bool, in store: PremiumStore) async {
        for _ in 0..<30 {
            await store.refreshEntitlements()
            if store.isPremium == expected { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Expected isPremium = \(expected), got \(store.isPremium)")
    }

    @MainActor
    private func waitForObservedEntitlement(_ expected: Bool, in store: PremiumStore) async {
        // Intentionally avoid refreshEntitlements: this checks the updates listener.
        for _ in 0..<80 {
            if store.isPremium == expected { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Transaction listener did not update isPremium to \(expected)")
    }
}

@MainActor
private final class ProductLoadGate {
    private var hasStarted = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var callCount = 0

    func waitUntilReleased() async {
        callCount += 1
        hasStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        isReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
