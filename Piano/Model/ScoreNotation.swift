import Foundation

enum ScoreClef: Sendable {
    case treble
    case bass

    var hand: PracticeHand { self == .treble ? .right : .left }
    var name: String { self == .treble ? "Treble" : "Bass" }
    var bottomLineDiatonicIndex: Int { self == .treble ? 30 : 18 } // E4, G2
}

enum ScoreAccidental: Sendable {
    case natural
    case sharp
    case flat

    var symbol: String {
        switch self {
        case .natural: "♮"
        case .sharp: "♯"
        case .flat: "♭"
        }
    }
}

struct ScorePitch: Equatable, Sendable {
    let midi: UInt8
    let letter: String
    let octave: Int
    let accidental: ScoreAccidental
    let diatonicIndex: Int

    func staffStep(in clef: ScoreClef) -> Int {
        diatonicIndex - clef.bottomLineDiatonicIndex
    }

    var spokenName: String {
        let modifier = accidental == .natural ? "" : accidental.symbol
        return "\(letter)\(modifier)\(octave)"
    }
}

enum ScoreBaseDuration: Double, Sendable {
    case whole = 4
    case half = 2
    case quarter = 1
    case eighth = 0.5
    case sixteenth = 0.25
    case thirtySecond = 0.125

    var name: String {
        switch self {
        case .whole: "whole"
        case .half: "half"
        case .quarter: "quarter"
        case .eighth: "eighth"
        case .sixteenth: "sixteenth"
        case .thirtySecond: "thirty-second"
        }
    }
}

struct ScoreDuration: Equatable, Hashable, Sendable {
    let base: ScoreBaseDuration
    let dotted: Bool

    var beats: Double { base.rawValue * (dotted ? 1.5 : 1) }
    var isFilled: Bool { base.rawValue <= 1 }
    var hasStem: Bool { base != .whole }
    var flagCount: Int {
        switch base {
        case .whole, .half, .quarter: 0
        case .eighth: 1
        case .sixteenth: 2
        case .thirtySecond: 3
        }
    }
    var spokenName: String { (dotted ? "dotted " : "") + base.name + " note" }
}

struct ScoreRhythmPiece: Equatable, Sendable {
    let startBeat: Double
    let duration: ScoreDuration
    let tiesFromPrevious: Bool
    let tiesToNext: Bool

    var endBeat: Double { startBeat + duration.beats }
}

struct ScoreHead: Sendable {
    let pitch: ScorePitch
    let displayedAccidental: ScoreAccidental?
}

struct ScoreChord: Sendable {
    let startBeat: Double
    let duration: ScoreDuration
    let hand: PracticeHand
    let heads: [ScoreHead]
    let tiesFromPrevious: Bool
    let tiesToNext: Bool

    var clef: ScoreClef { hand == .left ? .bass : .treble }
}

struct ScoreRest: Sendable {
    let startBeat: Double
    let duration: ScoreDuration
    let hand: PracticeHand
    var clef: ScoreClef { hand == .left ? .bass : .treble }
}

struct ScoreWindow: Sendable {
    let startBeat: Double
    let endBeat: Double
    let barLength: Double
    let staves: [ScoreClef]
    let chords: [ScoreChord]
    let rests: [ScoreRest]
    let rhythmSimplified: Bool
    let isDense: Bool
    let currentNoteNames: [String]
    let upcomingNoteNames: [String]

    var visibleBeats: Double { endBeat - startBeat }
}

enum ScoreNotation {
    static let sixteenthBeat = 0.25
    private static let ticksPerBeat = 8
    private static let durations: [ScoreDuration] = [
        .init(base: .whole, dotted: true),
        .init(base: .whole, dotted: false),
        .init(base: .half, dotted: true),
        .init(base: .half, dotted: false),
        .init(base: .quarter, dotted: true),
        .init(base: .quarter, dotted: false),
        .init(base: .eighth, dotted: true),
        .init(base: .eighth, dotted: false),
        .init(base: .sixteenth, dotted: true),
        .init(base: .sixteenth, dotted: false),
        .init(base: .thirtySecond, dotted: false)
    ]

    static func pitch(_ midi: UInt8) -> ScorePitch {
        let names: [(String, Int, ScoreAccidental)] = [
            ("C", 0, .natural), ("C", 0, .sharp),
            ("D", 1, .natural), ("E", 2, .flat),
            ("E", 2, .natural), ("F", 3, .natural),
            ("F", 3, .sharp), ("G", 4, .natural),
            ("A", 5, .flat), ("A", 5, .natural),
            ("B", 6, .flat), ("B", 6, .natural)
        ]
        let octave = Int(midi) / 12 - 1
        let (letter, offset, accidental) = names[Int(midi) % 12]
        return ScorePitch(midi: midi, letter: letter, octave: octave,
                          accidental: accidental, diatonicIndex: octave * 7 + offset)
    }

