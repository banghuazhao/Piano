// Mac Catalyst ships without ads: the Google Mobile Ads SDK has no Mac Catalyst
// slice, so the package is linked for iOS only. See AdManagerMac.swift for the
// no-op stand-ins that keep the shared call sites unchanged.
#if !targetEnvironment(macCatalyst)
import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI
import UserMessagingPlatform

enum AdManager {
    enum GoogleAdsID {
        static let bannerViewAdUnitID = Bundle.main.object(forInfoDictionaryKey: "bannerViewAdUnitID") as? String ?? ""
        static let appOpenAdID = Bundle.main.object(forInfoDictionaryKey: "appOpenAdID") as? String ?? ""
    }
}

@MainActor
final class AdPrivacyManager: ObservableObject {
    static let shared = AdPrivacyManager()

    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var canRequestAds = false
    @Published private(set) var requestGeneration = 0

    private var didStartMobileAds = false
    private var isPresentingPrivacyOptions = false
    private var consentTask: Task<Void, Never>?
    private var observedTrackingAuthorization: AdConsentGate.TrackingAuthorization?
    private var appliedTrackingAuthorization: AdConsentGate.TrackingAuthorization?
    private var onAdsReady: (() -> Void)?

    private lazy var consentGate = AdConsentGate(dependencies: .init(
        isEligible: {
            PremiumStore.shared.hasDeterminedEntitlement
                && !PremiumStore.shared.isPremium
                && UIApplication.shared.applicationState == .active
        },
        updateConsent: {
            let parameters = RequestParameters()
            #if DEBUG
            // Lets a Debug simulator run show Google's EEA form to verify the GDPR → ATT order.
            if ProcessInfo.processInfo.environment["PIANOFLOW_UMP_DEBUG_EEA"] == "1" {
                let debugSettings = DebugSettings()
                debugSettings.geography = .EEA
                parameters.debugSettings = debugSettings
            }
            #endif
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
        },
        presentConsent: {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        },
        canRequestAds: { ConsentInformation.shared.canRequestAds },
        regionalConsentAllowsTracking: { RegionalTrackingConsent.allowsTracking() },
        trackingAuthorization: { Self.trackingAuthorization },
        requestTracking: {
            // UMP may already have presented ATT through a configured IDFA message.
            // The gate checks the current system status and the regional choice first.
            _ = await ATTrackingManager.requestTrackingAuthorization()
        },
        onError: { print("[ADS] Consent could not be completed: \($0.localizedDescription)") }
    ))

    private init() {}

    /// Every load/presentation also checks the live status, including late SDK callbacks.
    var mayRequestAds: Bool {
        canRequestAds && !isPresentingPrivacyOptions && consentGate.isReady
            && Self.trackingAuthorization == appliedTrackingAuthorization
    }

    private static var trackingAuthorization: AdConsentGate.TrackingAuthorization {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// Revoke the visible/requestable state before an asynchronous entitlement refresh.
    func refreshPermission() {
        observeTrackingAuthorization()
        if !consentGate.isReady || Self.trackingAuthorization != appliedTrackingAuthorization {
            canRequestAds = false
        }
    }

    func prepareAds(onAdsReady: @escaping () -> Void) {
        guard PremiumStore.shared.hasDeterminedEntitlement,
              !PremiumStore.shared.isPremium else { return }
        self.onAdsReady = onAdsReady
        refreshPermission()
        guard consentTask == nil, !isPresentingPrivacyOptions else { return }
        consentTask = Task {
            _ = await consentGate.prepare()
            consentTask = nil
            updateConsentState()
        }
    }

    func stopAdsForPremium() {
        canRequestAds = false
        onAdsReady = nil
    }

    func presentPrivacyOptions() {
        guard privacyOptionsRequired, !isPresentingPrivacyOptions,
              consentTask == nil, UIApplication.shared.applicationState == .active else { return }
        isPresentingPrivacyOptions = true
        canRequestAds = false
        // Previously loaded ads must not survive a change to regional privacy choices.
        requestGeneration += 1
        Task {
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            } catch {
                print("[ADS] Privacy options could not be presented: \(error.localizedDescription)")
            }
            isPresentingPrivacyOptions = false
            _ = await consentGate.prepare()
            updateConsentState()
        }
    }

