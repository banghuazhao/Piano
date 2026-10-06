import SwiftUI

@MainActor
struct ImportedSongDetailView: View {
    let library: ImportedSongLibrary
    let songID: UUID
    let onStart: (PracticeExercise, PracticeOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var showRename = false
    @State private var newTitle = ""
    @State private var showDelete = false
    @State private var preparedExercise: PracticeExercise?
    @State private var preparedInput: ImportedPracticeSong?

    private var song: ImportedPracticeSong? { library.songs.first { $0.id == songID } }

    var body: some View {
        ScrollView {
            if let song {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(song.title).font(.largeTitle.bold()).foregroundStyle(PianoTheme.ivory)
                        Text(song.summary).foregroundStyle(PianoTheme.secondary)
                        Text("Choose the parts to practice. Track assignments are suggestions; adjust them to match your arrangement.")
                            .font(.subheadline)
                            .foregroundStyle(PianoTheme.secondary)
                    }

                    ForEach(song.tracks) { track in
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: Binding(
                                get: { track.isIncluded },
                                set: { value in perform { try library.setIncluded(value, forTrack: track.id, in: song.id) } }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title).font(.headline)
                                    Text("\(track.notes.count) notes").font(.caption).foregroundStyle(PianoTheme.secondary)
                                }
                            }
                            .tint(PianoTheme.brass)
                            Picker("Hand for \(track.title)", selection: Binding(
                                get: { track.hand },
                                set: { value in perform { try library.setHand(value, forTrack: track.id, in: song.id) } }
                            )) {
                                Text("Left").tag(PracticeHand.left)
                                Text("Right").tag(PracticeHand.right)
                                Text("Split at C4").tag(PracticeHand.both)
                            }
                            .pickerStyle(.segmented)
                            .disabled(!track.isIncluded)
                        }
                        .foregroundStyle(PianoTheme.ivory)
                        .padding(18)
                        .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                    }

                    if preparedInput != song {
                        ProgressView("Preparing practice parts…")
                            .tint(PianoTheme.brass)
                            .foregroundStyle(PianoTheme.secondary)
                    } else if let exercise = preparedExercise {
                        PracticeScoreView(exercise: exercise, currentBeat: 0)
                            .frame(height: 220)
                        NavigationLink {
                            PracticeSetupView(exercise: exercise, onStart: onStart)
                        } label: {
                            Label("Choose practice mode", systemImage: "pianokeys")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PianoTheme.brass)
                        .foregroundStyle(PianoTheme.background)
                    } else {
                        Text("Include at least one part to start practice.")
                            .foregroundStyle(PianoTheme.secondary)
                    }

                    Text("Saved on this device. MIDI provides notes and timing; the score uses a simplified spelling and the selected practice tempo.")
                        .font(.caption)
                        .foregroundStyle(PianoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(PianoTheme.background.ignoresSafeArea())
        .navigationTitle("MIDI song")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: song) {
            guard let snapshot = song else {
                preparedExercise = nil
                preparedInput = nil
                return
            }
            let worker = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return nil as PracticeExercise? }
                return snapshot.practiceExercise(hand: .both)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            preparedExercise = result
            preparedInput = snapshot
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        newTitle = song?.title ?? ""
                        showRename = true
                    }
                    Button("Delete song", systemImage: "trash", role: .destructive) { showDelete = true }
                } label: { Label("Song actions", systemImage: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
            }
        }
        .alert("Rename song", isPresented: $showRename) {
            TextField("Title", text: $newTitle)
            Button("Save") { perform { try library.rename(songID, to: newTitle) } }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this song from PianoFlow?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete song", role: .destructive) {
                perform {
                    try library.delete(songID)
                    dismiss()
                }
            }
        }
        .alert("Couldn’t save changes", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