    static func quantizeToSixteenth(_ beat: Double) -> Double {
        guard beat.isFinite else { return 0 }
        return min(1_000_000, max(0, (beat / sixteenthBeat).rounded() * sixteenthBeat))
    }

    /// Splits at measure lines, then spells each span as conventional dotted or plain values.
    static func spell(startBeat: Double, durationBeats: Double, barLength: Double) -> [ScoreRhythmPiece] {
        guard startBeat.isFinite, durationBeats.isFinite, durationBeats > 0,
              barLength.isFinite, barLength > 0,
              startBeat >= 0, startBeat <= 1_000_000,
              durationBeats <= 1_000_000, barLength <= 1_000 else { return [] }
        var tick = Int((quantizeToSixteenth(startBeat) * Double(ticksPerBeat)).rounded())
        var remaining = max(1, Int((quantizeToSixteenth(durationBeats) * Double(ticksPerBeat)).rounded()))
        let barTicks = max(1, Int((barLength * Double(ticksPerBeat)).rounded()))
        var pieces: [ScoreRhythmPiece] = []

        while remaining > 0 {
            guard pieces.count < 4_096 else { return [] }
            let inBar = tick % barTicks
            let room = min(remaining, barTicks - inBar)
            guard let value = durations.first(where: {
                Int(($0.beats * Double(ticksPerBeat)).rounded()) <= room
            }) else { break }
            let used = Int((value.beats * Double(ticksPerBeat)).rounded())
            pieces.append(ScoreRhythmPiece(
                startBeat: Double(tick) / Double(ticksPerBeat), duration: value,
                tiesFromPrevious: !pieces.isEmpty, tiesToNext: remaining > used
            ))
            tick += used
            remaining -= used
        }
        return pieces
    }

    /// Engraves only the visible measures of a sustained note. A note that
    /// starts before the window receives a tied carry head at the left edge.
    static func spellVisible(startBeat: Double, endBeat: Double, barLength: Double,
                             windowStart: Double, windowEnd: Double) -> [ScoreRhythmPiece] {
        guard endBeat > windowStart, startBeat < windowEnd,
              barLength.isFinite, barLength > 0 else { return [] }
        let carryStart = ceil(windowStart / sixteenthBeat) * sixteenthBeat
        let sliceStart = startBeat < windowStart ? max(startBeat, carryStart) : startBeat
        let nextBoundary = (floor(windowEnd / barLength) + 1) * barLength
        let sliceEnd = min(endBeat, nextBoundary)
        guard sliceEnd > sliceStart else { return [] }
        let pieces = spell(startBeat: sliceStart, durationBeats: sliceEnd - sliceStart,
                           barLength: barLength)
        return pieces.map { piece in
            ScoreRhythmPiece(startBeat: piece.startBeat, duration: piece.duration,
                             tiesFromPrevious: piece.tiesFromPrevious || startBeat < sliceStart,
                             tiesToNext: piece.tiesToNext || endBeat > sliceEnd)
        }
    }

    struct Index: Sendable {
        private struct Note: Sendable {
            let original: PracticeScoreNote
            let start: Double
            let end: Double
        }

        private let notes: [Note]
        private let blockMaxEnds: [Double]
        private let hasLeft: Bool
        private let hasRight: Bool
        let barLength: Double
        let beatsPerBar: Int
        let beatUnit: Int
        let totalBeats: Double
        let rhythmSimplified: Bool

        init(exercise: PracticeExercise) {
            beatsPerBar = exercise.beatsPerBar
            beatUnit = exercise.beatUnit
            barLength = Double(exercise.beatsPerBar) * 4 / Double(exercise.beatUnit)
            var simplified = false
            var lastEnd = 0.0
            var foundLeft = false
            var foundRight = false
            notes = exercise.score.map { note in
                let start = ScoreNotation.quantizeToSixteenth(note.startBeat)
                let duration = max(sixteenthBeat, ScoreNotation.quantizeToSixteenth(note.durationBeats))
                if abs(start - note.startBeat) > 0.000_001
                    || abs(duration - note.durationBeats) > 0.000_001 {
                    simplified = true
                }
                lastEnd = max(lastEnd, start + duration)
                if note.hand == .left { foundLeft = true } else { foundRight = true }
                return Note(original: note, start: start, end: start + duration)
            }
            rhythmSimplified = simplified
            totalBeats = lastEnd
            hasLeft = foundLeft
            hasRight = foundRight

            var maxima: [Double] = []
            maxima.reserveCapacity((notes.count + 127) / 128)
            for offset in stride(from: 0, to: notes.count, by: 128) {
                maxima.append(notes[offset..<min(offset + 128, notes.count)].map(\.end).max() ?? 0)
            }
            blockMaxEnds = maxima
        }

