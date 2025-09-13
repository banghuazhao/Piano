//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI
import UIKit

struct PianoKeyView: View {
    let key: PianoKey
    let isPressed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    @AppStorage("showKeyDisplayNames") private var showKeyDisplayNames: Bool = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled: Bool = true

    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        Group {
            if key.isBlack {
                blackKeyView
            } else {
                whiteKeyView
            }
        }
        .scaleEffect(isPressed ? 0.98 : 1.0, anchor: .top)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        if hapticsEnabled {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                        onPress()
                    }
                }
                .onEnded { _ in
                    onRelease()
                }
        )
    }
    
    private var whiteKeyView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white)
            .fill(whiteKeyOverlayGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
            .overlay(
                VStack {
                    Spacer()
                    if showKeyDisplayNames {
                        Text(key.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.6))
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(OctaveColor.color(for: key.octave).opacity(0.3))
                            )
                    }
                    Spacer().frame(height: 8)
                }
            )
            .shadow(
                color: isPressed ? Color.black.opacity(0.3) : Color.black.opacity(0.1),
                radius: isPressed ? 2 : 4,
                x: 0,
                y: isPressed ? 1 : 2
            )
    }
    
    private var blackKeyView: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black)
                .fill(blackKeyOverlayGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    VStack {
                        Spacer()
                        if showKeyDisplayNames {
                            Text(key.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.bottom, 6)
                        }
                        Spacer().frame(height: 8)
                    }
                )
                .shadow(
                    color: isPressed ? Color.black.opacity(0.5) : Color.black.opacity(0.3),
                    radius: isPressed ? 1 : 3,
                    x: 0,
                    y: isPressed ? 1 : 2
                )
                .frame(height: geo.size.height * 0.6)
        }
    }
    
    private var whiteKeyOverlayGradient: LinearGradient {
        if isPressed {
            return LinearGradient(
                colors: [Color.gray.opacity(0.1), Color.black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color.gray.opacity(0.05), Color.gray.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var blackKeyOverlayGradient: LinearGradient {
        if isPressed {
            return LinearGradient(
                colors: [Color.white.opacity(0), Color.white.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

#Preview {
    HStack(spacing: 2) {
        PianoKeyView(
            key: PianoKey(note: .C, octave: 4),
            isPressed: false,
            onPress: {},
            onRelease: {}
        )
        PianoKeyView(
            key: PianoKey(note: .CSharp, octave: 4),
            isPressed: false,
            onPress: {},
            onRelease: {}
        )
        PianoKeyView(
            key: PianoKey(note: .D, octave: 4),
            isPressed: true,
            onPress: {},
            onRelease: {}
        )
        PianoKeyView(
            key: PianoKey(note: .CSharp, octave: 4),
            isPressed: true,
            onPress: {},
            onRelease: {}
        )
    }
    .frame(height: 200)
    .padding()
}
