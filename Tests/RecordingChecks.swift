import Foundation

/// Standalone checks for migration, MIDI, editing, persistence, and playback.
/// Compile with PerformanceTake, PianoSoundProfile, MIDIExporter, RecordingEditor,
/// AudioExporter, PremiumStore, and PerformanceStudio source files.
@main
struct RecordingChecks {
    @MainActor
    static func main() async throws {
        let legacyJSON = """
        [{"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"duration":1,
          "events":[{"note":60,"time":0,"isNoteOn":true},
                    {"note":60,"time":0.5,"isNoteOn":false}]}]
        """
        let legacy = try JSONDecoder().decode([PerformanceTake].self, from: Data(legacyJSON.utf8))[0]
        expect(legacy.title == "Untitled take", "Legacy take title must default")
        expect(legacy.events[0].velocity == 100, "Legacy note velocity must default")
        expect(legacy.isValid, "Legacy take must remain playable")

        let edited = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 1,
            events: [
                PerformanceEvent(time: 0.1, sustain: true),
                PerformanceEvent(note: 60, time: 0.2, isNoteOn: true, velocity: 74),
                PerformanceEvent(note: 60, time: 0.4, isNoteOn: false),
                PerformanceEvent(note: 64, time: 0.5, isNoteOn: true, velocity: 83),
                PerformanceEvent(note: 64, time: 0.8, isNoteOn: false),
                PerformanceEvent(time: 0.9, sustain: false)
            ], title: "Evening practice"
        )
        let encoded = try JSONEncoder().encode(edited)
        let decodedEdited = try JSONDecoder().decode(PerformanceTake.self, from: encoded)
        expect(decodedEdited.title == edited.title,
               "New titles must round trip")
        let midi = try MIDIExporter.data(for: edited)
        expect(midi.containsSubsequence([0x90, 60, 74]), "MIDI must retain touch velocity")
        expect(midi.containsSubsequence([0x90, 64, 83]), "MIDI must retain every note velocity")

        guard let sustainedClip = RecordingEditor.excerpt(from: edited, start: 0.45, end: 0.7) else {
            fatalError("Could not trim sustained clip")
        }
        expect(sustainedClip.isValid && abs(sustainedClip.duration - 0.25) < 0.000_001,
               "Clip duration and ordering must remain valid")
        expect(sustainedClip.events[0].sustain == true, "Pedal state must carry into clip")
        expect(sustainedClip.events.contains { $0.note == 60 && $0.isNoteOn && $0.time == 0 },
               "Sustained note must be synthesized at the cut")
        expect(sustainedClip.events.contains {
            $0.note == 64 && !$0.isNoteOn && abs($0.time - 0.25) < 0.000_001
        },
               "Held note must close at the end cut")
        expect(sustainedClip.events.last?.sustain == false, "Pedal must close at end cut")
        expect(RecordingEditor.excerpt(from: edited, start: 0.91, end: 1) == nil,
               "A silent selection should not create a take")

