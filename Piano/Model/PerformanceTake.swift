import Foundation

struct PerformanceEvent: Codable, Sendable {
    let note: UInt8
    let time: TimeInterval
    let isNoteOn: Bool
    let sustain: Bool?
    let velocity: UInt8

    init(
        note: UInt8 = 0,
        time: TimeInterval,
        isNoteOn: Bool = false,
        sustain: Bool? = nil,
        velocity: UInt8 = 100
    ) {
        self.note = note
        self.time = time
        self.isNoteOn = isNoteOn
        self.sustain = sustain
        self.velocity = velocity
    }

    private enum CodingKeys: String, CodingKey {
        case note, time, isNoteOn, sustain, velocity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = try container.decode(UInt8.self, forKey: .note)
        time = try container.decode(TimeInterval.self, forKey: .time)
        isNoteOn = try container.decode(Bool.self, forKey: .isNoteOn)
        sustain = try container.decodeIfPresent(Bool.self, forKey: .sustain)
        velocity = try container.decodeIfPresent(UInt8.self, forKey: .velocity) ?? 100
    }
}

struct PerformanceTake: Codable, Identifiable, Sendable {
    /// Keeps playback delays and MIDI delta times within representable limits.
    static let maximumDuration: TimeInterval = 72 * 60 * 60

    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let events: [PerformanceEvent]
    let title: String

    init(
        id: UUID,
        createdAt: Date,
        duration: TimeInterval,
        events: [PerformanceEvent],
        title: String = "Untitled take"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.events = events
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, duration, events, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        events = try container.decode([PerformanceEvent].self, forKey: .events)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled take"
    }

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
                  (event.sustain != nil || event.note <= 127),
                  (!event.isNoteOn || (1...127).contains(event.velocity)) else {
                return false
            }
            previousTime = event.time
        }
        return true
    }
}

struct PerformancePlaybackOptions: Sendable {
    var rate: Double = 1
    var loop = false
    var region: ClosedRange<TimeInterval>?
}
