//
// Created by Banghua Zhao on 04/09/2025
// Copyright Apps Bay Limited. All rights reserved.
//

import SwiftUI

struct PianoKeyboardView: View {
    @State private var viewModel = PianoViewModel()
    @State private var scrollPosition: Double = 0.0
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                scrubber(proxy: proxy)
                keyboardScrollView
            }
        }
        .background(
            LinearGradient(
                colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func scrubber(proxy: ScrollViewProxy) -> some View {
        HStack {
            Text("Keyboard")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Slider(value: $scrollPosition)
                .onChange(of: scrollPosition) { _, newValue in
                    let total = max(viewModel.whiteKeys.count - 1, 1)
                    let index = Int(round(newValue * Double(total)))
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(index, anchor: .leading)
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var keyboardScrollView: some View {
        let whiteKeyWidth: CGFloat = 48
        let spacing: CGFloat = 1
        let blackKeyWidth: CGFloat = whiteKeyWidth * 0.6
        let horizontalPadding: CGFloat = 16
        let count = viewModel.whiteKeys.count
        let contentWidth = CGFloat(count) * whiteKeyWidth + CGFloat(max(count - 1, 0)) * spacing + horizontalPadding * 2

        return ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // White keys row
                HStack(spacing: spacing) {
                    ForEach(Array(viewModel.whiteKeys.enumerated()), id: \.offset) { index, whiteKey in
                        PianoKeyView(
                            key: whiteKey,
                            isPressed: viewModel.isKeyPressed(whiteKey),
                            onPress: { viewModel.keyPressed(whiteKey) },
                            onRelease: { viewModel.keyReleased(whiteKey) }
                        )
                        .frame(width: whiteKeyWidth)
                        .id(index)
                    }
                }
                .padding(.horizontal, horizontalPadding)

                // Black keys overlay positioned globally across the row
                ForEach(Array(viewModel.whiteKeys.enumerated()), id: \.offset) { index, whiteKey in
                    if let blackKey = whiteKey.nextBlackKey() {
                        PianoKeyView(
                            key: blackKey,
                            isPressed: viewModel.isKeyPressed(blackKey),
                            onPress: { viewModel.keyPressed(blackKey) },
                            onRelease: { viewModel.keyReleased(blackKey) }
                        )
                        .frame(width: blackKeyWidth)
                        .offset(x: horizontalPadding + CGFloat(index) * (whiteKeyWidth + spacing) + whiteKeyWidth * 0.7, y: 0)
                        .zIndex(10)
                    }
                }
            }
            .frame(width: contentWidth, alignment: .topLeading)
        }
    }
}

#Preview(traits: .landscapeRight) {
    PianoKeyboardView()
}
