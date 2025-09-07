//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import AVFoundation
import SwiftUI

@Observable
@MainActor
class PianoViewModel {
    
    var isSustainOn: Bool = false
    var currentOctave: Int = 4


    private var keys: [PianoKey] = []
    private var pressedKeys: Set<PianoKey> = []
    private let startOctave = 1
    private let endOctave = 7
    
    private let audioEngine: AudioEngine

    var pianoKeys: [PianoKey] {
        keys.filter { $0.octave == currentOctave }
    }

    var whiteKeys: [PianoKey] {
        pianoKeys.filter { !$0.isBlack }
    }

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
        if !isSustainOn {
            audioEngine.stopNote(key.midiNote)
        }
    }

    func isKeyPressed(_ key: PianoKey) -> Bool {
        pressedKeys.contains(key)
    }

    // MARK: - Octave Control Methods

    func increaseOctave() {
        guard currentOctave < endOctave else { return }
        currentOctave += 1
    }

    func decreaseOctave() {
        guard currentOctave > startOctave else { return }
        currentOctave -= 1
    }
}
