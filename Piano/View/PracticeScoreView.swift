import SwiftUI

/// A live, horizontally scrolling engraving window. Timing stays in quarter-note beats.
@MainActor
struct PracticeScoreView: View {
    let exercise: PracticeExercise
    let currentBeat: Double
    let hand: PracticeHand
    let isCompact: Bool

    @State private var index: ScoreNotation.Index?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(exercise: PracticeExercise, currentBeat: Double,
         hand: PracticeHand = .both, isCompact: Bool = false) {
        self.exercise = exercise
        self.currentBeat = currentBeat
        self.hand = hand
        self.isCompact = isCompact
    }

    var body: some View {
        GeometryReader { geometry in
            if let index {
                let window = index.window(currentBeat: currentBeat, hand: hand,
                                          width: Double(geometry.size.width),
                                          isCompact: isCompact, reducedMotion: reduceMotion)
                Canvas(opaque: false) { context, size in
                    drawScore(context: context, size: size, window: window, index: index)
                }
                .overlay(alignment: .topLeading) { heading(for: window) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sheet music for \(exercise.title)")
                .accessibilityValue(accessibilitySummary(for: window))
                .accessibilityHint("The notation moves left as practice advances")
            } else {
                ProgressView("Preparing sheet music")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(Self.ink)
            }
        }
        .background(Self.paper, in: RoundedRectangle(cornerRadius: isCompact ? 10 : 18))
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 10 : 18)
                .strokeBorder(Self.rule.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 10 : 18))
        .task(id: exercise.renderID) {
            index = nil
            let snapshot = exercise
            let worker = Task.detached(priority: .userInitiated) { () -> ScoreNotation.Index? in
                guard !Task.isCancelled else { return nil }
                let prepared = ScoreNotation.Index(exercise: snapshot,
                                                   shouldCancel: { Task.isCancelled })
                return Task.isCancelled ? nil : prepared
            }
            let prepared = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let prepared else { return }
            index = prepared
        }
    }

    private func heading(for window: ScoreWindow) -> some View {
        HStack(spacing: isCompact ? 6 : 12) {
            Text("SCORE")
                .font(isCompact ? .system(size: 10, weight: .heavy) : .caption.bold())
                .tracking(isCompact ? 1 : 1.5)
                .foregroundStyle(Self.ink)

            if window.rhythmSimplified {
                Text(window.isDense
                     ? "Rhythm simplified to sixteenth notes · dense passage"
                     : "Rhythm simplified to sixteenth notes")
                    .foregroundStyle(Self.warning)
            } else if window.isDense {
                Text("Dense passage · notes summarized")
                    .foregroundStyle(Self.warning)
            }

            Spacer(minLength: 2)

            Text("BAR \(displayBar(in: window))")
                .foregroundStyle(Self.rule)
                .monospacedDigit()
        }
        .font(isCompact ? .system(size: 9, weight: .semibold) : .caption)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .padding(.horizontal, isCompact ? 8 : 16)
        .padding(.top, isCompact ? 4 : 12)
        .allowsHitTesting(false)
    }

    private func accessibilitySummary(for window: ScoreWindow) -> String {
        let bar = displayBar(in: window)
        var parts = ["Bar \(bar), \(hand.title)."]
        if !window.currentNoteNames.isEmpty {
            parts.append("Current notes: \(window.currentNoteNames.joined(separator: ", ")).")
        }
        if !window.upcomingNoteNames.isEmpty {
            parts.append("Coming next: \(window.upcomingNoteNames.joined(separator: ", ")).")
        }
        if window.rhythmSimplified {
            parts.append("Rhythm simplified to sixteenth notes for the display; practice follows original timing.")
        }
        if window.isDense { parts.append("Dense passage: some noteheads are summarized.") }
        return parts.joined(separator: " ")
    }

    private func displayBar(in window: ScoreWindow) -> Int {
        let beat = currentBeat.isFinite ? min(1_000_000, max(0, currentBeat)) : 0
        return max(1, Int(floor(beat / window.barLength)) + 1)
    }

    private func drawScore(context: GraphicsContext, size: CGSize,
                           window: ScoreWindow, index: ScoreNotation.Index) {
        let metrics = Metrics(size: size, staves: window.staves, isCompact: isCompact,
                              startBeat: window.startBeat, endBeat: window.endBeat)
        guard metrics.musicWidth > 1 else { return }

        for clef in window.staves {
            drawStaff(context: context, clef: clef, metrics: metrics, index: index)
        }
        drawBarlines(context: context, window: window, metrics: metrics)
        drawPlayhead(context: context, metrics: metrics)

        for rest in window.rests {
            drawRest(context: context, rest: rest, metrics: metrics)
        }
        for chord in window.chords {
            drawChord(context: context, chord: chord, metrics: metrics)
        }
        drawTies(context: context, chords: window.chords, metrics: metrics)
    }

    private func drawStaff(context: GraphicsContext, clef: ScoreClef,
                           metrics: Metrics, index: ScoreNotation.Index) {
        let top = metrics.top(for: clef)
        for line in 0..<5 {
            let y = top + CGFloat(line) * metrics.spacing
            var path = Path()
            path.move(to: CGPoint(x: metrics.staffLeft, y: y))
            path.addLine(to: CGPoint(x: metrics.size.width - metrics.rightInset, y: y))
            context.stroke(path, with: .color(Self.rule.opacity(0.76)), lineWidth: 0.8)
        }

        let clefSize = clef == .treble ? metrics.spacing * 6.1 : metrics.spacing * 4.5
        context.draw(
            Text(clef == .treble ? "𝄞" : "𝄢")
                .font(.system(size: clefSize))
                .foregroundColor(Self.ink),
            at: CGPoint(x: metrics.staffLeft + metrics.spacing * 1.6,
                        y: top + metrics.spacing * (clef == .treble ? 2.2 : 2.1)),
            anchor: .center
        )

        let signatureX = metrics.noteStart - metrics.spacing * 1.65
        let signatureFont = Font.system(size: max(9, metrics.spacing * 1.45), weight: .bold)
        context.draw(Text("\(index.beatsPerBar)").font(signatureFont).foregroundColor(Self.ink),
                     at: CGPoint(x: signatureX, y: top + metrics.spacing * 1.15), anchor: .center)
        context.draw(Text("\(index.beatUnit)").font(signatureFont).foregroundColor(Self.ink),
                     at: CGPoint(x: signatureX, y: top + metrics.spacing * 2.85), anchor: .center)
    }

    private func drawBarlines(context: GraphicsContext, window: ScoreWindow, metrics: Metrics) {
        let firstBar = Int(ceil(window.startBeat / window.barLength))
        let lastBar = Int(floor(window.endBeat / window.barLength))
        guard firstBar <= lastBar else { return }
        for bar in firstBar...lastBar {
            let beat = Double(bar) * window.barLength
            let x = metrics.x(for: beat)
            guard x >= metrics.noteStart - 1, x <= metrics.size.width - metrics.rightInset else { continue }
            for clef in window.staves {
                let top = metrics.top(for: clef)
                var path = Path()
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: top + 4 * metrics.spacing))
                context.stroke(path, with: .color(Self.rule.opacity(0.7)), lineWidth: 1)
            }
            if !isCompact && bar > 0 {
                context.draw(
                    Text("\(bar + 1)").font(.system(size: 10, weight: .medium))
                        .foregroundColor(Self.rule),
                    at: CGPoint(x: x + 4, y: metrics.top(for: window.staves[0]) - 10),
                    anchor: .leading
                )
            }
        }
    }

    private func drawPlayhead(context: GraphicsContext, metrics: Metrics) {
        let x = metrics.x(for: max(0, currentBeat))
        guard x >= metrics.noteStart, x <= metrics.size.width - metrics.rightInset else { return }
        let top = metrics.top(for: metrics.staves[0]) - metrics.spacing * 1.1
        let bottom = metrics.top(for: metrics.staves.last!) + metrics.spacing * 5.1
        context.fill(Path(roundedRect: CGRect(x: x - 3, y: top, width: 6,
                                              height: max(0, bottom - top)), cornerRadius: 3),
                     with: .color(Self.gold.opacity(0.16)))
        var line = Path()
        line.move(to: CGPoint(x: x, y: top))
        line.addLine(to: CGPoint(x: x, y: bottom))
        context.stroke(line, with: .color(Self.gold.opacity(0.85)), lineWidth: 1.1)
    }

    private func drawChord(context: GraphicsContext, chord: ScoreChord, metrics: Metrics) {
        let x = metrics.x(for: chord.startBeat)
        guard x >= metrics.noteStart - metrics.headWidth,
              x <= metrics.size.width - metrics.rightInset + metrics.headWidth else { return }
        let clef = chord.clef
        let top = metrics.top(for: clef)
        let active = chord.startBeat <= currentBeat + 0.001
            && chord.startBeat + chord.duration.beats > currentBeat + 0.001
        let color = active ? Self.gold : Self.ink
        var points: [(CGFloat, CGFloat)] = []

        for (position, head) in chord.heads.enumerated() {
            let (step, octaveShift) = displayedStep(for: head.pitch, in: clef)
            let y = top + (4 - CGFloat(step) / 2) * metrics.spacing
            let previousStep = position > 0
                ? displayedStep(for: chord.heads[position - 1].pitch, in: clef).0 : -100
            let stagger = abs(step - previousStep) == 1 ? metrics.headWidth * 0.55 : 0
            let headX = x + stagger
            points.append((headX, y))
            drawLedgerLines(context: context, x: headX, step: step, top: top, metrics: metrics)

            let noteRect = CGRect(x: headX - metrics.headWidth / 2,
                                  y: y - metrics.headHeight / 2,
                                  width: metrics.headWidth, height: metrics.headHeight)
            let notePath = Path(ellipseIn: noteRect)
            if active {
                context.fill(Path(ellipseIn: noteRect.insetBy(dx: -3, dy: -3)),
                             with: .color(Self.gold.opacity(0.17)))
            }
            if chord.duration.isFilled {
                context.fill(notePath, with: .color(color))
            } else {
                context.fill(notePath, with: .color(Self.paper))
                context.stroke(notePath, with: .color(color), lineWidth: max(1.1, metrics.spacing * 0.22))
            }

            if let accidental = head.displayedAccidental {
                context.draw(
                    Text(accidental.symbol)
                        .font(.system(size: max(8, metrics.spacing * 1.7), weight: .medium))
                        .foregroundColor(color),
                    at: CGPoint(x: headX - metrics.headWidth * 1.35, y: y), anchor: .center
                )
            }
            if chord.duration.dotted {
                let dotY = step.isMultiple(of: 2) ? y - metrics.spacing / 2 : y
                context.fill(Path(ellipseIn: CGRect(x: headX + metrics.headWidth * 0.85,
                                                    y: dotY - 1.2, width: 2.4, height: 2.4)),
                             with: .color(color))
            }
            if octaveShift != 0 {
                let octaveMark = abs(octaveShift) == 1 ? "8v" : "15m"
                context.draw(
                    Text(octaveMark + (octaveShift > 0 ? "a" : "b"))
                        .font(.system(size: max(6, metrics.spacing * 0.8), weight: .semibold))
                        .foregroundColor(Self.rule),
                    at: CGPoint(x: headX + metrics.headWidth * 0.2,
                                y: y + (octaveShift > 0 ? -metrics.spacing * 1.4 : metrics.spacing * 1.4)),
                    anchor: .center
                )
            }
        }

        guard chord.duration.hasStem, !points.isEmpty else { return }
        let minimumY = points.map(\.1).min()!
        let maximumY = points.map(\.1).max()!
        let meanStep = chord.heads.map { displayedStep(for: $0.pitch, in: clef).0 }
            .reduce(0, +) / chord.heads.count
        let stemUp = meanStep < 4
        let stemX = x + (stemUp ? metrics.headWidth / 2 : -metrics.headWidth / 2)
        let stemStart = stemUp ? maximumY : minimumY
        let stemEnd = stemUp ? minimumY - 3.2 * metrics.spacing : maximumY + 3.2 * metrics.spacing
        var stem = Path()
        stem.move(to: CGPoint(x: stemX, y: stemStart))
        stem.addLine(to: CGPoint(x: stemX, y: stemEnd))
        context.stroke(stem, with: .color(color), lineWidth: max(1, metrics.spacing * 0.19))

        for flag in 0..<chord.duration.flagCount {
            let flagY = stemEnd + CGFloat(flag) * metrics.spacing * (stemUp ? 0.72 : -0.72)
            var curve = Path()
            curve.move(to: CGPoint(x: stemX, y: flagY))
            curve.addQuadCurve(to: CGPoint(x: stemX + (stemUp ? 1 : -1) * metrics.headWidth * 0.95,
                                           y: flagY + (stemUp ? 1 : -1) * metrics.spacing * 1.1),
                               control: CGPoint(x: stemX + (stemUp ? 1 : -1) * metrics.headWidth * 0.95,
                                                y: flagY + (stemUp ? 1 : -1) * metrics.spacing * 0.25))
            context.stroke(curve, with: .color(color),
                           style: StrokeStyle(lineWidth: max(1.5, metrics.spacing * 0.25),
                                              lineCap: .round))
        }
    }

    private func drawLedgerLines(context: GraphicsContext, x: CGFloat, step: Int,
                                 top: CGFloat, metrics: Metrics) {
        let ledgerSteps: [Int]
        if step <= -2 {
            ledgerSteps = stride(from: -2, through: step.isMultiple(of: 2) ? step : step + 1,
                                 by: -2).map { $0 }
        } else if step >= 10 {
            ledgerSteps = stride(from: 10, through: step.isMultiple(of: 2) ? step : step - 1,
                                 by: 2).map { $0 }
        } else {
            return
        }
        for ledgerStep in ledgerSteps {
            let y = top + (4 - CGFloat(ledgerStep) / 2) * metrics.spacing
            var line = Path()
            line.move(to: CGPoint(x: x - metrics.headWidth * 0.78, y: y))
            line.addLine(to: CGPoint(x: x + metrics.headWidth * 0.78, y: y))
            context.stroke(line, with: .color(Self.rule), lineWidth: 0.9)
        }
    }

    private func drawTies(context: GraphicsContext, chords: [ScoreChord], metrics: Metrics) {
        for chord in chords where chord.tiesToNext {
            let x1 = metrics.x(for: chord.startBeat)
            for head in chord.heads {
                let next = chords.first {
                    $0.hand == chord.hand && $0.startBeat > chord.startBeat
                        && $0.tiesFromPrevious && $0.heads.contains { $0.pitch.midi == head.pitch.midi }
                }
                let x2 = next.map { metrics.x(for: $0.startBeat) }
                    ?? min(metrics.size.width - metrics.rightInset, x1 + 3 * metrics.spacing)
                guard x2 - x1 > metrics.headWidth else { continue }
                let (step, _) = displayedStep(for: head.pitch, in: chord.clef)
                let y = metrics.top(for: chord.clef) + (4 - CGFloat(step) / 2) * metrics.spacing
                let under = y + metrics.spacing * 0.85
                var tie = Path()
                tie.move(to: CGPoint(x: x1 + metrics.headWidth * 0.45, y: under))
                tie.addQuadCurve(to: CGPoint(x: x2 - metrics.headWidth * 0.45, y: under),
                                 control: CGPoint(x: (x1 + x2) / 2, y: under + metrics.spacing * 0.9))
                context.stroke(tie, with: .color(Self.ink.opacity(0.8)), lineWidth: 1)
            }
        }
    }

    private func drawRest(context: GraphicsContext, rest: ScoreRest, metrics: Metrics) {
        let x = metrics.x(for: rest.startBeat)
        guard x >= metrics.noteStart, x <= metrics.size.width - metrics.rightInset else { return }
        let y = metrics.top(for: rest.clef) + 2 * metrics.spacing
        let s = metrics.spacing
        if rest.duration.base == .whole || rest.duration.base == .half {
            let restY = y + (rest.duration.base == .whole ? -s * 0.9 : -s * 0.25)
            context.fill(Path(CGRect(x: x - s * 0.65, y: restY, width: s * 1.3,
                                     height: max(2, s * 0.43))), with: .color(Self.ink))
        } else if rest.duration.base == .quarter {
            var zigzag = Path()
            zigzag.move(to: CGPoint(x: x - s * 0.2, y: y - s * 1.2))
            zigzag.addLine(to: CGPoint(x: x + s * 0.35, y: y - s * 0.5))
            zigzag.addLine(to: CGPoint(x: x - s * 0.2, y: y + s * 0.2))
            zigzag.addLine(to: CGPoint(x: x + s * 0.32, y: y + s * 0.72))
            zigzag.addQuadCurve(to: CGPoint(x: x - s * 0.2, y: y + s * 1.2),
                                control: CGPoint(x: x + s * 0.12, y: y + s * 1.45))
            context.stroke(zigzag, with: .color(Self.ink),
                           style: StrokeStyle(lineWidth: max(1.4, s * 0.31), lineCap: .round))
        } else {
            var stem = Path()
            stem.move(to: CGPoint(x: x + s * 0.2, y: y - s * 1.2))
            stem.addLine(to: CGPoint(x: x - s * 0.25, y: y + s * 1.1))
            context.stroke(stem, with: .color(Self.ink), lineWidth: max(1.1, s * 0.2))
            for flag in 0..<rest.duration.flagCount {
                let flagY = y - s * (1.0 - CGFloat(flag) * 0.55)
                context.fill(Path(ellipseIn: CGRect(x: x - s * 0.15, y: flagY - s * 0.25,
                                                    width: s * 0.55, height: s * 0.48)),
                             with: .color(Self.ink))
            }
        }
        if rest.duration.dotted {
            context.fill(Path(ellipseIn: CGRect(x: x + s * 0.9, y: y - 1.2,
                                                width: 2.4, height: 2.4)), with: .color(Self.ink))
        }
    }

    private func displayedStep(for pitch: ScorePitch, in clef: ScoreClef) -> (Int, Int) {
        var step = pitch.staffStep(in: clef)
        var octaveShift = 0
        while step > 12 { step -= 7; octaveShift += 1 }
        while step < -4 { step += 7; octaveShift -= 1 }
        return (step, octaveShift)
    }

    private struct Metrics {
        let size: CGSize
        let staves: [ScoreClef]
        let spacing: CGFloat
        let tops: [CGFloat]
        let staffLeft: CGFloat
        let noteStart: CGFloat
        let rightInset: CGFloat
        let startBeat: Double
        let endBeat: Double

        var musicWidth: CGFloat { max(0, size.width - noteStart - rightInset) }
        var headWidth: CGFloat { max(6.5, spacing * 1.34) }
        var headHeight: CGFloat { max(4.4, spacing * 0.88) }

        init(size: CGSize, staves: [ScoreClef], isCompact: Bool,
             startBeat: Double, endBeat: Double) {
            self.size = size
            self.staves = staves
            self.startBeat = startBeat
            self.endBeat = endBeat
            let header: CGFloat = isCompact ? 16 : 32
            let available = max(45, size.height - header)
            if staves.count == 2 {
                spacing = min(isCompact ? 8 : 13, max(4.6, (available - 28) / 10))
                let gap = spacing * 3
                let content = spacing * 8 + gap
                let first = header + max(2, (available - content) / 2)
                tops = [first, first + spacing * 4 + gap]
            } else {
                spacing = min(isCompact ? 10 : 14, max(6, (available - 24) / 7))
                tops = [header + max(2, (available - spacing * 4) / 2)]
            }
            staffLeft = isCompact ? 8 : 13
            noteStart = isCompact ? max(54, spacing * 7.9) : max(76, spacing * 6.8)
            rightInset = isCompact ? 8 : 15
        }

        func top(for clef: ScoreClef) -> CGFloat {
            guard staves.count > 1 else { return tops[0] }
            return clef == .treble ? tops[0] : tops[1]
        }

        func x(for beat: Double) -> CGFloat {
            noteStart + CGFloat((beat - startBeat) / max(0.125, endBeat - startBeat)) * musicWidth
        }
    }

    private static let paper = Color(red: 0.975, green: 0.966, blue: 0.936)
    private static let ink = Color(red: 0.13, green: 0.13, blue: 0.14)
    private static let rule = Color(red: 0.30, green: 0.29, blue: 0.28)
    private static let gold = Color(red: 0.64, green: 0.39, blue: 0.12)
    private static let warning = Color(red: 0.52, green: 0.31, blue: 0.12)
}
