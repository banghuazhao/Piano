import SwiftUI
import UIKit

struct PianoView: View {
    @State private var viewModel = PianoViewModel()
    @State private var studio = PerformanceStudio()
    @State private var metronome = MetronomeService()
    @State private var practice = PracticeSession()
    @State private var songs = ImportedSongLibrary.shared
    @State private var midi = MIDIInputService()
    @State private var premium = PremiumStore.shared
    @State private var scrollAction: ((AnyHashable, UnitPoint?) -> Void)?
    @State private var navigatorPosition = 0.5
    @State private var showLibrary = false
    @State private var showTempo = false
    @State private var showPractice = false
    @State private var keyboardViewportWidth: CGFloat = 0

    @AppStorage("keyWidth") private var keyWidth = 50.0
    @AppStorage("hapticsEnabled") private var hapticsEnabled = false
    @AppStorage("showKeyDisplayNames") private var showKeyDisplayNames = true
    @AppStorage("showFirstKeyNameForOctavesOnly") private var octaveNamesOnly = false
    @AppStorage("masterVolume") private var masterVolume = 0.85
    @AppStorage("soundProfile") private var soundProfileRaw = PianoSoundProfile.concert.rawValue
    @AppStorage("practiceShowScore") private var showPracticeScore = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
                PianoToolbar(
                    chordName: ChordDetector.name(for: viewModel.pressedMIDINotes),
                    isRecording: studio.isRecording,
                    hasTake: !studio.takes.isEmpty,
                    isPlaying: studio.playingTakeID != nil,
                    sustainEnabled: viewModel.sustainEnabled,
                    metronomeRunning: metronome.isRunning,
                    bpm: metronome.bpm,
                    rhythmPracticeActive: practice.isActive && practice.options.mode == .rhythm,
                    practicePaused: practice.isPaused,
                    onRecord: toggleRecording,
                    onPlay: togglePlayback,
                    onLibrary: { showLibrary = true },
                    onPractice: { showPractice = true },
                    onSustain: toggleSustain,
                    onMetronome: toggleMetronome,
                    onTempo: {
                        if practice.options.mode == .rhythm { practice.pause() }
                        showTempo = true
                    },
                    onSettings: { practice.pause(); viewModel.showSettings = true }
                )

                if practice.exercise != nil {
                    PracticeSessionPanel(session: practice)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                if practice.exercise == nil || !showPracticeScore {
                    KeyboardNavigator(
                    position: $navigatorPosition,
                    octaves: viewModel.octaves,
                    currentOctave: viewModel.currentOctave,
                    onOctave: jumpToOctave
                    )
                }

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [PianoTheme.felt, PianoTheme.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 10)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(PianoTheme.brass.opacity(0.55))
                            .frame(height: 1)
                    }

                GeometryReader { keyArea in
                    let showsMusicStand = keyArea.size.height > 700
                        && keyArea.size.height > keyArea.size.width
                    let hasScore = practice.exercise != nil && showPracticeScore
                    let scoreHeight = showsMusicStand
                        ? keyArea.size.height - min(500, keyArea.size.height * 0.52)
                        : min(practice.options.hand == .both ? 148 : 104, keyArea.size.height * 0.48)
                    let keyboardHeight = hasScore ? max(1, keyArea.size.height - scoreHeight) : showsMusicStand && practice.exercise == nil
                        ? min(500, keyArea.size.height * 0.52)
                        : keyArea.size.height

                    VStack(spacing: 0) {
                        if hasScore {
                            PracticeScoreFollower(session: practice, isCompact: !showsMusicStand)
                                .frame(height: scoreHeight)
                        } else if showsMusicStand && practice.exercise == nil {
                            PortraitPracticeStand(
                                chordName: ChordDetector.name(for: viewModel.pressedMIDINotes),
                                takeCount: studio.takes.count,
                                isRecording: studio.isRecording,
                                soundTitle: activeSoundProfile.title,
                                onRecord: toggleRecording,
                                onLibrary: { showLibrary = true }
                            )
                        }
                        keyboard(height: keyboardHeight)
                            .frame(height: keyboardHeight)
                    }
                    .onAppear { keyboardViewportWidth = keyArea.size.width }
                    .onChange(of: keyArea.size.width) { _, width in keyboardViewportWidth = width }
                }

