import Foundation

/// MIDI timing is kept in quarter-note beats. Playback practice uses one selected
/// tempo, while the original tempo map remains visible in the song metadata.
struct ImportedSongNote: Codable, Equatable, Sendable {
    let pitch: UInt8
    let startBeat: Double
    let durationBeats: Double
    let velocity: UInt8
}

struct ImportedSongTrack: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceTrackIndex: Int
    let channel: UInt8 // Zero based MIDI channel.
    var title: String
    var hand: PracticeHand
    var isIncluded: Bool
    let notes: [ImportedSongNote]

    init(id: UUID, sourceTrackIndex: Int, channel: UInt8, title: String,
         hand: PracticeHand, isIncluded: Bool = true, notes: [ImportedSongNote]) {
        self.id = id
        self.sourceTrackIndex = sourceTrackIndex
        self.channel = channel
        self.title = title
        self.hand = hand
        self.isIncluded = isIncluded
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceTrackIndex, channel, title, hand, isIncluded, notes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceTrackIndex = try values.decode(Int.self, forKey: .sourceTrackIndex)
        channel = try values.decode(UInt8.self, forKey: .channel)
        title = try values.decode(String.self, forKey: .title)
        hand = try values.decode(PracticeHand.self, forKey: .hand)
        isIncluded = try values.decodeIfPresent(Bool.self, forKey: .isIncluded) ?? true
        notes = try values.decode([ImportedSongNote].self, forKey: .notes)
    }

    var detail: String {
        let assignment = hand == .both ? "Split at C4" : hand.title
        return "Channel \(Int(channel) + 1) · \(notes.count) notes · \(assignment)"
    }
}

struct ImportedTempoChange: Codable, Equatable, Sendable {
    let beat: Double
    let microsecondsPerQuarterNote: Int

    var bpm: Double { 60_000_000 / Double(microsecondsPerQuarterNote) }
}

struct ImportedTimeSignature: Codable, Equatable, Sendable {
    let beat: Double
    let beatsPerBar: Int
    let beatUnit: Int

    var label: String { "\(beatsPerBar)/\(beatUnit)" }
}

struct ImportedKeySignature: Codable, Equatable, Sendable {
    let beat: Double
    let fifths: Int
    let isMinor: Bool

    var label: String {
        let major = ["C♭", "G♭", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯"]
        let minor = ["A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯", "G♯", "D♯", "A♯"]
        let index = fifths + 7
        guard (0..<major.count).contains(index) else { return "Unknown key" }
        return "\(isMinor ? minor[index] : major[index]) \(isMinor ? "minor" : "major")"
    }
}

struct ImportedPracticeSong: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    let importedAt: Date
    let sourceFormat: Int
    let ticksPerQuarterNote: Int
    var tracks: [ImportedSongTrack]
    let tempoChanges: [ImportedTempoChange]
    let timeSignatures: [ImportedTimeSignature]
    let keySignatures: [ImportedKeySignature]
    let skippedPercussionNotes: Int
    let skippedOutOfRangeNotes: Int
    let closedDanglingNotes: Int

    var noteCount: Int { tracks.reduce(0) { $0 + $1.notes.count } }
    var durationBeats: Double {
        tracks.flatMap(\.notes).map { $0.startBeat + $0.durationBeats }.max() ?? 0
    }

    var suggestedBPM: Int {
        let first = tempoChanges.first(where: { $0.beat == 0 }) ?? tempoChanges.first
        return min(240, max(40, Int((first?.bpm ?? 120).rounded())))
    }

    private var initialSourceBPM: Double {
        (tempoChanges.first(where: { $0.beat == 0 }) ?? tempoChanges.first)?.bpm ?? 120
    }

    var initialTimeSignature: ImportedTimeSignature {
        timeSignatures.first(where: { $0.beat == 0 })
            ?? timeSignatures.first
            ?? ImportedTimeSignature(beat: 0, beatsPerBar: 4, beatUnit: 4)
    }

    private var practiceTimeSignature: ImportedTimeSignature {
        let initial = initialTimeSignature
        return ImportedTimeSignature(beat: 0, beatsPerBar: min(16, initial.beatsPerBar),
                                     beatUnit: [1, 2, 4, 8, 16, 32].contains(initial.beatUnit)
                                        ? initial.beatUnit : 4)
    }

