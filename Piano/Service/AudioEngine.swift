//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import AVFoundation
import SwiftUI

class AudioEngine {
    private let audioEngine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    init() {
        setupAudioEngine()
        loadSoundFont()
    }

    private func setupAudioEngine() {
        // Attach the sampler to the audio engine
        audioEngine.attach(sampler)

        // Connect the sampler to the main mixer
        let mainMixer = audioEngine.mainMixerNode
        audioEngine.connect(sampler, to: mainMixer, format: nil)

        // Start the audio engine
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }

        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    func loadSoundFont()  {
        guard let soundFontURL = Bundle.main.url(forResource: "Piano", withExtension: "sf2") else {
            return
        }
        print("✅ Found soundfont at: \(soundFontURL.path)")

        do {
            // Load the SoundFont file into the sampler
            try sampler.loadSoundBankInstrument(
                at: soundFontURL,
                program: 0, // MIDI program number (e.g., 0 for the first preset)
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), // Melodic bank
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            print("SF2 file loaded successfully")
        } catch {
            print("Failed to load SF2 file: \(error)")
        }
    }

    func playNote(_ midiNote: UInt8, velocity: UInt8 = 100) {
        sampler.startNote(midiNote, withVelocity: velocity, onChannel: 0)
    }

    func stopNote(_ midiNote: UInt8) {
        sampler.stopNote(midiNote, onChannel: 0)
    }

    func stopAllNotes() {
        sampler.sendController(123, withValue: 0, onChannel: 0) // All notes off
    }
}

enum AudioEngineError: Error, LocalizedError {
    case soundFontNotFound
    case engineNotAvailable
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .soundFontNotFound:
            return "Piano soundfont file not found"
        case .engineNotAvailable:
            return "Audio engine not available"
        case .initializationFailed:
            return "Failed to initialize audio engine"
        }
    }
}
