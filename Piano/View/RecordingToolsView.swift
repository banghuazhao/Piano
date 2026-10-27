import SwiftUI

@MainActor
struct RecordingToolsView: View {
    let take: PerformanceTake
    let studio: PerformanceStudio
    let onPlay: (PerformanceTake, PerformancePlaybackOptions) -> Void
    let onStop: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var titleText: String
    @State private var playbackRate = 1.0
    @State private var loopEnabled = false
    @State private var useSection = false
    @State private var sectionStart = 0.0
    @State private var sectionEnd = 1.0
    @State private var audioFormat: RecordingAudioFormat = .m4a
    @State private var soundProfile: PianoSoundProfile = .concert
    @State private var audioURL: URL?
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var premium = PremiumStore.shared
    @State private var showPremium = false
    @State private var premiumFeature: PremiumFeature?
    @State private var requestedWAV = false
    @State private var requestedProfile: PianoSoundProfile?
    @State private var toolError: String?
    @State private var savedClipTitle: String?

    init(
        take: PerformanceTake,
        studio: PerformanceStudio,
        onPlay: @escaping (PerformanceTake, PerformancePlaybackOptions) -> Void,
        onStop: @escaping () -> Void
    ) {
        self.take = take
        self.studio = studio
        self.onPlay = onPlay
        self.onStop = onStop
        _titleText = State(initialValue: take.title)
    }

    private var currentTake: PerformanceTake {
        studio.takes.first(where: { $0.id == take.id }) ?? take
    }

    private var minimumFraction: Double {
        take.duration > 0 ? min(1, max(0.0005, 0.05 / take.duration)) : 1
    }

    private var selectedRange: ClosedRange<TimeInterval> {
        (sectionStart * take.duration)...(sectionEnd * take.duration)
    }

    private var playbackOptions: PerformancePlaybackOptions {
        PerformancePlaybackOptions(
            rate: playbackRate,
            loop: loopEnabled,
            region: useSection ? selectedRange : nil
        )
    }

    /// A loop is rendered once so shared files have a finite duration.
    private var exportOptions: PerformancePlaybackOptions {
        PerformancePlaybackOptions(
            rate: playbackRate,
            loop: false,
            region: useSection ? selectedRange : nil
        )
    }

    private var hasEditedSection: Bool {
        sectionStart > 0.0005 || sectionEnd < 0.9995
    }

