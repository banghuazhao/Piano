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
    @ObservationIgnored private let libraryURL: URL

    init(libraryURL: URL? = nil) {
        self.libraryURL = libraryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("PianoFlow", isDirectory: true)
            .appendingPathComponent("performances.json")
        loadTakes()
    }

    func beginRecording(
        heldNotes: [UInt8] = [],
        heldVelocities: [UInt8: UInt8] = [:],
        sustain: Bool = false
    ) {
        guard !isRecording else { return }
        isRecording = true
        capturedEvents = []
        heldRecordingNotes = []
        recordingSustain = false
        recordingStartedAt = ProcessInfo.processInfo.systemUptime
        captureSustain(sustain)
        for note in Set(heldNotes).sorted() {
            capture(note: note, isNoteOn: true, velocity: heldVelocities[note] ?? 100)
        }
    }

    func capture(note: UInt8, isNoteOn: Bool, velocity: UInt8 = 100) {
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
                isNoteOn: isNoteOn,
                velocity: isNoteOn ? min(max(velocity, 1), 127) : 0
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

        let createdAt = Date()
        let take = PerformanceTake(
            id: UUID(),
            createdAt: createdAt,
            duration: duration,
            events: capturedEvents,
            title: "Take \(createdAt.formatted(date: .abbreviated, time: .shortened))"
        )
        guard take.isValid else {
            lastError = "This performance was too long to save."
            return nil
        }
        let updatedTakes = [take] + takes
        guard persistTakes(updatedTakes) else { return nil }
        takes = updatedTakes
        return take
    }

    func play(
        _ take: PerformanceTake,
        options: PerformancePlaybackOptions = .init(),
        noteOn: @escaping (UInt8, UInt8) -> Void,
        noteOff: @escaping (UInt8) -> Void,
        sustain: @escaping (Bool) -> Void
    ) {
        stopPlayback()
        guard take.isValid else {
            lastError = "This performance could not be played."
            return
        }
        guard options.rate.isFinite, (0.5...2).contains(options.rate) else {
            lastError = "Choose a playback speed between 0.5× and 2×."
            return
        }
        let playbackTake: PerformanceTake
        if let region = options.region {
            guard let excerpt = RecordingEditor.excerpt(
                from: take,
                start: region.lowerBound,
                end: region.upperBound
            ) else {
                lastError = "Choose a section containing notes."
                return
            }
            playbackTake = excerpt
        } else {
            playbackTake = take
        }
        guard playbackTake.noteCount > 0 else {
            lastError = "This section has no notes to play."
            return
        }
        let generation = UUID()
        playbackGeneration = generation
        playingTakeID = take.id
        playbackNoteOff = noteOff
        playbackSustain = sustain
        playbackTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                let startedAt = ProcessInfo.processInfo.systemUptime
                for event in playbackTake.events {
                    guard await self.waitUntil(event.time / options.rate, startedAt: startedAt),
                          self.playbackGeneration == generation else { return }
                    if let isSustained = event.sustain {
                        sustain(isSustained)
                    } else if event.isNoteOn {
                        self.playbackHeldNotes.insert(event.note)
                        noteOn(event.note, event.velocity)
                    } else {
                        self.playbackHeldNotes.remove(event.note)
                        noteOff(event.note)
                    }
                }
                let cycleDuration = max(playbackTake.duration / options.rate, options.loop ? 0.05 : 0)
                guard await self.waitUntil(cycleDuration, startedAt: startedAt),
                      self.playbackGeneration == generation else { return }
                self.releasePlaybackNotes(clearCallback: false)
                sustain(false)
            } while options.loop
            self.playbackNoteOff = nil
            self.playbackSustain = nil
            self.playingTakeID = nil
            self.playbackTask = nil
        }
    }

    private func waitUntil(_ time: TimeInterval, startedAt: TimeInterval) async -> Bool {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let remaining = max(0, time - elapsed)
        if remaining > 0 {
            do {
                try await Task.sleep(nanoseconds: UInt64((remaining * 1_000_000_000).rounded()))
            } catch {
                return false
            }
        }
        return !Task.isCancelled
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
        let remainingTakes = takes.filter { $0.id != take.id }
        guard persistTakes(remainingTakes) else { return }
        if playingTakeID == take.id { stopPlayback() }
        takes = remainingTakes
    }

    @discardableResult
    func rename(_ take: PerformanceTake, to proposedTitle: String) -> Bool {
        let title = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 64,
              let index = takes.firstIndex(where: { $0.id == take.id }) else {
            lastError = "Enter a title of 1–64 characters."
            return false
        }
        var updatedTakes = takes
        updatedTakes[index] = PerformanceTake(
            id: take.id,
            createdAt: take.createdAt,
            duration: take.duration,
            events: take.events,
            title: title
        )
        guard persistTakes(updatedTakes) else { return false }
        takes = updatedTakes
        return true
    }

    @discardableResult
    func saveExcerpt(of take: PerformanceTake, from start: TimeInterval, to end: TimeInterval) -> PerformanceTake? {
        guard let excerpt = RecordingEditor.excerpt(from: take, start: start, end: end) else {
            lastError = "Choose a section containing notes."
            return nil
        }
        let updatedTakes = [excerpt] + takes
        guard persistTakes(updatedTakes) else { return nil }
        takes = updatedTakes
        return excerpt
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

    func audioFileURL(
        for take: PerformanceTake,
        format: RecordingAudioFormat,
        profile: PianoSoundProfile,
        options: PerformancePlaybackOptions = .init()
    ) async -> URL? {
        if profile.isPremium {
            await PremiumStore.shared.prepare()
            guard !Task.isCancelled else { return nil }
            guard PremiumStore.shared.isPremium else {
                lastError = "Unlock Premium to export with this piano sound."
                return nil
            }
        }
        do {
            let url = try await AudioExporter.export(
                take: take,
                format: format,
                profile: profile,
                options: options
            )
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return url
        } catch is CancellationError {
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func releasePlaybackNotes(clearCallback: Bool = true) {
        for note in playbackHeldNotes {
            playbackNoteOff?(note)
        }
        playbackHeldNotes = []
        if clearCallback { playbackNoteOff = nil }
    }

    private func loadTakes() {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        do {
            let decoded = try JSONDecoder().decode([PerformanceTake].self, from: Data(contentsOf: libraryURL))
            takes = decoded.filter(\.isValid)
            if takes.count != decoded.count {
                lastError = "Some saved performances could not be loaded."
            }
        } catch {
            lastError = "Saved performances could not be loaded."
        }
    }

    @discardableResult
    private func persistTakes(_ updatedTakes: [PerformanceTake]) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: libraryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(updatedTakes).write(to: libraryURL, options: .atomic)
            return true
        } catch {
            lastError = "The performance library could not be updated."
            return false
        }
    }
}