    var summary: String {
        var parts = ["\(noteCount) notes", initialTimeSignature.label, "Suggested \(suggestedBPM) BPM"]
        if let key = keySignatures.first { parts.append(key.label) }
        if tempoChanges.count > 1 || abs(initialSourceBPM - Double(suggestedBPM)) >= 0.5 {
            let original = Int(initialSourceBPM.rounded())
            parts.append("Original tempo \(original) BPM with \(tempoChanges.count) marks; practice uses your selected tempo throughout")
        }
        if timeSignatures.count > 1 || practiceTimeSignature.label != initialTimeSignature.label {
            parts.append("\(timeSignatures.count) original time signature marks; practice uses \(practiceTimeSignature.label) throughout")
        }
        if skippedPercussionNotes > 0 { parts.append("\(skippedPercussionNotes) percussion notes skipped") }
        if skippedOutOfRangeNotes > 0 { parts.append("\(skippedOutOfRangeNotes) notes outside A0–C8 skipped") }
        if closedDanglingNotes > 0 { parts.append("\(closedDanglingNotes) missing note-offs repaired") }
        return parts.joined(separator: " · ")
    }

    /// Converts a hand assignment to the score used by guided practice.
    /// A track assigned to both hands is divided at middle C (C4, MIDI 60).
    func practiceExercise(hand selectedHand: PracticeHand = .both) -> PracticeExercise? {
        guard isValidForPractice else { return nil }
        let notes: [PracticeScoreNote] = tracks.filter(\.isIncluded).flatMap { track in
            track.notes.compactMap { note in
                let noteHand: PracticeHand = track.hand == .both
                    ? (note.pitch < 60 ? .left : .right) : track.hand
                guard selectedHand == .both || selectedHand == noteHand else { return nil }
                return PracticeScoreNote(pitch: note.pitch, startBeat: note.startBeat,
                                         durationBeats: note.durationBeats, hand: noteHand,
                                         velocity: note.velocity)
            }
        }
        var unique: [NoteOnset: PracticeScoreNote] = [:]
        for note in notes {
            let tick = Int((note.startBeat * Double(ticksPerQuarterNote)).rounded())
            let key = NoteOnset(pitch: note.pitch, tick: tick)
            if let current = unique[key],
               current.durationBeats > note.durationBeats
                || (current.durationBeats == note.durationBeats && current.velocity >= note.velocity) {
                continue
            }
            unique[key] = note
        }
        guard !unique.isEmpty else { return nil }
        let meter = practiceTimeSignature
        return PracticeExercise(id: "imported-\(id.uuidString)-\(selectedHand.rawValue)",
                                title: title, detail: summary, category: .melodies,
                                difficulty: .developing, suggestedBPM: suggestedBPM,
                                beatsPerBar: meter.beatsPerBar, beatUnit: meter.beatUnit,
                                score: Array(unique.values))
    }

    /// Validate decoded files before they can reach PracticeExercise preconditions.
    var isValidForPractice: Bool {
        !title.isEmpty && title.count <= 80
            && (0...1).contains(sourceFormat)
            && (1...32_767).contains(ticksPerQuarterNote)
            && !tracks.isEmpty && tracks.count <= 32 && noteCount > 0 && noteCount <= 40_000
            && Set(tracks.map(\.id)).count == tracks.count
            && tracks.allSatisfy { track in
                !track.title.isEmpty && track.title.count <= 80 && track.channel < 16
                    && (0..<32).contains(track.sourceTrackIndex)
            }
            && tracks.flatMap(\.notes).allSatisfy { note in
                (21...108).contains(note.pitch) && (1...127).contains(note.velocity)
                    && note.startBeat.isFinite && note.startBeat >= 0 && note.startBeat <= 8_192
                    && note.durationBeats.isFinite && note.durationBeats > 0
                    && note.startBeat + note.durationBeats <= 8_193
            }
            && tempoChanges.count <= 2_048 && tempoChanges.allSatisfy {
                $0.beat.isFinite && $0.beat >= 0 && $0.beat <= 8_192
                    && (1...0xFF_FFFF).contains($0.microsecondsPerQuarterNote)
            }
            && timeSignatures.count <= 2_048 && timeSignatures.allSatisfy {
                $0.beat.isFinite && $0.beat >= 0 && $0.beat <= 8_192
                    && (1...255).contains($0.beatsPerBar)
                    && [1, 2, 4, 8, 16, 32, 64, 128].contains($0.beatUnit)
            }
            && keySignatures.count <= 2_048 && keySignatures.allSatisfy {
                $0.beat.isFinite && $0.beat >= 0 && $0.beat <= 8_192
                    && (-7...7).contains($0.fifths)
            }
            && skippedPercussionNotes >= 0 && skippedOutOfRangeNotes >= 0
            && closedDanglingNotes >= 0
    }
}

private struct NoteOnset: Hashable {
    let pitch: UInt8
    let tick: Int
}
