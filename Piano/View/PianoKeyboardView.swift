//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI
import UIKit

struct PianoKeyboardView: View {
    @State private var viewModel = PianoViewModel()
    @State private var scrollAction: ((AnyHashable, UnitPoint?) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            scrollSection
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    GeometryReader { geometry in
                        ZStack {
                            whiteKeysView(geometry: geometry)
                            blackKeysView(geometry: geometry)
                        }
                    }
                    .frame(width: viewModel.totalKeyboardWidth)
                    .background(Color.gray.opacity(0.1))
                }
                .onAppear {
                    scrollAction = proxy.scrollTo
                    scrollToMiddle(scrollTo: proxy.scrollTo)
                }
            }
        }
    }
    
    private var scrollSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(1...7, id: \.self) { octave in
                    OctaveButton(
                        octave: octave,
                        action: { scrollToOctave(octave) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.black.opacity(0.05))
        .frame(height: 60)
    }
    
    private func whiteKeysView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 1) {
            ForEach(viewModel.whiteKeys, id: \.id) { key in
                PianoKeyView(
                    key: key,
                    isPressed: viewModel.isKeyPressed(key),
                    onPress: { viewModel.keyPressed(key) },
                    onRelease: { viewModel.keyReleased(key) }
                )
                .frame(width: 50)
                .id(key.id)
            }
        }
    }
    
    private func blackKeysView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 1) {
            ForEach(viewModel.whiteKeys, id: \.id) { whiteKey in
                ZStack {
                    Color.clear
                        .frame(width: 50)
                    
                    if let blackKey = whiteKey.nextBlackKey(),
                       viewModel.pianoKeys.contains(blackKey) {
                        HStack {
                            Spacer()
//                                .frame(width: 35)
                            PianoKeyView(
                                key: blackKey,
                                isPressed: viewModel.isKeyPressed(blackKey),
                                onPress: { viewModel.keyPressed(blackKey) },
                                onRelease: { viewModel.keyReleased(blackKey) }
                            )
                            .frame(width: 30)
                            .zIndex(1)
                            Spacer()
                        }
                        .offset(x: 25)
                    }
                }
            }
        }
    }
    
    private func scrollToMiddle(scrollTo: @escaping (AnyHashable, UnitPoint?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.8)) {
                if let middleKey = viewModel.whiteKeys.first(where: { $0.note == .F && $0.octave == 4 }) {
                    scrollTo(middleKey.id, .center)
                }
            }
        }
    }
    
    private func scrollToOctave(_ octave: Int) {
        guard let scrollAction else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        withAnimation(.linear(duration: 0.2)) {
            if let targetKey = viewModel.whiteKeys.first(where: { $0.note == .F && $0.octave == octave }) {
                scrollAction(targetKey.id, .center)
            }
        }
    }
}

struct OctaveButton: View {
    let octave: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("C\(octave)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Octave \(octave)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview(traits: .landscapeLeft) {
    PianoKeyboardView()
}
