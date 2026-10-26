import Foundation

/// Standalone checks; compile with PracticeExercise.swift and the three import files.
@main
struct MIDIImportChecks {
    @MainActor
    static func main() async throws {
        let singleTrack = midi(format: 0, tracks: [
            event(0, [0xFF, 0x03, 0x05] + Array("Piano".utf8))
            + event(0, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])
            + event(0, [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])
            + event(0, [0xFF, 0x59, 0x02, 0x00, 0x00])
            + event(0, [0x90, 60, 90])
            + event(0, [64, 70]) // Running note-on status.
            + event(480, [60, 0]) // Note-on with velocity zero is note-off.
            + event(0, [64, 0])
            + event(0, [0x99, 36, 100])
            + event(120, [0x89, 36, 0])
            + event(0, [0x90, 10, 100])
            + event(120, [0x80, 10, 0])
            + event(0, [0xFF, 0x2F, 0x00])
        ])
        let song = try MIDIFileImporter.parse(data: singleTrack, title: "  My\n Song.mid  ")
        expect(song.title == "My Song", "File titles should be bounded and cleaned")
        expect(song.sourceFormat == 0 && song.ticksPerQuarterNote == 480, "SMF header should parse")
        expect(song.tracks.count == 1 && song.noteCount == 2, "Running status should preserve both notes")
        expect(song.tracks[0].hand == .both && song.tracks[0].detail.contains("Split at C4"),
               "A mixed track should show its split heuristic")
        expect(song.tracks[0].notes.map(\.velocity) == [90, 70], "Note-on velocity should survive import")
        expect(song.tracks[0].notes.allSatisfy { $0.durationBeats == 1 }, "Note-off timing should survive import")
        expect(song.skippedPercussionNotes == 1 && song.skippedOutOfRangeNotes == 1,
               "Percussion and off-keyboard notes should be counted")
        expect(song.summary.contains("outside A0–C8") && song.summary.contains("percussion"),
               "Skipped notes should be explained")
        expect(song.keySignatures.first?.label == "C major", "Key signature should parse")
        expect(song.practiceExercise(hand: .both)?.score.count == 2,
               "Imported notes should convert into timed practice score")
        expect(song.practiceExercise(hand: .left) == nil,
               "C4 and higher in a split track should go to the right hand")

