## 🎹 PianoFlow

A tactile iOS piano keyboard built with SwiftUI and AVAudioEngine. Play the full 88-key A0–C8 range with SoundFont piano audio, multi-touch chords, sustain, a metronome, and saved MIDI performances.

<img src="screenshots/pianoflow-premium.jpg" alt="PianoFlow instrument view" width="720" />

### 📲 Download on the App Store

- iOS: [PianoFlow on the App Store](https://apps.apple.com/us/app/pianoflow-keyboard/id6752531110)

### ✨ Features
- **🎹 88-key keyboard**: The acoustic piano range, A0 through C8, with independent finger tracking for chords and glissandos
- **🧭 Range navigation**: Octave shortcuts and a range slider keep navigation separate from the playing surface
- **⚙️ Customizable Settings**: Adjustable key width, key labels, piano volume, and haptic feedback
- **🎵 Expressive playing**: SoundFont-backed piano audio, balanced note release, sustain, and a live chord readout
- **⏱️ Practice tools**: Audible metronome with adjustable tempo, meter, and click volume
- **⏺️ Performance library**: Record note and sustain events, replay takes, and share Standard MIDI files
- **📱 Instrument design**: Responsive ivory and ebony keys with a compact dark control panel
- **🏗️ MVVM Architecture**: Clean separation with `@Observable` view models and Swift concurrency

### 🏗️ Architecture
- **📋 Pattern**: MVVM with Swift concurrency
- **🎛️ ViewModel**: `@Observable` and `@MainActor`-scoped for UI-safe state management
- **🔊 Audio**: `AVAudioEngine` + `AVAudioUnitSampler` for SoundFont playback
- **💾 State Management**: User preferences stored with `@AppStorage`

**🔄 Data Flow**:
- 📱 `PianoView` renders the scrollable keyboard and handles user interactions
- 🎚️ `PianoViewModel` manages key state, scroll position, and audio playback
- 🔊 `AudioEngine` handles the audio session and SoundFont, while `MetronomeService` produces the click track
- 💾 `PerformanceStudio` saves note events locally, replays takes, and uses `MIDIExporter` for sharing
- ⚙️ `SettingsView` provides customization options with persistent storage

### 🛠️ Requirements
- 💻 Xcode 16 or later
- 📱 iOS 17.6 or later
- 🖥️ macOS Sonoma or later for development

### 🚀 Getting Started
1. 📥 Clone the repository
```bash
git clone https://github.com/banghuazhao/PianoFlow.git
cd PianoFlow
```
2. 🔧 Open the project in Xcode
```bash
open Piano.xcodeproj
```
3. ▶️ Select the `Piano` scheme and a simulator or device, then Run.

**📝 Note**: If you replace the SoundFont, put your `.sf2` file in `Piano/Sound/` and update the load call if needed.

### 📁 Project Structure
```text
Piano/
  App/                 # 🚀 App entry point (`PianoApp.swift`)
  Sound/               # 🎵 SoundFont file (`Piano.sf2`)
  Assets.xcassets/     # 🎨 App icons and colors
  Config/              # ⚙️ Build configurations
  Model/               # 📋 Piano notes, keys, and recorded takes
  Service/             # 🔊 Sampler, metronome, recording, MIDI export, chord detection
  View/                # 📱 Keyboard, instrument controls, library, and settings
  ViewModel/           # 🎛️ `PianoViewModel` with @Observable
```

### 🎼 Usage
- **🎹 Playing Notes**: Touch multiple keys for chords, or move a finger across keys for a glissando. The keyboard stays fixed while playing.
- **🧭 Navigation**: 
  - Use octave buttons (C1–C7) to jump across the full A0–C8 range
  - Drag the range slider for fine control
- **⏺️ Record and replay**: Tap Record, play, then tap Stop. Play replays the latest take; Takes opens saved performances and MIDI sharing.
- **🎛️ Sustain and metronome**: Toggle them on the control panel. Tap the BPM display to adjust tempo, beats per bar, and click volume.
- **⚙️ Settings**: Tap the gear icon to access:
  - Key width adjustment (30–90 points)
  - Show/hide key names on keys
  - Toggle haptic feedback
  - Octave-specific key name display options
  - Piano volume
- **🎨 Customization**: Replace `Piano.sf2` with a licensed SoundFont to change the piano sound.

### 🗺️ Roadmap
- **🎹 MIDI Support**: MIDI input/output for external controllers
- **🎼 Guided practice**: Scale and song lessons with progress feedback
- **🎙️ Audio export**: Render a performance to an audio file in addition to MIDI

### 🤝 Contributing
- 📝 Open an issue or pull request on GitHub
- 🏗️ Follow MVVM architecture with `@Observable` view models and Swift concurrency
- 🔧 Prefer small, well-scoped changes
- 📚 Maintain consistent code style and documentation

### 📄 License
See [LICENSE](LICENSE).

### 🙏 Acknowledgements
- 🛠️ Built with SwiftUI and AVFoundation
- 🎵 Uses a bundled SoundFont file (`Piano.sf2`). Replace with your own if licensing requires.
- ©️ Copyright Apps Bay Limited. All rights reserved.

### 🔗 Links
- 📦 Repository: `https://github.com/banghuazhao/PianoFlow`
- 🛍️ App Store: `https://apps.apple.com/us/app/pianoflow-keyboard/id6752531110`