        func window(currentBeat: Double, hand: PracticeHand, width: Double, isCompact: Bool) -> ScoreWindow {
            let safeBeat = currentBeat.isFinite
                ? min(1_000_000, max(0, currentBeat)) : 0
            let span = visibleSpan(around: safeBeat, hand: hand, width: width, isCompact: isCompact)
            let start = max(0, safeBeat - min(barLength * 0.4, span * 0.28))
            let end = start + span
            let staves: [ScoreClef]
            switch hand {
            case .left: staves = [.bass]
            case .right: staves = [.treble]
            case .both:
                staves = hasLeft && hasRight ? [.treble, .bass] : (hasLeft ? [.bass] : [.treble])
            }

            let contextStart = floor(start / barLength) * barLength
            var relevant: [Note] = []
            relevant.reserveCapacity(128)
            var dense = false
            let lastIndex = lowerBound(start: end)
            for block in 0..<min(blockMaxEnds.count, (lastIndex + 127) / 128) {
                guard blockMaxEnds[block] > contextStart else { continue }
                for index in (block * 128)..<min((block + 1) * 128, lastIndex) {
                    let note = notes[index]
                    guard note.end > contextStart, includes(note.original.hand, in: hand) else { continue }
                    if relevant.count >= 256 {
                        dense = true
                        break
                    }
                    relevant.append(note)
                }
                if dense { break }
            }

            let completeChords = makeChords(from: relevant, start: start, end: end)
            var chords: [ScoreChord] = []
            chords.reserveCapacity(min(48, completeChords.count))
            var remainingHeads = 96
            for chord in completeChords {
                guard chords.count < 48, remainingHeads > 0 else {
                    dense = true
                    break
                }
                let visibleHeads = Array(chord.heads.prefix(min(12, remainingHeads)))
                if visibleHeads.count < chord.heads.count { dense = true }
                chords.append(ScoreChord(startBeat: chord.startBeat, duration: chord.duration,
                                         hand: chord.hand, heads: visibleHeads,
                                         tiesFromPrevious: chord.tiesFromPrevious,
                                         tiesToNext: chord.tiesToNext))
                remainingHeads -= visibleHeads.count
            }
            let rests = dense ? [] : makeRests(from: relevant, staves: staves, start: start, end: end)
            let current = relevant.filter { $0.start <= safeBeat && $0.end > safeBeat }
                .prefix(6).map { ScoreNotation.pitch($0.original.pitch).spokenName }
            let upcoming = relevant.filter { $0.start > safeBeat }
                .prefix(4).map { ScoreNotation.pitch($0.original.pitch).spokenName }
            return ScoreWindow(startBeat: start, endBeat: end, barLength: barLength,
                               staves: staves, chords: chords, rests: rests,
                               rhythmSimplified: rhythmSimplified, isDense: dense,
                               currentNoteNames: current, upcomingNoteNames: upcoming)
        }

        private func visibleSpan(around beat: Double, hand: PracticeHand,
                                 width: Double, isCompact: Bool) -> Double {
            let maximum = max(0.25, barLength * 2)
            let sampleStart = max(0, beat - barLength * 0.25)
            let sampleEnd = sampleStart + maximum
            let first = lowerBound(start: sampleStart)
            let last = lowerBound(start: sampleEnd)
            var onsets = 0
            var previous: Double? = nil
            for index in first..<min(last, first + 512) {
                let note = notes[index]
                guard includes(note.original.hand, in: hand) else { continue }
                if previous != note.start {
                    onsets += 1
                    previous = note.start
                }
            }
            guard onsets > 0 else { return maximum }
            let usable = max(90, width - (isCompact ? 62 : 94))
            let capacity = max(4, usable / (isCompact ? 17 : 25))
            let density = Double(onsets) / maximum
            let minimum = min(maximum, max(0.25, min(1, barLength)))
            let desired = min(maximum, max(minimum, capacity / density))
            return max(minimum, ScoreNotation.quantizeToSixteenth(desired))
        }

