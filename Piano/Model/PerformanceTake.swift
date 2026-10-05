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
    let id: UUID
    let createdAt: Date
    let duration: TimeInterval
    let events: [PerformanceEvent]

    var noteCount: Int {
        events.filter { $0.sustain == nil && $0.isNoteOn }.count
    }
}
