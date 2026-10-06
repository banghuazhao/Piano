import Foundation

/// Standalone engraving checks; compile with PracticeExercise.swift and ScoreNotation.swift.
@main
struct ScoreNotationChecks {
    static func main() {
        let middleC = ScoreNotation.pitch(60)
        expect(middleC.spokenName == "C4", "Middle C needs the correct octave")
        expect(middleC.staffStep(in: .treble) == -2, "C4 belongs on the treble ledger line")
        expect(middleC.staffStep(in: .bass) == 10, "C4 belongs on the bass ledger line")
        expect(ScoreNotation.pitch(64).staffStep(in: .treble) == 0, "E4 is treble's bottom line")
        expect(ScoreNotation.pitch(43).staffStep(in: .bass) == 0, "G2 is bass's bottom line")
        expect(ScoreNotation.pitch(66).accidental == .sharp, "F-sharp needs a sharp")
        expect(ScoreNotation.pitch(58).accidental == .flat, "B-flat needs a flat")

        let dotted = ScoreNotation.spell(startBeat: 0, durationBeats: 3, barLength: 4)
        expect(dotted.count == 1 && dotted[0].duration.base == .half && dotted[0].duration.dotted,
               "Three beats should spell as a dotted half note")
        let tied = ScoreNotation.spell(startBeat: 3.5, durationBeats: 1, barLength: 4)
        expect(tied.count == 2 && tied.allSatisfy { $0.duration.base == .eighth },
               "A note crossing a 4/4 barline should split into two eighth notes")
        expect(tied[0].tiesToNext && tied[1].tiesFromPrevious,
               "Barline split needs a tie in both directions")
        let sixEight = ScoreNotation.spell(startBeat: 2.5, durationBeats: 1, barLength: 3)
        expect(sixEight.count == 2 && sixEight[1].startBeat == 3,
               "Six-eight bars last three quarter-note beats")

        let exercise = PracticeExercise(
            id: "score-check", title: "Score check", detail: "", category: .melodies,
            difficulty: .beginner, beatsPerBar: 4, beatUnit: 4,
            score: [
                .init(pitch: 61, startBeat: 0, durationBeats: 1, hand: .right),
                .init(pitch: 61, startBeat: 1, durationBeats: 1, hand: .right),
                .init(pitch: 60, startBeat: 2, durationBeats: 1, hand: .right),
                .init(pitch: 48, startBeat: 0, durationBeats: 1, hand: .left)
            ]
        )
        let index = ScoreNotation.Index(exercise: exercise)
        let both = index.window(currentBeat: 0, hand: .both, width: 800, isCompact: false)
        expect(both.staves.count == 2, "Both-hand score should include treble and bass")
        let right = index.window(currentBeat: 0, hand: .right, width: 800, isCompact: false)
        expect(right.staves == [.treble] && right.chords.allSatisfy { $0.hand == .right },
               "Right-hand score should only include treble notes")
        let accidentals = right.chords.flatMap { $0.heads.map(\.displayedAccidental) }
        expect(accidentals.prefix(3).elementsEqual([.sharp, nil, .natural]),
               "Sharp should appear once in a bar, followed by a natural sign")
        expect(right.rests.contains { abs($0.startBeat - 3) < 0.001 },
               "The gap after the melody should be represented as a rest")

        let imported = PracticeExercise(
            id: "imported-check", title: "Imported", detail: "", category: .melodies,
            difficulty: .developing, beatsPerBar: 6, beatUnit: 8,
            score: [.init(pitch: 60, startBeat: 1.0 / 3, durationBeats: 2.0 / 3, hand: .right)]
        )
        let importedIndex = ScoreNotation.Index(exercise: imported)
        expect(importedIndex.barLength == 3, "6/8 should have three quarter-note beats per bar")
        expect(importedIndex.rhythmSimplified, "Triplet timing must be disclosed as simplified")
        expect(ScoreNotation.quantizeToSixteenth(1.0 / 3) == 0.25,
               "Engraving should snap imported timing to a sixteenth-note grid")
        expect(ScoreNotation.spell(startBeat: Double.greatestFiniteMagnitude,
                                   durationBeats: 1, barLength: 4).isEmpty,
               "Invalidly large beat values must not overflow integer conversion")

        let longNote = PracticeExercise(
            id: "long-note", title: "Long note", detail: "", category: .melodies,
            difficulty: .developing,
            score: [.init(pitch: 48, startBeat: 0, durationBeats: 8_192, hand: .left)]
        )
        let heldWindow = ScoreNotation.Index(exercise: longNote)
            .window(currentBeat: 4_096.5, hand: .left, width: 320, isCompact: true)
        expect(!heldWindow.chords.isEmpty && heldWindow.chords[0].tiesFromPrevious,
               "A long held note must show a tied carry head in the visible window")
        expect(heldWindow.chords.count < 10,
               "A long held note must not engrave thousands of offscreen bars")

        let denseNotes = (0..<300).map { offset in
            PracticeScoreNote(pitch: UInt8(60 + offset % 12),
                              startBeat: Double(offset) / 1_000,
                              durationBeats: 0.25, hand: .right)
        }
        let denseExercise = PracticeExercise(
            id: "dense-check", title: "Dense", detail: "", category: .melodies,
            difficulty: .developing, score: denseNotes
        )
        let denseWindow = ScoreNotation.Index(exercise: denseExercise)
            .window(currentBeat: 0, hand: .right, width: 160, isCompact: true)
        expect(denseWindow.isDense, "Dense score should disclose omitted glyphs")
        expect(denseWindow.chords.reduce(0) { $0 + $1.heads.count } <= 96,
               "Dense score should cap noteheads for readability")

        print("Score notation checks passed: pitch, clefs, accidentals, tied bars, 6/8, rests, quantization, long holds, density")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
