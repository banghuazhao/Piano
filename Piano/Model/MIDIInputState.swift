import Foundation

enum MIDIInputEvent: Equatable, Sendable {
    case noteOn(UInt8, velocity: UInt8)
    case noteOff(UInt8)
    case sustain(Bool)
    case allSoundOff
}

struct MIDIInputMessage: Sendable {
    let group: UInt8
    let channel: UInt8
    let status: UInt8
    let data1: UInt8
    let data2: UInt8
}

/// Combines independent devices/channels without releasing another device's held key.
struct MIDIInputState {
    private struct Channel: Hashable {
        let source: UInt32
        let group: UInt8
        let number: UInt8
    }
    private var notes: [Channel: Set<UInt8>] = [:]
    private var pedals: Set<Channel> = []
    private var heldNotes: Set<UInt8> { Set(notes.values.flatMap { $0 }) }

    mutating func receive(_ message: MIDIInputMessage, source: UInt32) -> [MIDIInputEvent] {
        let channel = Channel(source: source, group: message.group, number: message.channel)
        let before = heldNotes
        let sustained = !pedals.isEmpty
        var events: [MIDIInputEvent] = []
        switch message.status {
        case 0x9 where message.data2 > 0:
            guard (21...108).contains(message.data1) else { return [] }
            notes[channel, default: []].insert(message.data1)
            if !before.contains(message.data1) {
                events.append(.noteOn(message.data1, velocity: min(message.data2, 127)))
            }
        case 0x8, 0x9:
            notes[channel]?.remove(message.data1)
        case 0xB:
            switch message.data1 {
            case 64:
                if message.data2 >= 64 { pedals.insert(channel) } else { pedals.remove(channel) }
            case 120:
                // Sources share this instrument. A hardware panic silences the whole piano.
                _ = reset()
                return [.allSoundOff]
            case 123:
                notes[channel] = nil
            case 121:
                pedals.remove(channel)
            default: break
            }
        default: break
        }
        events += before.subtracting(heldNotes).sorted().map { .noteOff($0) }
        if sustained != !pedals.isEmpty { events.append(.sustain(!pedals.isEmpty)) }
        return events
    }

    mutating func disconnect(source: UInt32) -> [MIDIInputEvent] {
        let before = heldNotes
        let sustained = !pedals.isEmpty
        notes = notes.filter { $0.key.source != source }
        pedals = pedals.filter { $0.source != source }
        var events = before.subtracting(heldNotes).sorted().map { MIDIInputEvent.noteOff($0) }
        if sustained != !pedals.isEmpty { events.append(.sustain(!pedals.isEmpty)) }
        return events
    }

    mutating func reset() -> [MIDIInputEvent] {
        var events = heldNotes.sorted().map { MIDIInputEvent.noteOff($0) }
        if !pedals.isEmpty { events.append(.sustain(false)) }
        notes.removeAll()
        pedals.removeAll()
        return events
    }
}
