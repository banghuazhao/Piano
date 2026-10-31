import Foundation

/// Standalone deterministic checks; no ad SDK, network, or system permission changes.
@main
struct AdConsentChecks {
    @MainActor
    static func main() async {
        await checkOrderAndLiveState()
        await checkConcurrentPreparation()
        await checkIneligibleAndInterruptedPreparation()
        await checkConsentErrors()
        await checkTrackingResponses()
        await checkPremiumChangesDuringPreparation()
        await checkRegionalTrackingRefusal()
        checkTCFParsing()
        print("Ad consent checks passed")
    }

    @MainActor
    private static func checkOrderAndLiveState() async {
        let fixture = Fixture()
        let gate = fixture.makeGate()
        expect(!gate.isReady, "Existing permission alone must not bypass consent preparation")
        let ready = await gate.prepare()
        expect(ready && gate.isReady, "Completed consent should allow advertising")
        expect(fixture.events == ["update", "form", "tracking"],
               "Regional consent must finish before the tracking request")
        _ = await gate.prepare()
        expect(fixture.events.count == 3, "Repeated preparation must not repeat consent or ATT")

        fixture.eligible = false
        expect(!gate.isReady, "Premium or inactive apps must immediately stop being ready")
        fixture.eligible = true
        fixture.adsAllowed = false
        expect(!gate.isReady, "Withdrawal of UMP permission must immediately block ads")
        fixture.adsAllowed = true
        fixture.authorization = .notDetermined
        expect(!gate.isReady, "Tracking permission must be read live, not cached")
    }

    @MainActor
    private static func checkConcurrentPreparation() async {
        let fixture = Fixture()
        let enteredUpdate = Latch()
        let finishUpdate = Latch()
        fixture.update = {
            enteredUpdate.open()
            await finishUpdate.wait()
        }
        let gate = fixture.makeGate()
        let first = Task { await gate.prepare() }
        await enteredUpdate.wait()
        let second = Task { await gate.prepare() }
        await Task.yield()
        expect(!gate.isReady && fixture.events == ["update"],
               "Ads must remain blocked while duplicate callers share an unfinished update")
        finishUpdate.open()
        let firstReady = await first.value
        let secondReady = await second.value
        expect(firstReady && secondReady, "Both callers should observe the resolved gate")
        expect(fixture.events == ["update", "form", "tracking"],
               "Concurrent preparation must not present duplicate prompts")
    }

    @MainActor
    private static func checkIneligibleAndInterruptedPreparation() async {
        let fixture = Fixture()
        fixture.eligible = false
        let gate = fixture.makeGate()
        let inactiveReady = await gate.prepare()
        expect(!inactiveReady && fixture.events.isEmpty,
               "Inactive or Premium apps must not start a privacy flow")
        fixture.eligible = true
        fixture.update = { fixture.eligible = false }
        let interruptedReady = await gate.prepare()
        expect(!interruptedReady && fixture.events == ["update"],
               "Backgrounding during consent update must defer all prompts")
        fixture.eligible = true
        let resumedReady = await gate.prepare()
        expect(resumedReady && fixture.events == ["update", "form", "tracking"],
               "Resuming should continue without another update in the same session")
    }

