import Foundation
import Observation

@MainActor
@Observable
final class PerformanceStudio {
    private(set) var takes: [PerformanceTake] = []
    private(set) var isRecording = false
    private(set) var playingTakeID: UUID?
    var lastError: String?

    @ObservationIgnored private var recordingStartedAt: TimeInterval = 0
    @ObservationIgnored private var capturedEvents: [PerformanceEvent] = []
    @ObservationIgnored private var heldRecordingNotes: Set<UInt8> = []
    @ObservationIgnored private var recordingSustain = false
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var playbackHeldNotes: Set<UInt8> = []
    @ObservationIgnored private var playbackNoteOff: ((UInt8) -> Void)?
    @ObservationIgnored private var playbackSustain: ((Bool) -> Void)?
    @ObservationIgnored private var playbackGeneration = UUID()

    init() {
        loadTakes()
    }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        capturedEvents = []
        heldRecordingNotes = []
        recordingSustain = false
        recordingStartedAt = ProcessInfo.processInfo.systemUptime
    }

    func capture(note: UInt8, isNoteOn: Bool) {
        guard isRecording else { return }
        if isNoteOn {
            guard heldRecordingNotes.insert(note).inserted else { return }
        } else {
            guard heldRecordingNotes.remove(note) != nil else { return }
        }
        capturedEvents.append(
            PerformanceEvent(
                note: note,
                time: ProcessInfo.processInfo.systemUptime - recordingStartedAt,
                isNoteOn: isNoteOn
            )
        )
    }

    func captureSustain(_ enabled: Bool) {
        guard isRecording, recordingSustain != enabled else { return }
        recordingSustain = enabled
        capturedEvents.append(
            PerformanceEvent(
                time: ProcessInfo.processInfo.systemUptime - recordingStartedAt,
                sustain: enabled
            )
        )
    }

    @discardableResult
    func finishRecording() -> PerformanceTake? {
        guard isRecording else { return nil }
        isRecording = false
        let duration = max(0, ProcessInfo.processInfo.systemUptime - recordingStartedAt)
        for note in heldRecordingNotes.sorted() {
            capturedEvents.append(PerformanceEvent(note: note, time: duration, isNoteOn: false))
        }
        if recordingSustain {
            capturedEvents.append(PerformanceEvent(time: duration, sustain: false))
        }
        heldRecordingNotes = []
        recordingSustain = false
        guard capturedEvents.contains(where: { $0.sustain == nil && $0.isNoteOn }) else { return nil }

        let take = PerformanceTake(
            id: UUID(),
            createdAt: Date(),
            duration: duration,
            events: capturedEvents
        )
        takes.insert(take, at: 0)
        persistTakes()
        return take
    }

    func play(
        _ take: PerformanceTake,
        noteOn: @escaping (UInt8) -> Void,
        noteOff: @escaping (UInt8) -> Void,
        sustain: @escaping (Bool) -> Void
    ) {
        stopPlayback()
        let generation = UUID()
        playbackGeneration = generation
        playingTakeID = take.id
        playbackNoteOff = noteOff
        playbackSustain = sustain
        playbackTask = Task { [weak self] in
            guard let self else { return }
            var previousTime: TimeInterval = 0
            for event in take.events {
                let delay = max(0, event.time - previousTime)
                previousTime = event.time
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled, self.playbackGeneration == generation else { break }
                if let isSustained = event.sustain {
                    sustain(isSustained)
                    continue
                }
                if event.isNoteOn {
                    self.playbackHeldNotes.insert(event.note)
                    noteOn(event.note)
                } else {
                    self.playbackHeldNotes.remove(event.note)
                    noteOff(event.note)
                }
            }
            if self.playbackGeneration == generation {
                self.releasePlaybackNotes()
                sustain(false)
                self.playbackSustain = nil
                self.playingTakeID = nil
                self.playbackTask = nil
            }
        }
    }

    func stopPlayback() {
        playbackGeneration = UUID()
        playbackTask?.cancel()
        playbackTask = nil
        releasePlaybackNotes()
        playbackSustain?(false)
        playbackSustain = nil
        playingTakeID = nil
    }

    func delete(_ take: PerformanceTake) {
        if playingTakeID == take.id { stopPlayback() }
        takes.removeAll { $0.id == take.id }
        persistTakes()
    }

    func midiFileURL(for take: PerformanceTake) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PianoFlow-\(take.id.uuidString).mid")
        do {
            try MIDIExporter.data(for: take).write(to: url, options: .atomic)
            return url
        } catch {
            lastError = "Could not prepare the MIDI file."
            return nil
        }
    }

    private func releasePlaybackNotes() {
        for note in playbackHeldNotes {
            playbackNoteOff?(note)
        }
        playbackHeldNotes = []
        playbackNoteOff = nil
    }

    private var libraryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PianoFlow", isDirectory: true)
            .appendingPathComponent("performances.json")
    }

    private func loadTakes() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        do {
            takes = try JSONDecoder().decode([PerformanceTake].self, from: Data(contentsOf: libraryURL))
        } catch {
            lastError = "Saved performances could not be loaded."
        }
    }

    private func persistTakes() {
        do {
            try FileManager.default.createDirectory(
                at: libraryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(takes).write(to: libraryURL, options: .atomic)
        } catch {
            lastError = "The performance could not be saved."
        }
    }
}
