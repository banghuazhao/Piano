//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import Foundation

enum PianoNote: String, CaseIterable {
    case C = "C"
    case CSharp = "C#"
    case D = "D"
    case DSharp = "D#"
    case E = "E"
    case F = "F"
    case FSharp = "F#"
    case G = "G"
    case GSharp = "G#"
    case A = "A"
    case ASharp = "A#"
    case B = "B"
    
    var isBlack: Bool {
        switch self {
        case .CSharp, .DSharp, .FSharp, .GSharp, .ASharp:
            return true
        default:
            return false
        }
    }
    
    var midiOffset: Int {
        switch self {
        case .C: return 0
        case .CSharp: return 1
        case .D: return 2
        case .DSharp: return 3
        case .E: return 4
        case .F: return 5
        case .FSharp: return 6
        case .G: return 7
        case .GSharp: return 8
        case .A: return 9
        case .ASharp: return 10
        case .B: return 11
        }
    }
    
    func midiNote(octave: Int) -> UInt8 {
        // MIDI note 60 is C4 (middle C)
        return UInt8(60 + (octave - 4) * 12 + midiOffset)
    }
}

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
        
        for octave in startOctave...endOctave {
            for note in PianoNote.allCases {
                keys.append(PianoKey(note: note, octave: octave))
            }
        }
        
        return keys
    }
}
