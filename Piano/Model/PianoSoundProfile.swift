import Foundation

enum PianoSoundProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case concert
    case warmStudio
    case brightHall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concert: "Concert Grand"
        case .warmStudio: "Warm Studio"
        case .brightHall: "Bright Hall"
        }
    }

    var subtitle: String {
        switch self {
        case .concert: "Balanced, natural piano tone"
        case .warmStudio: "Round lows with a close, intimate room"
        case .brightHall: "Clear highs with a spacious hall"
        }
    }

    var isPremium: Bool { self != .concert }

    // These values are shared by live playback and offline audio export.
    var lowShelfGainDB: Float {
        switch self {
        case .concert: 0
        case .warmStudio: 3
        case .brightHall: -1
        }
    }

    var highShelfGainDB: Float {
        switch self {
        case .concert: 0
        case .warmStudio: -2.5
        case .brightHall: 3
        }
    }

    var reverbWetDryMix: Float {
        switch self {
        case .concert: 8
        case .warmStudio: 5
        case .brightHall: 22
        }
    }
}
