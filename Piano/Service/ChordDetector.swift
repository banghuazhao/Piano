import Foundation

enum ChordDetector {
    private static let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    private static let patterns: [(intervals: Set<Int>, suffix: String)] = [
        ([0, 4, 7, 11], "maj7"),
        ([0, 3, 7, 10], "m7"),
        ([0, 4, 7, 10], "7"),
        ([0, 3, 6, 9], "dim7"),
        ([0, 4, 7], ""),
        ([0, 3, 7], "m"),
        ([0, 3, 6], "dim"),
        ([0, 4, 8], "aug"),
        ([0, 2, 7], "sus2"),
        ([0, 5, 7], "sus4")
    ]

    static func name(for notes: [UInt8]) -> String {
        guard let bass = notes.min() else { return "READY TO PLAY" }
        let pitchClasses = Set(notes.map { Int($0) % 12 })
        if pitchClasses.count == 1 {
            let octave = Int(bass) / 12 - 1
            return "\(names[Int(bass) % 12])\(octave)"
        }

        for (intervals, suffix) in patterns where intervals.count == pitchClasses.count {
            for root in 0..<12 {
                let shifted = Set(intervals.map { ($0 + root) % 12 })
                if shifted == pitchClasses {
                    let slash = Int(bass) % 12 == root ? "" : "/\(names[Int(bass) % 12])"
                    return "\(names[root])\(suffix)\(slash)"
                }
            }
        }
        return "\(notes.count) NOTES"
    }
}
