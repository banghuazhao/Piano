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
    @ObservationIgnored private var playbackLease: PlaybackLease?
    @ObservationIgnored private let libraryURL: URL
    @ObservationIgnored private let hasPremiumAccess: @MainActor () -> Bool
    @ObservationIgnored private var persistenceBlocked = false

    init(
        libraryURL: URL? = nil,
        hasPremiumAccess: @escaping @MainActor () -> Bool = { PremiumStore.shared.isPremium }
    ) {
        self.libraryURL = libraryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("PianoFlow", isDirectory: true)
            .appendingPathComponent("performances.json")
        self.hasPremiumAccess = hasPremiumAccess
        loadTakes()
    }

    deinit {
        playbackTask?.cancel()
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
        guard take.isValid else {
            lastError = "This performance could not be played."
            return
        }
        guard options.rate.isFinite, (0.5...2).contains(options.rate) else {
            lastError = "Choose a playback speed between 0.5× and 2×."
            return
        }
        let requiresPremium = Self.usesAdvancedPlayback(options)
        guard !requiresPremium || hasPremiumAccess() else {
            lastError = "Unlock Premium for speed, loops, and selected-section playback."
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
        stopPlayback()
        let generation = UUID()
        let lease = PlaybackLease()
        playbackGeneration = generation
        playbackLease = lease
        playingTakeID = take.id
        playbackNoteOff = noteOff
        playbackSustain = sustain
        playbackTask = Task { [weak self] in
            var locallyHeldNotes: Set<UInt8> = []
            defer {
                // A Studio can disappear while a looping playback is asleep.
                // The task retains its callbacks and releases any sounding notes.
                if !lease.wasReleased {
                    for note in locallyHeldNotes { noteOff(note) }
                    sustain(false)
                }
            }
            repeat {
                if requiresPremium, let self,
                   self.playbackGeneration == generation,
                   !self.hasPremiumAccess() {
                    self.stopPlayback()
                    return
                }
                let startedAt = ProcessInfo.processInfo.systemUptime
                for event in playbackTake.events {
                    guard await Self.waitUntil(event.time / options.rate, startedAt: startedAt),
                          let self,
                          self.playbackGeneration == generation else { return }
                    if let isSustained = event.sustain {
                        sustain(isSustained)
                    } else if event.isNoteOn {
                        locallyHeldNotes.insert(event.note)
                        self.playbackHeldNotes.insert(event.note)
                        noteOn(event.note, event.velocity)
                    } else {
                        locallyHeldNotes.remove(event.note)
                        self.playbackHeldNotes.remove(event.note)
                        noteOff(event.note)
                    }
                }
                let cycleDuration = max(playbackTake.duration / options.rate, options.loop ? 0.05 : 0)
                guard await Self.waitUntil(cycleDuration, startedAt: startedAt),
                      let self,
                      self.playbackGeneration == generation else { return }
                self.releasePlaybackNotes(clearCallback: false)
                locallyHeldNotes.removeAll()
                sustain(false)
            } while options.loop
            guard let self, self.playbackGeneration == generation else { return }
            lease.wasReleased = true
            self.playbackLease = nil
            self.playbackNoteOff = nil
            self.playbackSustain = nil
            self.playingTakeID = nil
            self.playbackTask = nil
        }
    }

    private static func waitUntil(_ time: TimeInterval, startedAt: TimeInterval) async -> Bool {
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
        playbackLease?.wasReleased = true
        playbackLease = nil
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
        guard hasPremiumAccess() else {
            lastError = "Unlock Premium to save a selected section."
            return nil
        }
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
        let needsPremium = format == .wav || profile.isPremium || Self.usesAdvancedPlayback(options)
        if needsPremium {
            await PremiumStore.shared.prepare()
            await PremiumStore.shared.refreshEntitlements()
            guard !Task.isCancelled else { return nil }
            guard hasPremiumAccess() else {
                lastError = Self.premiumExportMessage(format: format, profile: profile)
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
            if needsPremium && !hasPremiumAccess() {
                try? FileManager.default.removeItem(at: url)
                lastError = "Premium access changed during export. The audio file was removed."
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

    private static func usesAdvancedPlayback(_ options: PerformancePlaybackOptions) -> Bool {
        options.rate != 1 || options.loop || options.region != nil
    }

    private static func premiumExportMessage(
        format: RecordingAudioFormat,
        profile: PianoSoundProfile
    ) -> String {
        if format == .wav { return "Unlock Premium to export lossless WAV audio." }
        if profile.isPremium { return "Unlock Premium to export with this piano sound." }
        return "Unlock Premium to export a selected section or custom speed."
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
                if preserveDamagedLibrary(moveOriginal: false) {
                    lastError = "Some saved performances were invalid. A backup was kept before the library changes."
                }
            }
        } catch {
            if preserveDamagedLibrary(moveOriginal: true) {
                lastError = "Saved performances could not be loaded. The original library was kept as a backup."
            }
        }
    }

    /// Never overwrite records that failed decoding or validation before a
    /// recovery copy exists. A failed backup leaves the library read-only.
    private func preserveDamagedLibrary(moveOriginal: Bool) -> Bool {
        let backup = libraryURL.deletingLastPathComponent().appendingPathComponent(
            "performances.recovery-\(UUID().uuidString).json"
        )
        do {
            if moveOriginal {
                try FileManager.default.moveItem(at: libraryURL, to: backup)
            } else {
                try FileManager.default.copyItem(at: libraryURL, to: backup)
            }
            return true
        } catch {
            persistenceBlocked = true
            lastError = "Saved performances could not be backed up. Recording changes are disabled to protect them."
            return false
        }
    }

    @discardableResult
    private func persistTakes(_ updatedTakes: [PerformanceTake]) -> Bool {
        guard !persistenceBlocked else {
            lastError = "Recording changes are disabled until the saved library can be backed up."
            return false
        }
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

@MainActor
private final class PlaybackLease {
    var wasReleased = false
}
