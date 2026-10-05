import SwiftUI
import UIKit

struct PianoView: View {
    @State private var viewModel = PianoViewModel()
    @State private var studio = PerformanceStudio()
    @State private var metronome = MetronomeService()
    @State private var scrollAction: ((AnyHashable, UnitPoint?) -> Void)?
    @State private var navigatorPosition = 0.5
    @State private var showLibrary = false
    @State private var showTempo = false

    @AppStorage("keyWidth") private var keyWidth = 50.0
    @AppStorage("hapticsEnabled") private var hapticsEnabled = false
    @AppStorage("showKeyDisplayNames") private var showKeyDisplayNames = true
    @AppStorage("showFirstKeyNameForOctavesOnly") private var octaveNamesOnly = false
    @AppStorage("masterVolume") private var masterVolume = 0.85
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
                    onRecord: toggleRecording,
                    onPlay: togglePlayback,
                    onLibrary: { showLibrary = true },
                    onSustain: toggleSustain,
                    onMetronome: toggleMetronome,
                    onTempo: { showTempo = true },
                    onSettings: { viewModel.showSettings = true }
                )

                KeyboardNavigator(
                    position: $navigatorPosition,
                    octaves: viewModel.octaves,
                    currentOctave: viewModel.currentOctave,
                    onOctave: jumpToOctave
                )

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
                    let keyboardHeight = showsMusicStand
                        ? min(500, keyArea.size.height * 0.52)
                        : keyArea.size.height

                    VStack(spacing: 0) {
                        if showsMusicStand {
                            PortraitPracticeStand(
                                chordName: ChordDetector.name(for: viewModel.pressedMIDINotes),
                                takeCount: studio.takes.count,
                                isRecording: studio.isRecording,
                                onRecord: toggleRecording,
                                onLibrary: { showLibrary = true }
                            )
                        }
                        keyboard(height: keyboardHeight)
                            .frame(height: keyboardHeight)
                    }
                }

                Rectangle()
                    .fill(PianoTheme.background)
                    .frame(height: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PianoTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showLibrary) {
            PerformanceLibraryView(studio: studio, onPlay: playTake, onStop: stopPlayback)
        }
        .popover(isPresented: $showTempo) {
            TempoPopoverView(metronome: metronome)
        }
        .onChange(of: navigatorPosition) { _, position in
            viewModel.scrollPosition = position
            scrollToPosition(position)
        }
        .onAppear { viewModel.setMasterVolume(masterVolume) }
        .onChange(of: masterVolume) { _, volume in
            viewModel.setMasterVolume(volume)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { endActiveSession() }
        }
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
                                showLabels: showKeyDisplayNames,
                                octaveNamesOnly: octaveNamesOnly,
                                onPress: { press(key) },
                                onRelease: { release(key) }
                            )
                            .frame(width: keyWidth, height: height)
                            .id(key.id)
                        }
                    }

                    HStack(spacing: 1) {
                        ForEach(viewModel.whiteKeys) { key in
                            Color.clear
                                .frame(width: keyWidth, height: height)
                                .overlay(alignment: .topTrailing) {
                                    if let blackKey = key.nextBlackKey() {
                                        PianoKeyView(
                                            key: blackKey,
                                            isPressed: viewModel.isKeyPressed(blackKey),
                                            showLabels: showKeyDisplayNames,
                                            octaveNamesOnly: octaveNamesOnly,
                                            onPress: { press(blackKey) },
                                            onRelease: { release(blackKey) }
                                        )
                                        .frame(width: keyWidth * 0.62, height: height)
                                        .offset(x: keyWidth * 0.31)
                                    }
                                }
                        }
                    }
                }
                .frame(width: totalKeyboardWidth, height: height)
                .overlay {
                    KeyboardTouchSurface(
                        whiteKeys: viewModel.whiteKeys,
                        keyWidth: keyWidth,
                        onPress: press,
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
        return CGFloat(count) * keyWidth + CGFloat(max(0, count - 1))
    }

    private func press(_ key: PianoKey) {
        guard viewModel.keyPressed(key) else { return }
        PianoSessionActivity.markPlayed()
        studio.capture(note: key.midiNote, isNoteOn: true)
        if hapticsEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func release(_ key: PianoKey) {
        if viewModel.keyReleased(key) {
            studio.capture(note: key.midiNote, isNoteOn: false)
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
            studio.beginRecording()
            studio.captureSustain(viewModel.sustainEnabled)
        }
    }

    private func togglePlayback() {
        if studio.playingTakeID != nil {
            stopPlayback()
        } else if let take = studio.takes.first {
            playTake(take)
        }
    }

    private func playTake(_ take: PerformanceTake) {
        PianoSessionActivity.markPlayed()
        if studio.isRecording { studio.finishRecording() }
        studio.play(
            take,
            noteOn: { _ = viewModel.playbackNoteOn($0) },
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
        viewModel.setSustain(enabled)
        studio.captureSustain(enabled)
    }

    private func toggleMetronome() {
        PianoSessionActivity.markPlayed()
        if metronome.isRunning {
            metronome.stop()
        } else {
            metronome.start(bpm: metronome.bpm)
        }
    }

    private func endActiveSession() {
        if studio.isRecording || studio.playingTakeID != nil || metronome.isRunning {
            PianoSessionActivity.markPlayed()
        }
        if studio.isRecording { studio.finishRecording() }
        stopPlayback()
        metronome.stop()
        viewModel.stopAllNotes()
    }
}

#Preview(traits: .landscapeLeft) {
    PianoView()
}
