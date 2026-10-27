import Foundation
import SwiftUI

/// Explicit UI-test launches use their own preferences and temporary libraries.
/// Release builds and physical devices always use the normal app environment.
@MainActor
enum PianoRuntimeEnvironment {
    private static let testSessionID: String? = {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        let supplied = ProcessInfo.processInfo.environment["PIANOFLOW_UI_TEST_RUN_ID"]
        return supplied.flatMap(UUID.init(uuidString:))?.uuidString ?? UUID().uuidString
        #else
        return nil
        #endif
    }()

    static var isUITesting: Bool { testSessionID != nil }

    static let defaults: UserDefaults = {
        guard let testSessionID else { return .standard }
        guard let suite = UserDefaults(suiteName: "com.appsbay.PianoFlow.UITests.\(testSessionID)") else {
            // This can only be reached by an explicitly requested simulator test.
            preconditionFailure("Could not create the isolated UI test preferences")
        }
        return suite
    }()

    private static var testDirectory: URL? {
        testSessionID.map {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("PianoFlowUITests", isDirectory: true)
                .appendingPathComponent($0, isDirectory: true)
        }
    }

    static var performanceLibraryURL: URL? {
        testDirectory?.appendingPathComponent("performances.json")
    }

    static var importedSongsURL: URL? {
        testDirectory?.appendingPathComponent("songs.json")
    }

    static var usesLargestText: Bool {
        #if DEBUG && targetEnvironment(simulator)
        isUITesting && ProcessInfo.processInfo.environment["PIANOFLOW_UI_TEST_LARGE_TEXT"] == "1"
        #else
        false
        #endif
    }
}

extension View {
    @MainActor
    @ViewBuilder
    func pianoUITestTextSize() -> some View {
        if PianoRuntimeEnvironment.usesLargestText {
            self.dynamicTypeSize(.accessibility5)
        } else {
            self
        }
    }
}
