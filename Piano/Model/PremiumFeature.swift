import Foundation

/// The benefits delivered by the single non-consumable Premium purchase.
enum PremiumFeature: String, CaseIterable, Identifiable, Sendable {
    case adFree
    case pianoSounds
    case recordingStudio
    case losslessExport

    var id: String { rawValue }

    /// The Mac Catalyst build ships without ads, so it never advertises the ad-free
    /// benefit. Everything else is unlocked by the same shared purchase.
    static var purchasable: [PremiumFeature] {
        #if targetEnvironment(macCatalyst)
        allCases.filter { $0 != .adFree }
        #else
        allCases
        #endif
    }

    /// One-line pitch for the settings panel. The Mac build has no ads to remove.
    static var upgradeSubtitle: String {
        #if targetEnvironment(macCatalyst)
        "More piano sounds and studio tools"
        #else
        "Ad-free playing and more studio tools"
        #endif
    }

    /// Named benefits for the confirmation shown after a verified purchase.
    static var unlockedSummary: String {
        #if targetEnvironment(macCatalyst)
        "Both piano sounds, advanced recording tools, and lossless WAV export are unlocked."
        #else
        "Ad-free playing, both piano sounds, advanced recording tools, and lossless WAV export are unlocked."
        #endif
    }

    var title: String {
        switch self {
        case .adFree: "Ad-free playing"
        case .pianoSounds: "Two expressive piano sounds"
        case .recordingStudio: "Advanced recording studio"
        case .losslessExport: "Lossless WAV export"
        }
    }

    var detail: String {
        switch self {
        case .adFree: "Play without banners or app-open ads."
        case .pianoSounds: "Shape your tone with the mellow Warm Studio and spacious Bright Hall sounds."
        case .recordingStudio: "Adjust playback speed, loop a passage, and save trimmed copies of your takes."
        case .losslessExport: "Share full-quality WAV audio, ready for your music workflow."
        }
    }

    var symbol: String {
        switch self {
        case .adFree: "sparkles"
        case .pianoSounds: "pianokeys"
        case .recordingStudio: "slider.horizontal.3"
        case .losslessExport: "waveform"
        }
    }
}
