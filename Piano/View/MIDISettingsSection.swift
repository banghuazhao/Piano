import CoreAudioKit
import SwiftUI

struct MIDISettingsSection: View {
    @Bindable var midi: MIDIInputService
    @State private var showBluetooth = false

    var body: some View {
        SettingsPanel(title: "MIDI keyboard", subtitle: "Play with real keys and a sustain pedal", symbol: "pianokeys") {
            SettingsToggleRow(title: "Keyboard input", subtitle: "Use velocity from your connected keyboard",
                              symbol: "cable.connector", isOn: $midi.isEnabled)
            if midi.isEnabled {
                Divider().overlay(PianoTheme.divider)
                if midi.sources.isEmpty {
                    Text("Connect a USB MIDI keyboard using a compatible adapter, or pair a Bluetooth MIDI keyboard below.")
                        .font(.subheadline)
                        .foregroundStyle(PianoTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(midi.sources) { source in
                        Label(source.name, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(PianoTheme.brass)
                    }
                }
                Button { showBluetooth = true } label: {
                    Label("Connect Bluetooth MIDI", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(PianoTheme.ivory)
                if let error = midi.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(PianoTheme.recording)
                }
            }
        }
        .sheet(isPresented: $showBluetooth) { BluetoothMIDIView() }
    }
}

/// Apple's native MIDI browser pairs devices and adds them to CoreMIDI's source list.
private struct BluetoothMIDIView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let browser = CABTMIDICentralViewController()
        browser.navigationItem.title = "Bluetooth MIDI"
        browser.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: context.coordinator, action: #selector(Coordinator.done)
        )
        return UINavigationController(rootViewController: browser)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        @objc func done() { dismiss() }
    }
}
