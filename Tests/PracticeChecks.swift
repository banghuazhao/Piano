import Foundation

/// Standalone model checks. Compile with PracticeExercise.swift and PracticeSession.swift.
@main
struct PracticeChecks {
    @MainActor
    static func main() async {
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

        session.start(chord)
        session.noteOn(60, heldNotes: [60])
        session.pause()
        session.noteOff(60)
        expect(session.matchedNotes.isEmpty && session.isPaused,
               "Releasing a partial wait-mode chord during pause should clear its matched key")
        session.resume()
        session.stop()

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

        var uptime = 100.0
        let rhythm = PracticeSession(defaults: defaults, now: { clock }, calendar: calendar,
                                     uptime: { uptime }, automaticTicks: false)
        var clickStarts = 0
        var clickStops = 0
        rhythm.onRhythmStart = { bpm, numerator, denominator in
            clickStarts += 1
            expect(bpm >= 40 && numerator > 0 && denominator > 0, "Click setup needs valid meter and tempo")
            return uptime
        }
        rhythm.onRhythmStop = { clickStops += 1 }

        let sixEight = PracticeExercise(
            id: "test-six-eight", title: "Six eight", detail: "Test",
            category: .melodies, difficulty: .beginner,
            suggestedBPM: 120, beatsPerBar: 6, beatUnit: 8,
            score: [
                PracticeScoreNote(pitch: 60, startBeat: 0, durationBeats: 0.5, hand: .right),
                PracticeScoreNote(pitch: 62, startBeat: 0.5, durationBeats: 0.5, hand: .right)
            ]
        )
        rhythm.start(sixEight, options: PracticeOptions(mode: .rhythm, bpm: 120, countInBars: 1))
        expect(rhythm.isCountingIn && rhythm.countInBeat == 1, "Six-eight should begin with beat one of the count-in")
        uptime = 100.25
        rhythm.tick()
        expect(rhythm.countInBeat == 2, "An eighth-note meter click advances every half quarter-note")
        rhythm.noteOn(60, heldNotes: [60])
        expect(rhythm.correctNoteCount == 0 && rhythm.wrongNoteCount == 0,
               "Count-in notes should not be graded")
        rhythm.noteOff(60)
        uptime = 101.5
        rhythm.tick()
        expect(!rhythm.isCountingIn && abs(rhythm.currentBeat) < 0.0001,
               "A six-eight bar at 120 quarter BPM lasts 1.5 seconds")
        rhythm.noteOn(60, heldNotes: [60])
        rhythm.noteOff(60)
        uptime = 101.75
        rhythm.noteOn(62, heldNotes: [62])
        rhythm.noteOff(62)
        uptime = 102
        rhythm.tick()
        expect(rhythm.lastCompletedResult?.accuracyPercent == 100 &&
               rhythm.lastCompletedResult?.onsetTimingAccuracyPercent == 100,
               "On-time six-eight notes should finish with perfect pitch and onset timing")
        expect(clickStarts == 1 && clickStops == 1, "The click should stop when a rhythm pass finishes")

        let eighthBar = PracticeExercise(
            id: "test-one-eight", title: "One eighth", detail: "Test",
            category: .melodies, difficulty: .beginner,
            suggestedBPM: 120, beatsPerBar: 1, beatUnit: 8,
            score: [PracticeScoreNote(pitch: 67, startBeat: 0, durationBeats: 0.5, hand: .right)]
        )
        uptime = 150
        rhythm.start(eighthBar, options: PracticeOptions(mode: .rhythm, bpm: 120, countInBars: 1))
        uptime = 150.249
        rhythm.tick()
        expect(rhythm.isCountingIn && rhythm.countInBeat == 1,
               "A one-eighth bar should still be counting in just before 250 ms")
        uptime = 150.25
        rhythm.tick()
        expect(!rhythm.isCountingIn && rhythm.currentBeat == 0,
               "A one-eighth count-in should finish after half a quarter beat")
        rhythm.stop()

        let threeFour = PracticeExercise(
            id: "test-two-bars", title: "Two bars", detail: "Test",
            category: .melodies, difficulty: .beginner,
            suggestedBPM: 100, beatsPerBar: 3, beatUnit: 4,
            score: [PracticeScoreNote(pitch: 69, startBeat: 0, durationBeats: 1, hand: .right)]
        )
        uptime = 160
        rhythm.start(threeFour, options: PracticeOptions(mode: .rhythm, bpm: 100, countInBars: 2))
        uptime = 163.59
        rhythm.tick()
        expect(rhythm.isCountingIn && rhythm.countInBeat == 3,
               "Two bars of three-four at 100 BPM should still count in at 3.59 seconds")
        uptime = 163.6
        rhythm.tick()
        expect(!rhythm.isCountingIn && abs(rhythm.currentBeat) < 0.0001,
               "Two bars of three-four should end after six quarter beats")
        rhythm.stop()

        let syncopated = PracticeExercise(
            id: "test-off-bpm", title: "Syncopated", detail: "Test",
            category: .melodies, difficulty: .beginner,
            suggestedBPM: 75,
            score: [PracticeScoreNote(pitch: 71, startBeat: 1.5, durationBeats: 0.5, hand: .right)]
        )
        uptime = 170
        rhythm.start(syncopated, options: PracticeOptions(mode: .rhythm, bpm: 75, countInBars: 1))
        uptime = 174.4 // Four count-in beats, then 1.5 score beats at 0.8 seconds each.
        rhythm.tick()
        expect(abs(rhythm.currentBeat - 1.5) < 0.0001 && rhythm.missedNoteCount == 0,
               "Odd BPM and fractional score beats should use the absolute epoch")
        rhythm.noteOn(71, heldNotes: [71])
        rhythm.noteOff(71)
        uptime = 174.8
        rhythm.tick()
        expect(rhythm.lastCompletedResult?.onsetTimingAccuracyPercent == 100,
               "An on-time syncopated note should grade correctly at 75 BPM")

        let shortFinal = PracticeExercise(
            id: "test-short-final", title: "Short final note", detail: "Test",
            category: .melodies, difficulty: .beginner, suggestedBPM: 120,
            score: [PracticeScoreNote(pitch: 72, startBeat: 0,
                                      durationBeats: 0.05, hand: .right)]
        )
        uptime = 180
        rhythm.start(shortFinal, options: PracticeOptions(mode: .rhythm, bpm: 120, countInBars: 0))
        uptime = 180.195 // 0.39 beats: after the scored duration but within the 0.4-beat onset window.
        rhythm.tick()
        expect(rhythm.isActive && rhythm.missedNoteCount == 0,
               "A short final duration must not end the run before the onset grace window")
        rhythm.noteOn(72, heldNotes: [72])
        expect(rhythm.lastCompletedResult?.correctNotes == 1 && rhythm.lastCompletedResult?.missedNotes == 0,
               "A late but in-window final onset should be accepted and complete the run")
        rhythm.noteOff(72)

        let chordRepeat = PracticeExercise(
            id: "test-rhythm-chord", title: "Chord then repeat", detail: "Test",
            category: .chords, difficulty: .beginner, suggestedBPM: 120,
            score: [
                PracticeScoreNote(pitch: 60, startBeat: 0, durationBeats: 1, hand: .left),
                PracticeScoreNote(pitch: 64, startBeat: 0, durationBeats: 1, hand: .right),
                PracticeScoreNote(pitch: 60, startBeat: 1, durationBeats: 1, hand: .left)
            ]
        )
        uptime = 200
        rhythm.start(chordRepeat, options: PracticeOptions(mode: .rhythm, bpm: 120, countInBars: 0))
        rhythm.noteOn(60, heldNotes: [60])
        expect(rhythm.matchedNotes == [60], "The first chord onset should be marked while the chord is incomplete")
        uptime = 200.04
        rhythm.noteOn(64, heldNotes: [60, 64])
        expect(rhythm.currentStepIndex == 1, "Near-simultaneous chord notes should resolve together")
        rhythm.noteOff(60)
        rhythm.noteOff(64)
        uptime = 200.5
        rhythm.noteOn(60, heldNotes: [60])
        expect(rhythm.correctNoteCount == 3, "A released repeated pitch should match its later onset")
        rhythm.noteOff(60)
        uptime = 201
        rhythm.tick()
        expect(rhythm.lastCompletedResult?.correctNotes == 3 && rhythm.lastCompletedResult?.missedNotes == 0,
               "Chord and repeated onsets should all count once")

        let miss = PracticeExercise(
            id: "test-rhythm-miss", title: "Miss", detail: "Test",
            category: .melodies, difficulty: .beginner, suggestedBPM: 60,
            score: [
                PracticeScoreNote(pitch: 60, startBeat: 0, durationBeats: 1, hand: .right),
                PracticeScoreNote(pitch: 62, startBeat: 1, durationBeats: 1, hand: .right)
            ]
        )
        uptime = 300
        rhythm.start(miss, options: PracticeOptions(mode: .rhythm, bpm: 60, countInBars: 0))
        uptime = 300.25
        rhythm.tick()
        expect(rhythm.missedNoteCount == 1 && rhythm.currentStepIndex == 1,
               "An expired onset should be missed and advance the target")
        uptime = 300.9
        rhythm.noteOn(65, heldNotes: [65])
        rhythm.noteOff(65)
        uptime = 301
        rhythm.noteOn(62, heldNotes: [62])
        rhythm.noteOff(62)
        uptime = 302
        rhythm.tick()
        expect(rhythm.lastCompletedResult?.accuracyPercent == 33 &&
               rhythm.lastCompletedResult?.onsetTimingAccuracyPercent == 50,
               "Pitch accuracy should include wrong and missed notes; onset timing includes misses")

        let paused = PracticeExercise(
            id: "test-rhythm-pause", title: "Pause", detail: "Test",
            category: .melodies, difficulty: .beginner, suggestedBPM: 120,
            score: [
                PracticeScoreNote(pitch: 60, startBeat: 0, durationBeats: 1, hand: .right),
                PracticeScoreNote(pitch: 62, startBeat: 4, durationBeats: 1, hand: .right)
            ]
        )
        uptime = 400
        rhythm.start(paused, options: PracticeOptions(mode: .rhythm, bpm: 120, countInBars: 0))
        rhythm.noteOn(60, heldNotes: [60])
        rhythm.noteOff(60)
        uptime = 400.65
        rhythm.pause()
        expect(rhythm.isPaused && rhythm.currentBeat > 1.2 && rhythm.currentBeat < 1.4,
               "Pausing should freeze the absolute score position")
        uptime = 500
        rhythm.tick()
        expect(rhythm.missedNoteCount == 0, "No misses should accrue during a long interruption")
        rhythm.onRhythmStart = { _, _, _ in nil }
        rhythm.resume()
        expect(rhythm.isPaused && rhythm.correctNoteCount == 1
               && rhythm.currentBeat > 1.2,
               "A failed click restart should preserve the paused score before bar replay")
        rhythm.onRhythmStart = { _, _, _ in uptime }
        rhythm.resume()
        expect(rhythm.isCountingIn && rhythm.currentBeat == 0,
               "Resuming mid-bar should replay from the bar line after a fresh count-in")
        expect(rhythm.correctNoteCount == 0 && rhythm.missedNoteCount == 0,
               "Rewinding a bar should undo its prior scoring")
        uptime = 502
        rhythm.tick()
        expect(!rhythm.isCountingIn && rhythm.currentBeat == 0,
               "The resumed metronome downbeat should align with the score bar line")
        rhythm.noteOn(60, heldNotes: [60])
        rhythm.noteOff(60)
        expect(rhythm.correctNoteCount == 1 && rhythm.wrongNoteCount == 0,
               "A previously matched note should be playable again after rewind")
        uptime = 504
        rhythm.noteOn(62, heldNotes: [62])
        rhythm.noteOff(62)
        uptime = 504.5
        rhythm.tick()
        expect(rhythm.lastCompletedResult?.missedNotes == 0,
               "A paused and resumed pass should retain resolved notes without inventing misses")

        let interruptedChord = PracticeExercise(
            id: "test-interrupted-chord", title: "Interrupted chord", detail: "Test",
            category: .chords, difficulty: .beginner, suggestedBPM: 120,
            score: [
                PracticeScoreNote(pitch: 60, startBeat: 0, durationBeats: 1, hand: .left),
                PracticeScoreNote(pitch: 64, startBeat: 0, durationBeats: 1, hand: .right),
                PracticeScoreNote(pitch: 67, startBeat: 4, durationBeats: 1, hand: .right)
            ]
        )
        uptime = 550
        rhythm.start(interruptedChord, options: PracticeOptions(mode: .rhythm, bpm: 120, countInBars: 0))
        rhythm.noteOn(60, heldNotes: [60])
        rhythm.noteOff(60)
        uptime = 550.18
        rhythm.noteOn(70, heldNotes: [70])
        rhythm.noteOff(70)
        rhythm.pause()
        expect(rhythm.correctNoteCount == 1 && rhythm.wrongNoteCount == 1,
               "An interrupted chord can contain both a matched tone and a wrong attempt")
        uptime = 570
        rhythm.resume()
        expect(rhythm.correctNoteCount == 0 && rhythm.wrongNoteCount == 0,
               "Bar rewind should clear partial chord and wrong attempts from that bar")
        uptime = 572
        rhythm.noteOn(60, heldNotes: [60])
        uptime = 572.04
        rhythm.noteOn(64, heldNotes: [60, 64])
        expect(rhythm.currentStepIndex == 1 && rhythm.correctNoteCount == 2,
               "The full chord should be graded again after the interruption")
        rhythm.noteOff(60)
        rhythm.noteOff(64)
        rhythm.stop()

        uptime = 600
        rhythm.start(single, options: PracticeOptions(mode: .rhythm, bpm: 80,
            countInBars: 0, tempoStep: 5, targetBPM: 90))
        rhythm.noteOn(60, heldNotes: [60])
        rhythm.noteOff(60)
        uptime = 600.75
        rhythm.tick()
        expect(rhythm.currentBPM == 80 && rhythm.suggestedNextBPM == 85,
               "A strong pass should offer, but not automatically apply, the next tempo")
        expect(rhythm.increaseTempo() && rhythm.isActive && rhythm.currentBPM == 85,
               "An explicit tempo increase should begin a new pass at the next step")
        rhythm.stop()

        rhythm.onRhythmStart = { _, _, _ in nil }
        rhythm.start(single, options: PracticeOptions(mode: .rhythm, countInBars: 0))
        expect(rhythm.isPaused && rhythm.feedbackMessage.contains("unavailable"),
               "An unavailable click must leave the run safely paused")
        rhythm.stop()

        let liveTicker = PracticeSession(defaults: defaults, now: { clock }, calendar: calendar)
        let completionsBeforeSilentRun = liveTicker.todayCompletions
        liveTicker.start(single, options: PracticeOptions(mode: .rhythm, bpm: 240, countInBars: 0))
        try? await Task.sleep(for: .milliseconds(650))
        expect(liveTicker.lastCompletedResult?.missedNotes == 1,
               "The automatic ticker should finish a silent rhythm pass without note input")
        expect(liveTicker.todayCompletions == completionsBeforeSilentRun,
               "An unattended timed run must not advance the daily practice goal")

        let largeScore = (0..<40_000).map { index in
            PracticeScoreNote(pitch: UInt8(60 + index % 12), startBeat: Double(index) * 0.5,
                              durationBeats: 0.5, hand: .right)
        }
        let large = PracticeExercise(id: "test-large", title: "Large", detail: "Test",
                                     category: .melodies, difficulty: .developing,
                                     suggestedBPM: 120, score: largeScore)
        rhythm.onRhythmStart = nil
        uptime = 1_000
        rhythm.start(large, options: PracticeOptions(mode: .rhythm, bpm: 120, countInBars: 0))
        uptime = 6_000
        rhythm.tick()
        expect(rhythm.currentStepIndex == 20_000 && rhythm.missedNoteCount == 20_000,
               "Large scores should expire prior steps without rescanning every step on each tick")
        rhythm.noteOn(UInt8(60 + 20_000 % 12), heldNotes: [UInt8(60 + 20_000 % 12)])
        expect(rhythm.correctNoteCount == 1, "A distant onset should be found near its beat")
        rhythm.stop()

        print("Practice checks passed: wait mode, persistence, 0/1/2-bar count-in, 1/8 and 6/8 meter, odd BPM, chords, repeated notes, misses, pause/resume, tempo, ticker, click failure, 40k-score lookup")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
