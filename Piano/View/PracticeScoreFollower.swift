import SwiftUI

/// Keep the continuously moving playhead's observation within the score view.
@MainActor
struct PracticeScoreFollower: View {
    let session: PracticeSession
    let isCompact: Bool

    var body: some View {
        if let exercise = session.exercise {
            PracticeScoreView(exercise: exercise, currentBeat: max(0, session.currentBeat),
                              hand: session.options.hand, isCompact: isCompact)
        }
    }
}
