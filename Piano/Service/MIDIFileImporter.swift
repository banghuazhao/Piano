import Foundation

enum MIDIImportError: LocalizedError {
    case fileTooLarge
    case malformed(String)
    case unsupportedFormat(Int)
    case unsupportedTimeDivision
    case tooComplex(String)
    case noPlayableNotes(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "This MIDI file is larger than the 8 MB import limit."
        case .malformed(let reason):
            "This MIDI file could not be read: \(reason)."
        case .unsupportedFormat(let format):
            "MIDI format \(format) is not supported. Choose a type 0 or type 1 file."
        case .unsupportedTimeDivision:
            "This file uses SMPTE timing. Export it with ticks-per-quarter-note timing to practice it here."
        case .tooComplex(let reason):
            "This MIDI file exceeds the import limit: \(reason)."
        case .noPlayableNotes(let detail):
            "No playable piano notes were found. \(detail)"
        }
    }
}

/// A bounded Standard MIDI File (SMF) type 0/1, PPQN parser. It does not execute
/// SysEx data or require AudioToolbox, so it can be used off the main actor.
enum MIDIFileImporter {
    static let maximumFileBytes = 8 * 1_024 * 1_024
    private static let maximumSourceTracks = 32
    private static let maximumPracticeTracks = 32
    private static let maximumEvents = 250_000
    private static let maximumNotes = 40_000
    private static let maximumBeats = 8_192