                Rectangle()
                    .fill(PianoTheme.background)
                    .frame(height: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PianoTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(midi: midi)
        }
        .sheet(isPresented: $showLibrary) {
            PerformanceLibraryView(studio: studio, onPlay: playTake, onStop: stopPlayback)
        }
        .sheet(isPresented: $showPractice) {
            PracticeLibraryView(session: practice, library: songs)
        }
        .popover(isPresented: $showTempo) {
            if practice.exercise != nil, practice.options.mode == .rhythm {
                PracticeTempoView(session: practice)
            } else {
                TempoPopoverView(metronome: metronome)
            }
        }
        .onChange(of: navigatorPosition) { _, position in
            viewModel.scrollPosition = position
            scrollToPosition(position)
        }
        .onAppear {
            viewModel.setMasterVolume(masterVolume)
            applySoundProfile()
            configureMIDI()
            configurePractice()
        }
        .onChange(of: masterVolume) { _, volume in
            viewModel.setMasterVolume(volume)
        }
        .onChange(of: scenePhase) { _, phase in
            midi.setActive(phase == .active)
            if phase != .active { endActiveSession() }
        }
        .onChange(of: soundProfileRaw) { _, _ in applySoundProfile() }
        .onChange(of: premium.isPremium) { _, _ in applySoundProfile() }
        .onChange(of: premium.hasDeterminedEntitlement) { _, _ in applySoundProfile() }
        .onChange(of: practice.isActive) { _, active in
            if active {
                PianoSessionActivity.markPlayed()
                stopPlayback()
                revealPracticeNotes(force: true)
            }
        }
        .onChange(of: practice.targetNotes) { _, _ in revealPracticeNotes() }
        .onChange(of: practice.currentStepIndex) { _, _ in revealPracticeNotes() }
        .onChange(of: practice.exercise?.id) { _, _ in revealPracticeNotes(force: true) }
        .onChange(of: showPractice) { _, shown in if shown { practice.pause() } }
        .onChange(of: showLibrary) { _, shown in if shown { practice.pause() } }
        .onChange(of: keyboardViewportWidth) { _, _ in revealPracticeNotes() }
    }

    private func keyboard(height: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1) {
                        ForEach(viewModel.whiteKeys) { key in
                            PianoKeyView(
                                key: key,
                                isPressed: viewModel.isKeyPressed(key),
                                isTarget: practice.targetNotes.contains(key.midiNote),
                                showLabels: showKeyDisplayNames,
                                octaveNamesOnly: octaveNamesOnly,
                                onPress: { press(key) },
                                onRelease: { release(key) }
                            )
                            .frame(width: playingKeyWidth, height: height)
                            .id(key.id)
                        }
                    }

                    HStack(spacing: 1) {
                        ForEach(viewModel.whiteKeys) { key in
                            Color.clear
                                .frame(width: playingKeyWidth, height: height)
                                .overlay(alignment: .topTrailing) {
                                    if let blackKey = key.nextBlackKey() {
                                        PianoKeyView(
                                            key: blackKey,
                                            isPressed: viewModel.isKeyPressed(blackKey),
                                            isTarget: practice.targetNotes.contains(blackKey.midiNote),
                                            showLabels: showKeyDisplayNames,
                                            octaveNamesOnly: octaveNamesOnly,
                                            onPress: { press(blackKey) },
                                            onRelease: { release(blackKey) }
                                        )
                                        .frame(width: playingKeyWidth * 0.62, height: height * 0.62)
                                        .offset(x: playingKeyWidth * 0.31)
                                    }
                                }
                        }
                    }
                }
                .frame(width: totalKeyboardWidth, height: height)
                .overlay {
                    KeyboardTouchSurface(
                        whiteKeys: viewModel.whiteKeys,
                        keyWidth: playingKeyWidth,
                        onPress: { _ = press($0) },
                        onRelease: release
                    )
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .clipped()
            .background(PianoTheme.background)
            .onAppear {
                scrollAction = proxy.scrollTo
                Task { @MainActor in
                    await Task.yield()
                    if let middleKey = viewModel.middleAnchorKey() {
                        proxy.scrollTo(middleKey.id, anchor: .center)
                        navigatorPosition = viewModel.normalizedPosition(for: middleKey) ?? 0.5
                    }
                }
            }
        }
    }

    private var totalKeyboardWidth: CGFloat {
        let count = viewModel.whiteKeys.count
        return CGFloat(count) * playingKeyWidth + CGFloat(max(0, count - 1))
    }

    /// Fit the measure, including sustained bass notes, so each new melody note
    /// does not resize the keyboard underneath a held finger.
    private var playingKeyWidth: CGFloat {
        guard practiceDisplayNotes.count > 1, keyboardViewportWidth > 0,
              let range = practiceKeyRange else { return keyWidth }
        let keysToFit = CGFloat(range.upperBound - range.lowerBound + 4)
        return max(30, min(keyWidth, keyboardViewportWidth / keysToFit - 1))
    }

    private var practiceKeyRange: ClosedRange<Int>? {
        let indices = practiceDisplayNotes.compactMap { note in
            viewModel.whiteKeys.lastIndex(where: { $0.midiNote <= note })
        }
        guard let first = indices.min(), let last = indices.max() else { return nil }
        return first...last
    }

    private var practiceDisplayNotes: Set<UInt8> {
        guard let exercise = practice.exercise, !exercise.steps.isEmpty else { return [] }
        let index = min(practice.currentStepIndex, exercise.steps.count - 1)
        let barLength = Double(exercise.beatsPerBar) * 4 / Double(exercise.beatUnit)
        let start = floor(exercise.steps[index].beat / barLength) * barLength
        return Set(exercise.score.filter {
            $0.startBeat < start + barLength && $0.startBeat + $0.durationBeats > start
        }.map(\.pitch))
    }

    @discardableResult
    private func press(_ key: PianoKey) -> Bool {
        let wasHeld = viewModel.pressedMIDINotes.contains(key.midiNote)
        guard viewModel.keyPressed(key) else { return false }
        PianoSessionActivity.markPlayed()
        if !wasHeld { studio.capture(note: key.midiNote, isNoteOn: true) }
        practice.noteOn(key.midiNote, heldNotes: Set(viewModel.pressedMIDINotes))
        if hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        return true
    }

    private func release(_ key: PianoKey) {
        if viewModel.keyReleased(key), !viewModel.pressedMIDINotes.contains(key.midiNote) {
            studio.capture(note: key.midiNote, isNoteOn: false)
            practice.noteOff(key.midiNote)
        }
    }

    private func scrollToPosition(_ position: Double) {
        guard let target = viewModel.keyForPosition(position), let scrollAction else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            scrollAction(target.id, .center)
        }
    }

    private func jumpToOctave(_ octave: Int) {
        guard let target = viewModel.anchorKey(forOctave: octave),
              let position = viewModel.normalizedPosition(for: target) else { return }
        navigatorPosition = position
        if hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func toggleRecording() {
        PianoSessionActivity.markPlayed()
        if studio.isRecording {
            studio.finishRecording()
        } else {
            stopPlayback()
            studio.beginRecording(
                heldNotes: viewModel.pressedMIDINotes,
                heldVelocities: viewModel.heldVelocities,
                sustain: viewModel.recordingSustainEnabled
            )
        }
    }

    private func togglePlayback() {
        if studio.playingTakeID != nil {
            stopPlayback()
        } else if let take = studio.takes.first {
            playTake(take, options: .init())
        }
    }

    private func playTake(_ take: PerformanceTake, options: PerformancePlaybackOptions) {
        PianoSessionActivity.markPlayed()
        if studio.isRecording { studio.finishRecording() }
        practice.stop()
        studio.play(
            take,
            options: options,
            noteOn: { note, velocity in _ = viewModel.playbackNoteOn(note, velocity: velocity) },
            noteOff: { _ = viewModel.playbackNoteOff($0) },
            sustain: { viewModel.setPlaybackSustain($0) }
        )
    }

    private func stopPlayback() {
        studio.stopPlayback()
        viewModel.stopPlaybackNotes()
    }

    private func toggleSustain() {
        let enabled = !viewModel.sustainEnabled
        let wasEnabled = viewModel.recordingSustainEnabled
        viewModel.setSustain(enabled)
        if wasEnabled != viewModel.recordingSustainEnabled {
            studio.captureSustain(viewModel.recordingSustainEnabled)
        }
    }

    private func toggleMetronome() {
        PianoSessionActivity.markPlayed()
        if practice.isActive, practice.options.mode == .rhythm {
            if practice.isPaused { practice.resume() } else { practice.pause() }
            return
        }
        if metronome.isRunning {
            metronome.stop()
        } else {
            metronome.start(bpm: metronome.bpm)
        }
    }

    private func endActiveSession() {
        if studio.isRecording || studio.playingTakeID != nil || metronome.isRunning || practice.isActive {
            PianoSessionActivity.markPlayed()
        }
        if studio.isRecording { studio.finishRecording() }
        stopPlayback()
        practice.pause()
        metronome.stop()
        viewModel.stopAllNotes()
        for note: UInt8 in 21...108 { practice.noteOff(note) }
    }

    private func applySoundProfile() {
        let requested = PianoSoundProfile(rawValue: soundProfileRaw) ?? .concert
        let allowed = !requested.isPremium || premium.isPremium
        viewModel.setSoundProfile(allowed ? requested : .concert)
        if premium.hasDeterminedEntitlement && !allowed {
            soundProfileRaw = PianoSoundProfile.concert.rawValue
        }
    }

    private var activeSoundProfile: PianoSoundProfile {
        let profile = PianoSoundProfile(rawValue: soundProfileRaw) ?? .concert
        return profile.isPremium && !premium.isPremium ? .concert : profile
    }

    private func revealPracticeNotes(force: Bool = false) {
        guard let range = practiceKeyRange else { return }
        let denominator = Double(viewModel.whiteKeys.count - 1)
        let center = Double(range.lowerBound + range.upperBound) / 2
        let halfVisible = max(0, keyboardViewportWidth / (playingKeyWidth + 1) / 2 - 1.5)
        let visibleCenter = navigatorPosition * denominator
        if force || Double(range.lowerBound) < visibleCenter - halfVisible
            || Double(range.upperBound) > visibleCenter + halfVisible {
            navigatorPosition = center / denominator
        }
    }

    private func configureMIDI() {
        midi.onEvent = { [weak viewModel, weak studio, weak practice] event in
            guard let viewModel, let studio, let practice else { return }
            Self.handleMIDI(event, viewModel: viewModel, studio: studio, practice: practice)
        }
        viewModel.onAudioReset = { [weak midi, weak studio, weak practice, weak metronome] in
            midi?.resetHeldNotes()
            if studio?.isRecording == true { studio?.finishRecording() }
            studio?.stopPlayback()
            practice?.pause()
            metronome?.stop()
            for note: UInt8 in 21...108 { practice?.noteOff(note) }
        }
        midi.setActive(scenePhase == .active)
        midi.start()
    }

    private func configurePractice() {
        practice.onRhythmStart = { [weak metronome] bpm, numerator, denominator in
            metronome?.startForPractice(bpm: bpm, beatsPerBar: numerator, beatUnit: denominator)
        }
        practice.onRhythmStop = { [weak metronome] in metronome?.stop() }
        metronome.onTimingReset = { [weak practice] in practice?.pause() }
    }

    private static func handleMIDI(
        _ event: MIDIInputEvent, viewModel: PianoViewModel,
        studio: PerformanceStudio, practice: PracticeSession
    ) {
        switch event {
        case let .noteOn(note, velocity):
            let wasHeld = viewModel.pressedMIDINotes.contains(note)
            guard viewModel.midiNoteOn(note, velocity: velocity) else { return }
            PianoSessionActivity.markPlayed()
            if !wasHeld { studio.capture(note: note, isNoteOn: true, velocity: velocity) }
            practice.noteOn(note, heldNotes: Set(viewModel.pressedMIDINotes))
        case let .noteOff(note):
            if viewModel.midiNoteOff(note), !viewModel.pressedMIDINotes.contains(note) {
                studio.capture(note: note, isNoteOn: false)
                practice.noteOff(note)
            }
        case let .sustain(enabled):
            let wasEnabled = viewModel.recordingSustainEnabled
            viewModel.setMIDISustain(enabled)
            if wasEnabled != viewModel.recordingSustainEnabled {
                studio.captureSustain(viewModel.recordingSustainEnabled)
            }
        case .allSoundOff:
            if studio.isRecording { studio.finishRecording() }
            studio.stopPlayback()
            practice.pause()
            viewModel.stopAllNotes()
            for note: UInt8 in 21...108 { practice.noteOff(note) }
        }
    }
}

#Preview(traits: .landscapeLeft) {
    PianoView()
}
