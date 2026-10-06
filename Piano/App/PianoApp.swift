//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

@main
struct PianoApp: App {
    @StateObject private var openAd = OpenAd()
    @State private var premium = PremiumStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PianoView()
                .task {
                    await premium.prepare()
                    if !premium.isPremium {
                        prepareAds()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await premium.refreshEntitlements()
                            guard scenePhase == .active else { return }
                            if premium.isPremium {
                                AdPrivacyManager.shared.stopAdsForPremium()
                                openAd.discardCachedAd()
                            } else {
                                prepareAds()
                                openAd.sceneDidBecomeActive()
                            }
                        }
                    } else if newPhase == .background {
                        openAd.sceneDidEnterBackground()
                    }
                }
                .onChange(of: premium.isPremium) { _, isPremium in
                    if isPremium {
                        AdPrivacyManager.shared.stopAdsForPremium()
                        openAd.discardCachedAd()
                    } else if premium.hasDeterminedEntitlement {
                        prepareAds()
                    }
                }
        }
    }

    private func prepareAds() {
        AdPrivacyManager.shared.prepareAds {
            openAd.requestAppOpenAd()
        }
    }
}
