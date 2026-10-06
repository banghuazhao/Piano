import Foundation

/// Standalone model checks. Compile with PracticeExercise.swift and PracticeSession.swift.
@main
struct PracticeChecks {
    @MainActor
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var clock = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!

        let suiteName = "PianoFlow.PracticeChecks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create test preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        expect(Set(PracticeCatalog.all.map(\.id)).count == PracticeCatalog.all.count, "Exercise IDs must be unique")
        for category in PracticeCategory.allCases {
            expect(!PracticeCatalog.exercises(in: category).isEmpty, "Every category needs an exercise")
        }

        let repeated = PracticeExercise(
            id: "test-repeated",
            title: "Repeated C",
            detail: "Test",
            category: .melodies,
            difficulty: .beginner,
            steps: [PracticeStep([60]), PracticeStep([60])]
        )
        let chord = PracticeExercise(
            id: "test-chord",
            title: "C chord",
            detail: "Test",
            category: .chords,
            difficulty: .beginner,
            steps: [PracticeStep([60, 64, 67])]
        )
        let single = PracticeExercise(
            id: "test-single",
            title: "Middle C",
            detail: "Test",
            category: .scales,
            difficulty: .beginner,
            steps: [PracticeStep([60])]
        )

        let session = PracticeSession(defaults: defaults, now: { clock }, calendar: calendar)
        session.start(repeated)
        expect(session.targetNotes == [60] && session.targetAnchorNote == 60, "Target hooks should expose C4")
        session.noteOn(60, heldNotes: [60])
        expect(session.currentStepIndex == 1, "First C should advance one step")
        session.noteOn(60, heldNotes: [60])
        expect(session.currentStepIndex == 1, "A held C must not complete a repeated note")
        session.noteOff(60)
        session.noteOn(60, heldNotes: [60])
        expect(session.lastCompletedResult?.accuracyPercent == 100, "Replaying C after release should complete")
        session.noteOff(60)

        session.start(chord)
        session.noteOn(60, heldNotes: [60])
        expect(session.matchedNotes == [60], "First chord tone should be shown as matched")
        session.noteOff(60)
        expect(session.matchedNotes.isEmpty, "A released chord tone must no longer count")
        session.noteOn(64, heldNotes: [64])
        session.noteOn(67, heldNotes: [64, 67])
        expect(session.isActive, "A chord must not complete without simultaneous tones")
        session.noteOn(60, heldNotes: [60, 64, 67])
        expect(session.lastCompletedResult != nil, "A held three-note chord should complete")
        session.noteOff(60)
        session.noteOff(64)
        session.noteOff(67)

        session.start(single)
        session.noteOn(62, heldNotes: [62])
        expect(session.wrongNoteCount == 1 && session.isActive, "Wrong notes should not advance")
        session.noteOff(62)
        session.noteOn(60, heldNotes: [60])
        expect(session.lastCompletedResult?.accuracyPercent == 50, "Accuracy should include wrong attempts")
        expect(session.todayCompletions == 3 && session.streakDays == 1, "Daily completions should accumulate")
        expect(session.dailyGoalFraction == 1, "Three exercises should fill the daily goal")
        session.noteOff(60)

        let restored = PracticeSession(defaults: defaults, now: { clock }, calendar: calendar)
        expect(restored.todayCompletions == 3 && restored.streakDays == 1, "Progress should survive a new session")

        clock = calendar.date(byAdding: .day, value: 1, to: clock)!
        expect(restored.todayCompletions == 0 && restored.streakDays == 1, "Yesterday's streak should remain active")
        restored.start(single)
        restored.noteOn(60, heldNotes: [60])
        expect(restored.todayCompletions == 1 && restored.streakDays == 2, "A next-day completion should extend the streak")

        clock = calendar.date(byAdding: .day, value: 3, to: clock)!
        expect(restored.streakDays == 0, "A missed day should end the current streak")

        print("Practice checks passed: catalog, repeated notes, chord hold, accuracy, daily progress, persistence, streaks")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
