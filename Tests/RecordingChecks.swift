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
        let studio = PerformanceStudio(libraryURL: libraryURL)
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
        expect(failingStudio.finishRecording() == nil && failingStudio.takes.isEmpty,
               "Failed write must not display an unsaved take")

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
