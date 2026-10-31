//
// Created by Banghua Zhao on 01/11/2026
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit

enum MacWindow {
    /// The toolbar, range controls, and a playable span of keys need this much room
    /// before anything clips. macOS remembers the window size the player chooses above it.
    static let minimumSize = CGSize(width: 960, height: 600)

    @MainActor
    static func applySizeRestrictions() {
        for scene in UIApplication.shared.connectedScenes {
            guard let restrictions = (scene as? UIWindowScene)?.sizeRestrictions else { continue }
            restrictions.minimumSize = minimumSize
            restrictions.maximumSize = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }
}
#endif

extension View {
    /// A Mac Catalyst window is freely resizable by default. Give it a floor so the
    /// keyboard stays playable. Does nothing on iOS and iPadOS.
    @MainActor
    func pianoMacWindowSizing() -> some View {
        #if targetEnvironment(macCatalyst)
        onAppear(perform: MacWindow.applySizeRestrictions)
        #else
        self
        #endif
    }
}
