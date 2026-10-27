import Foundation

@main
struct MIDIInputChecks {
    static func main() {
        var state = MIDIInputState()
        func message(_ status: UInt8, _ note: UInt8, _ value: UInt8, channel: UInt8 = 0) -> MIDIInputMessage {
            MIDIInputMessage(group: 0, channel: channel, status: status, data1: note, data2: value)
        }
        precondition(state.receive(message(9, 60, 35), source: 1) == [.noteOn(60, velocity: 35)])
        precondition(state.receive(message(9, 60, 90), source: 2).isEmpty)
        precondition(state.receive(message(8, 60, 0), source: 1).isEmpty)
        precondition(state.receive(message(9, 60, 0), source: 2) == [.noteOff(60)])
        precondition(state.receive(message(9, 20, 100), source: 1).isEmpty)
        precondition(state.receive(message(9, 109, 100), source: 1).isEmpty)
        precondition(state.receive(message(0xB, 64, 127), source: 1) == [.sustain(true)])
        precondition(state.receive(message(0xB, 64, 127), source: 2).isEmpty)
        precondition(state.receive(message(0xB, 64, 0), source: 1).isEmpty)
        precondition(state.disconnect(source: 2) == [.sustain(false)])
        _ = state.receive(message(9, 60, 100), source: 1)
        _ = state.receive(message(9, 60, 100, channel: 1), source: 1)
        precondition(state.receive(message(0xB, 123, 0), source: 1).isEmpty)
        precondition(state.disconnect(source: 1) == [.noteOff(60)])
        _ = state.receive(message(9, 64, 100), source: 1)
        _ = state.receive(message(0xB, 64, 127), source: 1)
        precondition(state.receive(message(0xB, 120, 0), source: 1) == [.allSoundOff])
        precondition(state.reset().isEmpty)
        _ = state.receive(message(9, 65, 127), source: 3)
        _ = state.receive(message(0xB, 64, 127), source: 3)
        precondition(state.reset() == [.noteOff(65), .sustain(false)])
        precondition(state.receive(message(8, 65, 0), source: 3).isEmpty)
        precondition(state.receive(message(9, 65, 72), source: 3) == [.noteOn(65, velocity: 72)])
        precondition(state.receive(message(8, 65, 0), source: 3) == [.noteOff(65)])
        precondition(state.receive(message(0xB, 64, 127), source: 3) == [.sustain(true)])
        precondition(state.reset() == [.sustain(false)])
        precondition(state.receive(message(0xB, 64, 127), source: 3) == [.sustain(true)])
        print("MIDI input checks passed")
    }
}
