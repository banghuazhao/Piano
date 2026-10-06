//
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct PerformanceLibraryView: View {
    let studio: PerformanceStudio
    let onPlay: (PerformanceTake, PerformancePlaybackOptions) -> Void
    let onStop: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(PianoTheme.panelRaised)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .strokeBorder(PianoTheme.brass.opacity(0.35), lineWidth: 1)
                                }

                            Image(systemName: "waveform")
                                .font(.title)
                                .foregroundStyle(PianoTheme.brass)
                                .accessibilityHidden(true)
                        }
                        .frame(width: 68, height: 68)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your performances")
                                .font(.title2.bold())
                                .foregroundStyle(PianoTheme.ivory)

                            Text("Replay a moment or take it into your music workflow.")
                                .font(.subheadline)
                                .foregroundStyle(PianoTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)

                    if studio.takes.isEmpty {
                        ContentUnavailableView(
                            "No performances yet",
                            systemImage: "record.circle",
                            description: Text("Tap Record above the keyboard to save your first take.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        HStack {
                            Text("SAVED TAKES")
                                .font(.caption.bold())
                                .tracking(2)
                                .foregroundStyle(PianoTheme.secondary)

                            Spacer()

                            Text(studio.takes.count, format: .number)
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(PianoTheme.brass)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(PianoTheme.brass.opacity(0.12), in: Capsule())
                                .accessibilityLabel(studio.takes.count == 1 ? "1 saved performance" : "\(studio.takes.count) saved performances")
                        }

                        LazyVStack(spacing: 14) {
                            ForEach(studio.takes) { take in
                                PerformanceTakeCard(
                                    take: take,
                                    studio: studio,
                                    onPlay: onPlay,
                                    onStop: onStop
                                )
                            }
                        }

                        Text("Your performances are saved on this device.")
                            .font(.footnote)
                            .foregroundStyle(PianoTheme.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 740)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .background(PianoTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PianoTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PERFORMANCE LIBRARY")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(PianoTheme.secondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                        .bold()
                }
            }
        }
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .onAppear { showingError = studio.lastError != nil }
        .onChange(of: studio.lastError) { _, error in
            showingError = error != nil
        }
        .alert("Performance library", isPresented: $showingError) {
            Button("OK") { studio.lastError = nil }
        } message: {
            Text(studio.lastError ?? "Please try again.")
        }
    }
}