        private func lowerBound(start: Double) -> Int {
            var low = 0
            var high = notes.count
            while low < high {
                let mid = low + (high - low) / 2
                if notes[mid].start < start { low = mid + 1 } else { high = mid }
            }
            return low
        }

        private func includes(_ noteHand: PracticeHand, in selectedHand: PracticeHand) -> Bool {
            selectedHand == .both || selectedHand == noteHand
        }

        private struct ChordKey: Hashable {
            let tick: Int
            let duration: ScoreDuration
            let hand: PracticeHand
            let tiesFromPrevious: Bool
            let tiesToNext: Bool
        }

        private func makeChords(from relevant: [Note], start: Double, end: Double) -> [ScoreChord] {
            var groups: [ChordKey: [ScorePitch]] = [:]
            var accidentalState: [PracticeHand: [Int: ScoreAccidental]] = [:]
            var currentBar = Int(floor(start / barLength))
            let barStart = Double(currentBar) * barLength

            for note in relevant where note.start >= barStart && note.start < start {
                let pitch = ScoreNotation.pitch(note.original.pitch)
                accidentalState[note.original.hand, default: [:]][pitch.diatonicIndex] = pitch.accidental
            }

            for note in relevant where note.end > start {
                for piece in ScoreNotation.spellVisible(startBeat: note.start, endBeat: note.end,
                                                        barLength: barLength,
                                                        windowStart: start, windowEnd: end) {
                    guard piece.startBeat >= start, piece.startBeat < end else { continue }
                    let key = ChordKey(tick: Int((piece.startBeat * 8).rounded()),
                                       duration: piece.duration, hand: note.original.hand,
                                       tiesFromPrevious: piece.tiesFromPrevious,
                                       tiesToNext: piece.tiesToNext)
                    groups[key, default: []].append(ScoreNotation.pitch(note.original.pitch))
                }
            }

            return groups.keys.sorted {
                if $0.tick != $1.tick { return $0.tick < $1.tick }
                if $0.hand != $1.hand { return $0.hand.rawValue < $1.hand.rawValue }
                return $0.duration.beats > $1.duration.beats
            }.map { key in
                let beat = Double(key.tick) / 8
                let bar = Int(floor((beat + 0.000_001) / barLength))
                if bar != currentBar {
                    currentBar = bar
                    accidentalState.removeAll()
                }
                let pitches = Array(Set(groups[key]!.map(\.midi)))
                    .map(ScoreNotation.pitch).sorted { $0.diatonicIndex < $1.diatonicIndex }
                let heads = pitches.map { pitch -> ScoreHead in
                    guard !key.tiesFromPrevious else {
                        return ScoreHead(pitch: pitch, displayedAccidental: nil)
                    }
                    let previous = accidentalState[key.hand]?[pitch.diatonicIndex] ?? .natural
                    accidentalState[key.hand, default: [:]][pitch.diatonicIndex] = pitch.accidental
                    return ScoreHead(pitch: pitch,
                                     displayedAccidental: pitch.accidental == previous ? nil : pitch.accidental)
                }
                return ScoreChord(startBeat: beat, duration: key.duration, hand: key.hand,
                                  heads: heads, tiesFromPrevious: key.tiesFromPrevious,
                                  tiesToNext: key.tiesToNext)
            }
        }

        private func makeRests(from relevant: [Note], staves: [ScoreClef],
                               start: Double, end: Double) -> [ScoreRest] {
            var rests: [ScoreRest] = []
            for clef in staves {
                let intervals = relevant.filter { $0.original.hand == clef.hand && $0.end > start }
                    .map { (max(start, $0.start), min(end, $0.end)) }
                    .filter { $0.0 < $0.1 }
                    .sorted { $0.0 < $1.0 }
                var cursor = start
                for (onset, release) in intervals {
                    if onset > cursor + 0.000_001 {
                        rests += ScoreNotation.spell(startBeat: cursor,
                            durationBeats: onset - cursor, barLength: barLength)
                            .filter { $0.startBeat >= start && $0.startBeat < end }
                            .map { ScoreRest(startBeat: $0.startBeat, duration: $0.duration, hand: clef.hand) }
                    }
                    cursor = max(cursor, release)
                }
                if cursor < end - 0.000_001 {
                    rests += ScoreNotation.spell(startBeat: cursor,
                        durationBeats: end - cursor, barLength: barLength)
                        .filter { $0.startBeat >= start && $0.startBeat < end }
                        .map { ScoreRest(startBeat: $0.startBeat, duration: $0.duration, hand: clef.hand) }
                }
            }
            return rests
        }
    }
}