    private func updatePrivacyOptionsRequirement() {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func observeTrackingAuthorization() {
        let current = Self.trackingAuthorization
        if observedTrackingAuthorization != current {
            observedTrackingAuthorization = current
            requestGeneration += 1
        }
    }

    private func updateConsentState() {
        updatePrivacyOptionsRequirement()
        observeTrackingAuthorization()
        let isAllowed = consentGate.isReady && !isPresentingPrivacyOptions
        guard isAllowed else {
            canRequestAds = false
            return
        }
        let tracking = Self.trackingAuthorization
        // ATT denial/restriction or a regional refusal never becomes an alternative
        // identifier or a personalized request. UMP restrictions still apply when allowed.
        let configuration = MobileAds.shared.requestConfiguration
        configuration.setPublisherFirstPartyIDEnabled(false)
        configuration.publisherPrivacyPersonalizationState = consentGate.mayTrack ? .default : .disabled
        appliedTrackingAuthorization = tracking
        let shouldStartMobileAds = isAllowed && !didStartMobileAds
        if shouldStartMobileAds {
            didStartMobileAds = true
            MobileAds.shared.start(completionHandler: nil)
        }
        canRequestAds = isAllowed
        let callback = onAdsReady
        onAdsReady = nil
        callback?()
    }
}

@MainActor
final class OpenAd: NSObject, ObservableObject, FullScreenContentDelegate {
    private var appOpenAd: AppOpenAd?
    private var loadTime: Date?
    private var hasEnteredBackground = false
    private var isLoading = false
    private var isShowing = false
    private var requestGeneration: Int?

    func sceneDidEnterBackground() {
        hasEnteredBackground = true
    }

    func sceneDidBecomeActive() {
        let isReturning = hasEnteredBackground
        hasEnteredBackground = false
        guard AdPrivacyManager.shared.mayRequestAds,
              !PremiumStore.shared.isPremium else { return }

        if isReturning && !PianoSessionActivity.shouldDeferAppOpenAd,
           !isShowing,
           let ad = availableAd(),
           let rootViewController = foregroundRootViewController(),
           rootViewController.presentedViewController == nil {
            isShowing = true
            ad.present(from: rootViewController)
            return
        }

        requestAppOpenAd()
    }

    func requestAppOpenAd() {
        guard AdPrivacyManager.shared.mayRequestAds,
              !PremiumStore.shared.isPremium,
              !isLoading, !isShowing else { return }
        guard availableAd() == nil else { return }
        guard !AdManager.GoogleAdsID.appOpenAdID.isEmpty else { return }

        isLoading = true
        let generation = AdPrivacyManager.shared.requestGeneration
        let request = Request()
        request.scene = foregroundWindowScene()
        AppOpenAd.load(with: AdManager.GoogleAdsID.appOpenAdID, request: request) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                guard AdPrivacyManager.shared.mayRequestAds,
                      AdPrivacyManager.shared.requestGeneration == generation,
                      !PremiumStore.shared.isPremium else { return }
                guard let ad else {
                    if let error {
                        print("[ADS] App open ad failed to load: \(error.localizedDescription)")
                    }
                    return
                }
                self.appOpenAd = ad
                self.loadTime = Date()
                self.requestGeneration = generation
                ad.fullScreenContentDelegate = self
            }
        }
    }

    private func availableAd() -> AppOpenAd? {
        guard let appOpenAd, let loadTime,
              requestGeneration == AdPrivacyManager.shared.requestGeneration,
              Date().timeIntervalSince(loadTime) >= 0,
              Date().timeIntervalSince(loadTime) < 4 * 60 * 60 else {
            self.appOpenAd = nil
            self.loadTime = nil
            return nil
        }
        return appOpenAd
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("[ADS] App open ad failed to present: \(error.localizedDescription)")
        finishPresentation()
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finishPresentation()
    }

    private func finishPresentation() {
        appOpenAd = nil
        loadTime = nil
        isShowing = false
        requestAppOpenAd()
    }

    func discardCachedAd() {
        appOpenAd = nil
        loadTime = nil
        requestGeneration = nil
    }
}

