import Foundation

enum PianoSessionActivity {
    private static let lastPlayedKey = "lastPianoInteractionAt"
    private static let uninterruptedPracticeInterval: TimeInterval = 20 * 60

    static func markPlayed() {
        UserDefaults.standard.set(Date(), forKey: lastPlayedKey)
    }

    static var shouldDeferAppOpenAd: Bool {
        guard let lastPlayed = UserDefaults.standard.object(forKey: lastPlayedKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastPlayed) < uninterruptedPracticeInterval
    }
}
