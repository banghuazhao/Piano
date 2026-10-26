import AVFoundation

enum RecordingAudioFormat: String, CaseIterable, Identifiable, Sendable {
    case m4a
    case wav

    var id: String { rawValue }
    var title: String { self == .m4a ? "M4A · compact" : "WAV · lossless" }
    var fileExtension: String { rawValue }
}

/// Renders the bundled piano SoundFont without recording the microphone or speaker output.
enum AudioExporter {
    enum ExportError: LocalizedError {
        case invalidTake
        case missingSoundFont
        case unavailableFormat
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .invalidTake: "This performance cannot be exported."
            case .missingSoundFont: "The piano instrument could not be loaded."
            case .unavailableFormat: "The audio format is unavailable on this device."
            case .renderFailed: "Audio rendering stopped before the file was complete."
            }
        }
    }

    static func export(
        take: PerformanceTake,
        format: RecordingAudioFormat,
        profile: PianoSoundProfile,
        options: PerformancePlaybackOptions = .init(),
        soundFontURL: URL? = nil
    ) async throws -> URL {
        try Task.checkCancellation()
        guard take.isValid,
              options.rate.isFinite,
              (0.5...2).contains(options.rate) else { throw ExportError.invalidTake }
        let selectedTake: PerformanceTake
        if let region = options.region {
            guard let excerpt = RecordingEditor.excerpt(
                from: take,
                start: region.lowerBound,
                end: region.upperBound
            ) else { throw ExportError.invalidTake }
            selectedTake = excerpt
        } else {
            selectedTake = take
        }
        guard selectedTake.noteCount > 0 else { throw ExportError.invalidTake }
        guard let fontURL = soundFontURL ?? Bundle.main.url(forResource: "Piano", withExtension: "sf2") else {
            throw ExportError.missingSoundFont
        }

        let task = Task.detached(priority: .userInitiated) {
            try render(take: selectedTake, format: format, profile: profile,
                       rate: options.rate, soundFontURL: fontURL)
        }
        let url = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        return url
    }

    private static func render(
        take: PerformanceTake,
        format: RecordingAudioFormat,
        profile: PianoSoundProfile,
        rate: Double,
        soundFontURL: URL
    ) throws -> URL {
        purgeStaleExports()
        let sampleRate = 44_100.0
        let maximumFrameCount: AVAudioFrameCount = 4096
        guard let pcmFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 2
        ) else { throw ExportError.unavailableFormat }

        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let equalizer = AVAudioUnitEQ(numberOfBands: 2)
        let reverb = AVAudioUnitReverb()
        let lowShelf = equalizer.bands[0]
        lowShelf.filterType = .lowShelf
        lowShelf.frequency = 180
        lowShelf.gain = profile.lowShelfGainDB
        lowShelf.bypass = false
        let highShelf = equalizer.bands[1]
        highShelf.filterType = .highShelf
        highShelf.frequency = 3_200
        highShelf.gain = profile.highShelfGainDB
        highShelf.bypass = false
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = profile.reverbWetDryMix

        engine.attach(sampler)
        engine.attach(equalizer)
        engine.attach(reverb)
        try connect(engine, from: sampler, to: equalizer, format: pcmFormat)
        try connect(engine, from: equalizer, to: reverb, format: pcmFormat)
        try connect(engine, from: reverb, to: engine.mainMixerNode, format: pcmFormat)
        try sampler.loadSoundBankInstrument(
            at: soundFontURL,
            program: 0,
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
        try engine.enableManualRenderingMode(
            .offline, format: pcmFormat, maximumFrameCount: maximumFrameCount
        )
        try engine.start()
        defer { engine.stop() }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: maximumFrameCount
        ) else { throw ExportError.unavailableFormat }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PianoFlow-\(take.id.uuidString)-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)
        do {
            try write(
                take: take, rate: rate, format: format, sampleRate: sampleRate,
                outputURL: outputURL, engine: engine, sampler: sampler, buffer: buffer
            )
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func connect(
        _ engine: AVAudioEngine,
        from source: AVAudioNode,
        to destination: AVAudioNode,
        format: AVAudioFormat
    ) throws {
        if #available(iOS 27.0, macOS 27.0, *) {
            try engine.connectNode(source, to: destination, format: format)
        } else {
            engine.connect(source, to: destination, format: format)
        }
    }

    private static func purgeStaleExports() {
        let directory = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in files where url.lastPathComponent.hasPrefix("PianoFlow-")
            && ["wav", "m4a"].contains(url.pathExtension.lowercased()) {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func write(
        take: PerformanceTake,
        rate: Double,
        format: RecordingAudioFormat,
        sampleRate: Double,
        outputURL: URL,
        engine: AVAudioEngine,
        sampler: AVAudioUnitSampler,
        buffer: AVAudioPCMBuffer
    ) throws {
        let settings: [String: Any]
        switch format {
        case .wav:
            settings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        case .m4a:
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
        }
        let file = try AVAudioFile(forWriting: outputURL, settings: settings)
        defer {
            if #available(iOS 18.0, macOS 15.0, *) { file.close() }
        }
        var renderedFrames: AVAudioFramePosition = 0

        func renderUntil(_ targetFrame: AVAudioFramePosition) throws {
            var retries = 0
            while renderedFrames < targetFrame {
                try Task.checkCancellation()
                let frameCount = AVAudioFrameCount(
                    min(AVAudioFramePosition(buffer.frameCapacity), targetFrame - renderedFrames)
                )
                let status = try engine.renderOffline(frameCount, to: buffer)
                switch status {
                case .success:
                    guard buffer.frameLength > 0 else { throw ExportError.renderFailed }
                    try file.write(from: buffer)
                    renderedFrames += AVAudioFramePosition(buffer.frameLength)
                    retries = 0
                case .cannotDoInCurrentContext:
                    retries += 1
                    if retries > 16 { throw ExportError.renderFailed }
                case .insufficientDataFromInputNode, .error:
                    throw ExportError.renderFailed
                @unknown default:
                    throw ExportError.renderFailed
                }
            }
        }

        for event in take.events {
            let frame = AVAudioFramePosition((event.time / rate * sampleRate).rounded())
            try renderUntil(frame)
            if let pedal = event.sustain {
                sampler.sendController(64, withValue: pedal ? 127 : 0, onChannel: 0)
            } else if event.isNoteOn {
                sampler.startNote(event.note, withVelocity: event.velocity, onChannel: 0)
            } else {
                sampler.stopNote(event.note, onChannel: 0)
            }
        }

        let endFrame = AVAudioFramePosition((take.duration / rate * sampleRate).rounded())
        try renderUntil(endFrame)
        sampler.sendController(64, withValue: 0, onChannel: 0)
        sampler.sendController(123, withValue: 0, onChannel: 0)
        // Preserve the instrument release and room reverb after the last note.
        try renderUntil(endFrame + AVAudioFramePosition(2 * sampleRate))
    }
}
