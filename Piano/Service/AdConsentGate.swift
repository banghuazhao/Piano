import Foundation

/// Serializes regional consent and Apple's tracking permission before advertising starts.
/// Permission is always read from its provider, never copied into persistent app storage.
@MainActor
final class AdConsentGate {
    enum TrackingAuthorization: Equatable {
        case notDetermined
        case restricted
        case denied
        case authorized
    }

    struct Dependencies {
        var isEligible: @MainActor () -> Bool
        var updateConsent: @MainActor () async throws -> Void
        var presentConsent: @MainActor () async throws -> Void
        var canRequestAds: @MainActor () -> Bool
        /// False when the user declined tracking-related purposes on a regional (GDPR) form.
        /// Apple's tracking request is then never shown in the same flow.
        var regionalConsentAllowsTracking: @MainActor () -> Bool
        var trackingAuthorization: @MainActor () -> TrackingAuthorization
        var requestTracking: @MainActor () async -> Void
        var onError: @MainActor (Error) -> Void
    }

    private let dependencies: Dependencies
    private var preparationTask: Task<Void, Never>?
    private var didAttemptConsentUpdate = false
    private var didUpdateConsent = false
    private var didCompleteConsentForm = false
    private var didResolvePreparation = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Denial and restrictions permit the caller to configure nonpersonalized ads.
    /// A regional refusal to tracking also permits only nonpersonalized ads, without ATT.
    /// An unanswered or interrupted tracking request never permits advertising.
    var isReady: Bool {
        preparationTask == nil
            && didResolvePreparation
            && dependencies.isEligible()
            && dependencies.canRequestAds()
            && isTrackingResolved
    }

    /// Tracking is allowed only when the regional choice permits it and ATT is authorized.
    var mayTrack: Bool {
        dependencies.regionalConsentAllowsTracking()
            && dependencies.trackingAuthorization() == .authorized
    }

    private var isTrackingResolved: Bool {
        dependencies.trackingAuthorization() != .notDetermined
            || !dependencies.regionalConsentAllowsTracking()
    }

    func prepare() async -> Bool {
        if let preparationTask {
            await preparationTask.value
            return isReady
        }
        if isReady { return true }

        let task = Task { [self] in
            await resolvePreparation()
            preparationTask = nil
        }
        preparationTask = task
        await task.value
        return isReady
    }

    private func resolvePreparation() async {
        didResolvePreparation = false
        guard dependencies.isEligible() else { return }

        if !didAttemptConsentUpdate {
            didAttemptConsentUpdate = true
            do {
                try await dependencies.updateConsent()
                didUpdateConsent = true
            } catch {
                // UMP can allow ads using valid consent from a previous session.
                dependencies.onError(error)
            }
            guard dependencies.isEligible() else { return }
        }

        if didUpdateConsent && !didCompleteConsentForm {
            do {
                try await dependencies.presentConsent()
                didCompleteConsentForm = true
            } catch {
                dependencies.onError(error)
                // Retry a failed presentation on the next eligible preparation.
                return
            }
            guard dependencies.isEligible() else { return }
        }

        guard dependencies.isEligible(), dependencies.canRequestAds() else { return }
        // A user who refused tracking on the regional form is not asked again by ATT.
        if dependencies.trackingAuthorization() == .notDetermined,
           dependencies.regionalConsentAllowsTracking() {
            await dependencies.requestTracking()
            guard dependencies.isEligible() else { return }
        }

        // iOS can leave permission undetermined when a request is interrupted or
        // another system prompt is visible. A later foreground attempt retries it.
        didResolvePreparation = dependencies.canRequestAds() && isTrackingResolved
    }
}

/// Reads the IAB TCF v2 values that Google's consent form stores in UserDefaults.
enum RegionalTrackingConsent {
    /// Store/access device information, create a personalized ads profile, and use it.
    static let trackingPurposes = [1, 3, 4]

    static func allowsTracking(gdprApplies: Int?, purposeConsents: String?) -> Bool {
        guard gdprApplies == 1 else { return true }
        guard let purposeConsents else { return false }
        let consents = Array(purposeConsents)
        return trackingPurposes.allSatisfy { $0 <= consents.count && consents[$0 - 1] == "1" }
    }

    static func allowsTracking(defaults: UserDefaults = .standard) -> Bool {
        let applies = defaults.object(forKey: "IABTCF_gdprApplies")
        let gdprApplies = (applies as? NSNumber)?.intValue ?? (applies as? String).flatMap { Int($0) }
        return allowsTracking(
            gdprApplies: gdprApplies,
            purposeConsents: defaults.string(forKey: "IABTCF_PurposeConsents")
        )
    }
}
