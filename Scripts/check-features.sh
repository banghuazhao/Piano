#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
checks_dir="$(mktemp -d "${TMPDIR:-/tmp}/PianoFlowChecks.XXXXXX")"
trap 'rm -rf "$checks_dir"' EXIT

xcrun swiftc Piano/Model/MIDIInputState.swift Tests/MIDIInputChecks.swift -o "$checks_dir/midi"
"$checks_dir/midi"

xcrun swiftc Piano/Model/PracticeExercise.swift Piano/Service/PracticeSession.swift \
  Tests/PracticeChecks.swift -o "$checks_dir/practice"
"$checks_dir/practice"

xcrun swiftc Piano/Model/PracticeExercise.swift Piano/Model/ImportedPracticeSong.swift \
  Piano/Service/MIDIFileImporter.swift Piano/Service/ImportedSongLibrary.swift \
  Tests/MIDIImportChecks.swift -o "$checks_dir/import"
"$checks_dir/import"

xcrun swiftc Piano/Model/PracticeExercise.swift Piano/Model/ScoreNotation.swift \
  Tests/ScoreNotationChecks.swift -o "$checks_dir/score"
"$checks_dir/score"

xcrun swiftc Piano/Model/PerformanceTake.swift Piano/Model/PianoSoundProfile.swift \
  Piano/Service/RecordingEditor.swift Piano/Service/MIDIExporter.swift \
  Piano/Service/AudioExporter.swift Piano/Service/PremiumStore.swift \
  Piano/Service/PerformanceStudio.swift \
  Tests/RecordingChecks.swift -o "$checks_dir/recording"
"$checks_dir/recording"

xcrun swiftc Piano/Model/PerformanceTake.swift Piano/Model/PianoSoundProfile.swift \
  Piano/Service/RecordingEditor.swift Piano/Service/AudioExporter.swift \
  Tests/AudioExportChecks.swift -o "$checks_dir/audio"
"$checks_dir/audio" "$PWD/Piano/Sound/Piano.sf2"
