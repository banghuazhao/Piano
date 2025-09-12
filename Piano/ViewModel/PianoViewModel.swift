//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import AVFoundation
import SwiftUI

@Observable
@MainActor
class PianoViewModel {
    private var keys: [PianoKey] = []
    private var pressedKeys: Set<PianoKey> = []
    private let startOctave = 1
    private let endOctave = 7

    private let audioEngine: AudioEngine

    /// All keys across available octaves
    var pianoKeys: [PianoKey] {
        keys
    }

    /// All white keys across all octaves in playing order
    var whiteKeys: [PianoKey] {
        pianoKeys.filter { !$0.isBlack }
    }

    /// All black keys across all octaves in playing order
    var blackKeys: [PianoKey] {
        pianoKeys.filter { $0.isBlack }
    }

    /// Normalized scroll position across the full keyboard [0, 1]
    var scrollPosition: Double = 0.5

    /// Available octave numbers in display order
    var octaves: [Int] {
        Array(startOctave...endOctave)
    }

    // MARK: - Scrolling Helpers (logic only)

    /// Given a normalized position [0,1], return the nearest white key.
    func keyForPosition(_ position: Double) -> PianoKey? {
        guard !whiteKeys.isEmpty else { return nil }
        let clamped = max(0.0, min(1.0, position))
        let index = Int(round(clamped * Double(whiteKeys.count - 1)))
        return whiteKeys[index]
    }

    /// Compute normalized position [0,1] for a given key within white keys.
    func normalizedPosition(for key: PianoKey) -> Double? {
        guard let idx = whiteKeys.firstIndex(where: { $0.id == key.id }) else { return nil }
        let denominator = max(1, whiteKeys.count - 1)
        return Double(idx) / Double(denominator)
    }

    /// Anchor key used when centering on appear (C4 by design).
    func middleAnchorKey() -> PianoKey? {
        whiteKeys.first(where: { $0.note == .F && $0.octave == 4 })
    }

    /// Anchor key used when jumping to an octave from controls (F-octave by design).
    func anchorKey(forOctave octave: Int) -> PianoKey? {
        whiteKeys.first(where: { $0.note == .F && $0.octave == octave })
    }

    // MARK: - Initialization

    init(audioEngine: AudioEngine = AudioEngine()) {
        self.audioEngine = audioEngine
        setupKeys()
    }

    // MARK: - Setup Methods

    private func setupKeys() {
        var keys: [PianoKey] = []

        for octave in startOctave ... endOctave {
            for note in PianoNote.allCases {
                keys.append(PianoKey(note: note, octave: octave))
            }
        }

        self.keys = keys
    }

    // MARK: - Key Interaction Methods

    func keyPressed(_ key: PianoKey) {
        pressedKeys.insert(key)
        audioEngine.playNote(key.midiNote, velocity: 100)
    }

    func keyReleased(_ key: PianoKey) {
        pressedKeys.remove(key)
    }

    func isKeyPressed(_ key: PianoKey) -> Bool {
        pressedKeys.contains(key)
    }
    
    var totalKeyboardWidth: CGFloat {
        let whiteKeyWidth: CGFloat = 50
        let whiteKeySpacing: CGFloat = 1
        let whiteKeyCount = whiteKeys.count
        return CGFloat(whiteKeyCount) * whiteKeyWidth + CGFloat(whiteKeyCount - 1) * whiteKeySpacing
    }
}
