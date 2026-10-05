//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

/// Live metronome adjustments. The service applies changes while the click is playing.
@MainActor
struct TempoPopoverView: View {
    let metronome: MetronomeService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "metronome")
                    .font(.title3)
                    .foregroundStyle(PianoTheme.brass)
                    .frame(width: 44, height: 44)
                    .background(PianoTheme.brass.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("METRONOME")
                        .font(.caption.bold())
                        .tracking(1.5)
                        .foregroundStyle(PianoTheme.ivory)
                    Text("Find your pulse")
                        .font(.caption)
                        .foregroundStyle(PianoTheme.secondary)
                }
            }

            Divider().overlay(PianoTheme.divider)

            HStack(spacing: 8) {
                tempoStepButton("Decrease tempo", symbol: "minus") {
                    metronome.setTempo(metronome.bpm - 1)
                }

                VStack(spacing: 0) {
                    Text("\(metronome.bpm)")
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PianoTheme.ivory)
                    Text("BEATS / MIN")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(PianoTheme.brass)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metronome.bpm) beats per minute")

                tempoStepButton("Increase tempo", symbol: "plus") {
                    metronome.setTempo(metronome.bpm + 1)
                }
            }

            Slider(value: tempoBinding, in: 40...240, step: 1)
                .tint(PianoTheme.brass)
                .frame(minHeight: 44)
                .accessibilityLabel("Tempo")
                .accessibilityValue("\(metronome.bpm) beats per minute")

            HStack {
                Text("40 SLOW")
                Spacer()
                Text("240 FAST")
            }
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(PianoTheme.secondary)
            .padding(.top, -11)

            Divider().overlay(PianoTheme.divider)

            Stepper(value: beatsBinding, in: 2...8) {
                HStack {
                    Label("Beats per bar", systemImage: "music.note")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.ivory)
                    Spacer(minLength: 8)
                    Text("\(metronome.beatsPerBar)/4")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(PianoTheme.brass)
                }
            }
            .tint(PianoTheme.brass)
            .frame(minHeight: 44)
            .accessibilityValue("\(metronome.beatsPerBar) beats per bar")

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("Click volume", systemImage: "speaker.wave.2")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.ivory)
                    Spacer()
                    Text("\(Int((metronome.volume * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(PianoTheme.brass)
                }
                Slider(value: volumeBinding, in: 0...1)
                    .tint(PianoTheme.brass)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Click volume")
                    .accessibilityValue("\(Int((metronome.volume * 100).rounded())) percent")
            }
        }
        .padding(18)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(PianoTheme.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(PianoTheme.brass.opacity(0.25), lineWidth: 1)
                }
        }
        .environment(\.colorScheme, .dark)
        .presentationCompactAdaptation(.popover)
    }

    private var tempoBinding: Binding<Double> {
        Binding(
            get: { Double(metronome.bpm) },
            set: { metronome.setTempo(Int($0.rounded())) }
        )
    }

    private var beatsBinding: Binding<Int> {
        Binding(
            get: { metronome.beatsPerBar },
            set: { metronome.setBeatsPerBar($0) }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { metronome.volume },
            set: { metronome.setVolume($0) }
        )
    }

    private func tempoStepButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(PianoTheme.brass)
            .frame(width: 44, height: 44)
            .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(PianoTheme.brass.opacity(0.18), lineWidth: 1)
            }
            .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    TempoPopoverView(metronome: MetronomeService())
}
#endif
