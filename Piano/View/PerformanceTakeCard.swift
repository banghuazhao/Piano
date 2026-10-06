//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct PerformanceTakeCard: View {
    let take: PerformanceTake
    let studio: PerformanceStudio
    let onPlay: (PerformanceTake, PerformancePlaybackOptions) -> Void
    let onStop: () -> Void

    @State private var midiURL: URL?
    @State private var didPrepareMIDI = false
    @State private var showingDeleteConfirmation = false
    @State private var showingTools = false

    private var isPlaying: Bool {
        studio.playingTakeID == take.id
    }

    private var durationText: String {
        String(format: "%d:%02d", durationSeconds / 60, durationSeconds % 60)
    }

    private var durationSeconds: Int {
        max(0, Int(take.duration.rounded()))
    }

    private var noteCountText: String {
        take.noteCount == 1 ? "1 note" : "\(take.noteCount) notes"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "music.note.list")
                    .font(.title3)
                    .foregroundStyle(PianoTheme.brass)
                    .frame(width: 42, height: 42)
                    .background(PianoTheme.brass.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(take.title)
                        .font(.headline)
                        .foregroundStyle(PianoTheme.ivory)

                    Text(take.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(PianoTheme.secondary)
                }

                Spacer(minLength: 0)

                if isPlaying {
                    Label("Playing", systemImage: "waveform")
                        .font(.caption.bold())
                        .foregroundStyle(PianoTheme.brass)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(PianoTheme.brass.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 18) {
                Label(noteCountText, systemImage: "pianokeys")
                Label(durationText, systemImage: "clock")
                    .accessibilityLabel("Duration \(durationSeconds / 60) minutes and \(durationSeconds % 60) seconds")
            }
            .font(.subheadline)
            .foregroundStyle(PianoTheme.secondary)

            Rectangle()
                .fill(PianoTheme.divider)
                .frame(height: 1)
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    playbackButton
                        .fixedSize(horizontal: true, vertical: false)
                    midiControl
                        .fixedSize(horizontal: true, vertical: false)
                    toolsButton
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    deleteButton
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 10) {
                    playbackButton
                    midiControl
                    toolsButton
                    deleteButton
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(PianoTheme.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(PianoTheme.brass.opacity(isPlaying ? 0.45 : 0.17), lineWidth: 1)
                }
        }
        .task(id: take.id) {
            midiURL = studio.midiFileURL(for: take)
            didPrepareMIDI = true
        }
        .sheet(isPresented: $showingTools) {
            RecordingToolsView(take: take, studio: studio, onPlay: onPlay, onStop: onStop)
        }
    }

    private var playbackButton: some View {
        Button(isPlaying ? "Stop" : "Play", systemImage: isPlaying ? "stop.fill" : "play.fill") {
            if isPlaying {
                onStop()
            } else {
                onPlay(take, .init())
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(PianoTheme.brass)
        .foregroundStyle(PianoTheme.background)
        .frame(minHeight: 44)
        .accessibilityHint(isPlaying ? "Stops this performance" : "Plays this performance")
    }

    private var toolsButton: some View {
        Button("Tools", systemImage: "slider.horizontal.3") {
            showingTools = true
        }
        .buttonStyle(.bordered)
        .tint(PianoTheme.ivory)
        .frame(minHeight: 44)
        .accessibilityHint("Rename, loop, trim, and export audio")
    }

    @ViewBuilder
    private var midiControl: some View {
        if let midiURL {
            ShareLink(item: midiURL) {
                Label("MIDI", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .tint(PianoTheme.ivory)
            .frame(minHeight: 44)
            .accessibilityLabel("Share MIDI for this performance")
            .accessibilityHint("Exports a Standard MIDI file")
        } else if !didPrepareMIDI {
            ProgressView("Preparing MIDI")
                .font(.subheadline)
                .tint(PianoTheme.brass)
                .frame(minHeight: 44)
        } else {
            Label("MIDI unavailable", systemImage: "square.and.arrow.up")
                .font(.subheadline)
                .foregroundStyle(PianoTheme.secondary)
                .accessibilityLabel("MIDI export unavailable")
        }
    }

    private var deleteButton: some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            showingDeleteConfirmation = true
        }
        .labelStyle(.titleAndIcon)
        .frame(minWidth: 44, minHeight: 44)
        .foregroundStyle(PianoTheme.secondary)
        .accessibilityLabel("Delete performance from \(take.createdAt.formatted(date: .abbreviated, time: .shortened))")
        .confirmationDialog(
            "Delete this performance?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Performance", role: .destructive) {
                studio.delete(take)
            }
        } message: {
            Text("This take will be removed from your library.")
        }
    }
}