    private var audioFormatSelection: Binding<RecordingAudioFormat> {
        Binding(
            get: { audioFormat },
            set: { format in
                if format == .wav && !premium.isPremium {
                    requestedWAV = true
                    presentPremium(.losslessExport)
                } else {
                    audioFormat = format
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    renamePanel
                    playbackPanel
                    sectionPanel
                    exportPanel
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .accessibilityIdentifier("recording.tools.scroll")
            .background(PianoTheme.background.ignoresSafeArea())
            .navigationTitle("Recording studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .tint(PianoTheme.brass)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showPremium, onDismiss: {
            premiumFeature = nil
            if !premium.isPremium {
                requestedWAV = false
                requestedProfile = nil
            }
        }) {
            PremiumView(feature: premiumFeature)
        }
        .alert(
            "Recording tools",
            isPresented: Binding(
                get: { toolError != nil },
                set: { if !$0 { toolError = nil } }
            )
        ) {
            Button("OK") { toolError = nil }
        } message: {
            Text(toolError ?? "Please try again.")
        }
        .onChange(of: audioFormat) { _, _ in invalidateExport() }
        .onChange(of: soundProfile) { _, _ in invalidateExport() }
        .onChange(of: playbackRate) { _, _ in invalidateExport() }
        .onChange(of: useSection) { _, _ in invalidateExport() }
        .onChange(of: sectionStart) { _, _ in invalidateExport() }
        .onChange(of: sectionEnd) { _, _ in invalidateExport() }
        .onChange(of: premium.isPremium) { _, isPremium in
            if isPremium {
                if requestedWAV { audioFormat = .wav }
                if let requestedProfile { soundProfile = requestedProfile }
            } else {
                onStop()
                invalidateExport()
                playbackRate = 1
                loopEnabled = false
                useSection = false
                sectionStart = 0
                sectionEnd = 1
                soundProfile = .concert
                audioFormat = .m4a
            }
            requestedWAV = false
            requestedProfile = nil
        }
        .onDisappear { invalidateExport() }
        .task {
            guard !PianoRuntimeEnvironment.isUITesting else { return }
            await premium.prepare()
        }
    }

    private var intro: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path")
                .font(.title2)
                .foregroundStyle(PianoTheme.brass)
                .frame(width: 54, height: 54)
                .background(PianoTheme.brass.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text(currentTake.title)
                    .font(.headline)
                    .foregroundStyle(PianoTheme.ivory)
                Text("\(take.noteCount == 1 ? "1 note" : "\(take.noteCount) notes") · \(timeLabel(take.duration))")
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var renamePanel: some View {
        panel("NAME", symbol: "pencil") {
            HStack(spacing: 10) {
                TextField("Performance title", text: $titleText)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Performance title")
                Button("Save") {
                    if !studio.rename(currentTake, to: titleText) {
                        showStudioErrorIfPresent()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
            }
        }
    }

    private var playbackPanel: some View {
        panel("PLAYBACK", symbol: "play.circle") {
            VStack(alignment: .leading, spacing: 13) {
                if premium.isPremium {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text("\(playbackRate, specifier: "%.2f")×")
                            .monospacedDigit()
                            .foregroundStyle(PianoTheme.brass)
                    }
                    .font(.subheadline)
                    Slider(value: $playbackRate, in: 0.5...2, step: 0.05)
                        .accessibilityLabel("Playback speed")
                        .accessibilityValue("\(playbackRate, specifier: "%.2f") times")

                    Toggle("Loop playback", isOn: $loopEnabled)
                        .font(.subheadline)
                    Toggle("Play selected section", isOn: $useSection)
                        .font(.subheadline)
                        .disabled(take.duration <= 0.05)
                }

                Button {
                    if studio.playingTakeID == take.id {
                        onStop()
                    } else {
                        onPlay(currentTake, premium.isPremium ? playbackOptions : .init())
                        showStudioErrorIfPresent()
                    }
                } label: {
                    Label(
                        studio.playingTakeID == take.id ? "Stop playback" : "Play performance",
                        systemImage: studio.playingTakeID == take.id ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)

                if !premium.isPremium {
                    premiumOffer(
                        "Studio playback",
                        detail: "Set the speed, repeat a passage, and play just the section you choose.",
                        buttonTitle: "Unlock studio playback",
                        feature: .recordingStudio,
                        identifier: "recording.premium.studio"
                    )
                }
            }
        }
    }

    private var sectionPanel: some View {
        panel("SECTION", symbol: "waveform.path.ecg.rectangle") {
            if premium.isPremium {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Start")
                        Spacer()
                        Text(timeLabel(sectionStart * take.duration))
                            .foregroundStyle(PianoTheme.brass)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $sectionStart,
                        in: 0...max(0, sectionEnd - minimumFraction)
                    )
                    .accessibilityLabel("Section start")

                    HStack {
                        Text("End")
                        Spacer()
                        Text(timeLabel(sectionEnd * take.duration))
                            .foregroundStyle(PianoTheme.brass)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $sectionEnd,
                        in: min(1, sectionStart + minimumFraction)...1
                    )
                    .accessibilityLabel("Section end")

                    Text("Save a separate clip. Your original take stays intact.")
                        .font(.footnote)
                        .foregroundStyle(PianoTheme.secondary)
                    Button("Save section as new take", systemImage: "square.on.square") {
                        guard premium.isPremium else {
                            presentPremium(.recordingStudio)
                            return
                        }
                        if let clip = studio.saveExcerpt(
                            of: currentTake,
                            from: selectedRange.lowerBound,
                            to: selectedRange.upperBound
                        ) {
                            savedClipTitle = clip.title
                        } else {
                            showStudioErrorIfPresent()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasEditedSection || take.duration <= 0.05)
                    .frame(minHeight: 44)
                    if let savedClipTitle {
                        Label("Saved \(savedClipTitle) to your library", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(PianoTheme.brass)
                    }
                }
                .font(.subheadline)
            } else {
                premiumOffer(
                    "Save a section",
                    detail: "Trim a copy of your take while the original stays in your library.",
                    buttonTitle: "Unlock section tools",
                    feature: .recordingStudio,
                    identifier: "recording.premium.section"
                )
            }
        }
    }

    private var exportPanel: some View {
        panel("AUDIO EXPORT", symbol: "square.and.arrow.up") {
            VStack(alignment: .leading, spacing: 12) {
                Text(premium.isPremium
                     ? (useSection
                        ? "Render the selected section at your chosen speed. Looping is saved as one pass."
                        : "Render the full take at your chosen speed. No microphone needed.")
                     : "Render the full take with the Concert piano sound. No microphone needed.")
                    .font(.footnote)
                    .foregroundStyle(PianoTheme.secondary)

                Picker("Format", selection: audioFormatSelection) {
                    ForEach(RecordingAudioFormat.allCases) { format in
                        Text(format == .wav && !premium.isPremium ? "WAV · Premium" : format.title)
                            .tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if !premium.isPremium {
                    Button {
                        requestedWAV = true
                        presentPremium(.losslessExport)
                    } label: {
                        Label("Unlock lossless WAV", systemImage: "lock.fill")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PianoTheme.brass)
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("recording.premium.export")
                }

                Menu {
                    ForEach(PianoSoundProfile.allCases) { profile in
                        Button {
                            if profile.isPremium && !premium.isPremium {
                                requestedProfile = profile
                                presentPremium(.pianoSounds)
                            } else {
                                soundProfile = profile
                            }
                        } label: {
                            Label(
                                profile.isPremium && !premium.isPremium ? "\(profile.title) · Premium" : profile.title,
                                systemImage: profile.isPremium && !premium.isPremium ? "lock.fill" : "music.note"
                            )
                        }
                    }
                } label: {
                    HStack {
                        Label("Sound", systemImage: "pianokeys")
                        Spacer()
                        Text(soundProfile.title)
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.subheadline)
                    .foregroundStyle(PianoTheme.ivory)
                    .padding(12)
                    .background(PianoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Export sound: \(soundProfile.title)")

                if isExporting {
                    HStack(spacing: 12) {
                        ProgressView("Rendering audio…")
                        Spacer()
                        Button("Cancel") { invalidateExport() }
                    }
                    .frame(minHeight: 44)
                } else {
                    Button("Prepare \(audioFormat.rawValue.uppercased())", systemImage: "waveform") {
                        prepareAudio()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(audioFormat == .m4a ? "recording.export.prepareM4A" : "recording.export.prepareWAV")
                }

                if let audioURL {
                    ShareLink(item: audioURL) {
                        Label("Share \(audioFormat.rawValue.uppercased())", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(audioFormat == .m4a ? "recording.export.shareM4A" : "recording.export.shareWAV")
                }
            }
        }
    }

    private func panel<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .tracking(1.3)
                .foregroundStyle(PianoTheme.brass)
            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PianoTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(PianoTheme.brass.opacity(0.18), lineWidth: 1)
        }
    }

    private func premiumOffer(
        _ title: String,
        detail: String,
        buttonTitle: String,
        feature: PremiumFeature,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PianoTheme.ivory)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(PianoTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, systemImage: "sparkles") {
                presentPremium(feature)
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentPremium(_ feature: PremiumFeature) {
        premiumFeature = feature
        showPremium = true
    }

    private func prepareAudio() {
        if !premium.isPremium {
            if audioFormat == .wav {
                requestedWAV = true
                presentPremium(.losslessExport)
                return
            }
            if soundProfile.isPremium {
                requestedProfile = soundProfile
                presentPremium(.pianoSounds)
                return
            }
            if playbackRate != 1 || useSection {
                presentPremium(.recordingStudio)
                return
            }
        }
        invalidateExport()
        isExporting = true
        let format = audioFormat
        let profile = soundProfile
        let options = exportOptions
        let selectedTake = currentTake
        exportTask = Task {
            let url = await studio.audioFileURL(
                for: selectedTake,
                format: format,
                profile: profile,
                options: options
            )
            guard !Task.isCancelled else {
                if let url { try? FileManager.default.removeItem(at: url) }
                return
            }
            audioURL = url
            if url == nil { showStudioErrorIfPresent() }
            isExporting = false
            exportTask = nil
        }
    }

    private func invalidateExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
    }

    private func showStudioErrorIfPresent() {
        guard let error = studio.lastError else { return }
        toolError = error
        studio.lastError = nil
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = time - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, seconds)
    }
}
