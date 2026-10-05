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
    let onRecord: () -> Void
    let onPlay: () -> Void
    let onLibrary: () -> Void
    let onSustain: () -> Void
    let onMetronome: () -> Void
    let onTempo: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                identity
                chordDisplay
                Spacer(minLength: 8)
                controls(compact: false)
            }
            .fixedSize(horizontal: true, vertical: false)

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
            .fixedSize(horizontal: true, vertical: false)

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
                    action: onPlay
                )
                .frame(width: 44)

                moreControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
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
            Button("Saved performances", systemImage: "square.stack", action: onLibrary)
            Button(sustainEnabled ? "Turn sustain off" : "Turn sustain on", systemImage: "waveform.path", action: onSustain)
            Button(metronomeRunning ? "Stop metronome" : "Start metronome", systemImage: "metronome", action: onMetronome)
            Button("Tempo settings (\(bpm) BPM)", systemImage: "slider.horizontal.3", action: onTempo)
            Divider()
            Button("Settings", systemImage: "gearshape", action: onSettings)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PianoTheme.ivory)
                .frame(width: 44, height: 44)
                .background(controlBackground(isActive: sustainEnabled || metronomeRunning, activeColor: PianoTheme.brass))
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
                action: onRecord
            )
            control(
                title: isPlaying ? "Stop playback" : "Play latest recording",
                caption: "PLAY",
                symbol: isPlaying ? "stop.fill" : "play.fill",
                isActive: isPlaying,
                isEnabled: hasTake || isPlaying,
                compact: compact,
                action: onPlay
            )
            control(
                title: "Saved recordings",
                caption: "TAKES",
                symbol: "square.stack",
                compact: compact,
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
                action: onSustain
            )
            control(
                title: metronomeRunning ? "Stop metronome" : "Start metronome",
                caption: "CLICK",
                symbol: "metronome",
                isActive: metronomeRunning,
                compact: compact,
                action: onMetronome
            )
            tempoButton(compact: compact)
            control(
                title: "Settings",
                caption: "SETTINGS",
                symbol: "gearshape",
                compact: compact,
                action: onSettings
            )
        }
        .frame(maxWidth: compact ? .infinity : nil)
    }

    private func control(
        title: String,
        caption: String,
        symbol: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        activeColor: Color = PianoTheme.brass,
        compact: Bool,
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
            .background(controlBackground(isActive: isActive, activeColor: activeColor))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityLabel(title)
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
            .background(controlBackground(isActive: false, activeColor: PianoTheme.brass))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tempo settings, \(bpm) beats per minute")
    }

    private func controlBackground(isActive: Bool, activeColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isActive ? activeColor.opacity(0.16) : PianoTheme.panelRaised)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isActive ? activeColor.opacity(0.65) : PianoTheme.brass.opacity(0.14),
                        lineWidth: 1
                    )
            }
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
        onSustain: {},
        onMetronome: {},
        onTempo: {},
        onSettings: {}
    )
}
#endif
