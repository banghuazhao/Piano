import StoreKit
import StoreKitTest
import XCTest
@testable import Piano

/// StoreKit test sessions share one environment; keep this suite serial.
final class PremiumStoreTests: XCTestCase {
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
    func testCancelledPurchaseLeavesPremiumLocked() async throws {
        let session = try makeSession()
        session.clearTransactions()
        let store = PremiumStore.shared
        await store.prepare()
        await waitForEntitlement(false, in: store)

        // The purchase sheet's userCancelled result needs a human UI tap;
        // simulate StoreKit's equivalent cancellation error in this unit test.
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        let result = await store.purchase()
        guard case .cancelled = result else {
            return XCTFail("Expected a cancelled purchase, received \(String(describing: result))")
        }
        XCTAssertFalse(store.isPremium)
        XCTAssertTrue(session.allTransactions().isEmpty)
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
}
