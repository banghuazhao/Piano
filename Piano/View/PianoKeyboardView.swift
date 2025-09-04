//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct PianoKeyboardView: View {
    @State private var viewModel = PianoViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Octave Controls
            octaveControls
            
            // Piano Keyboard
            ZStack(alignment: .topLeading) {
                // White keys background
                whiteKeysView
                
                // Black keys overlay
                blackKeysView
            }
            .frame(height: 200)
            .padding(.horizontal, 16)
            
            // Status indicator
            statusView
        }
        .background(
            LinearGradient(
                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .task {
            await viewModel.initializeAudio()
        }
    }
    
    private var octaveControls: some View {
        HStack {
            Button(action: viewModel.decreaseOctave) {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(viewModel.currentOctave <= 2)
            
            Text("Octave \(viewModel.currentOctave)")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(minWidth: 100)
            
            Button(action: viewModel.increaseOctave) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(viewModel.currentOctave >= 6)
        }
        .padding(.vertical, 12)
    }
    
    private var whiteKeysView: some View {
        HStack(spacing: 2) {
            ForEach(viewModel.whiteKeys) { key in
                PianoKeyView(
                    key: key,
                    isPressed: viewModel.isKeyPressed(key),
                    onPress: {
                        viewModel.keyPressed(key)
                    },
                    onRelease: {
                        viewModel.keyReleased(key)
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var blackKeysView: some View {
        HStack(spacing: 2) {
            ForEach(viewModel.whiteKeys) { whiteKey in
                HStack(spacing: 0) {
                    // Spacer for positioning
                    Spacer()
                        .frame(maxWidth: .infinity)
                    
                    // Black key if it exists between this white key and the next
                    if let blackKey = blackKeyAfter(whiteKey) {
                        PianoKeyView(
                            key: blackKey,
                            isPressed: viewModel.isKeyPressed(blackKey),
                            onPress: {
                                viewModel.keyPressed(blackKey)
                            },
                            onRelease: {
                                viewModel.keyReleased(blackKey)
                            }
                        )
                        .frame(width: 24)
                        .zIndex(1)
                    } else {
                        Spacer()
                            .frame(width: 24)
                    }
                }
            }
        }
    }
    
    private var statusView: some View {
        HStack {
            if viewModel.isInitialized {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Ready")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Error: \(errorMessage)")
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        viewModel.retryInitialization()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            Text("\(viewModel.pressedKeysCount) keys pressed")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private func blackKeyAfter(_ whiteKey: PianoKey) -> PianoKey? {
        let blackKeyNotes: [PianoNote: PianoNote] = [
            .C: .CSharp,
            .D: .DSharp,
            .F: .FSharp,
            .G: .GSharp,
            .A: .ASharp
        ]
        
        if let blackNote = blackKeyNotes[whiteKey.note] {
            return PianoKey(note: blackNote, octave: whiteKey.octave)
        }
        return nil
    }
}

#Preview {
    PianoKeyboardView()
        .frame(height: 300)
}
