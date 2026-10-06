import Foundation

/// Creates an independent take while preserving notes and pedal state at cut points.
enum RecordingEditor {
    static func excerpt(
        from take: PerformanceTake,
        start requestedStart: TimeInterval,
        end requestedEnd: TimeInterval
    ) -> PerformanceTake? {
        guard take.isValid, requestedStart.isFinite, requestedEnd.isFinite else { return nil }
        let start = min(max(0, requestedStart), take.duration)
        let end = min(max(0, requestedEnd), take.duration)
        guard end > start else { return nil }

        var state = NoteState()
        for event in take.events where event.time < start {
            state.apply(event)
        }

        var events: [PerformanceEvent] = []
        if state.sustain {
            events.append(PerformanceEvent(time: 0, sustain: true))
        }
        // A released note may still be sounding under the pedal at the cut point.
        for (note, velocities) in state.sustained.sorted(by: { $0.key < $1.key }) {
            for velocity in velocities {
                events.append(PerformanceEvent(note: note, time: 0, isNoteOn: true, velocity: velocity))
                events.append(PerformanceEvent(note: note, time: 0, isNoteOn: false))
            }
        }
        for (note, velocity) in state.held.sorted(by: { $0.key < $1.key }) {
            events.append(PerformanceEvent(note: note, time: 0, isNoteOn: true, velocity: velocity))
        }

        for event in take.events where event.time >= start && event.time <= end {
            events.append(
                PerformanceEvent(
                    note: event.note,
                    time: event.time - start,
                    isNoteOn: event.isNoteOn,
                    sustain: event.sustain,
                    velocity: event.velocity
                )
            )
            state.apply(event)
        }

        let duration = end - start
        for note in state.held.keys.sorted() {
            events.append(PerformanceEvent(note: note, time: duration, isNoteOn: false))
        }
        if state.sustain {
            events.append(PerformanceEvent(time: duration, sustain: false))
        }
        guard events.contains(where: { $0.sustain == nil && $0.isNoteOn }) else { return nil }

        let excerpt = PerformanceTake(
            id: UUID(),
            createdAt: Date(),
            duration: duration,
            events: events,
            title: "\(take.title) clip"
        )
        return excerpt.isValid ? excerpt : nil
    }

    private struct NoteState {
        var held: [UInt8: UInt8] = [:]
        var sustained: [UInt8: [UInt8]] = [:]
        var sustain = false

        mutating func apply(_ event: PerformanceEvent) {
            if let pedal = event.sustain {
                sustain = pedal
                if !pedal { sustained.removeAll() }
            } else if event.isNoteOn {
                held[event.note] = event.velocity
            } else if let velocity = held.removeValue(forKey: event.note), sustain {
                sustained[event.note, default: []].append(velocity)
            }
        }
    }
}
