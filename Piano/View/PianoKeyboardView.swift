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
            sustainControl
            
            // Piano Keyboard
            ZStack(alignment: .topLeading) {
                // White keys background
                whiteKeysView
                
                // Black keys overlay
                blackKeysView
            }
            .frame(height: 200)
            .padding(.horizontal, 16)
        }
        .background(
            LinearGradient(
                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var sustainControl: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $viewModel.isSustainOn) {
                Text("Sustain")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
        }
        .padding(.vertical, 8)
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
        GeometryReader { geometry in
            let totalSpacing = CGFloat(viewModel.whiteKeys.count - 1) * 2
            let whiteKeyWidth = (geometry.size.width - totalSpacing) / CGFloat(viewModel.whiteKeys.count)
            let blackKeyWidth: CGFloat = whiteKeyWidth * 0.6
            
            ZStack {
                ForEach(Array(viewModel.whiteKeys.enumerated()), id: \.element.id) { index, whiteKey in
                    if let blackKey = whiteKey.nextBlackKey() {
                        let whiteKeyPosition = CGFloat(index) * (whiteKeyWidth + 2)
                        let blackKeyPosition = whiteKeyPosition + whiteKeyWidth * 0.75 // Position in the gap between white keys
                        
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
                        .frame(width: blackKeyWidth)
                        .position(x: blackKeyPosition + blackKeyWidth / 2, y: geometry.size.height * 0.3) // Position higher to appear raised
                        .zIndex(1)
                    }
                }
            }
        }
    }
}

#Preview {
    PianoKeyboardView()
        .frame(height: 300)
}
