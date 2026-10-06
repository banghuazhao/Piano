import SwiftUI

@MainActor
struct PracticeLibraryView: View {
    let session: PracticeSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    dailyProgressCard

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
            .toolbarBackground(PianoTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        }
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
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
                Text("Follow the highlighted keys. Play at your own pace and hear your progress.")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dailyProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        Button {
            session.start(exercise)
            dismiss()
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
        .accessibilityLabel("Start \(exercise.title)")
        .accessibilityValue("\(exercise.difficulty.rawValue), \(exercise.steps.count) steps")
        .accessibilityHint("Starts this exercise from the beginning")
    }
}

#Preview {
    PracticeLibraryView(session: PracticeSession())
}
