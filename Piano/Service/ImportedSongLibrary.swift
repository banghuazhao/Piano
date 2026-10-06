import Foundation
import Observation

enum ImportedSongLibraryError: LocalizedError {
    case tooManySongs
    case notFound
    case invalidSong
    case storageFull
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .tooManySongs: "The song library is full. Remove a song before importing another."
        case .notFound: "That imported song or track is no longer in the library."
        case .invalidSong: "This song contains invalid notes or metadata and cannot be saved."
        case .storageFull: "The song library has reached its 32 MB storage limit."
        case .storageUnavailable: "The song library could not be saved. Its previous file was kept for recovery."
        }
    }
}

@MainActor
@Observable
final class ImportedSongLibrary {
    static let shared = ImportedSongLibrary()
    private static let maximumSongs = 50
    private static let maximumStorageBytes = 32 * 1_024 * 1_024

    private(set) var songs: [ImportedPracticeSong] = []
    private(set) var loadWarning: String?
    @ObservationIgnored private let storageURL: URL
    @ObservationIgnored private var storageUnavailable = false

    init(storageURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageURL = storageURL ?? base.appendingPathComponent("PianoFlow/ImportedPracticeSongs.json")
        loadSavedSongs()
    }

    /// UI entry point. Security-scoped access remains open until the detached
    /// read and parse finish, keeping large imports off the main actor.
    func importFile(url: URL) async throws -> ImportedPracticeSong {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let worker = Task.detached(priority: .userInitiated) { () throws -> ImportedPracticeSong in
            try Task.checkCancellation()
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > MIDIFileImporter.maximumFileBytes {
                throw MIDIImportError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try Task.checkCancellation()
            return try MIDIFileImporter.parse(data: data, title: url.lastPathComponent)
        }
        let song = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        try add(song)
        return song
    }

    /// Useful for a generated MIDI document and for the standalone parser checks.
    @discardableResult
    func importData(_ data: Data, title: String) throws -> ImportedPracticeSong {
        let song = try MIDIFileImporter.parse(data: data, title: title)
        try add(song)
        return song
    }

    func setHand(_ hand: PracticeHand, forTrack trackID: UUID, in songID: UUID) throws {
        try edit(songID: songID) { song in
            guard let index = song.tracks.firstIndex(where: { $0.id == trackID }) else {
                throw ImportedSongLibraryError.notFound
            }
            song.tracks[index].hand = hand
        }
    }

    func setIncluded(_ included: Bool, forTrack trackID: UUID, in songID: UUID) throws {
        try edit(songID: songID) { song in
            guard let index = song.tracks.firstIndex(where: { $0.id == trackID }) else {
                throw ImportedSongLibraryError.notFound
            }
            song.tracks[index].isIncluded = included
        }
    }

    func rename(_ songID: UUID, to rawTitle: String) throws {
        try edit(songID: songID) { song in
            song.title = MIDIFileImporter.cleanTitle(rawTitle, fallback: song.title, limit: 80)
        }
    }

    func delete(_ songID: UUID) throws {
        guard songs.contains(where: { $0.id == songID }) else {
            throw ImportedSongLibraryError.notFound
        }
        let next = songs.filter { $0.id != songID }
        try save(next)
        songs = next
    }

    private func add(_ song: ImportedPracticeSong) throws {
        guard songs.count < Self.maximumSongs else { throw ImportedSongLibraryError.tooManySongs }
        guard song.isValidForPractice else { throw ImportedSongLibraryError.invalidSong }
        let next = [song] + songs
        try save(next)
        songs = next
    }

    private func edit(songID: UUID, change: (inout ImportedPracticeSong) throws -> Void) throws {
        guard let index = songs.firstIndex(where: { $0.id == songID }) else {
            throw ImportedSongLibraryError.notFound
        }
        var next = songs
        try change(&next[index])
        guard next[index].isValidForPractice else { throw ImportedSongLibraryError.invalidSong }
        try save(next)
        songs = next
    }

    private func save(_ next: [ImportedPracticeSong]) throws {
        guard !storageUnavailable else { throw ImportedSongLibraryError.storageUnavailable }
        let encoded = try JSONEncoder().encode(next)
        guard encoded.count <= Self.maximumStorageBytes else { throw ImportedSongLibraryError.storageFull }
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoded.write(to: storageURL, options: .atomic)
    }

    private func loadSavedSongs() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
            if let bytes = attributes[.size] as? NSNumber,
               bytes.intValue > Self.maximumStorageBytes {
                throw ImportedSongLibraryError.storageFull
            }
            let data = try Data(contentsOf: storageURL)
            let decoded = try JSONDecoder().decode([ImportedPracticeSong].self, from: data)
            guard decoded.count <= Self.maximumSongs,
                  Set(decoded.map(\.id)).count == decoded.count,
                  decoded.allSatisfy(\.isValidForPractice) else {
                throw ImportedSongLibraryError.invalidSong
            }
            songs = decoded
        } catch {
            let backup = storageURL.deletingLastPathComponent()
                .appendingPathComponent("ImportedPracticeSongs.corrupt-\(UUID().uuidString).json")
            do {
                try FileManager.default.moveItem(at: storageURL, to: backup)
                loadWarning = "A damaged song library was moved to a backup. You can import songs again."
            } catch {
                storageUnavailable = true
                loadWarning = "The song library could not be loaded or backed up. Its file was left untouched."
            }
        }
    }
}
