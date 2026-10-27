import Foundation

@MainActor
enum PianoSessionActivity {
    private static let lastPlayedKey = "lastPianoInteractionAt"
    private static let uninterruptedPracticeInterval: TimeInterval = 20 * 60

    static func markPlayed() {
        PianoRuntimeEnvironment.defaults.set(Date(), forKey: lastPlayedKey)
    }

    static var shouldDeferAppOpenAd: Bool {
        guard let lastPlayed = PianoRuntimeEnvironment.defaults.object(forKey: lastPlayedKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastPlayed) < uninterruptedPracticeInterval
    }
}
