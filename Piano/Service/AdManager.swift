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

    private var didRequestConsent = false
    private var hasResolvedConsent = false
    private var didStartMobileAds = false
    private var isPresentingPrivacyOptions = false
    private var onAdsReady: (() -> Void)?

    private init() {}

    func prepareAds(onAdsReady: @escaping () -> Void) {
        guard PremiumStore.shared.hasDeterminedEntitlement,
              !PremiumStore.shared.isPremium else { return }
        if didStartMobileAds {
            canRequestAds = ConsentInformation.shared.canRequestAds
            if canRequestAds { onAdsReady() }
            return
        }

        self.onAdsReady = onAdsReady
        if hasResolvedConsent {
            updateConsentState()
            return
        }
        guard !didRequestConsent else { return }
        didRequestConsent = true

        Task {
            do {
                // UMP must update its status at least once in every app session.
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
                updatePrivacyOptionsRequirement()
                if !PremiumStore.shared.isPremium {
                    try await ConsentForm.loadAndPresentIfRequired(from: nil)
                }
            } catch {
                // UMP may still permit requests using consent from a previous session.
                print("[ADS] Consent update failed: \(error.localizedDescription)")
            }
            hasResolvedConsent = true
            updateConsentState()
        }
    }

    func stopAdsForPremium() {
        canRequestAds = false
        onAdsReady = nil
    }

    func presentPrivacyOptions() {
        guard privacyOptionsRequired, !isPresentingPrivacyOptions else { return }
        isPresentingPrivacyOptions = true
        Task {
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            } catch {
                print("[ADS] Privacy options could not be presented: \(error.localizedDescription)")
            }
            isPresentingPrivacyOptions = false
            updateConsentState()
        }
    }

    private func updatePrivacyOptionsRequirement() {
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func updateConsentState() {
        updatePrivacyOptionsRequirement()
        let isAllowed = PremiumStore.shared.hasDeterminedEntitlement
            && !PremiumStore.shared.isPremium
            && ConsentInformation.shared.canRequestAds
        let shouldStartMobileAds = isAllowed && !didStartMobileAds
        if shouldStartMobileAds {
            didStartMobileAds = true
            MobileAds.shared.start(completionHandler: nil)
        }
        canRequestAds = isAllowed
        guard shouldStartMobileAds else { return }
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

    func sceneDidEnterBackground() {
        hasEnteredBackground = true
    }

    func sceneDidBecomeActive() {
        let isReturning = hasEnteredBackground
        hasEnteredBackground = false
        guard AdPrivacyManager.shared.canRequestAds,
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
        guard AdPrivacyManager.shared.canRequestAds,
              !PremiumStore.shared.isPremium,
              !isLoading, !isShowing else { return }
        guard availableAd() == nil else { return }
        guard !AdManager.GoogleAdsID.appOpenAdID.isEmpty else { return }

        isLoading = true
        let request = Request()
        request.scene = foregroundWindowScene()
        AppOpenAd.load(with: AdManager.GoogleAdsID.appOpenAdID, request: request) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                guard !PremiumStore.shared.isPremium else { return }
                guard let ad else {
                    if let error {
                        print("[ADS] App open ad failed to load: \(error.localizedDescription)")
                    }
                    return
                }
                self.appOpenAd = ad
                self.loadTime = Date()
                ad.fullScreenContentDelegate = self
            }
        }
    }

    private func availableAd() -> AppOpenAd? {
        guard let appOpenAd, let loadTime,
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

    final class Coordinator: NSObject, BannerViewControllerWidthDelegate, BannerViewDelegate {
        let parent: AdBannerControllerView

        init(_ parent: AdBannerControllerView) {
            self.parent = parent
        }

        func bannerViewController(_ controller: BannerViewController, didUpdate width: CGFloat) {
            parent.viewWidth = width
        }

        func bannerViewDidReceiveAd(_ bannerView: GoogleMobileAds.BannerView) {
            bannerView.isHidden = !AdPrivacyManager.shared.canRequestAds
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
