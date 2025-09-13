//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI
import UIKit

struct PianoView: View {
    @State private var viewModel = PianoViewModel()
    @AppStorage("keyWidth") private var keyWidth: Double = 50.0
    @State private var scrollAction: ((AnyHashable, UnitPoint?) -> Void)?

    var totalKeyboardWidth: CGFloat {
        let whiteKeySpacing: CGFloat = 1
        let whiteKeyCount = viewModel.whiteKeys.count
        return CGFloat(whiteKeyCount) * keyWidth + CGFloat(whiteKeyCount - 1) * whiteKeySpacing
    }

    var body: some View {
        VStack(spacing: 0) {
            topSection

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    GeometryReader { geometry in
                        ZStack {
                            whiteKeysView(geometry: geometry)
                            blackKeysView(geometry: geometry)
                        }
                    }
                    .frame(width: totalKeyboardWidth)
                }
                .onAppear {
                    scrollAction = proxy.scrollTo
                    scrollToMiddle(scrollTo: proxy.scrollTo)
                }
                .onChange(of: viewModel.scrollPosition) { _, _ in
                    scrollToPosition(viewModel.scrollPosition)
                }
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView()
        }
    }

    private var topSection: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }

            ZStack {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                Slider(value: $viewModel.scrollPosition, in: 0 ... 1)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .onChange(of: viewModel.scrollPosition) { _, _ in
                        scrollToPosition(viewModel.scrollPosition)
                    }
            }
            .frame(minWidth: 180, idealWidth: 240, maxWidth: 320, minHeight: 32)
            ForEach(viewModel.octaves, id: \.self) { octave in
                OctaveButton(
                    octave: octave,
                    isSelected: viewModel.currentOctave == octave,
                    action: { scrollToOctave(octave) }
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
                .frame(width: keyWidth)
                .id(key.id)
            }
        }
    }

    private func blackKeysView(geometry: GeometryProxy) -> some View {
        HStack(spacing: 1) {
            ForEach(viewModel.whiteKeys, id: \.id) { whiteKey in
                Color.clear
                    .frame(width: keyWidth)
                    .overlay {
                        if let blackKey = whiteKey.nextBlackKey(),
                           viewModel.pianoKeys.contains(blackKey) {
                            HStack {
                                Spacer()
                                PianoKeyView(
                                    key: blackKey,
                                    isPressed: viewModel.isKeyPressed(blackKey),
                                    onPress: { viewModel.keyPressed(blackKey) },
                                    onRelease: { viewModel.keyReleased(blackKey) }
                                )
                                .frame(width: keyWidth * 0.6)
                                .zIndex(1)
                                Spacer()
                            }
                            .offset(x: keyWidth / 2)
                        }
                    }
            }
        }
    }

    private func scrollToMiddle(scrollTo: @escaping (AnyHashable, UnitPoint?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.8)) {
                if let middleKey = viewModel.middleAnchorKey() {
                    scrollTo(middleKey.id, .center)
                    updateScrollPosition(to: middleKey)
                }
            }
        }
    }

    private func scrollToOctave(_ octave: Int) {
        guard let scrollAction else { return }

        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        withAnimation(.easeInOut(duration: 0.3)) {
            if let targetKey = viewModel.anchorKey(forOctave: octave) {
                scrollAction(targetKey.id, .leading)
                updateScrollPosition(to: targetKey)
            }
        }
    }

    private func scrollToPosition(_ position: Double) {
        guard let scrollAction else { return }
        guard let key = viewModel.keyForPosition(position) else { return }
        withAnimation(.linear(duration: 0.15)) {
            scrollAction(key.id, .center)
        }
    }

    private func updateScrollPosition(to key: PianoKey) {
        if let pos = viewModel.normalizedPosition(for: key) {
            if abs(viewModel.scrollPosition - pos) > 0.001 {
                viewModel.scrollPosition = pos
            }
        }
    }
}

struct OctaveButton: View {
    let octave: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("C\(octave)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Octave\(octave)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? backgroundColor.opacity(0.8) : backgroundColor.opacity(0.3))
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    var backgroundColor: Color {
        OctaveColor.color(for: octave)
    }
}

#Preview(traits: .landscapeLeft) {
    PianoView()
}
