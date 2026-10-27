//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

/// The instrument's compact control surface. PianoView owns each action and its state.
struct PianoToolbar: View {
    let chordName: String
    let isRecording: Bool
    let hasTake: Bool
    let isPlaying: Bool
    let sustainEnabled: Bool
    let metronomeRunning: Bool
    let bpm: Int
    var rhythmPracticeActive = false
    var practicePaused = false
    let onRecord: () -> Void
    let onPlay: () -> Void
    let onLibrary: () -> Void
    let onPractice: () -> Void
    let onSustain: () -> Void
    let onMetronome: () -> Void
    let onTempo: () -> Void
    let onSettings: () -> Void
    let onStopAllSound: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
          Group {
            if geometry.size.width >= 1080 && !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 12) {
                identity
                chordDisplay
                Spacer(minLength: 8)
                controls(compact: false)
            }
            } else if geometry.size.width >= 720 && !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: 8) {
                compactIdentity
                Text(chordName == "READY TO PLAY" ? "LIVE" : chordName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(PianoTheme.ivory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minWidth: 42, maxWidth: 90, alignment: .leading)
                    .accessibilityLabel(chordName)
                controls(compact: true)
            }
            } else {
            HStack(spacing: 8) {
                compactIdentity

                Text(chordName == "READY TO PLAY" ? "LIVE" : chordName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(PianoTheme.ivory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(chordName)

                control(
                    title: isRecording ? "Stop recording" : "Record",
                    caption: "REC",
                    symbol: isRecording ? "stop.circle.fill" : "record.circle",
                    isActive: isRecording,
                    activeColor: PianoTheme.recording,
                    compact: true,
                    identifier: "piano.record",
                    action: onRecord
                )
                .frame(width: 44)

                control(
                    title: isPlaying ? "Stop playback" : "Play latest recording",
                    caption: "PLAY",
                    symbol: isPlaying ? "stop.fill" : "play.fill",
                    isActive: isPlaying,
                    isEnabled: hasTake || isPlaying,
                    compact: true,
                    identifier: "piano.play",
                    action: onPlay
                )
                .frame(width: 44)

                moreControls
            }
            }
          }
        .pianoGlassContainer()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 60)
        .background {
            LinearGradient(
                colors: [PianoTheme.panelRaised, PianoTheme.panel, PianoTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(alignment: .bottom) {
                PianoTheme.brass.opacity(0.38).frame(height: 1)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var identity: some View {
        HStack(spacing: 8) {
            Image(systemName: "pianokeys")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(PianoTheme.brass)
                .frame(width: 34, height: 34)
                .background(PianoTheme.brass.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("PIANOFLOW")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(PianoTheme.ivory)
                Text("STUDIO PIANO")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(PianoTheme.brass)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var compactIdentity: some View {
        Image(systemName: "pianokeys")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(PianoTheme.brass)
            .frame(width: 44, height: 44)
            .background(PianoTheme.brass.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("PianoFlow")
    }

    private var moreControls: some View {
        Menu {
            Button("Guided practice", systemImage: "graduationcap", action: onPractice)
                .accessibilityIdentifier("piano.practice")
            Button("Saved performances", systemImage: "square.stack", action: onLibrary)
                .accessibilityIdentifier("piano.library")
            Button(sustainEnabled ? "Turn sustain off" : "Turn sustain on", systemImage: "waveform.path", action: onSustain)
                .accessibilityIdentifier("piano.sustain")
            Button(metronomeActionTitle, systemImage: "metronome", action: onMetronome)
                .accessibilityIdentifier("piano.metronome")
            Button("Tempo settings (\(bpm) BPM)", systemImage: "slider.horizontal.3", action: onTempo)
                .accessibilityIdentifier("piano.tempo")
            Divider()
            Button("Stop all sound", systemImage: "speaker.slash.fill", action: onStopAllSound)
                .accessibilityIdentifier("piano.stopAllSound")
            Button("Settings", systemImage: "gearshape", action: onSettings)
                .accessibilityIdentifier("piano.settings")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PianoTheme.ivory)
                .frame(width: 44, height: 44)
                .pianoControlSurface(cornerRadius: 10,
                                     tint: sustainEnabled || metronomeRunning ? PianoTheme.brass : nil,
                                     interactive: true)
                .overlay(alignment: .topTrailing) {
                    if sustainEnabled || metronomeRunning {
                        Circle()
                            .fill(PianoTheme.brass)
                            .frame(width: 6, height: 6)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
        }
        .accessibilityLabel("More piano controls")
        .accessibilityValue(activeControlSummary)
        .accessibilityIdentifier("piano.moreControls")
    }

    private var activeControlSummary: String {
        let active = [
            sustainEnabled ? "Sustain on" : nil,
            metronomeRunning ? "Metronome running" : nil
        ].compactMap { $0 }
        return active.isEmpty ? "No active effects" : active.joined(separator: ", ")
    }

    private var chordDisplay: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("LIVE CHORD")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(PianoTheme.secondary)
            Text(chordName.isEmpty ? "—" : chordName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(PianoTheme.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 104, maxWidth: 144, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .background(PianoTheme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(PianoTheme.brass.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chordName.isEmpty ? "No chord detected" : "Chord: \(chordName)")
    }

    private func controls(compact: Bool) -> some View {
        HStack(spacing: compact ? 5 : 4) {
            control(
                title: isRecording ? "Stop recording" : "Record",
                caption: "REC",
                symbol: isRecording ? "stop.circle.fill" : "record.circle",
                isActive: isRecording,
                activeColor: PianoTheme.recording,
                compact: compact,
                identifier: "piano.record",
                action: onRecord
            )
            control(
                title: isPlaying ? "Stop playback" : "Play latest recording",
                caption: "PLAY",
                symbol: isPlaying ? "stop.fill" : "play.fill",
                isActive: isPlaying,
                isEnabled: hasTake || isPlaying,
                compact: compact,
                identifier: "piano.play",
                action: onPlay
            )
            control(
                title: "Guided practice",
                caption: "PRACTICE",
                symbol: "graduationcap",
                compact: compact,
                identifier: "piano.practice",
                action: onPractice
            )
            control(
                title: "Saved recordings",
                caption: "TAKES",
                symbol: "square.stack",
                compact: compact,
                identifier: "piano.library",
                action: onLibrary
            )

            Rectangle()
                .fill(PianoTheme.divider)
                .frame(width: 1, height: 27)
                .padding(.horizontal, compact ? 1 : 4)
                .accessibilityHidden(true)

            control(
                title: sustainEnabled ? "Turn sustain off" : "Turn sustain on",
                caption: "SUSTAIN",
                symbol: "waveform.path",
                isActive: sustainEnabled,
                compact: compact,
                identifier: "piano.sustain",
                action: onSustain
            )
            control(
                title: metronomeActionTitle,
                caption: "CLICK",
                symbol: "metronome",
                isActive: metronomeRunning,
                compact: compact,
                identifier: "piano.metronome",
                action: onMetronome
            )
            tempoButton(compact: compact)
            control(
                title: "Settings",
                caption: "SETTINGS",
                symbol: "gearshape",
                compact: compact,
                identifier: "piano.settings",
                action: onSettings
            )
            moreControls
        }
        .frame(maxWidth: compact ? .infinity : nil)
    }

    private var metronomeActionTitle: String {
        rhythmPracticeActive
            ? (practicePaused ? "Resume rhythm practice" : "Pause rhythm practice")
            : (metronomeRunning ? "Stop metronome" : "Start metronome")
    }

    private func control(
        title: String,
        caption: String,
        symbol: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        activeColor: Color = PianoTheme.brass,
        compact: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                if !compact {
                    Text(caption)
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.7)
                }
            }
            .foregroundStyle(isActive ? activeColor : PianoTheme.ivory)
            .frame(minWidth: compact ? 44 : 56, minHeight: 44)
            .frame(maxWidth: compact ? .infinity : nil)
            .pianoControlSurface(cornerRadius: 10, tint: isActive ? activeColor : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func tempoButton(compact: Bool) -> some View {
        Button(action: onTempo) {
            VStack(spacing: 1) {
                Text("\(bpm)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.9)
            }
            .foregroundStyle(PianoTheme.brass)
            .frame(minWidth: compact ? 53 : 62, minHeight: 44)
            .frame(maxWidth: compact ? .infinity : nil)
            .pianoControlSurface(cornerRadius: 10, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tempo settings, \(bpm) beats per minute")
        .accessibilityIdentifier("piano.tempo")
    }

}

#if DEBUG
#Preview(traits: .landscapeLeft) {
    PianoToolbar(
        chordName: "Cmaj7",
        isRecording: true,
        hasTake: true,
        isPlaying: false,
        sustainEnabled: true,
        metronomeRunning: true,
        bpm: 96,
        onRecord: {},
        onPlay: {},
        onLibrary: {},
        onPractice: {},
        onSustain: {},
        onMetronome: {},
        onTempo: {},
        onSettings: {},
        onStopAllSound: {}
    )
}
#endif
