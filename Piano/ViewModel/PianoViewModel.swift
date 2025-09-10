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
