//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

@main
struct PianoApp: App {
    @StateObject private var openAd = OpenAd()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PianoView()
                .onAppear {
                    AdPrivacyManager.shared.prepareAds {
                        openAd.requestAppOpenAd()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        openAd.sceneDidBecomeActive()
                    } else if newPhase == .background {
                        openAd.sceneDidEnterBackground()
                    }
                }
        }
    }
}
