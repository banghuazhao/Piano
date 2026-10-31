//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

@main
struct PianoApp: App {
    @StateObject private var openAd = OpenAd()
    @State private var premium = PremiumStore.shared
    @State private var activationTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        guard !PianoRuntimeEnvironment.isUITesting else { return }
#if DEBUG && targetEnvironment(simulator)
        // App-hosted StoreKit tests attach their local catalog during startup.
        // Let the test session bind before starting this optional early listener.
        guard ProcessInfo.processInfo.environment["PIANOFLOW_STOREKIT_TESTS"] != "1" else { return }
#endif
        PremiumStore.shared.startObservingTransactions()
    }

    var body: some Scene {
        WindowGroup {
            PianoView()
                .defaultAppStorage(PianoRuntimeEnvironment.defaults)
                .pianoUITestTextSize()
                .pianoMacWindowSizing()
                .task {
                    guard !PianoRuntimeEnvironment.isUITesting else { return }
                    await premium.prepare()
                    if scenePhase == .active && !premium.isPremium {
                        prepareAds()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        guard !PianoRuntimeEnvironment.isUITesting else { return }
                        AdPrivacyManager.shared.refreshPermission()
                        activationTask?.cancel()
                        activationTask = Task {
                            let needsRefresh = premium.hasDeterminedEntitlement
                            await premium.prepare()
                            if needsRefresh { await premium.refreshEntitlements() }
                            guard !Task.isCancelled, scenePhase == .active else { return }
                            if premium.isPremium {
                                AdPrivacyManager.shared.stopAdsForPremium()
                                openAd.discardCachedAd()
                            } else {
                                prepareAds()
                                openAd.sceneDidBecomeActive()
                            }
                        }
                    } else if newPhase == .background {
                        activationTask?.cancel()
                        activationTask = nil
                        openAd.sceneDidEnterBackground()
                    } else {
                        activationTask?.cancel()
                        activationTask = nil
                    }
                }
                .onChange(of: premium.isPremium) { _, isPremium in
                    if isPremium {
                        AdPrivacyManager.shared.stopAdsForPremium()
                        openAd.discardCachedAd()
                    } else if premium.hasDeterminedEntitlement && scenePhase == .active {
                        prepareAds()
                    }
                }
        }
    }

    private func prepareAds() {
        guard !PianoRuntimeEnvironment.isUITesting else { return }
        AdPrivacyManager.shared.prepareAds {
            openAd.requestAppOpenAd()
        }
    }
}
