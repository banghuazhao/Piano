import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct PracticeLibraryView: View {
    let session: PracticeSession
    let library: ImportedSongLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var importTask: Task<Void, Never>?
    @State private var importID: UUID?
    @State private var importError: String?
    @State private var importedSong: ImportedPracticeSong?
    @State private var showImportedSong = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    header
                    dailyProgressCard
                    importedSongs

                    ForEach(PracticeCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: category.symbol)
                                    .foregroundStyle(PianoTheme.brass)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.rawValue)
                                        .font(.title3.bold())
                                        .foregroundStyle(PianoTheme.ivory)
                                    Text(category.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(PianoTheme.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)

                            ForEach(PracticeCatalog.exercises(in: category)) { exercise in
                                exerciseCard(exercise)
                            }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(PianoTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .pianoNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("GUIDED PRACTICE")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(PianoTheme.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                        .bold()
                }
            }
            .navigationDestination(isPresented: $showImportedSong) {
                if let song = importedSong {
                    ImportedSongDetailView(library: library, songID: song.id, onStart: start)
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "mid") ?? .audio,
                                                UTType(filenameExtension: "midi") ?? .audio]) { result in
                switch result {
                case .success(let url):
                    importTask?.cancel()
                    let id = UUID()
                    importID = id
                    isImporting = true
                    importTask = Task {
                        defer {
                            if importID == id {
                                isImporting = false
                                importID = nil
                                importTask = nil
                            }
                        }
                        do {
                            let song = try await library.importFile(url: url)
                            guard !Task.isCancelled, importID == id else { return }
                            importedSong = song
                            showImportedSong = true
                        } catch is CancellationError {
                            // Leaving the library cancels an in-progress import.
                        } catch {
                            if importID == id { importError = error.localizedDescription }
                        }
                    }
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .alert("Couldn’t import MIDI", isPresented: Binding(
                get: { importError != nil }, set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: { Text(importError ?? "") }
        }
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .onDisappear {
            importTask?.cancel()
            importTask = nil
            importID = nil
            isImporting = false
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(PianoTheme.brass)
                .frame(width: 56, height: 56)
                .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 15))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("A little practice, every day")
                    .font(.title2.bold())
                    .foregroundStyle(PianoTheme.ivory)
                Text("Read the music, follow the keys, and build your rhythm. Start with an exercise or bring your own MIDI song.")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dailyProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let warning = library.loadWarning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Label("TODAY'S PRACTICE", systemImage: "sparkles")
                    .font(.caption.bold())
                    .tracking(1.2)
                    .foregroundStyle(PianoTheme.brass)
                Spacer(minLength: 8)
                Text("\(session.todayCompletions) / \(PracticeSession.dailyGoal)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(PianoTheme.ivory)
            }

            ProgressView(value: session.dailyGoalFraction)
                .tint(PianoTheme.brass)
                .accessibilityLabel("Daily practice goal")
                .accessibilityValue("\(session.todayCompletions) of \(PracticeSession.dailyGoal) exercises completed today")

            HStack(spacing: 6) {
                Image(systemName: session.streakDays > 0 ? "flame.fill" : "flame")
                    .accessibilityHidden(true)
                Text(session.streakDays > 0
                     ? "\(session.streakDays)-day practice streak"
                     : "Finish an exercise to start your streak")
            }
            .font(.subheadline)
            .foregroundStyle(PianoTheme.secondary)
        }
        .padding(18)
        .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(PianoTheme.brass.opacity(0.23), lineWidth: 1)
        }
    }

    private func exerciseCard(_ exercise: PracticeExercise) -> some View {
        NavigationLink {
            PracticeSetupView(exercise: exercise, onStart: start)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.title)
                            .font(.headline)
                            .foregroundStyle(PianoTheme.ivory)
                        Text(exercise.detail)
                            .font(.subheadline)
                            .foregroundStyle(PianoTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(PianoTheme.brass)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 12) {
                    Text(exercise.difficulty.rawValue)
                        .foregroundStyle(PianoTheme.brass)
                    Label("\(exercise.steps.count) steps", systemImage: "list.number")
                        .foregroundStyle(PianoTheme.secondary)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(16)
            .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(PianoTheme.brass.opacity(0.13), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Practice \(exercise.title)")
        .accessibilityValue("\(exercise.difficulty.rawValue), \(exercise.steps.count) steps")
        .accessibilityHint("Choose hands, tempo, and practice mode")
    }

    private var importedSongs: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your MIDI songs")
                    .font(.title3.bold())
                    .foregroundStyle(PianoTheme.ivory)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showImporter = true
                } label: {
                    if isImporting { ProgressView().tint(PianoTheme.brass) }
                    else { Label("Import", systemImage: "square.and.arrow.down") }
                }
                .disabled(isImporting)
                .frame(minHeight: 44)
                .accessibilityLabel(isImporting ? "Importing MIDI" : "Import MIDI song")
            }
            if library.songs.isEmpty {
                Text("Import a .mid or .midi file from Files. Assign its parts to each hand and turn it into guided practice.")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach(library.songs) { song in
                NavigationLink {
                    ImportedSongDetailView(library: library, songID: song.id, onStart: start)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(PianoTheme.brass)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).font(.headline).foregroundStyle(PianoTheme.ivory)
                            Text(song.summary).font(.caption).foregroundStyle(PianoTheme.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").foregroundStyle(PianoTheme.brass)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func start(_ exercise: PracticeExercise, options: PracticeOptions) {
        session.start(exercise, options: options)
        dismiss()
    }
}

#Preview {
    PracticeLibraryView(session: PracticeSession(), library: .shared)
}
