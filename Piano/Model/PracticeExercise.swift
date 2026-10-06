import Foundation

enum PracticeCategory: String, CaseIterable, Identifiable, Sendable {
    case scales = "Scales"
    case chords = "Chords & arpeggios"
    case melodies = "Melodies"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .scales: "pianokeys"
        case .chords: "circle.grid.2x2"
        case .melodies: "music.note.list"
        }
    }

    var subtitle: String {
        switch self {
        case .scales: "Find your way around the keyboard"
        case .chords: "Build confident harmony"
        case .melodies: "Play something familiar"
        }
    }
}

enum PracticeDifficulty: String, Sendable {
    case beginner = "Beginner"
    case developing = "Developing"
}

enum PracticeHand: String, Codable, CaseIterable, Identifiable, Sendable {
    case both, left, right

    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: "Both hands"
        case .left: "Left hand"
        case .right: "Right hand"
        }
    }
}

/// Beats use quarter-note units, as MIDI's PPQN division does.
struct PracticeScoreNote: Codable, Equatable, Sendable {
    let pitch: UInt8
    let startBeat: Double
    let durationBeats: Double
    let hand: PracticeHand
    let velocity: UInt8

    init(pitch: UInt8, startBeat: Double, durationBeats: Double,
         hand: PracticeHand, velocity: UInt8 = 100) {
        self.pitch = pitch
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.hand = hand
        self.velocity = velocity
    }
}

struct PracticeStep: Equatable, Sendable {
    let notes: Set<UInt8>
    let beat: Double
    let durationBeats: Double
    let leftHandNotes: Set<UInt8>

    init(_ notes: Set<UInt8>, beat: Double = 0, durationBeats: Double = 1,
         leftHandNotes: Set<UInt8> = []) {
        precondition(!notes.isEmpty, "A practice step needs at least one note")
        precondition(notes.allSatisfy { (21...108).contains($0) }, "Practice notes must fit the piano")
        self.notes = notes
        self.beat = beat
        self.durationBeats = durationBeats
        self.leftHandNotes = leftHandNotes.intersection(notes)
    }

    var isChord: Bool { notes.count > 1 }

    var noteNames: String {
        notes.sorted().map(PracticeNoteName.string).joined(separator: " · ")
    }
}

struct PracticeExercise: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let category: PracticeCategory
    let difficulty: PracticeDifficulty
    let steps: [PracticeStep]
    let score: [PracticeScoreNote]
    let suggestedBPM: Int
    let beatsPerBar: Int
    let beatUnit: Int
    let totalBeats: Double
    let availableHands: [PracticeHand]

    func selecting(hand: PracticeHand) -> PracticeExercise? {
        guard hand != .both else { return self }
        let selected = score.filter { $0.hand == hand }
        guard !selected.isEmpty else { return nil }
        return PracticeExercise(id: id, title: title, detail: detail,
                                category: category, difficulty: difficulty,
                                suggestedBPM: suggestedBPM, beatsPerBar: beatsPerBar,
                                beatUnit: beatUnit, score: selected)
    }

    init(
        id: String,
        title: String,
        detail: String,
        category: PracticeCategory,
        difficulty: PracticeDifficulty,
        steps: [PracticeStep] = [],
        suggestedBPM: Int = 80,
        beatsPerBar: Int = 4,
        beatUnit: Int = 4,
        score suppliedScore: [PracticeScoreNote]? = nil
    ) {
        var nextBeat = 0.0
        let generatedScore = steps.flatMap { step -> [PracticeScoreNote] in
            let start = step.beat > 0 ? step.beat : nextBeat
            nextBeat = start + step.durationBeats
            return step.notes.sorted().map {
                PracticeScoreNote(pitch: $0, startBeat: start,
                                  durationBeats: step.durationBeats,
                                  hand: step.leftHandNotes.contains($0) ? .left : .right)
            }
        }
        let score = (suppliedScore ?? generatedScore).sorted {
            $0.startBeat == $1.startBeat ? $0.pitch < $1.pitch : $0.startBeat < $1.startBeat
        }
        precondition(!score.isEmpty, "An exercise needs at least one note")
        precondition(score.allSatisfy {
            (21...108).contains($0.pitch) && $0.startBeat.isFinite && $0.startBeat >= 0
            && $0.durationBeats.isFinite && $0.durationBeats > 0 && $0.hand != .both
        }, "An exercise needs valid timed piano notes")
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.difficulty = difficulty
        self.score = score
        self.totalBeats = score.reduce(0) { max($0, $1.startBeat + $1.durationBeats) }
        let hands = Set(score.map(\.hand))
        self.availableHands = hands.contains(.left) && hands.contains(.right)
            ? [.both, .left, .right] : hands.sorted { $0.rawValue < $1.rawValue }
        self.suggestedBPM = min(240, max(40, suggestedBPM))
        self.beatsPerBar = min(16, max(1, beatsPerBar))
        self.beatUnit = [1, 2, 4, 8, 16, 32].contains(beatUnit) ? beatUnit : 4
        var grouped: [PracticeStep] = []
        var index = 0
        while index < score.count {
            let start = score[index].startBeat
            var chord: [PracticeScoreNote] = []
            while index < score.count, abs(score[index].startBeat - start) < 0.000_001 {
                chord.append(score[index])
                index += 1
            }
            grouped.append(PracticeStep(Set(chord.map(\.pitch)), beat: start,
                                        durationBeats: chord.map(\.durationBeats).max() ?? 1,
                                        leftHandNotes: Set(chord.filter { $0.hand == .left }.map(\.pitch))))
        }
        self.steps = grouped
    }
}

