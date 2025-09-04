//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import AVFoundation
import SwiftUI

@Observable
@MainActor
class PianoViewModel {
    // MARK: - Properties

    private let audioEngine: AudioEngine
    private var keys: [PianoKey] = []
    private var pressedKeys: Set<PianoKey> = []

    // MARK: - Published Properties

    var currentOctave: Int = 4
    var isInitialized: Bool = false
    var errorMessage: String?

    // MARK: - Computed Properties

    var pianoKeys: [PianoKey] {
        keys.filter { $0.octave == currentOctave }
    }

    var whiteKeys: [PianoKey] {
        pianoKeys.filter { !$0.isBlack }
    }

    var blackKeys: [PianoKey] {
        pianoKeys.filter { $0.isBlack }
    }

    var pressedKeysCount: Int {
        pressedKeys.count
    }

    // MARK: - Initialization

    init() {
        audioEngine = AudioEngine()
        setupKeys()
    }

    // MARK: - Setup Methods

    private func setupKeys() {
        keys = PianoKey.generateKeys(startOctave: 2, endOctave: 6)
    }

    func initializeAudio() async {
        do {
            try await audioEngine.loadSoundFont()
            isInitialized = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            isInitialized = false
            print(errorMessage)
        }
    }

    // MARK: - Key Interaction Methods

    func keyPressed(_ key: PianoKey) {
        guard isInitialized else { return }

        pressedKeys.insert(key)
        audioEngine.playNote(key.midiNote, velocity: 100)
    }

    func keyReleased(_ key: PianoKey) {
        guard isInitialized else { return }

        pressedKeys.remove(key)
        audioEngine.stopNote(key.midiNote)
    }

    func isKeyPressed(_ key: PianoKey) -> Bool {
        pressedKeys.contains(key)
    }

    // MARK: - Octave Control Methods

    func increaseOctave() {
        guard currentOctave < 6 else { return }
        currentOctave += 1
        stopAllNotes()
    }

    func decreaseOctave() {
        guard currentOctave > 2 else { return }
        currentOctave -= 1
        stopAllNotes()
    }

    private func stopAllNotes() {
        audioEngine.stopAllNotes()
        pressedKeys.removeAll()
    }

    // MARK: - Utility Methods

    func retryInitialization() {
        Task {
            await initializeAudio()
        }
    }
}