        let repeatedUnderPedal = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 0.7,
            events: [
                PerformanceEvent(time: 0, sustain: true),
                PerformanceEvent(note: 60, time: 0.1, isNoteOn: true, velocity: 50),
                PerformanceEvent(note: 60, time: 0.2, isNoteOn: false),
                PerformanceEvent(note: 60, time: 0.3, isNoteOn: true, velocity: 70),
                PerformanceEvent(note: 60, time: 0.4, isNoteOn: false),
                PerformanceEvent(time: 0.6, sustain: false)
            ]
        )
        let repeatedClip = RecordingEditor.excerpt(
            from: repeatedUnderPedal, start: 0.45, end: 0.55
        )!
        expect(repeatedClip.events.filter { $0.isNoteOn }.map(\.velocity) == [50, 70],
               "Repeated sustained strikes must survive a trim boundary")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PianoFlowRecordingChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryURL = directory.appendingPathComponent("performances.json")
        let studio = PerformanceStudio(libraryURL: libraryURL, hasPremiumAccess: { true })
        studio.beginRecording(heldNotes: [60], heldVelocities: [60: 71], sustain: true)
        studio.capture(note: 60, isNoteOn: false)
        guard let recorded = studio.finishRecording() else { fatalError("Recording failed") }
        expect(recorded.events.first?.sustain == true, "Initial pedal state must be captured")
        expect(recorded.events.first(where: { $0.isNoteOn })?.velocity == 71,
               "Held MIDI velocity must be captured")
        expect(PerformanceStudio(libraryURL: libraryURL).takes.count == 1,
               "Take must persist and reload")
        expect(studio.rename(recorded, to: "  Nocturne  "), "Rename should succeed")
        expect(PerformanceStudio(libraryURL: libraryURL).takes[0].title == "Nocturne",
               "Renamed title must persist")
        expect(studio.saveExcerpt(of: edited, from: 0.3, to: 0.6) != nil,
               "Section should save as a separate take")
        expect(studio.takes.count == 2, "Original take must be retained")

        let blockedParent = directory.appendingPathComponent("blocked")
        try Data().write(to: blockedParent)
        let failingStudio = PerformanceStudio(
            libraryURL: blockedParent.appendingPathComponent("performances.json")
        )
        failingStudio.beginRecording(heldNotes: [64])
        expect(failingStudio.finishRecording() == nil && failingStudio.takes.count == 1,
               "Failed write must keep the captured take available for recovery")
        let retainedTake = failingStudio.takes[0]
        expect(failingStudio.hasUnsavedTakes && failingStudio.unsavedTakeIDs.contains(retainedTake.id),
               "Retained takes must be clearly marked as unsaved")
        expect(retainedTake.isValid && retainedTake.events.last?.isNoteOn == false,
               "A failed save must still close held notes in the recoverable take")
        expect(failingStudio.midiFileURL(for: retainedTake) != nil,
               "An unsaved take must remain exportable")
        expect(!failingStudio.retrySavingTakes() && failingStudio.hasUnsavedTakes,
               "Failed retry must retain the take and its unsaved status")
        try FileManager.default.removeItem(at: blockedParent)
        expect(failingStudio.retrySavingTakes() && !failingStudio.hasUnsavedTakes,
               "Retry must save retained takes when storage becomes available")
        expect(failingStudio.lastError == nil, "Successful recovery must clear its save error")
        expect(PerformanceStudio(libraryURL: blockedParent.appendingPathComponent("performances.json"))
            .takes.first?.id == retainedTake.id,
               "A recovered take must survive relaunch without duplicating it")

        let damagedURL = directory.appendingPathComponent("damaged.json")
        let originalBytes = Data("not valid JSON".utf8)
        try originalBytes.write(to: damagedURL)
        let recoveringStudio = PerformanceStudio(libraryURL: damagedURL)
        expect(recoveringStudio.takes.isEmpty && recoveringStudio.lastError != nil,
               "Damaged library must load safely")
        recoveringStudio.beginRecording(heldNotes: [65])
        expect(recoveringStudio.finishRecording() != nil,
               "New recordings should save after a successful recovery backup")
        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("performances.recovery-") }
        let preservedBytes = try backupURLs.contains { try Data(contentsOf: $0) == originalBytes }
        expect(preservedBytes,
               "Corrupt library bytes must survive a subsequent recording")

        let protectedDirectory = directory.appendingPathComponent("protected", isDirectory: true)
        try FileManager.default.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
        let protectedURL = protectedDirectory.appendingPathComponent("performances.json")
        try originalBytes.write(to: protectedURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: protectedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protectedDirectory.path) }
        let blockedRecoveryStudio = PerformanceStudio(libraryURL: protectedURL)
        blockedRecoveryStudio.beginRecording(heldNotes: [67])
        expect(blockedRecoveryStudio.finishRecording() == nil && blockedRecoveryStudio.hasUnsavedTakes,
               "A failed recovery backup must retain new recordings without overwriting the original")
        let protectedBytes = try Data(contentsOf: protectedURL)
        expect(protectedBytes == originalBytes,
               "Failed recovery must preserve the damaged library bytes")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: protectedDirectory.path)
        expect(blockedRecoveryStudio.retrySavingTakes() && !blockedRecoveryStudio.hasUnsavedTakes,
               "Retry must repeat a previously blocked backup when storage becomes writable")
        let recoveredBackups = try FileManager.default.contentsOfDirectory(
            at: protectedDirectory, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("performances.recovery-") }
        let backupRetainsOriginal = try recoveredBackups.contains { try Data(contentsOf: $0) == originalBytes }
        expect(backupRetainsOriginal,
               "Retry must preserve the original damaged bytes before saving the retained take")

        let timed = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 0.4,
            events: [
                PerformanceEvent(note: 60, time: 0, isNoteOn: true, velocity: 55),
                PerformanceEvent(note: 60, time: 0.05, isNoteOn: false)
            ]
        )
        var playedVelocities: [UInt8] = []
        studio.play(timed, options: PerformancePlaybackOptions(rate: 2),
                    noteOn: { _, velocity in playedVelocities.append(velocity) },
                    noteOff: { _ in }, sustain: { _ in })
        try await Task.sleep(nanoseconds: 100_000_000)
        expect(studio.playingTakeID == timed.id, "Playback must retain trailing silence")
        try await Task.sleep(nanoseconds: 180_000_000)
        expect(studio.playingTakeID == nil && playedVelocities == [55],
               "Playback must finish and deliver recorded velocity")

        let shortLoop = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 0.1,
            events: [
                PerformanceEvent(note: 64, time: 0, isNoteOn: true),
                PerformanceEvent(note: 64, time: 0.02, isNoteOn: false)
            ]
        )
        var loopCount = 0
        studio.play(shortLoop, options: PerformancePlaybackOptions(loop: true),
                    noteOn: { _, _ in loopCount += 1 }, noteOff: { _ in }, sustain: { _ in })
        try await Task.sleep(nanoseconds: 340_000_000)
        studio.stopPlayback()
        expect(loopCount >= 2 && studio.playingTakeID == nil, "Loop must repeat and stop")

        var loopEntitled = true
        let revocableStudio = PerformanceStudio(
            libraryURL: directory.appendingPathComponent("revocable.json"),
            hasPremiumAccess: { loopEntitled }
        )
        var revocableOnsets = 0
        var revocableReleases = 0
        revocableStudio.play(shortLoop, options: PerformancePlaybackOptions(loop: true),
                             noteOn: { _, _ in revocableOnsets += 1 },
                             noteOff: { _ in revocableReleases += 1 }, sustain: { _ in })
        try await Task.sleep(nanoseconds: 60_000_000)
        expect(revocableOnsets >= 1, "Premium loop must start while entitled")
        loopEntitled = false
        try await Task.sleep(nanoseconds: 250_000_000)
        expect(revocableStudio.playingTakeID == nil && revocableReleases >= revocableOnsets,
               "An active premium loop must stop and release notes after entitlement loss")
        let onsetsAfterRevocation = revocableOnsets
        try await Task.sleep(nanoseconds: 140_000_000)
        expect(revocableOnsets == onsetsAfterRevocation,
               "A revoked loop must not schedule another note")

        let freeURL = directory.appendingPathComponent("free-performances.json")
        let freeStudio = PerformanceStudio(libraryURL: freeURL, hasPremiumAccess: { false })
        freeStudio.play(timed, noteOn: { _, _ in }, noteOff: { _ in }, sustain: { _ in })
        expect(freeStudio.playingTakeID == timed.id, "Full-speed replay must remain free")
        let advancedOptions: [PerformancePlaybackOptions] = [
            .init(rate: 1.5), .init(loop: true), .init(region: 0...0.3)
        ]
        for options in advancedOptions {
            freeStudio.lastError = nil
            freeStudio.play(edited, options: options,
                            noteOn: { _, _ in }, noteOff: { _ in }, sustain: { _ in })
            expect(freeStudio.playingTakeID == timed.id,
                   "Denied advanced playback must not replace a playing take")
            expect(freeStudio.lastError?.contains("Premium") == true,
                   "Speed, loop, and selected sections must require Premium")
        }
        freeStudio.stopPlayback()
        expect(freeStudio.saveExcerpt(of: edited, from: 0.3, to: 0.6) == nil
               && freeStudio.takes.isEmpty && !FileManager.default.fileExists(atPath: freeURL.path),
               "A free account must not save an excerpt or change its library")

        freeStudio.beginRecording(heldNotes: [60])
        guard let freeTake = freeStudio.finishRecording() else {
            fatalError("Basic recording must remain free")
        }
        expect(freeStudio.rename(freeTake, to: "Free take"), "Renaming must remain free")
        if let midiURL = freeStudio.midiFileURL(for: freeTake) {
            expect(FileManager.default.fileExists(atPath: midiURL.path), "MIDI sharing must remain free")
            try? FileManager.default.removeItem(at: midiURL)
        } else {
            fatalError("MIDI sharing must remain free")
        }

        for (format, profile, options) in [
            (RecordingAudioFormat.wav, PianoSoundProfile.concert, PerformancePlaybackOptions()),
            (.m4a, .warmStudio, .init()),
            (.m4a, .concert, .init(rate: 1.5)),
            (.m4a, .concert, .init(loop: true)),
            (.m4a, .concert, .init(region: 0...0.3))
        ] {
            freeStudio.lastError = nil
            let url = await freeStudio.audioFileURL(
                for: edited, format: format, profile: profile, options: options
            )
            expect(url == nil && freeStudio.lastError?.contains("Premium") == true,
                   "Protected audio export must be denied before rendering")
        }
        freeStudio.lastError = nil
        let freeAudioURL = await freeStudio.audioFileURL(
            for: edited, format: .m4a, profile: .concert
        )
        expect(freeAudioURL != nil || freeStudio.lastError?.contains("Premium") == false,
               "Full-speed Concert M4A must not be behind the Premium gate")
        if let freeAudioURL { try? FileManager.default.removeItem(at: freeAudioURL) }
        freeStudio.delete(freeTake)
        expect(freeStudio.takes.isEmpty, "Deleting a take must remain free")

        let heldLoop = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 1,
            events: [
                PerformanceEvent(note: 67, time: 0, isNoteOn: true),
                PerformanceEvent(note: 67, time: 0.9, isNoteOn: false)
            ]
        )
        var transientStudio: PerformanceStudio? = PerformanceStudio(
            libraryURL: directory.appendingPathComponent("transient.json"),
            hasPremiumAccess: { true }
        )
        weak let weakStudio = transientStudio
        var transientOnsets = 0
        var transientReleases = 0
        transientStudio?.play(heldLoop, options: PerformancePlaybackOptions(loop: true),
                              noteOn: { _, _ in transientOnsets += 1 },
                              noteOff: { _ in transientReleases += 1 },
                              sustain: { _ in })
        try await Task.sleep(nanoseconds: 60_000_000)
        expect(transientOnsets == 1, "Transient playback should start before teardown")
        transientStudio = nil
        try await Task.sleep(nanoseconds: 60_000_000)
        expect(weakStudio == nil && transientReleases == 1,
               "A looping Studio must deallocate and release its held notes")
        print("Recording checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}

private extension Data {
    func containsSubsequence(_ bytes: [UInt8]) -> Bool {
        range(of: Data(bytes)) != nil
    }
}
