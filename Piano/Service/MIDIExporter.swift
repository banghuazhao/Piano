import Foundation

enum MIDIExporter {
    enum ExportError: Error {
        case invalidTake
    }

    // Format 0, 480 ticks per quarter note, fixed 120 BPM.
    static func data(for take: PerformanceTake) throws -> Data {
        guard take.isValid else { throw ExportError.invalidTake }
        var track = Data([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])
        var previousTick = 0

        for event in take.events {
            let tick = max(previousTick, Int((event.time * 960).rounded()))
            track.append(contentsOf: variableLength(tick - previousTick))
            if let sustain = event.sustain {
                track.append(contentsOf: [0xB0, 64, sustain ? 127 : 0])
            } else {
                track.append(event.isNoteOn ? 0x90 : 0x80)
                track.append(event.note)
                track.append(event.isNoteOn ? 100 : 0)
            }
            previousTick = tick
        }

        let endTick = max(previousTick, Int((take.duration * 960).rounded()))
        track.append(contentsOf: variableLength(endTick - previousTick))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])

        var file = Data([0x4D, 0x54, 0x68, 0x64]) // MThd
        appendBigEndian(6, to: &file)
        file.append(contentsOf: [0, 0, 0, 1, 1, 0xE0])
        file.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // MTrk
        appendBigEndian(UInt32(track.count), to: &file)
        file.append(track)
        return file
    }

    private static func appendBigEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func variableLength(_ value: Int) -> [UInt8] {
        var remaining = max(0, value)
        var bytes = [UInt8(remaining & 0x7F)]
        remaining >>= 7
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        return bytes
    }
}