        let conductor = event(0, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])
            + event(0, [0xFF, 0x58, 0x04, 0x03, 0x02, 0x18, 0x08])
            + event(480, [0xFF, 0x51, 0x03, 0x06, 0x1A, 0x80])
            + event(0, [0xFF, 0x2F, 0x00])
        let melody = event(0, [0xFF, 0x03, 0x06] + Array("Melody".utf8))
            + event(0, [0x90, 72, 101])
            + event(480, [0x80, 72, 0])
            + event(0, [0xFF, 0x2F, 0x00])
        let bass = event(0, [0xFF, 0x03, 0x04] + Array("Bass".utf8))
            + event(0, [0x91, 48, 80])
            + event(960, [0x81, 48, 0])
            + event(0, [0xFF, 0x2F, 0x00])
        let multitrack = midi(format: 1, tracks: [conductor, melody, bass])
        let duet = try MIDIFileImporter.parse(data: multitrack, title: "Duet")
        expect(duet.tracks.count == 2 && duet.noteCount == 2, "Conductor tracks should not appear as playable tracks")
        expect(duet.tracks.first(where: { $0.title == "Bass" })?.hand == .left,
               "Lower part should default to left hand")
        expect(duet.tracks.first(where: { $0.title == "Melody" })?.hand == .right,
               "Higher part should default to right hand")
        expect(duet.tempoChanges.count == 2 && duet.tempoChanges[1].beat == 1,
               "Original tempo changes should remain in metadata")
        expect(duet.summary.contains("practice uses your selected tempo throughout"),
               "Fixed practice tempo should be disclosed")
        expect(duet.practiceExercise(hand: .both)?.beatsPerBar == 3,
               "Imported meter should reach the practice score")
        expect(duet.practiceExercise(hand: .left)?.score.map(\.pitch) == [48],
               "Left-hand practice should select its part")

        var overlapping = duet
        let original = overlapping.tracks[0]
        overlapping.tracks[0] = ImportedSongTrack(
            id: original.id, sourceTrackIndex: original.sourceTrackIndex,
            channel: original.channel, title: original.title, hand: original.hand,
            notes: [ImportedSongNote(pitch: 48, startBeat: 0, durationBeats: 1, velocity: 70)]
        )
        let other = overlapping.tracks[1]
        overlapping.tracks[1] = ImportedSongTrack(
            id: other.id, sourceTrackIndex: other.sourceTrackIndex,
            channel: other.channel, title: other.title, hand: other.hand,
            notes: [ImportedSongNote(pitch: 48, startBeat: 0, durationBeats: 2, velocity: 80)]
        )
        expect(overlapping.practiceExercise()?.score.count == 1,
               "Overlapping parts must not create duplicate score targets")
        expect(overlapping.practiceExercise()?.score.first?.durationBeats == 2,
               "The longer overlapping note should be retained")

        let fixtureURL = URL(fileURLWithPath: "Tests/Fixtures/Twinkle Duet.mid")
        let fixture = try MIDIFileImporter.parse(data: Data(contentsOf: fixtureURL),
                                                 title: fixtureURL.lastPathComponent)
        expect(fixture.tracks.count == 2 && fixture.noteCount == 18,
               "Repository MIDI fixture should import both hands")
        expect(fixture.practiceExercise()?.availableHands == [.both, .left, .right],
               "Fixture should convert to a two-hand guided score")

        try checkMalformed(singleTrack)
        try await checkPersistence(singleTrack, duet: duet)
        print("MIDI import checks passed: SMF 0/1, running status, note timing and velocity, tempo/meter/key metadata, hand assignment, duplicate notes, malformed files, async import, persistence and recovery")
    }

    private static func checkMalformed(_ valid: Data) throws {
        expectFailure(Data(), containing: "MThd")
        expectFailure(Data(valid.dropLast()), containing: "truncated")
        expectFailure(midi(format: 2, tracks: [[0, 0xFF, 0x2F, 0]]), containing: "format 2")
        expectFailure(midi(format: 0, division: 0xE728, tracks: [[0, 0xFF, 0x2F, 0]]),
                      containing: "SMPTE")
        expectFailure(midi(format: 0, tracks: [[0x81, 0x80, 0x80, 0x80, 0, 0xFF, 0x2F, 0]]),
                      containing: "four bytes")
        let statusAfterMeta = event(0, [0x90, 60, 90])
            + event(0, [0xFF, 0x01, 0x00])
            + event(0, [60, 0])
        expectFailure(midi(format: 0, tracks: [statusAfterMeta]), containing: "running status")
        expectFailure(Data(count: MIDIFileImporter.maximumFileBytes + 1), containing: "8 MB")

        let danglingFlood = Array(repeating: event(0, [0x90, 60, 80]), count: 40_001)
            .flatMap { $0 }
        expectFailure(midi(format: 0, tracks: [danglingFlood]), containing: "40000 piano notes")

        let dangling = midi(format: 0, tracks: [
            event(0, [0x90, 60, 80]) + event(240, [0xFF, 0x2F, 0])
        ])
        let repaired = try MIDIFileImporter.parse(data: dangling, title: "Dangling")
        expect(repaired.closedDanglingNotes == 1 && repaired.tracks[0].notes[0].durationBeats == 0.5,
               "Missing note-off should close at track end and be disclosed")

        let oddMeter = midi(format: 0, tracks: [
            event(0, [0xFF, 0x51, 0x03, 0xFF, 0xFF, 0xFF])
            + event(0, [0xFF, 0x58, 0x04, 0x20, 0x06, 0x18, 0x08])
            + event(0, [0x90, 60, 80]) + event(480, [0x80, 60, 0])
        ])
        let normalized = try MIDIFileImporter.parse(data: oddMeter, title: "Odd meter")
        expect(normalized.practiceExercise()?.beatsPerBar == 16
               && normalized.practiceExercise()?.beatUnit == 4,
               "Unsupported practice meter should be normalized")
        expect(normalized.summary.contains("practice uses 16/4 throughout")
               && normalized.summary.contains("practice uses your selected tempo throughout")
               && normalized.summary.contains("Suggested 40 BPM"),
               "Meter and tempo normalization must be disclosed")
    }

    @MainActor
    private static func checkPersistence(_ data: Data, duet: ImportedPracticeSong) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Piano-MIDIImportChecks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("songs.json")
        let library = ImportedSongLibrary(storageURL: storage)
        let song = try library.importData(data, title: "Saved.mid")
        let trackID = song.tracks[0].id
        try library.setHand(.left, forTrack: trackID, in: song.id)
        try library.setIncluded(false, forTrack: trackID, in: song.id)
        try library.rename(song.id, to: "  New\n Name ")
        let restored = ImportedSongLibrary(storageURL: storage)
        expect(restored.songs.count == 1 && restored.songs[0].title == "New Name",
               "Title and song should persist")
        expect(restored.songs[0].tracks[0].hand == .left
               && !restored.songs[0].tracks[0].isIncluded,
               "Track hand and inclusion should persist")
        expect(restored.songs[0].practiceExercise() == nil,
               "Excluded tracks should not become score targets")
        try restored.setIncluded(true, forTrack: trackID, in: song.id)
        expect(restored.songs[0].practiceExercise(hand: .left)?.score.count == 2,
               "Reincluded tracks should retain original notes")

        let file = directory.appendingPathComponent("Duet.mid")
        let conductor = event(0, [0xFF, 0x2F, 0])
        let note = event(0, [0x90, 60, 100]) + event(480, [0x80, 60, 0])
        try midi(format: 1, tracks: [conductor, note]).write(to: file)
        let asyncImported = try await restored.importFile(url: file)
        expect(asyncImported.title == "Duet" && restored.songs.count == 2,
               "Async URL import should add the parsed file")

        // Old saved tracks without inclusion state must remain enabled.
        let encoded = try JSONEncoder().encode(duet)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var tracks = object["tracks"] as! [[String: Any]]
        tracks[0].removeValue(forKey: "isIncluded")
        object["tracks"] = tracks
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ImportedPracticeSong.self, from: legacy)
        expect(decoded.tracks[0].isIncluded, "Older stored tracks should default to included")

        try restored.delete(song.id)
        expect(restored.songs.count == 1, "Delete should persist")
        try Data("corrupt".utf8).write(to: storage)
        let recovered = ImportedSongLibrary(storageURL: storage)
        expect(recovered.songs.isEmpty && recovered.loadWarning != nil,
               "Corrupt JSON should never reach a practice precondition")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        expect(backups.contains(where: { $0.hasPrefix("ImportedPracticeSongs.corrupt-") }),
               "Corrupt stored data should be retained as a backup")
        _ = try recovered.importData(data, title: "Reimport")
        expect(recovered.songs.count == 1, "Import should work after recoverable corruption")

        var invalidLibraryJSON = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([duet])) as! [[String: Any]]
        var invalidTracks = invalidLibraryJSON[0]["tracks"] as! [[String: Any]]
        var invalidNotes = invalidTracks[0]["notes"] as! [[String: Any]]
        invalidNotes[0]["pitch"] = 0
        invalidTracks[0]["notes"] = invalidNotes
        invalidLibraryJSON[0]["tracks"] = invalidTracks
        try JSONSerialization.data(withJSONObject: invalidLibraryJSON).write(to: storage)
        let structurallyCorrupt = ImportedSongLibrary(storageURL: storage)
        expect(structurallyCorrupt.songs.isEmpty && structurallyCorrupt.loadWarning != nil,
               "Valid JSON with invalid piano notes must be quarantined before score creation")
    }

    private static func expectFailure(_ data: Data, containing fragment: String) {
        do {
            _ = try MIDIFileImporter.parse(data: data, title: "Broken")
            fatalError("Expected MIDI import to fail: \(fragment)")
        } catch {
            expect(error.localizedDescription.contains(fragment),
                   "Expected \(fragment) in error, got \(error.localizedDescription)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    private static func midi(format: Int, division: Int = 480, tracks: [[UInt8]]) -> Data {
        var bytes: [UInt8] = Array("MThd".utf8)
            + [0, 0, 0, 6]
            + be16(format) + be16(tracks.count) + be16(division)
        for track in tracks {
            bytes += Array("MTrk".utf8) + be32(track.count) + track
        }
        return Data(bytes)
    }

    private static func event(_ delta: Int, _ bytes: [UInt8]) -> [UInt8] {
        vlq(delta) + bytes
    }

    private static func vlq(_ number: Int) -> [UInt8] {
        var value = number
        var bytes = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            bytes.insert(UInt8(value & 0x7F) | 0x80, at: 0)
            value >>= 7
        }
        return bytes
    }

    private static func be16(_ value: Int) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func be32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