enum PracticeNoteName {
    private static let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    static func string(_ midiNote: UInt8) -> String {
        let pitch = Int(midiNote)
        return "\(names[pitch % 12])\(pitch / 12 - 1)"
    }
}

enum PracticeCatalog {
    static let all: [PracticeExercise] = [
        PracticeExercise(
            id: "c-major-scale",
            title: "C major scale",
            detail: "One octave, up and back down",
            category: .scales,
            difficulty: .beginner,
            steps: notes([60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60])
        ),
        PracticeExercise(
            id: "a-minor-scale",
            title: "A natural minor scale",
            detail: "The natural minor sound, up and down",
            category: .scales,
            difficulty: .beginner,
            steps: notes([57, 59, 60, 62, 64, 65, 67, 69, 67, 65, 64, 62, 60, 59, 57], hand: .left)
        ),
        PracticeExercise(
            id: "g-major-scale",
            title: "G major scale",
            detail: "Meet F♯ in a familiar pattern",
            category: .scales,
            difficulty: .developing,
            steps: notes([55, 57, 59, 60, 62, 64, 66, 67, 66, 64, 62, 60, 59, 57, 55], hand: .left)
        ),
        PracticeExercise(
            id: "c-major-arpeggio",
            title: "C major arpeggio",
            detail: "Play a chord one note at a time",
            category: .chords,
            difficulty: .beginner,
            steps: notes([60, 64, 67, 72, 67, 64, 60])
        ),
        PracticeExercise(
            id: "f-major-arpeggio",
            title: "F major arpeggio",
            detail: "A warm four-note sweep",
            category: .chords,
            difficulty: .developing,
            steps: notes([53, 57, 60, 65, 60, 57, 53], hand: .left)
        ),
        PracticeExercise(
            id: "first-triads",
            title: "Your first chords",
            detail: "Hold each three-note chord together",
            category: .chords,
            difficulty: .beginner,
            steps: chords([
                [60, 64, 67],  // C major
                [57, 60, 64],  // A minor
                [53, 57, 60],  // F major
                [55, 59, 62],  // G major
                [60, 64, 67]
            ])
        ),
        PracticeExercise(
            id: "twinkle-opening",
            title: "Twinkle, Twinkle",
            detail: "A familiar opening melody",
            category: .melodies,
            difficulty: .beginner,
            steps: notes([60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60],
                         durations: [1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2])
        ),
        PracticeExercise(
            id: "ode-to-joy-opening",
            title: "Ode to Joy",
            detail: "The opening phrase, note by note",
            category: .melodies,
            difficulty: .beginner,
            steps: notes([64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62],
                         durations: [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5, 0.5, 2])
        ),
        PracticeExercise(
            id: "twinkle-two-hands",
            title: "Twinkle, together",
            detail: "Learn each hand, then add a simple bass accompaniment",
            category: .melodies,
            difficulty: .developing,
            suggestedBPM: 72,
            score: twinkleDuet
        )
    ]

    static func exercises(in category: PracticeCategory) -> [PracticeExercise] {
        all.filter { $0.category == category }
    }

    private static func notes(_ pitches: [UInt8], hand: PracticeHand = .right,
                              durations: [Double]? = nil) -> [PracticeStep] {
        pitches.enumerated().map { index, pitch in
            PracticeStep([pitch], durationBeats: durations?[index] ?? (index == pitches.count - 1 ? 2 : 1),
                         leftHandNotes: hand == .left ? [pitch] : [])
        }
    }

    private static func chords(_ pitches: [[UInt8]]) -> [PracticeStep] {
        pitches.map { PracticeStep(Set($0), durationBeats: 4) }
    }

    private static var twinkleDuet: [PracticeScoreNote] {
        var beat = 0.0
        let melody: [UInt8] = [60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60]
        let durations: [Double] = [1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2]
        let right = melody.enumerated().map { index, pitch in
            defer { beat += durations[index] }
            return PracticeScoreNote(pitch: pitch, startBeat: beat,
                                     durationBeats: durations[index], hand: .right)
        }
        let left = [UInt8(48), 53, 55, 48].enumerated().map { index, pitch in
            PracticeScoreNote(pitch: pitch, startBeat: Double(index * 4),
                              durationBeats: 4, hand: .left)
        }
        return right + left
    }
}