    static func parse(data: Data, title: String) throws -> ImportedPracticeSong {
        guard data.count <= maximumFileBytes else { throw MIDIImportError.fileTooLarge }
        guard data.count >= 14 else { throw MIDIImportError.malformed("missing MThd header or truncated header") }
        var reader = Reader(bytes: Array(data))
        guard try reader.readASCII(4) == "MThd" else {
            throw MIDIImportError.malformed("missing MThd header")
        }
        let headerLength = try reader.readBE32()
        guard headerLength >= 6, headerLength <= reader.remaining else {
            throw MIDIImportError.malformed("truncated header")
        }
        let headerEnd = reader.offset + headerLength
        let format = try reader.readBE16()
        guard format == 0 || format == 1 else { throw MIDIImportError.unsupportedFormat(format) }
        let sourceTrackCount = try reader.readBE16()
        guard (1...maximumSourceTracks).contains(sourceTrackCount) else {
            throw MIDIImportError.tooComplex("at most \(maximumSourceTracks) source tracks are supported")
        }
        guard format != 0 || sourceTrackCount == 1 else {
            throw MIDIImportError.malformed("type 0 must contain one track")
        }
        let division = try reader.readBE16()
        guard division & 0x8000 == 0, division > 0 else {
            throw MIDIImportError.unsupportedTimeDivision
        }
        reader.offset = headerEnd

        var parsedTracks: [ParsedTrack] = []
        var globalEvents = 0
        var chunkCount = 0
        while parsedTracks.count < sourceTrackCount {
            chunkCount += 1
            guard chunkCount <= sourceTrackCount + 32 else {
                throw MIDIImportError.malformed("too many non-track chunks")
            }
            let identifier = try reader.readASCII(4)
            let length = try reader.readBE32()
            guard length <= reader.remaining else {
                throw MIDIImportError.malformed("truncated \(identifier) chunk")
            }
            let chunkEnd = reader.offset + length
            if identifier == "MTrk" {
                let parsed = try parseTrack(reader: &reader, end: chunkEnd,
                                            sourceIndex: parsedTracks.count,
                                            ppqn: division, eventCount: &globalEvents)
                parsedTracks.append(parsed)
            }
            reader.offset = chunkEnd
        }

        var tracks: [ImportedSongTrack] = []
        for source in parsedTracks {
            let grouped = Dictionary(grouping: source.notes, by: \.channel)
            for channel in grouped.keys.sorted() {
                let rawNotes = grouped[channel] ?? []
                let notes: [ImportedSongNote] = rawNotes.map { raw in
                    let startBeat = Double(raw.startTick) / Double(division)
                    let duration = Double(raw.endTick - raw.startTick) / Double(division)
                    return ImportedSongNote(pitch: raw.pitch, startBeat: startBeat,
                                            durationBeats: max(0.0625, duration),
                                            velocity: raw.velocity)
                }.sorted {
                    $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat
                }
                let base = source.title ?? "Track \(source.sourceIndex + 1)"
                let label = grouped.count > 1 ? "\(base) · Ch \(Int(channel) + 1)" : base
                tracks.append(ImportedSongTrack(id: UUID(), sourceTrackIndex: source.sourceIndex,
                                                channel: channel, title: String(label.prefix(80)),
                                                hand: .both, notes: notes))
            }
        }
        guard tracks.count <= maximumPracticeTracks else {
            throw MIDIImportError.tooComplex("at most \(maximumPracticeTracks) melodic tracks are supported")
        }
        let noteCount = tracks.reduce(0) { $0 + $1.notes.count }
        guard noteCount <= maximumNotes else {
            throw MIDIImportError.tooComplex("at most \(maximumNotes) piano notes are supported")
        }
        let percussion = parsedTracks.reduce(0) { $0 + $1.skippedPercussion }
        let outOfRange = parsedTracks.reduce(0) { $0 + $1.skippedOutOfRange }
        guard noteCount > 0 else {
            throw MIDIImportError.noPlayableNotes("\(percussion) percussion and \(outOfRange) out-of-range notes were skipped.")
        }

        if tracks.count > 1 {
            let ordered = tracks.indices.sorted { lhs, rhs in
                let left = medianPitch(tracks[lhs].notes)
                let right = medianPitch(tracks[rhs].notes)
                return left == right ? lhs < rhs : left < right
            }
            for (position, index) in ordered.enumerated() {
                tracks[index].hand = position < (tracks.count + 1) / 2 ? .left : .right
            }
        }

        let tempoMarks = orderedMarks(parsedTracks.flatMap(\.tempo)) {
            ImportedTempoChange(beat: Double($0.tick) / Double(division),
                                microsecondsPerQuarterNote: $0.value)
        }
        let meterMarks = orderedMarks(parsedTracks.flatMap(\.meter)) {
            ImportedTimeSignature(beat: Double($0.tick) / Double(division),
                                  beatsPerBar: $0.value.0, beatUnit: $0.value.1)
        }
        let keyMarks = orderedMarks(parsedTracks.flatMap(\.key)) {
            ImportedKeySignature(beat: Double($0.tick) / Double(division),
                                 fifths: $0.value.0, isMinor: $0.value.1)
        }
        let song = ImportedPracticeSong(
            id: UUID(), title: cleanTitle(title, fallback: "Imported song", limit: 80),
            importedAt: Date(), sourceFormat: format, ticksPerQuarterNote: division,
            tracks: tracks,
            tempoChanges: tempoMarks.first?.beat == 0 ? tempoMarks
                : [ImportedTempoChange(beat: 0, microsecondsPerQuarterNote: 500_000)] + tempoMarks,
            timeSignatures: meterMarks.first?.beat == 0 ? meterMarks
                : [ImportedTimeSignature(beat: 0, beatsPerBar: 4, beatUnit: 4)] + meterMarks,
            keySignatures: keyMarks,
            skippedPercussionNotes: percussion, skippedOutOfRangeNotes: outOfRange,
            closedDanglingNotes: parsedTracks.reduce(0) { $0 + $1.closedDangling }
        )
        guard song.isValidForPractice else {
            throw MIDIImportError.malformed("the note timing or metadata is invalid")
        }
        return song
    }

    static func cleanTitle(_ raw: String, fallback: String, limit: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutExtension: String
        if trimmed.lowercased().hasSuffix(".midi") {
            withoutExtension = String(trimmed.dropLast(5))
        } else if trimmed.lowercased().hasSuffix(".mid") {
            withoutExtension = String(trimmed.dropLast(4))
        } else {
            withoutExtension = trimmed
        }
        let printable = withoutExtension.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        let collapsed = printable.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String((collapsed.isEmpty ? fallback : collapsed).prefix(limit))
    }

    private static func medianPitch(_ notes: [ImportedSongNote]) -> Int {
        let pitches = notes.map { Int($0.pitch) }.sorted()
        return pitches[pitches.count / 2]
    }

