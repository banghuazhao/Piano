import Foundation
import Observation

enum PracticeFeedbackTone {
    case neutral
    case correct
    case tryAgain
    case completed
}

enum PracticeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case wait
    case rhythm

    var id: String { rawValue }
}

struct PracticeOptions: Equatable, Sendable {
    var mode: PracticeMode
    /// Nil uses the exercise's suggested tempo.
    var bpm: Int?
    var countInBars: Int
    var hand: PracticeHand
    /// Zero leaves the tempo fixed after a completed pass.
    var tempoStep: Int
    /// Nil uses the exercise's suggested tempo.
    var targetBPM: Int?

    init(mode: PracticeMode = .wait, bpm: Int? = nil, countInBars: Int = 1,
         hand: PracticeHand = .both, tempoStep: Int = 5, targetBPM: Int? = nil) {
        self.mode = mode
        self.bpm = bpm
        self.countInBars = countInBars
        self.hand = hand
        self.tempoStep = tempoStep
        self.targetBPM = targetBPM
    }

    fileprivate func resolved(for exercise: PracticeExercise) -> Self {
        var copy = self
        copy.bpm = min(240, max(40, bpm ?? exercise.suggestedBPM))
        copy.countInBars = min(4, max(0, countInBars))
        copy.tempoStep = min(30, max(0, tempoStep))
        copy.targetBPM = min(240, max(40, targetBPM ?? exercise.suggestedBPM))
        return copy
    }
}

struct PracticeResult: Equatable {
    let exerciseID: String
    let title: String
    let completedAt: Date
    let stepCount: Int
    let correctNotes: Int
    let wrongNotes: Int
    let missedNotes: Int
    let mode: PracticeMode
    let bpm: Int?
    /// Grades note onsets against the score. Note lengths are not graded.
    let onsetTimingAccuracyPercent: Int?

    var accuracyPercent: Int {
        let attempts = correctNotes + wrongNotes + missedNotes
        guard attempts > 0 else { return 100 }
        return Int((Double(correctNotes) / Double(attempts) * 100).rounded())
    }
}

/// Tracks live playing separately from audio playback. The piano forwards physical note events.
@MainActor
@Observable
final class PracticeSession {
    private(set) var exercise: PracticeExercise?
    private(set) var options = PracticeOptions()
    private(set) var isActive = false
    private(set) var isPaused = false
    private(set) var isCountingIn = false
    /// One-based beat within the count-in bar, or zero outside the count-in.
    private(set) var countInBeat = 0
    /// Quarter-note beats since the score began, excluding count-in time.
    private(set) var currentBeat = 0.0
    private(set) var currentStepIndex = 0
    private(set) var correctNoteCount = 0
    private(set) var wrongNoteCount = 0
    private(set) var missedNoteCount = 0
    private(set) var matchedNotes: Set<UInt8> = []
    private(set) var feedbackMessage = ""
    private(set) var feedbackTone: PracticeFeedbackTone = .neutral
    private(set) var lastCompletedResult: PracticeResult?
    private(set) var dailyProgress: PracticeDailyProgress

    /// Return the monotonic uptime of the first scheduled click. A nil return pauses the run.
    /// Arguments are quarter-note BPM, meter numerator, and meter denominator.
    @ObservationIgnored var onRhythmStart: ((Int, Int, Int) -> TimeInterval?)?
    @ObservationIgnored var onRhythmStop: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let automaticTicks: Bool
    @ObservationIgnored private var sourceExercise: PracticeExercise?
    @ObservationIgnored private var heldNotes: Set<UInt8> = []
    @ObservationIgnored private var blockedUntilRelease: Set<UInt8> = []
    @ObservationIgnored private var pendingRhythmNotes: [Set<UInt8>] = []
    @ObservationIgnored private var pendingRhythmNoteCount = 0
    @ObservationIgnored private var matchedRhythmNotes: [Set<UInt8>] = []
    @ObservationIgnored private var onsetPointsByStep: [Double] = []
    @ObservationIgnored private var wrongRhythmBeats: [Double] = []
    @ObservationIgnored private var firstChordOnset: [Int: Double] = [:]
    @ObservationIgnored private var onsetAccuracyPoints = 0.0
    @ObservationIgnored private var rhythmEpoch = 0.0
    @ObservationIgnored private var rhythmTimelineOffset = 0.0
    @ObservationIgnored private var countInQuarterBeats = 0.0
    @ObservationIgnored private var rhythmClickRunning = false
    @ObservationIgnored private var expiryCursor = 0
    @ObservationIgnored private var tickerTask: Task<Void, Never>?

