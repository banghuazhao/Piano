import Foundation

struct PerformanceEvent: Codable {
    let note: UInt8
    let time: TimeInterval
    let isNoteOn: Bool
    let sustain: Bool?

    init(note: UInt8 = 0, time: TimeInterval, isNoteOn: Bool = false, sustain: Bool? = nil) {
        self.note = note
        self.time = time
        self.isNoteOn = isNoteOn
        self.sustain = sustain
    }
}

struct PerformanceTake: Codable, Identifiable {
    /// Keeps playback delays and MIDI delta times within representable limits.
    static let maximumDuration: TimeInterval = 72 * 60 * 60

    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let events: [PerformanceEvent]

    var noteCount: Int {
        events.filter { $0.sustain == nil && $0.isNoteOn }.count
    }

    var isValid: Bool {
        guard duration.isFinite, duration >= 0, duration <= Self.maximumDuration else {
            return false
        }

        var previousTime: TimeInterval = 0
        for event in events {
            guard event.time.isFinite,
                  event.time >= previousTime,
                  event.time <= duration,
                  (event.sustain != nil || event.note <= 127) else {
                return false
            }
            previousTime = event.time
        }
        return true
    }
}