    @MainActor
    private static func checkConsentErrors() async {
        let cached = Fixture()
        cached.update = { throw CheckError.update }
        let cachedGate = cached.makeGate()
        let cachedReady = await cachedGate.prepare()
        expect(cachedReady && cached.events == ["update", "tracking"] && cached.errors == 1,
               "A failed update can use cached UMP permission only after resolving ATT")
        _ = await cachedGate.prepare()
        expect(cached.events == ["update", "tracking"],
               "Consent info update must be attempted once per session")

        let uncached = Fixture()
        uncached.adsAllowed = false
        uncached.update = { throw CheckError.update }
        let uncachedGate = uncached.makeGate()
        let uncachedReady = await uncachedGate.prepare()
        expect(!uncachedReady && uncached.events == ["update"],
               "An update failure without cached consent must not request tracking or ads")

        let failedForm = Fixture()
        failedForm.form = { throw CheckError.form }
        let failedFormGate = failedForm.makeGate()
        let failedReady = await failedFormGate.prepare()
        expect(!failedReady && failedForm.events == ["update", "form"],
               "A failed consent form must not fall through to ATT even with cached consent")
        failedForm.form = nil
        let retriedReady = await failedFormGate.prepare()
        expect(retriedReady && failedForm.events == ["update", "form", "form", "tracking"],
               "Failed presentation should retry without another info update")

        let declinedConsent = Fixture()
        declinedConsent.form = { declinedConsent.adsAllowed = false }
        let declinedGate = declinedConsent.makeGate()
        let declinedReady = await declinedGate.prepare()
        expect(!declinedReady && declinedConsent.events == ["update", "form"],
               "The tracking request must not follow a UMP choice that disallows ads")
    }

    @MainActor
    private static func checkTrackingResponses() async {
        for status in [AdConsentGate.TrackingAuthorization.authorized, .denied, .restricted] {
            let fixture = Fixture()
            fixture.authorization = status
            let gate = fixture.makeGate()
            let ready = await gate.prepare()
            expect(ready && fixture.events == ["update", "form"],
                   "A resolved ATT state should not show another prompt; denial supports nonpersonalized ads")
        }

        let interrupted = Fixture()
        interrupted.tracking = {} // Simulates an interrupted request that iOS leaves undetermined.
        let gate = interrupted.makeGate()
        let firstReady = await gate.prepare()
        expect(!firstReady && !gate.isReady,
               "Returning from the request is not sufficient when permission remains undetermined")
        interrupted.tracking = { interrupted.authorization = .denied }
        let retryReady = await gate.prepare()
        expect(retryReady && interrupted.events == ["update", "form", "tracking", "tracking"],
               "An interrupted ATT request should retry on a later eligible preparation")
    }

    @MainActor
    private static func checkPremiumChangesDuringPreparation() async {
        let duringForm = Fixture()
        duringForm.form = { duringForm.eligible = false }
        let formGate = duringForm.makeGate()
        let formReady = await formGate.prepare()
        expect(!formReady && duringForm.events == ["update", "form"],
               "A Premium purchase during regional consent must suppress ATT and ads")
        duringForm.eligible = true
        let returnedFreeReady = await formGate.prepare()
        expect(returnedFreeReady && duringForm.events == ["update", "form", "tracking"],
               "A later free entitlement should resume without repeating successful consent")

        let duringTracking = Fixture()
        duringTracking.tracking = {
            duringTracking.authorization = .authorized
            duringTracking.eligible = false
        }
        let trackingGate = duringTracking.makeGate()
        let trackingReady = await trackingGate.prepare()
        expect(!trackingReady && !trackingGate.isReady,
               "A Premium purchase during ATT must prevent ad readiness even after approval")
    }

    @MainActor
    private static func checkRegionalTrackingRefusal() async {
        // App Review 5.1.1(iv): "Do not consent" on the GDPR form must not be followed by ATT.
        let declined = Fixture()
        declined.form = { declined.regionalTrackingAllowed = false }
        let gate = declined.makeGate()
        let ready = await gate.prepare()
        expect(ready && declined.events == ["update", "form"],
               "A GDPR refusal must skip ATT and still allow nonpersonalized ads")
        expect(declined.authorization == .notDetermined && !gate.mayTrack,
               "A GDPR refusal must never be treated as tracking permission")
        _ = await gate.prepare()
        expect(declined.events == ["update", "form"],
               "Later preparations must keep respecting the GDPR refusal")

        let cached = Fixture()
        cached.regionalTrackingAllowed = false
        cached.update = { throw CheckError.update }
        let cachedGate = cached.makeGate()
        let cachedReady = await cachedGate.prepare()
        expect(cachedReady && cached.events == ["update"],
               "A refusal saved in an earlier session must also skip ATT")

        let authorizedThenRefused = Fixture()
        authorizedThenRefused.authorization = .authorized
        let refusedGate = authorizedThenRefused.makeGate()
        _ = await refusedGate.prepare()
        expect(refusedGate.mayTrack, "Consent plus ATT authorization permits tracking")
        authorizedThenRefused.regionalTrackingAllowed = false
        expect(refusedGate.isReady && !refusedGate.mayTrack,
               "Withdrawing regional consent must stop tracking even with ATT authorized")

        let consented = Fixture()
        let consentedGate = consented.makeGate()
        _ = await consentedGate.prepare()
        expect(consented.events == ["update", "form", "tracking"] && consentedGate.mayTrack,
               "Regional consent may be followed by Apple's tracking request")
    }