    private static func orderedMarks<Value, Output>(
        _ marks: [Mark<Value>], convert: (Mark<Value>) -> Output
    ) -> [Output] {
        let sorted = marks.sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            if $0.sourceIndex != $1.sourceIndex { return $0.sourceIndex < $1.sourceIndex }
            return $0.order < $1.order
        }
        var seenTicks = Set<Int>()
        return sorted.compactMap { mark in
            guard seenTicks.insert(mark.tick).inserted else { return nil }
            return convert(mark)
        }
    }

    private static func parseTrack(reader: inout Reader, end: Int, sourceIndex: Int,
                                   ppqn: Int, eventCount: inout Int) throws -> ParsedTrack {
        var parsed = ParsedTrack(sourceIndex: sourceIndex)
        var runningStatus: UInt8?
        var tick = 0
        var order = 0
        var active: [NoteKey: [PendingNote]] = [:]
        while reader.offset < end {
            try Task.checkCancellation()
            eventCount += 1
            guard eventCount <= maximumEvents else {
                throw MIDIImportError.tooComplex("at most \(maximumEvents) MIDI events are supported")
            }
            let delta = try reader.readVLQ(until: end)
            guard delta <= ppqn * maximumBeats - tick else {
                throw MIDIImportError.tooComplex("songs longer than \(maximumBeats) quarter-note beats are not supported")
            }
            tick += delta
            let next = try reader.peek(until: end)
            let status: UInt8
            if next < 0x80 {
                guard let runningStatus else {
                    throw MIDIImportError.malformed("running status has no preceding channel event")
                }
                status = runningStatus
            } else {
                status = try reader.readByte(until: end)
                runningStatus = (0x80...0xEF).contains(status) ? status : nil
            }

            if status == 0xFF {
                let type = try reader.readByte(until: end)
                let length = try reader.readVLQ(until: end)
                let payload = try reader.readBytes(length, until: end)
                switch type {
                case 0x03:
                    if parsed.title == nil {
                        let decoded = String(bytes: payload, encoding: .utf8)
                            ?? String(bytes: payload, encoding: .isoLatin1) ?? ""
                        parsed.title = cleanTitle(decoded, fallback: "Track \(sourceIndex + 1)", limit: 64)
                    }
                case 0x2F:
                    reader.offset = end
                case 0x51:
                    guard payload.count == 3 else { throw MIDIImportError.malformed("invalid tempo event") }
                    let micros = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                    guard micros > 0 else { throw MIDIImportError.malformed("zero tempo") }
                    parsed.tempo.append(Mark(tick: tick, sourceIndex: sourceIndex,
                                             order: order, value: micros))
                case 0x58:
                    guard payload.count == 4, payload[0] > 0, payload[1] <= 7 else {
                        throw MIDIImportError.malformed("invalid time signature")
                    }
                    parsed.meter.append(Mark(tick: tick, sourceIndex: sourceIndex,
                                             order: order,
                                             value: (Int(payload[0]), 1 << Int(payload[1]))))
                case 0x59:
                    guard payload.count == 2 else { throw MIDIImportError.malformed("invalid key signature") }
                    let fifths = Int(Int8(bitPattern: payload[0]))
                    guard (-7...7).contains(fifths), payload[1] <= 1 else {
                        throw MIDIImportError.malformed("invalid key signature")
                    }
                    parsed.key.append(Mark(tick: tick, sourceIndex: sourceIndex,
                                           order: order, value: (fifths, payload[1] == 1)))
                default:
                    break
                }
                order += 1
                continue
            }
            if status == 0xF0 || status == 0xF7 {
                let length = try reader.readVLQ(until: end)
                try reader.skip(length, until: end)
                order += 1
                continue
            }
            if status >= 0xF0 {
                let count: Int
                switch status {
                case 0xF1, 0xF3: count = 1
                case 0xF2: count = 2
                case 0xF6, 0xF8...0xFE: count = 0
                default: throw MIDIImportError.malformed("unsupported system status \(status)")
                }
                for _ in 0..<count { _ = try reader.readDataByte(until: end) }
                order += 1
                continue
            }

            let kind = status & 0xF0
            let channel = status & 0x0F
            let first = try reader.readDataByte(until: end)
            let second: UInt8 = (kind == 0xC0 || kind == 0xD0) ? 0
                : try reader.readDataByte(until: end)
            if kind == 0x90, second > 0 {
                if channel == 9 {
                    parsed.skippedPercussion += 1
                } else if !(21...108).contains(first) {
                    parsed.skippedOutOfRange += 1
                } else {
                    let key = NoteKey(channel: channel, pitch: first)
                    active[key, default: []].append(PendingNote(tick: tick, velocity: second))
                }
            } else if kind == 0x80 || (kind == 0x90 && second == 0) {
                let key = NoteKey(channel: channel, pitch: first)
                if var stack = active[key], let onset = stack.popLast() {
                    active[key] = stack.isEmpty ? nil : stack
                    parsed.notes.append(RawNote(channel: channel, pitch: first,
                                                startTick: onset.tick, endTick: tick,
                                                velocity: onset.velocity))
                    guard parsed.notes.count <= maximumNotes else {
                        throw MIDIImportError.tooComplex("at most \(maximumNotes) piano notes are supported")
                    }
                }
            }
            order += 1
        }
        for (key, stack) in active {
            for onset in stack {
                parsed.notes.append(RawNote(channel: key.channel, pitch: key.pitch,
                                            startTick: onset.tick,
                                            endTick: max(tick, onset.tick),
                                            velocity: onset.velocity))
                parsed.closedDangling += 1
            }
        }
        return parsed
    }
}