    static let dailyGoal = 3
    private static let progressKey = "pianoflow.practice.progress.v1"

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        automaticTicks: Bool = true
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.uptime = uptime
        self.automaticTicks = automaticTicks
        if let data = defaults.data(forKey: Self.progressKey),
           let saved = try? JSONDecoder().decode(PracticeDailyProgress.self, from: data) {
            dailyProgress = saved
        } else {
            dailyProgress = PracticeDailyProgress()
        }
    }

    var currentBPM: Int { options.bpm ?? exercise?.suggestedBPM ?? 80 }
    var targetBPM: Int { options.targetBPM ?? exercise?.suggestedBPM ?? 80 }

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
        let attempts = correctNoteCount + wrongNoteCount + missedNoteCount
        guard attempts > 0 else { return 100 }
        return Int((Double(correctNoteCount) / Double(attempts) * 100).rounded())
    }

    var suggestedNextBPM: Int? {
        guard let result = lastCompletedResult, result.mode == .rhythm,
              options.tempoStep > 0, result.accuracyPercent >= 80,
              (result.onsetTimingAccuracyPercent ?? 0) >= 80,
              currentBPM < targetBPM else { return nil }
        return min(targetBPM, currentBPM + options.tempoStep)
    }

    var canIncreaseTempo: Bool { suggestedNextBPM != nil }

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
        start(exercise, options: PracticeOptions(mode: .wait))
    }

    func start(_ exercise: PracticeExercise, options requestedOptions: PracticeOptions) {
        stopRhythmClicks()
        guard let selected = exercise.selecting(hand: requestedOptions.hand) else {
            stop()
            feedbackMessage = "This exercise has no notes for that hand."
            return
        }
        sourceExercise = exercise
        self.exercise = selected
        options = requestedOptions.resolved(for: exercise)
        isActive = true
        isPaused = false
        isCountingIn = false
        countInBeat = 0
        currentBeat = requestedOptions.mode == .wait ? selected.steps[0].beat : 0
        currentStepIndex = 0
        correctNoteCount = 0
        wrongNoteCount = 0
        missedNoteCount = 0
        matchedNotes = []
        lastCompletedResult = nil
        blockedUntilRelease = selected.steps[0].notes.intersection(heldNotes)
        feedbackTone = .neutral
        feedbackMessage = prompt(for: selected.steps[0])

        if options.mode == .rhythm {
            pendingRhythmNotes = selected.steps.map(\.notes)
            pendingRhythmNoteCount = selected.steps.reduce(0) { $0 + $1.notes.count }
            matchedRhythmNotes = Array(repeating: [], count: selected.steps.count)
            onsetPointsByStep = Array(repeating: 0, count: selected.steps.count)
            wrongRhythmBeats = []
            firstChordOnset = [:]
            onsetAccuracyPoints = 0
            expiryCursor = 0
            beginRhythmTimeline(from: 0, countInBars: options.countInBars)
        } else {
            pendingRhythmNotes = []
            pendingRhythmNoteCount = 0
            matchedRhythmNotes = []
            onsetPointsByStep = []
            wrongRhythmBeats = []
        }
    }

    func restart() {
        guard let sourceExercise else { return }
        start(sourceExercise, options: options)
    }

    /// Starts another full pass only after the player explicitly requests a qualified tempo step.
    @discardableResult
    func increaseTempo() -> Bool {
        guard let nextBPM = suggestedNextBPM, let sourceExercise else { return false }
        var nextOptions = options
        nextOptions.bpm = nextBPM
        start(sourceExercise, options: nextOptions)
        return true
    }

    func stop() {
        stopRhythmClicks()
        exercise = nil
        sourceExercise = nil
        options = PracticeOptions()
        isActive = false
        isPaused = false
        isCountingIn = false
        countInBeat = 0
        currentBeat = 0
        currentStepIndex = 0
        correctNoteCount = 0
        wrongNoteCount = 0
        missedNoteCount = 0
        matchedNotes = []
        blockedUntilRelease = []
        pendingRhythmNotes = []
        pendingRhythmNoteCount = 0
        matchedRhythmNotes = []
        onsetPointsByStep = []
        wrongRhythmBeats = []
        firstChordOnset = [:]
        feedbackMessage = ""
        feedbackTone = .neutral
        lastCompletedResult = nil
    }

    func pause() {
        guard isActive, !isPaused else { return }
        if options.mode == .rhythm { tick() }
        guard isActive else { return }
        isPaused = true
        isCountingIn = false
        countInBeat = 0
        stopRhythmClicks()
        feedbackTone = .neutral
        feedbackMessage = "Paused · resume when ready."
    }

    func resume() {
        guard isActive, isPaused else { return }
        if options.mode == .rhythm {
            // Re-enter on a score bar line so the click's downbeat stays aligned.
            let barLength = Double((exercise?.beatsPerBar ?? 4) * 4) / Double(exercise?.beatUnit ?? 4)
            let replayBeat = floor(currentBeat / barLength) * barLength
            let replaying = replayBeat + 0.000_001 < currentBeat
            beginRhythmTimeline(from: replayBeat, countInBars: max(1, options.countInBars))
            guard !isPaused else { return }
            if replaying { rewindRhythmBar(from: replayBeat, to: replayBeat + barLength) }
            currentBeat = replayBeat
            if replaying { feedbackMessage = "Count in, then replay this bar." }
        } else {
            isPaused = false
            if let currentStep { feedbackMessage = prompt(for: currentStep) }
        }
    }

    /// Updates count-in and missed-note state from an absolute monotonic timestamp.
    func tick() { tick(at: uptime()) }

    func tick(at timestamp: TimeInterval) {
        guard isActive, !isPaused, options.mode == .rhythm, let exercise else { return }
        let secondsPerBeat = 60.0 / Double(currentBPM)
        let elapsedBeats = max(0, (timestamp - rhythmEpoch) / secondsPerBeat)
        if timestamp < rhythmEpoch || elapsedBeats + 0.000_001 < countInQuarterBeats {
            isCountingIn = true
            let clickInterval = 4.0 / Double(exercise.beatUnit)
            countInBeat = timestamp < rhythmEpoch ? 0
                : Int(floor(elapsedBeats / clickInterval)) % exercise.beatsPerBar + 1
            return
        }

        isCountingIn = false
        countInBeat = 0
        currentBeat = max(0, rhythmTimelineOffset + elapsedBeats - countInQuarterBeats)
        let tolerance = onsetToleranceBeats
        var newlyMissed = 0
        while expiryCursor < pendingRhythmNotes.count,
              exercise.steps[expiryCursor].beat + tolerance < currentBeat {
            newlyMissed += pendingRhythmNotes[expiryCursor].count
            pendingRhythmNotes[expiryCursor].removeAll()
            firstChordOnset.removeValue(forKey: expiryCursor)
            expiryCursor += 1
        }
        if newlyMissed > 0 {
            missedNoteCount += newlyMissed
            pendingRhythmNoteCount -= newlyMissed
            feedbackTone = .tryAgain
            feedbackMessage = newlyMissed == 1 ? "Missed a note · keep going." : "Missed \(newlyMissed) notes · keep going."
        }
        updateRhythmStep()

        if currentBeat + 0.000_001 >= exercise.totalBeats,
           pendingRhythmNoteCount == 0 {
            currentStepIndex = exercise.steps.count
            matchedNotes = []
            finish(exercise)
        }
    }

    /// Call after the piano accepts a physical key press. `heldNotes` includes the new key.
    func noteOn(_ note: UInt8, heldNotes liveHeldNotes: Set<UInt8>) {
        let wasHeld = heldNotes.contains(note)
        let updatedHeld = liveHeldNotes.union([note])
        let newlyObserved = updatedHeld.subtracting(heldNotes).subtracting([note])
        blockedUntilRelease.formUnion(newlyObserved.intersection(targetNotes))
        blockedUntilRelease.formIntersection(updatedHeld)
        heldNotes = updatedHeld

        guard isActive, !isPaused, !wasHeld else { return }
        if options.mode == .rhythm {
            tick()
            guard isActive, !isPaused else { return }
            if isCountingIn {
                feedbackTone = .neutral
                feedbackMessage = "Wait for the count-in."
                return
            }
            gradeRhythmOnset(note)
            return
        }

        guard let step = currentStep else { return }

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
                advanceWait()
            } else {
                feedbackTone = .correct
                let missing = step.notes.subtracting(matchedNotes).sorted().map(PracticeNoteName.string)
                feedbackMessage = "Hold those keys; add \(missing.joined(separator: " · "))."
            }
        } else {
            advanceWait()
        }
    }

    /// Call for every physical key release, including when practice is not active.
    func noteOff(_ note: UInt8) {
        heldNotes.remove(note)
        blockedUntilRelease.remove(note)
        guard options.mode == .wait, let step = currentStep, step.isChord else { return }
        matchedNotes = step.notes.intersection(heldNotes).subtracting(blockedUntilRelease)
        guard !isPaused else { return }
        if matchedNotes.isEmpty {
            feedbackTone = .neutral
            feedbackMessage = prompt(for: step)
        } else {
            feedbackTone = .correct
            let missing = step.notes.subtracting(matchedNotes).sorted().map(PracticeNoteName.string)
            feedbackMessage = "Add \(missing.joined(separator: " · "))."
        }
    }

    private var onsetToleranceBeats: Double {
        // About 200 ms at a moderate tempo, capped below the next eighth-note onset.
        min(0.45, max(0.14, 0.20 * Double(currentBPM) / 60.0))
    }

    private func gradeRhythmOnset(_ note: UInt8) {
        guard let exercise else { return }
        if blockedUntilRelease.contains(note) {
            feedbackTone = .neutral
            feedbackMessage = "Release \(PracticeNoteName.string(note)), then replay."
            return
        }

        let tolerance = onsetToleranceBeats
        var candidates: [(Int, Double)] = []
        var candidateIndex = lowerBoundForRhythmStep(at: currentBeat - tolerance)
        while candidateIndex < pendingRhythmNotes.count,
              exercise.steps[candidateIndex].beat <= currentBeat + tolerance {
            if pendingRhythmNotes[candidateIndex].contains(note),
               firstChordOnset[candidateIndex].map({ abs(currentBeat - $0) <= tolerance }) ?? true {
                candidates.append((candidateIndex, abs(currentBeat - exercise.steps[candidateIndex].beat)))
            }
            candidateIndex += 1
        }
        guard let best = candidates.min(by: {
            $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1
        }) else {
            wrongNoteCount += 1
            wrongRhythmBeats.append(currentBeat)
            feedbackTone = .tryAgain
            feedbackMessage = currentStep.map { "Listen for the beat · next: \($0.noteNames)." }
                ?? "Listen for the beat."
            return
        }

        let index = best.0
        if exercise.steps[index].isChord, firstChordOnset[index] == nil {
            firstChordOnset[index] = currentBeat
        }
        pendingRhythmNotes[index].remove(note)
        if pendingRhythmNotes[index].isEmpty { firstChordOnset.removeValue(forKey: index) }
        pendingRhythmNoteCount -= 1
        matchedRhythmNotes[index].insert(note)
        correctNoteCount += 1
        let timingPoints = min(1, max(0, 2 - 2 * best.1 / tolerance))
        onsetAccuracyPoints += timingPoints
        onsetPointsByStep[index] += timingPoints
        feedbackTone = .correct
        feedbackMessage = best.1 <= tolerance / 2 ? "On time." : "Good note · tighten the timing."
        updateRhythmStep()
        if currentBeat + 0.000_001 >= exercise.totalBeats,
           pendingRhythmNoteCount == 0 {
            finish(exercise)
        }
    }

    private func updateRhythmStep() {
        guard let exercise else { return }
        while currentStepIndex < pendingRhythmNotes.count,
              pendingRhythmNotes[currentStepIndex].isEmpty {
            currentStepIndex += 1
        }
        matchedNotes = exercise.steps.indices.contains(currentStepIndex)
            ? matchedRhythmNotes[currentStepIndex] : []
    }

    private func lowerBoundForRhythmStep(at beat: Double) -> Int {
        guard let exercise else { return 0 }
        var low = 0
        var high = exercise.steps.count
        while low < high {
            let middle = low + (high - low) / 2
            if exercise.steps[middle].beat < beat { low = middle + 1 }
            else { high = middle }
        }
        return low
    }

    private func rewindRhythmBar(from startBeat: Double, to endBeat: Double) {
        guard let exercise else { return }
        let first = lowerBoundForRhythmStep(at: startBeat)
        let end = lowerBoundForRhythmStep(at: endBeat)
        if first < end {
            for index in first..<end {
                let alreadyMatched = matchedRhythmNotes[index].count
                let previouslyMissed = exercise.steps[index].notes.count
                    - pendingRhythmNotes[index].count - alreadyMatched
                pendingRhythmNoteCount += alreadyMatched + previouslyMissed
                correctNoteCount = max(0, correctNoteCount - alreadyMatched)
                missedNoteCount = max(0, missedNoteCount - previouslyMissed)
                onsetAccuracyPoints = max(0, onsetAccuracyPoints - onsetPointsByStep[index])
                onsetPointsByStep[index] = 0
                pendingRhythmNotes[index] = exercise.steps[index].notes
                matchedRhythmNotes[index].removeAll()
                firstChordOnset.removeValue(forKey: index)
            }
            expiryCursor = min(expiryCursor, first)
            currentStepIndex = min(currentStepIndex, first)
            updateRhythmStep()
        }
        let previousWrongCount = wrongRhythmBeats.count
        wrongRhythmBeats.removeAll { $0 >= startBeat && $0 < endBeat }
        wrongNoteCount = max(0, wrongNoteCount - (previousWrongCount - wrongRhythmBeats.count))
    }

    private func beginRhythmTimeline(from beat: Double, countInBars: Int) {
        guard let exercise else { return }
        rhythmTimelineOffset = beat
        countInQuarterBeats = Double(countInBars * exercise.beatsPerBar) * 4.0 / Double(exercise.beatUnit)
        let epoch: TimeInterval?
        if let onRhythmStart {
            epoch = onRhythmStart(currentBPM, exercise.beatsPerBar, exercise.beatUnit)
        } else {
            epoch = uptime()
        }
        guard let epoch, epoch.isFinite, epoch >= 0 else {
            rhythmClickRunning = false
            cancelTicker()
            if onRhythmStart != nil { onRhythmStop?() }
            isPaused = true
            isCountingIn = false
            countInBeat = 0
            feedbackTone = .tryAgain
            feedbackMessage = "Metronome unavailable · try resuming."
            return
        }
        rhythmEpoch = epoch
        rhythmClickRunning = onRhythmStart != nil
        isPaused = false
        isCountingIn = countInQuarterBeats > 0 || uptime() < epoch
        countInBeat = isCountingIn && uptime() >= epoch ? 1 : 0
        feedbackTone = .neutral
        feedbackMessage = isCountingIn ? "Listen to the count-in." : "Play with the beat."
        startTicker()
    }

    private func stopRhythmClicks() {
        cancelTicker()
        guard rhythmClickRunning else { return }
        rhythmClickRunning = false
        onRhythmStop?()
    }

    private func startTicker() {
        cancelTicker()
        guard automaticTicks else { return }
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) }
                catch { break }
                guard let self else { break }
                self.tick()
                if !self.isActive || self.isPaused { break }
            }
        }
    }

    private func cancelTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func advanceWait() {
        guard let exercise else { return }
        currentStepIndex += 1
        matchedNotes = []

        if currentStepIndex == exercise.steps.count {
            finish(exercise)
            return
        }

        let next = exercise.steps[currentStepIndex]
        currentBeat = next.beat
        blockedUntilRelease = next.notes.intersection(heldNotes)
        feedbackTone = .correct
        feedbackMessage = blockedUntilRelease.isEmpty
            ? "Next: \(next.noteNames)."
            : "Release \(blockedUntilRelease.sorted().map(PracticeNoteName.string).joined(separator: " · ")), then replay."
    }

    private func finish(_ exercise: PracticeExercise) {
        stopRhythmClicks()
        currentBeat = exercise.totalBeats
        let expectedOnsets = exercise.steps.reduce(0) { $0 + $1.notes.count }
        let timingPercent: Int? = options.mode == .rhythm
            ? Int((onsetAccuracyPoints / Double(max(1, expectedOnsets)) * 100).rounded())
            : nil
        let result = PracticeResult(
            exerciseID: exercise.id,
            title: exercise.title,
            completedAt: now(),
            stepCount: exercise.steps.count,
            correctNotes: correctNoteCount,
            wrongNotes: wrongNoteCount,
            missedNotes: missedNoteCount,
            mode: options.mode,
            bpm: options.mode == .rhythm ? currentBPM : nil,
            onsetTimingAccuracyPercent: timingPercent
        )
        isActive = false
        isPaused = false
        isCountingIn = false
        countInBeat = 0
        blockedUntilRelease = []
        lastCompletedResult = result
        feedbackTone = .completed
        feedbackMessage = "Finished · \(result.accuracyPercent)% accuracy."
        // A silent timed run reaches its end automatically; it is not a practiced exercise.
        if result.mode == .wait || result.correctNotes > 0 {
            recordCompletion(at: result.completedAt)
        }
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
