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
    
    func nextBlackKey() -> PianoKey? {
        guard !isBlack else { return nil }
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
