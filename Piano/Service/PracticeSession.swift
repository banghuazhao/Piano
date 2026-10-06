import Foundation
import Observation

enum PracticeFeedbackTone {
    case neutral
    case correct
    case tryAgain
    case completed
}

struct PracticeResult: Equatable {
    let exerciseID: String
    let title: String
    let completedAt: Date
    let stepCount: Int
    let correctNotes: Int
    let wrongNotes: Int

    var accuracyPercent: Int {
        let attempts = correctNotes + wrongNotes
        guard attempts > 0 else { return 100 }
        return Int((Double(correctNotes) / Double(attempts) * 100).rounded())
    }
}

/// Tracks live playing separately from audio playback. The piano forwards physical note events.
@MainActor
@Observable
final class PracticeSession {
    private(set) var exercise: PracticeExercise?
    private(set) var isActive = false
    private(set) var currentStepIndex = 0
    private(set) var correctNoteCount = 0
    private(set) var wrongNoteCount = 0
    private(set) var matchedNotes: Set<UInt8> = []
    private(set) var feedbackMessage = ""
    private(set) var feedbackTone: PracticeFeedbackTone = .neutral
    private(set) var lastCompletedResult: PracticeResult?
    private(set) var dailyProgress: PracticeDailyProgress

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var heldNotes: Set<UInt8> = []
    @ObservationIgnored private var blockedUntilRelease: Set<UInt8> = []

