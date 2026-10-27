import CoreMIDI
import Foundation
import Observation

@Observable
@MainActor
final class MIDIInputService {
    struct Source: Identifiable {
        let id: MIDIEndpointRef
        let name: String
    }

    var isEnabled: Bool {
        didSet {
            PianoRuntimeEnvironment.defaults.set(isEnabled, forKey: "midiInputEnabled")
            refreshSources()
        }
    }
    private(set) var sources: [Source] = []
    private(set) var errorMessage: String?
    var onEvent: ((MIDIInputEvent) -> Void)?
    @ObservationIgnored private var client: MIDIClientRef = 0
    @ObservationIgnored private var port: MIDIPortRef = 0
    @ObservationIgnored private var connected: Set<MIDIEndpointRef> = []
    @ObservationIgnored private var state = MIDIInputState()
    @ObservationIgnored private var isActive = true

    init() {
        isEnabled = PianoRuntimeEnvironment.defaults.object(forKey: "midiInputEnabled") as? Bool ?? true
    }

    deinit {
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func start() {
        guard client == 0 else { refreshSources(); return }
        var status = MIDIClientCreateWithBlock("PianoFlow" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshSources() }
        }
        guard status == noErr else { report(status); return }
        status = MIDIInputPortCreateWithProtocol(client, "PianoFlow keyboard" as CFString, ._1_0, &port) {
            [weak self] eventList, sourceContext in
            // CoreMIDI owns this memory only for this callback. Copy decoded messages here.
            var messages: [MIDIInputMessage] = []
            withUnsafeMutablePointer(to: &messages) { storage in
                MIDIEventListForEachEvent(eventList, { context, _, message in
                    guard let context, message.type.rawValue == 2 else { return }
                    let voice = message.channelVoice1
                    let status = UInt8(voice.status.rawValue)
                    let data1: UInt8
                    let data2: UInt8
                    switch status {
                    case 0x8, 0x9:
                        data1 = voice.note.number
                        data2 = voice.note.velocity
                    case 0xB:
                        data1 = voice.controlChange.index
                        data2 = voice.controlChange.data
                    default: return
                    }
                    context.assumingMemoryBound(to: [MIDIInputMessage].self).pointee.append(
                        MIDIInputMessage(group: message.group, channel: voice.channel,
                                         status: status, data1: data1, data2: data2)
                    )
                }, storage)
            }
            guard !messages.isEmpty else { return }
            let copiedMessages = messages
            let source = UInt32(truncatingIfNeeded: UInt(bitPattern: sourceContext))
            // A serial main queue preserves MIDI event ordering across callback batches.
            DispatchQueue.main.async { self?.receive(copiedMessages, from: source) }
        }
        guard status == noErr else {
            report(status)
            MIDIClientDispose(client)
            client = 0
            return
        }
        refreshSources()
    }

    func resetHeldNotes() {
        emit(state.reset())
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active { resetHeldNotes() }
    }

    private func refreshSources() {
        guard port != 0 else { return }
        let available = (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.filter { $0 != 0 }
        let desired = isEnabled ? Set(available) : []
        errorMessage = nil
        for source in connected.subtracting(desired) {
            MIDIPortDisconnectSource(port, source)
            emit(state.disconnect(source: source))
        }
        connected.formIntersection(desired)
        for source in desired.subtracting(connected) {
            let status = MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: UInt(source)))
            if status == noErr { connected.insert(source) } else { report(status) }
        }
        sources = connected.sorted().map { source in
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            return Source(id: source, name: name?.takeRetainedValue() as String? ?? "MIDI keyboard")
        }
        if !isEnabled { resetHeldNotes() }
    }

    private func receive(_ messages: [MIDIInputMessage], from source: UInt32) {
        guard isActive, isEnabled, connected.contains(source) else { return }
        for message in messages { emit(state.receive(message, source: source)) }
    }

    private func emit(_ events: [MIDIInputEvent]) {
        for event in events { onEvent?(event) }
    }

    private func report(_ status: OSStatus) {
        errorMessage = "MIDI connection failed (\(status)). Try reconnecting your keyboard."
    }
}