private struct Reader {
    let bytes: [UInt8]
    var offset = 0
    var remaining: Int { bytes.count - offset }

    mutating func readByte(until end: Int? = nil) throws -> UInt8 {
        guard offset < (end ?? bytes.count) else { throw MIDIImportError.malformed("unexpected end of file") }
        defer { offset += 1 }
        return bytes[offset]
    }

    func peek(until end: Int) throws -> UInt8 {
        guard offset < end else { throw MIDIImportError.malformed("unexpected end of track") }
        return bytes[offset]
    }

    mutating func readDataByte(until end: Int) throws -> UInt8 {
        let byte = try readByte(until: end)
        guard byte < 0x80 else { throw MIDIImportError.malformed("expected MIDI data byte") }
        return byte
    }

    mutating func readBE16() throws -> Int {
        let high = Int(try readByte())
        let low = Int(try readByte())
        return high << 8 | low
    }

    mutating func readBE32() throws -> Int {
        var result = 0
        for _ in 0..<4 { result = result << 8 | Int(try readByte()) }
        return result
    }

    mutating func readASCII(_ count: Int) throws -> String {
        String(bytes: try readBytes(count, until: bytes.count), encoding: .ascii) ?? ""
    }

    mutating func readBytes(_ count: Int, until end: Int) throws -> [UInt8] {
        guard count >= 0, count <= end - offset else {
            throw MIDIImportError.malformed("truncated event payload")
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func skip(_ count: Int, until end: Int) throws {
        guard count >= 0, count <= end - offset else {
            throw MIDIImportError.malformed("truncated event payload")
        }
        offset += count
    }

    mutating func readVLQ(until end: Int) throws -> Int {
        var value = 0
        for _ in 0..<4 {
            let byte = try readByte(until: end)
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        throw MIDIImportError.malformed("variable-length value exceeds four bytes")
    }
}

private struct NoteKey: Hashable {
    let channel: UInt8
    let pitch: UInt8
}

private struct PendingNote {
    let tick: Int
    let velocity: UInt8
}

private struct RawNote {
    let channel: UInt8
    let pitch: UInt8
    let startTick: Int
    let endTick: Int
    let velocity: UInt8
}

private struct Mark<Value> {
    let tick: Int
    let sourceIndex: Int
    let order: Int
    let value: Value
}

private struct ParsedTrack {
    let sourceIndex: Int
    var title: String?
    var notes: [RawNote] = []
    var tempo: [Mark<Int>] = []
    var meter: [Mark<(Int, Int)>] = []
    var key: [Mark<(Int, Bool)>] = []
    var skippedPercussion = 0
    var skippedOutOfRange = 0
    var closedDangling = 0
}
