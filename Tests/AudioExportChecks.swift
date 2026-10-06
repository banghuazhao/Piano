import AVFoundation

/// Standalone offline-rendering checks. Pass the path to Piano.sf2 as argument.
@main
struct AudioExportChecks {
    static func main() async throws {
        precondition(CommandLine.arguments.count == 2, "Pass Piano.sf2 path")
        let font = URL(fileURLWithPath: CommandLine.arguments[1])
        let take = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 0.5,
            events: [
                PerformanceEvent(note: 60, time: 0, isNoteOn: true, velocity: 96),
                PerformanceEvent(note: 60, time: 0.35, isNoteOn: false)
            ]
        )
        let selection = PerformancePlaybackOptions(rate: 1.5, loop: true, region: 0.1...0.4)

        for format in RecordingAudioFormat.allCases {
            let url = try await AudioExporter.export(
                take: take, format: format, profile: .concert,
                options: selection, soundFontURL: font
            )
            defer { try? FileManager.default.removeItem(at: url) }
            let data = try Data(contentsOf: url)
            if format == .wav {
                precondition(Array(data.prefix(4)) == Array("RIFF".utf8), "Invalid WAV header")
            } else {
                precondition(Array(data[4..<8]) == Array("ftyp".utf8), "Invalid M4A header")
            }
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            precondition(duration > 2.1 && duration < 2.4, "Incorrect export duration: \(duration)")

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: 4096
            ) else { fatalError("Could not inspect rendered audio") }
            var peak: Float = 0
            while file.framePosition < file.length {
                try file.read(into: buffer)
                guard let channels = buffer.floatChannelData else { break }
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channels[0][frame]))
                }
            }
            precondition(peak > 0.001, "Rendered \(format.rawValue) is silent")
            print("\(format.rawValue): \(data.count) bytes, \(duration)s, peak \(peak)")
        }

        let longTake = PerformanceTake(
            id: UUID(), createdAt: Date(), duration: 120,
            events: [
                PerformanceEvent(note: 60, time: 0, isNoteOn: true),
                PerformanceEvent(note: 60, time: 0.1, isNoteOn: false)
            ]
        )
        let cancelledExport = Task {
            try await AudioExporter.export(
                take: longTake, format: .wav, profile: .concert,
                soundFontURL: font
            )
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        cancelledExport.cancel()
        do {
            let url = try await cancelledExport.value
            try? FileManager.default.removeItem(at: url)
            preconditionFailure("Cancelled export unexpectedly completed")
        } catch is CancellationError {
            let files = try FileManager.default.contentsOfDirectory(
                at: FileManager.default.temporaryDirectory,
                includingPropertiesForKeys: nil
            )
            let prefix = "PianoFlow-\(longTake.id.uuidString)-"
            precondition(!files.contains { $0.lastPathComponent.hasPrefix(prefix) },
                         "Cancelled export left a partial file")
        }
        print("Audio export checks passed")
    }
}
