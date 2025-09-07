//
// Created by Banghua Zhao on 07/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import Foundation

enum PianoNote: String, CaseIterable {
    case C
    case CSharp = "C#"
    case D
    case DSharp = "D#"
    case E
    case F
    case FSharp = "F#"
    case G
    case GSharp = "G#"
    case A
    case ASharp = "A#"
    case B

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