    static let dailyGoal = 3
    private static let progressKey = "pianoflow.practice.progress.v1"

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        if let data = defaults.data(forKey: Self.progressKey),
           let saved = try? JSONDecoder().decode(PracticeDailyProgress.self, from: data) {
            dailyProgress = saved
        } else {
            dailyProgress = PracticeDailyProgress()
        }
    }

    var targetNotes: Set<UInt8> {
        currentStep?.notes ?? []
    }

    var targetAnchorNote: UInt8? {
        targetNotes.min()
    }

    var currentStep: PracticeStep? {
        guard isActive, let exercise, exercise.steps.indices.contains(currentStepIndex) else { return nil }
        return exercise.steps[currentStepIndex]
    }

    var completedSteps: Int {
        if let lastCompletedResult { return lastCompletedResult.stepCount }
        return isActive ? currentStepIndex : 0
    }

    var totalSteps: Int {
        exercise?.steps.count ?? 0
    }

    var progressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }

    var accuracyPercent: Int {
        let attempts = correctNoteCount + wrongNoteCount
        guard attempts > 0 else { return 100 }
        return Int((Double(correctNoteCount) / Double(attempts) * 100).rounded())
    }

    var todayCompletions: Int {
        dailyProgress.lastDayKey == dayKey(for: now()) ? dailyProgress.completionsOnLastDay : 0
    }

    var streakDays: Int {
        guard let lastDay = dailyProgress.lastDayKey else { return 0 }
        let today = dayKey(for: now())
        let yesterday = dayKey(for: calendar.date(byAdding: .day, value: -1, to: now()) ?? now())
        return lastDay == today || lastDay == yesterday ? dailyProgress.streakDays : 0
    }

    var dailyGoalFraction: Double {
        min(1, Double(todayCompletions) / Double(Self.dailyGoal))
    }

    func start(_ exercise: PracticeExercise) {
        self.exercise = exercise
        isActive = true
        currentStepIndex = 0
        correctNoteCount = 0
        wrongNoteCount = 0
        matchedNotes = []
        lastCompletedResult = nil
        blockedUntilRelease = exercise.steps[0].notes.intersection(heldNotes)
        feedbackTone = .neutral
        feedbackMessage = prompt(for: exercise.steps[0])
    }

    func restart() {
        guard let exercise else { return }
        start(exercise)
    }

    func stop() {
        exercise = nil
        isActive = false
        currentStepIndex = 0
        correctNoteCount = 0
        wrongNoteCount = 0
        matchedNotes = []
        blockedUntilRelease = []
        feedbackMessage = ""
        feedbackTone = .neutral
        lastCompletedResult = nil
    }

    /// Call after the piano accepts a physical key press. `heldNotes` includes the new key.
    func noteOn(_ note: UInt8, heldNotes liveHeldNotes: Set<UInt8>) {
        let wasHeld = heldNotes.contains(note)
        let updatedHeld = liveHeldNotes.union([note])
        let newlyObserved = updatedHeld.subtracting(heldNotes).subtracting([note])
        blockedUntilRelease.formUnion(newlyObserved.intersection(targetNotes))
        blockedUntilRelease.formIntersection(updatedHeld)
        heldNotes = updatedHeld

        guard isActive, let step = currentStep, !wasHeld else { return }

        if blockedUntilRelease.contains(note) {
            feedbackTone = .neutral
            feedbackMessage = "Release \(PracticeNoteName.string(note)), then replay."
            return
        }

        guard step.notes.contains(note) else {
            wrongNoteCount += 1
            feedbackTone = .tryAgain
            feedbackMessage = "Try \(step.noteNames)."
            return
        }

        correctNoteCount += 1
        if step.isChord {
            matchedNotes = step.notes.intersection(heldNotes).subtracting(blockedUntilRelease)
            if matchedNotes == step.notes {
                advance()
            } else {
                feedbackTone = .correct
                let missing = step.notes.subtracting(matchedNotes).sorted().map(PracticeNoteName.string)
                feedbackMessage = "Hold those keys; add \(missing.joined(separator: " · "))."
            }
        } else {
            advance()
        }
    }

    /// Call for every physical key release, including when practice is not active.
    func noteOff(_ note: UInt8) {
        heldNotes.remove(note)
        blockedUntilRelease.remove(note)
        guard let step = currentStep, step.isChord else { return }
        matchedNotes = step.notes.intersection(heldNotes).subtracting(blockedUntilRelease)
        if matchedNotes.isEmpty {
            feedbackTone = .neutral
            feedbackMessage = prompt(for: step)
        } else {
            feedbackTone = .correct
            let missing = step.notes.subtracting(matchedNotes).sorted().map(PracticeNoteName.string)
            feedbackMessage = "Add \(missing.joined(separator: " · "))."
        }
    }

    private func advance() {
        guard let exercise else { return }
        currentStepIndex += 1
        matchedNotes = []

        if currentStepIndex == exercise.steps.count {
            finish(exercise)
            return
        }

        let next = exercise.steps[currentStepIndex]
        blockedUntilRelease = next.notes.intersection(heldNotes)
        feedbackTone = .correct
        feedbackMessage = blockedUntilRelease.isEmpty
            ? "Next: \(next.noteNames)."
            : "Release \(blockedUntilRelease.sorted().map(PracticeNoteName.string).joined(separator: " · ")), then replay."
    }

    private func finish(_ exercise: PracticeExercise) {
        let result = PracticeResult(
            exerciseID: exercise.id,
            title: exercise.title,
            completedAt: now(),
            stepCount: exercise.steps.count,
            correctNotes: correctNoteCount,
            wrongNotes: wrongNoteCount
        )
        isActive = false
        blockedUntilRelease = []
        lastCompletedResult = result
        feedbackTone = .completed
        feedbackMessage = "Finished · \(result.accuracyPercent)% accuracy."
        recordCompletion(at: result.completedAt)
    }

    private func prompt(for step: PracticeStep) -> String {
        let blocked = step.notes.intersection(blockedUntilRelease)
        if !blocked.isEmpty {
            return "Release \(blocked.sorted().map(PracticeNoteName.string).joined(separator: " · ")), then play again."
        }
        return step.isChord
            ? "Hold \(step.noteNames) together."
            : "Play \(step.noteNames)."
    }

    private func recordCompletion(at date: Date) {
        let today = dayKey(for: date)
        if dailyProgress.lastDayKey == today {
            dailyProgress.completionsOnLastDay += 1
        } else {
            let yesterday = dayKey(for: calendar.date(byAdding: .day, value: -1, to: date) ?? date)
            dailyProgress.streakDays = dailyProgress.lastDayKey == yesterday
                ? dailyProgress.streakDays + 1 : 1
            dailyProgress.lastDayKey = today
            dailyProgress.completionsOnLastDay = 1
        }
        dailyProgress.longestStreakDays = max(dailyProgress.longestStreakDays, dailyProgress.streakDays)
        dailyProgress.lifetimeCompletions += 1
        if let data = try? JSONEncoder().encode(dailyProgress) {
            defaults.set(data, forKey: Self.progressKey)
        }
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

struct PracticeDailyProgress: Codable, Equatable {
    var lastDayKey: String?
    var completionsOnLastDay = 0
    var streakDays = 0
    var longestStreakDays = 0
    var lifetimeCompletions = 0
}