@MainActor
private func foregroundWindowScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
}

@MainActor
private func foregroundRootViewController() -> UIViewController? {
    guard let scene = foregroundWindowScene() else { return nil }
    return scene.windows.first(where: \.isKeyWindow)?.rootViewController
        ?? scene.windows.first?.rootViewController
}

struct BannerView: View {
    @State private var premium = PremiumStore.shared
    @ObservedObject private var privacy = AdPrivacyManager.shared

    var body: some View {
        if premium.hasDeterminedEntitlement && !premium.isPremium && privacy.canRequestAds {
            AdBannerControllerView()
                .id(privacy.requestGeneration)
        }
    }
}

private struct AdBannerControllerView: UIViewControllerRepresentable {
    @State private var viewWidth: CGFloat = .zero

    func makeUIViewController(context: Context) -> BannerViewController {
        let controller = BannerViewController()
        let banner = controller.bannerView
        banner.adUnitID = AdManager.GoogleAdsID.bannerViewAdUnitID
        banner.rootViewController = controller
        banner.delegate = context.coordinator
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.isHidden = true
        controller.view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor),
            banner.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
        ])
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: BannerViewController, context: Context) {
        let banner = controller.bannerView
        guard AdPrivacyManager.shared.mayRequestAds,
              context.coordinator.requestGeneration == AdPrivacyManager.shared.requestGeneration else { return }
        guard viewWidth > .zero, !AdManager.GoogleAdsID.bannerViewAdUnitID.isEmpty else { return }
        guard abs(controller.lastRequestedWidth - viewWidth) > 1 else { return }

        controller.lastRequestedWidth = viewWidth
        banner.isHidden = true
        banner.adSize = currentOrientationAnchoredAdaptiveBanner(width: viewWidth)
        let request = Request()
        request.scene = controller.view.window?.windowScene
        banner.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewControllerWidthDelegate, BannerViewDelegate {
        let parent: AdBannerControllerView
        let requestGeneration = AdPrivacyManager.shared.requestGeneration

        init(_ parent: AdBannerControllerView) {
            self.parent = parent
        }

        func bannerViewController(_ controller: BannerViewController, didUpdate width: CGFloat) {
            parent.viewWidth = width
        }

        func bannerViewDidReceiveAd(_ bannerView: GoogleMobileAds.BannerView) {
            bannerView.isHidden = !AdPrivacyManager.shared.mayRequestAds
                || requestGeneration != AdPrivacyManager.shared.requestGeneration
                || PremiumStore.shared.isPremium
        }

        func bannerView(
            _ bannerView: GoogleMobileAds.BannerView,
            didFailToReceiveAdWithError error: Error
        ) {
            bannerView.isHidden = true
            print("[ADS] Banner failed to load: \(error.localizedDescription)")
        }
    }
}

@MainActor
fileprivate protocol BannerViewControllerWidthDelegate: AnyObject {
    func bannerViewController(_ controller: BannerViewController, didUpdate width: CGFloat)
}

final class BannerViewController: UIViewController {
    let bannerView = GoogleMobileAds.BannerView()
    fileprivate var lastRequestedWidth: CGFloat = .zero
    fileprivate weak var delegate: BannerViewControllerWidthDelegate?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        notifyWidth()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { _ in self.notifyWidth() }
    }

    private func notifyWidth() {
        delegate?.bannerViewController(
            self,
            didUpdate: view.bounds.inset(by: view.safeAreaInsets).width
        )
    }
}

#endif
