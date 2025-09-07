//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import Foundation

struct PianoKey: Identifiable, Hashable {
    let id = UUID()
    let note: PianoNote
    let octave: Int
    var isPressed: Bool = false

    var isBlack: Bool {
        note.isBlack
    }

    var midiNote: UInt8 {
        note.midiNote(octave: octave)
    }

    var displayName: String {
        "\(note.rawValue)\(octave)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(note)
        hasher.combine(octave)
    }

    static func == (lhs: PianoKey, rhs: PianoKey) -> Bool {
        lhs.note == rhs.note && lhs.octave == rhs.octave
    }
}

extension PianoKey {
    static func generateKeys(startOctave: Int = 2, endOctave: Int = 6) -> [PianoKey] {
        var keys: [PianoKey] = []

        for octave in startOctave ... endOctave {
            for note in PianoNote.allCases {
                keys.append(PianoKey(note: note, octave: octave))
            }
        }

        return keys
    }
}