    private static func checkTCFParsing() {
        typealias C = RegionalTrackingConsent
        expect(C.allowsTracking(gdprApplies: nil, purposeConsents: nil), "No GDPR data outside the EEA")
        expect(C.allowsTracking(gdprApplies: 0, purposeConsents: "0000000000"), "GDPR does not apply")
        expect(C.allowsTracking(gdprApplies: 1, purposeConsents: "1111111111"), "Full consent")
        expect(C.allowsTracking(gdprApplies: 1, purposeConsents: "1011"), "Purposes 1, 3, 4 granted")
        expect(!C.allowsTracking(gdprApplies: 1, purposeConsents: "0000000000"), "Do not consent")
        expect(!C.allowsTracking(gdprApplies: 1, purposeConsents: ""), "Empty consent string")
        expect(!C.allowsTracking(gdprApplies: 1, purposeConsents: nil), "GDPR without a saved choice")
        expect(!C.allowsTracking(gdprApplies: 1, purposeConsents: "1100111111"), "Profile purposes refused")
        expect(!C.allowsTracking(gdprApplies: 1, purposeConsents: "101"), "Missing purpose 4")

        let suite = "PianoFlowTCFChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(C.allowsTracking(defaults: defaults), "Empty defaults allow the ATT request")
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        defaults.set("0000000000", forKey: "IABTCF_PurposeConsents")
        expect(!C.allowsTracking(defaults: defaults), "Stored GDPR refusal is read from defaults")
        defaults.set("1111111111", forKey: "IABTCF_PurposeConsents")
        expect(C.allowsTracking(defaults: defaults), "Stored GDPR consent is read from defaults")
        defaults.set("1", forKey: "IABTCF_gdprApplies")
        defaults.set("0", forKey: "IABTCF_PurposeConsents")
        expect(!C.allowsTracking(defaults: defaults), "String-typed gdprApplies is honored")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}

private enum CheckError: Error { case update, form }

@MainActor
private final class Fixture {
    var eligible = true
    var adsAllowed = true
    var regionalTrackingAllowed = true
    var authorization = AdConsentGate.TrackingAuthorization.notDetermined
    var events: [String] = []
    var errors = 0
    var update: (() async throws -> Void)?
    var form: (() async throws -> Void)?
    var tracking: (() async -> Void)?

    func makeGate() -> AdConsentGate {
        AdConsentGate(dependencies: .init(
            isEligible: { self.eligible },
            updateConsent: {
                self.events.append("update")
                try await self.update?()
            },
            presentConsent: {
                self.events.append("form")
                try await self.form?()
            },
            canRequestAds: { self.adsAllowed },
            regionalConsentAllowsTracking: { self.regionalTrackingAllowed },
            trackingAuthorization: { self.authorization },
            requestTracking: {
                self.events.append("tracking")
                if let tracking = self.tracking {
                    await tracking()
                } else {
                    self.authorization = .authorized
                }
            },
            onError: { _ in self.errors += 1 }
        ))
    }
}

@MainActor
private final class Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
