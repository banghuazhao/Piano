import Foundation

enum PracticeCategory: String, CaseIterable, Identifiable {
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

enum PracticeDifficulty: String {
    case beginner = "Beginner"
    case developing = "Developing"
}

struct PracticeStep: Equatable {
    let notes: Set<UInt8>

    init(_ notes: Set<UInt8>) {
        precondition(!notes.isEmpty, "A practice step needs at least one note")
        precondition(notes.allSatisfy { (21...108).contains($0) }, "Practice notes must fit the piano")
        self.notes = notes
    }

    var isChord: Bool { notes.count > 1 }

    var noteNames: String {
        notes.sorted().map(PracticeNoteName.string).joined(separator: " · ")
    }
}

struct PracticeExercise: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let category: PracticeCategory
    let difficulty: PracticeDifficulty
    let steps: [PracticeStep]

    init(
        id: String,
        title: String,
        detail: String,
        category: PracticeCategory,
        difficulty: PracticeDifficulty,
        steps: [PracticeStep]
    ) {
        precondition(!steps.isEmpty, "An exercise needs at least one step")
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.difficulty = difficulty
        self.steps = steps
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
            steps: notes([57, 59, 60, 62, 64, 65, 67, 69, 67, 65, 64, 62, 60, 59, 57])
        ),
        PracticeExercise(
            id: "g-major-scale",
            title: "G major scale",
            detail: "Meet F♯ in a familiar pattern",
            category: .scales,
            difficulty: .developing,
            steps: notes([55, 57, 59, 60, 62, 64, 66, 67, 66, 64, 62, 60, 59, 57, 55])
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
            steps: notes([53, 57, 60, 65, 60, 57, 53])
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
            steps: notes([60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60])
        ),
        PracticeExercise(
            id: "ode-to-joy-opening",
            title: "Ode to Joy",
            detail: "The opening phrase, note by note",
            category: .melodies,
            difficulty: .beginner,
            steps: notes([64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62])
        )
    ]

    static func exercises(in category: PracticeCategory) -> [PracticeExercise] {
        all.filter { $0.category == category }
    }

    private static func notes(_ pitches: [UInt8]) -> [PracticeStep] {
        pitches.map { PracticeStep([$0]) }
    }

    private static func chords(_ pitches: [[UInt8]]) -> [PracticeStep] {
        pitches.map { PracticeStep(Set($0)) }
    }
}
