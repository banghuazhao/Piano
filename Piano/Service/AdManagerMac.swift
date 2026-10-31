//
// Created by Banghua Zhao on 01/11/2026
// Copyright Apps Bay Limited. All rights reserved.
//

// The Mac Catalyst build is ad-free. The Google Mobile Ads SDK publishes no Mac
// Catalyst slice, so its package is linked for iOS only and these stand-ins keep
// the shared SwiftUI call sites compiling without conditional code of their own.
#if targetEnvironment(macCatalyst)
import SwiftUI

@MainActor
final class AdPrivacyManager: ObservableObject {
    static let shared = AdPrivacyManager()

    /// No ad consent is collected on the Mac, so no privacy options are offered.
    let privacyOptionsRequired = false
    let canRequestAds = false
    let requestGeneration = 0

    private init() {}

    var mayRequestAds: Bool { false }

    func refreshPermission() {}

    func prepareAds(onAdsReady: @escaping () -> Void) {}

    func stopAdsForPremium() {}

    func presentPrivacyOptions() {}
}

@MainActor
final class OpenAd: ObservableObject {
    func sceneDidEnterBackground() {}

    func sceneDidBecomeActive() {}

    func requestAppOpenAd() {}

    func discardCachedAd() {}
}

struct BannerView: View {
    var body: some View { EmptyView() }
}
#endif
