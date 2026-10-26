//
// Copyright Apps Bay Limited. All rights reserved.
//

import AVFoundation
import Darwin
import Observation

/// A looped PCM bar keeps beats sample-accurate without a UI timer.
@Observable
@MainActor
final class MetronomeService {
    private(set) var isRunning = false
    private(set) var bpm = 96
    private(set) var beatsPerBar = 4
    private(set) var beatUnit = 4
    private(set) var volume = 0.7
    @ObservationIgnored var onTimingReset: (() -> Void)?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var loopBuffer: AVAudioPCMBuffer?
    @ObservationIgnored private var connectedSampleRate: Double?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    init() {
        audioEngine.attach(player)
        player.volume = Float(volume)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.connectedSampleRate = nil
                self.onTimingReset?()
                if self.isRunning { self.start(bpm: self.bpm) }
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let rawType,
                      AVAudioSession.InterruptionType(rawValue: rawType) == .began else {
                    return
                }
                self?.onTimingReset?()
                self?.stop()
            }
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func start(bpm requestedBPM: Int) {
        _ = startAligned(bpm: requestedBPM, numerator: beatsPerBar,
                         denominator: beatUnit, scheduled: false)
    }

    /// Audio and scoring share the scheduled first click, including the count-in.
    func startForPractice(bpm: Int, beatsPerBar: Int, beatUnit: Int) -> TimeInterval? {
        startAligned(bpm: bpm, numerator: beatsPerBar, denominator: beatUnit, scheduled: true)
    }

    private func startAligned(bpm requestedBPM: Int, numerator: Int,
                              denominator: Int, scheduled: Bool) -> TimeInterval? {
        bpm = min(max(requestedBPM, 40), 240)
        beatsPerBar = min(max(numerator, 1), 16)
        beatUnit = [1, 2, 4, 8, 16, 32].contains(denominator) ? denominator : 4

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            let sampleRate = session.sampleRate > 0 ? session.sampleRate : 44_100
            guard let buffer = makeBarBuffer(sampleRate: sampleRate) else {
                stop()
                return nil
            }

            player.stop()
            if connectedSampleRate != sampleRate {
                audioEngine.stop()
                if #available(iOS 27.0, *) {
                    try audioEngine.connectNode(
                        player, to: audioEngine.mainMixerNode, format: buffer.format
                    )
                } else {
                    audioEngine.connect(player, to: audioEngine.mainMixerNode, format: buffer.format)
                }
                connectedSampleRate = sampleRate
            }
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }

            loopBuffer = buffer
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            let leadTime = scheduled ? 0.12 : 0
            let epoch = ProcessInfo.processInfo.systemUptime + leadTime
            if scheduled {
                let hostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: leadTime)
                player.play(at: AVAudioTime(hostTime: hostTime))
            } else {
                player.play()
            }
            isRunning = true
            return epoch
        } catch {
            stop()
            connectedSampleRate = nil
            print("Failed to start metronome: \(error)")
            return nil
        }
    }

    func stop() {
        player.stop()
        audioEngine.stop()
        isRunning = false
    }

    func setTempo(_ requestedBPM: Int) {
        let newBPM = min(max(requestedBPM, 40), 240)
        guard bpm != newBPM else { return }
        bpm = newBPM
        if isRunning { start(bpm: newBPM) }
    }

    func setBeatsPerBar(_ requestedBeats: Int) {
        let newBeats = min(max(requestedBeats, 2), 8)
        guard beatsPerBar != newBeats else { return }
        beatsPerBar = newBeats
        if isRunning { start(bpm: bpm) }
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(max(value, 0), 1)
        player.volume = Float(volume)
    }

    private func makeBarBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let framesPerBeat = sampleRate * 60 / Double(bpm) * 4 / Double(beatUnit)
        let frameCount = Int((framesPerBeat * Double(beatsPerBar)).rounded())
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let samples = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for frame in 0..<frameCount { samples[frame] = 0 }

        let clickFrameCount = Int(sampleRate * 0.055)
        for beat in 0..<beatsPerBar {
            let beatStart = Int((Double(beat) * framesPerBeat).rounded())
            let isDownbeat = beat == 0
            let frequency = isDownbeat ? 760.0 : 570.0
            let amplitude = isDownbeat ? 0.36 : 0.25

            for frame in 0..<min(clickFrameCount, frameCount - beatStart) {
                let time = Double(frame) / sampleRate
                let attack = min(1, time * 2_500)
                let envelope = attack * exp(-72 * time)
                let body = sin(2 * .pi * frequency * time)
                    + 0.22 * sin(2 * .pi * frequency * 1.5 * time)
                samples[beatStart + frame] = Float(amplitude * envelope * body)
            }
        }

        return buffer
    }
}
