//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

@Observable
@MainActor
class PianoViewModel {
    var pianoKeys: [PianoKey] = []
    private(set) var whiteKeys: [PianoKey] = []
    private(set) var blackKeys: [PianoKey] = []
    /// Normalized scroll position across the full keyboard [0, 1]
    var scrollPosition: Double = 0.5
    var showSettings = false
    private(set) var sustainEnabled = false
    private(set) var midiSustainEnabled = false
    private(set) var masterVolume = 0.85

    let octaves = [1, 2, 3, 4, 5, 6, 7]
    private var pressedKeys: Set<PianoKey> = []
    private var playbackNotes: Set<UInt8> = []
    private var midiNotes: Set<UInt8> = []
    private var midiVelocities: [UInt8: UInt8] = [:]
    var onAudioReset: (() -> Void)?

    private let audioEngine: AudioEngine

    var pressedMIDINotes: [UInt8] {
        Set(pressedKeys.map(\.midiNote)).union(midiNotes).sorted()
    }

    var recordingSustainEnabled: Bool { sustainEnabled || midiSustainEnabled }
    var heldVelocities: [UInt8: UInt8] {
        var velocities = midiVelocities
        for key in pressedKeys where velocities[key.midiNote] == nil {
            velocities[key.midiNote] = 100
        }
        return velocities
    }

    var currentOctave: Int? {
        keyForPosition(scrollPosition)?.octave
    }

    // MARK: - Initialization

    init(audioEngine: AudioEngine? = nil) {
        self.audioEngine = audioEngine ?? AudioEngine()
        setupKeys()
        self.audioEngine.setMasterVolume(masterVolume)
        self.audioEngine.onReset = { [weak self] in
            self?.pressedKeys.removeAll()
            self?.playbackNotes.removeAll()
            self?.midiNotes.removeAll()
            self?.midiVelocities.removeAll()
            self?.sustainEnabled = false
            self?.midiSustainEnabled = false
            self?.onAudioReset?()
        }
    }

    // MARK: - Setup Methods

    private func setupKeys() {
        // A0 through C8 is the 88-key acoustic piano range (MIDI 21...108).
        var keys: [PianoKey] = [
            PianoKey(note: .A, octave: 0),
            PianoKey(note: .ASharp, octave: 0),
            PianoKey(note: .B, octave: 0)
        ]

        for octave in octaves {
            for note in PianoNote.allCases {
                keys.append(PianoKey(note: note, octave: octave))
            }
        }

        keys.append(PianoKey(note: .C, octave: 8))

        pianoKeys = keys
        whiteKeys = keys.filter { !$0.isBlack }
        blackKeys = keys.filter(\.isBlack)
    }

    // MARK: - Key Interaction Methods

    @discardableResult
    func keyPressed(_ key: PianoKey) -> Bool {
        guard pressedKeys.insert(key).inserted else { return false }
        audioEngine.playNote(key.midiNote, velocity: 100)
        return true
    }

    @discardableResult
    func keyReleased(_ key: PianoKey) -> Bool {
        guard pressedKeys.remove(key) != nil else { return false }
        audioEngine.stopNote(key.midiNote)
        return true
    }

    func isKeyPressed(_ key: PianoKey) -> Bool {
        pressedKeys.contains(key) || playbackNotes.contains(key.midiNote) || midiNotes.contains(key.midiNote)
    }

    func setSustain(_ enabled: Bool) {
        guard sustainEnabled != enabled else { return }
        sustainEnabled = enabled
        applyLiveSustain()
    }

    func setMasterVolume(_ value: Double) {
        guard value.isFinite else { return }
        masterVolume = min(max(value, 0), 1)
        audioEngine.setMasterVolume(masterVolume)
    }

    func setSoundProfile(_ profile: PianoSoundProfile) {
        audioEngine.setSoundProfile(profile)
    }

    @discardableResult
    func midiNoteOn(_ note: UInt8, velocity: UInt8) -> Bool {
        guard midiNotes.insert(note).inserted else { return false }
        midiVelocities[note] = velocity
        audioEngine.playMIDINote(note, velocity: velocity)
        return true
    }

    @discardableResult
    func midiNoteOff(_ note: UInt8) -> Bool {
        guard midiNotes.remove(note) != nil else { return false }
        midiVelocities[note] = nil
        audioEngine.stopMIDINote(note)
        return true
    }

    func setMIDISustain(_ enabled: Bool) {
        midiSustainEnabled = enabled
        applyLiveSustain()
    }

    private func applyLiveSustain() {
        audioEngine.setSustain(recordingSustainEnabled)
        audioEngine.setMIDISustain(recordingSustainEnabled)
    }

    @discardableResult
    func playbackNoteOn(_ midiNote: UInt8, velocity: UInt8 = 100) -> Bool {
        guard playbackNotes.insert(midiNote).inserted else { return false }
        audioEngine.playRecordedNote(midiNote, velocity: velocity)
        return true
    }

    @discardableResult
    func playbackNoteOff(_ midiNote: UInt8) -> Bool {
        guard playbackNotes.remove(midiNote) != nil else { return false }
        audioEngine.stopRecordedNote(midiNote)
        return true
    }

    func setPlaybackSustain(_ enabled: Bool) {
        audioEngine.setRecordedSustain(enabled)
    }

    func stopPlaybackNotes() {
        playbackNotes.removeAll()
        audioEngine.stopRecordedNotes()
    }

    func stopAllNotes() {
        pressedKeys.removeAll()
        playbackNotes.removeAll()
        sustainEnabled = false
        midiNotes.removeAll()
        midiVelocities.removeAll()
        midiSustainEnabled = false
        audioEngine.stopAllNotes()
    }
    
    // MARK: - Scrolling

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
}
