//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import Foundation

struct PianoKey: Identifiable, Hashable {
    let note: PianoNote
    let octave: Int
    var isPressed: Bool = false

    /// MIDI pitch is stable across reconstructed keys and uniquely identifies the 88-key range.
    var id: UInt8 { midiNote }

    var isBlack: Bool {
        note.isBlack
    }

    var midiNote: UInt8 {
        note.midiNote(octave: octave)
    }

    var displayName: String {
        "\(note.rawValue)\(octave)"
    }
    
    var firstKeyDisplayName: String? {
        if note == .C {
            displayName
        } else {
            nil
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(note)
        hasher.combine(octave)
    }

    static func == (lhs: PianoKey, rhs: PianoKey) -> Bool {
        lhs.note == rhs.note && lhs.octave == rhs.octave
    }
    
    func nextBlackKey() -> PianoKey? {
        guard !isBlack, midiNote < 108 else { return nil }
        let blackKeyNotes: [PianoNote: PianoNote] = [
            .C: .CSharp,
            .D: .DSharp,
            .F: .FSharp,
            .G: .GSharp,
            .A: .ASharp
        ]
        
        if let blackNote = blackKeyNotes[self.note] {
            return PianoKey(note: blackNote, octave: octave)
        }
        return nil
    }
}
