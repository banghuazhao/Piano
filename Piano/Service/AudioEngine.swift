//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import AVFoundation

/// Owns the sampler and keeps live playing separate from recorded playback.
@MainActor
final class AudioEngine {
    private enum MIDIChannel {
        static let keyboard: UInt8 = 0
        static let playback: UInt8 = 1
        static let external: UInt8 = 2
    }

    private let audioEngine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private let equalizer = AVAudioUnitEQ(numberOfBands: 2)
    private let reverb = AVAudioUnitReverb()
    private var interruptionObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?
    private var isInterrupted = false

    /// Called when an interruption invalidates keys that the interface considers held.
    var onReset: (() -> Void)?

    init() {
        configureAudioSession()
        audioEngine.attach(sampler)
        audioEngine.attach(equalizer)
        audioEngine.attach(reverb)
        equalizer.bands[0].filterType = .lowShelf
        equalizer.bands[0].frequency = 180
        equalizer.bands[1].filterType = .highShelf
        equalizer.bands[1].frequency = 3_200
        equalizer.bands.forEach { $0.bypass = false }
        reverb.loadFactoryPreset(.mediumHall)
        audioEngine.connect(sampler, to: equalizer, format: nil)
        audioEngine.connect(equalizer, to: reverb, format: nil)
        audioEngine.connect(reverb, to: audioEngine.mainMixerNode, format: nil)
        setSoundProfile(.concert)
        loadSoundFont()
        audioEngine.prepare()
        startEngineIfNeeded()
        observeAudioChanges()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            // A preference rather than a guarantee; the active route chooses the actual value.
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    private func loadSoundFont() {
        guard let soundFontURL = Bundle.main.url(forResource: "Piano", withExtension: "sf2") else {
            print("Piano soundfont not found")
            return
        }

        do {
            try sampler.loadSoundBankInstrument(
                at: soundFontURL,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            // The playback channel uses the same piano preset as live playing.
            for channel in [MIDIChannel.playback, MIDIChannel.external] {
                sampler.sendProgramChange(
                    0,
                    bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                    bankLSB: UInt8(kAUSampler_DefaultBankLSB),
                    onChannel: channel
                )
            }
        } catch {
            print("Failed to load piano soundfont: \(error)")
        }
    }

    private func startEngineIfNeeded() {
        guard !isInterrupted, !audioEngine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func observeAudioChanges() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(rawType: rawType)
            }
        }

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            // The engine posts this on an internal queue. Restart after that callback returns.
            Task { @MainActor [weak self] in
                self?.startEngineIfNeeded()
            }
        }
    }

    private func handleInterruption(rawType: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            isInterrupted = true
            stopAllNotes()
            audioEngine.pause()
            onReset?()
        case .ended:
            isInterrupted = false
            startEngineIfNeeded()
        @unknown default:
            break
        }
    }

    func playNote(_ midiNote: UInt8, velocity: UInt8 = 100) {
        guard !isInterrupted else { return }
        startEngineIfNeeded()
        sampler.startNote(midiNote, withVelocity: velocity, onChannel: MIDIChannel.keyboard)
    }

    func stopNote(_ midiNote: UInt8) {
        sampler.stopNote(midiNote, onChannel: MIDIChannel.keyboard)
    }

    func playRecordedNote(_ midiNote: UInt8, velocity: UInt8 = 100) {
        guard !isInterrupted else { return }
        startEngineIfNeeded()
        sampler.startNote(midiNote, withVelocity: velocity, onChannel: MIDIChannel.playback)
    }

    func stopRecordedNote(_ midiNote: UInt8) {
        sampler.stopNote(midiNote, onChannel: MIDIChannel.playback)
    }

    func stopRecordedNotes() {
        sampler.sendController(64, withValue: 0, onChannel: MIDIChannel.playback)
        sampler.sendController(120, withValue: 0, onChannel: MIDIChannel.playback)
    }

    func playMIDINote(_ note: UInt8, velocity: UInt8) {
        guard !isInterrupted else { return }
        startEngineIfNeeded()
        sampler.startNote(note, withVelocity: velocity, onChannel: MIDIChannel.external)
    }

    func stopMIDINote(_ note: UInt8) {
        sampler.stopNote(note, onChannel: MIDIChannel.external)
    }

    func setMIDISustain(_ enabled: Bool) {
        sampler.sendController(64, withValue: enabled ? 127 : 0, onChannel: MIDIChannel.external)
    }

    func stopMIDINotes() {
        sampler.sendController(64, withValue: 0, onChannel: MIDIChannel.external)
        sampler.sendController(120, withValue: 0, onChannel: MIDIChannel.external)
    }

    func setSoundProfile(_ profile: PianoSoundProfile) {
        equalizer.bands[0].gain = profile.lowShelfGainDB
        equalizer.bands[1].gain = profile.highShelfGainDB
        reverb.wetDryMix = profile.reverbWetDryMix
    }

    func setSustain(_ enabled: Bool) {
        sampler.sendController(64, withValue: enabled ? 127 : 0, onChannel: MIDIChannel.keyboard)
    }

    func setRecordedSustain(_ enabled: Bool) {
        sampler.sendController(64, withValue: enabled ? 127 : 0, onChannel: MIDIChannel.playback)
    }

    func setMasterVolume(_ value: Double) {
        sampler.volume = Float(min(max(value, 0), 1))
    }

    func stopAllNotes() {
        sampler.sendController(64, withValue: 0, onChannel: MIDIChannel.keyboard)
        sampler.sendController(120, withValue: 0, onChannel: MIDIChannel.keyboard)
        stopRecordedNotes()
        stopMIDINotes()
    }
}
