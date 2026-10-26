import SwiftUI
import UIKit

/// Tracks each finger independently so chords and glissandos behave like a real keyboard.
struct KeyboardTouchSurface: UIViewRepresentable {
    let whiteKeys: [PianoKey]
    let keyWidth: CGFloat
    let onPress: (PianoKey) -> Void
    let onRelease: (PianoKey) -> Void

    func makeUIView(context: Context) -> KeyboardTouchView {
        let view = KeyboardTouchView()
        view.isMultipleTouchEnabled = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: KeyboardTouchView, context: Context) {
        view.whiteKeys = whiteKeys
        view.keyWidth = keyWidth
        view.onPress = onPress
        view.onRelease = onRelease
    }
}

final class KeyboardTouchView: UIView {
    var whiteKeys: [PianoKey] = []
    var keyWidth: CGFloat = 50
    var onPress: ((PianoKey) -> Void)?
    var onRelease: ((PianoKey) -> Void)?

    private var activeKeys: [ObjectIdentifier: PianoKey] = [:]
    private var keyTouchCounts: [PianoKey: Int] = [:]
    private var previousSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if previousSize != bounds.size {
            releaseAllTouches()
            previousSize = bounds.size
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouches(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouches(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseTouches(touches)
    }

    private func updateTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            let identifier = ObjectIdentifier(touch)
            let nextKey = key(at: touch.location(in: self))
            let currentKey = activeKeys[identifier]
            guard currentKey != nextKey else { continue }
            if let currentKey { release(currentKey) }
            if let nextKey {
                activeKeys[identifier] = nextKey
                press(nextKey)
            } else {
                activeKeys.removeValue(forKey: identifier)
            }
        }
    }

    private func releaseTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if let key = activeKeys.removeValue(forKey: ObjectIdentifier(touch)) {
                release(key)
            }
        }
    }

    private func press(_ key: PianoKey) {
        let count = keyTouchCounts[key, default: 0]
        keyTouchCounts[key] = count + 1
        if count == 0 { onPress?(key) }
    }

    private func release(_ key: PianoKey) {
        let count = keyTouchCounts[key, default: 0]
        if count <= 1 {
            keyTouchCounts.removeValue(forKey: key)
            onRelease?(key)
        } else {
            keyTouchCounts[key] = count - 1
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            releaseAllTouches()
        }
    }

    private func releaseAllTouches() {
        let keys = Array(keyTouchCounts.keys)
        keyTouchCounts.removeAll()
        activeKeys.removeAll()
        for key in keys { onRelease?(key) }
    }

    private func key(at point: CGPoint) -> PianoKey? {
        KeyboardHitTester.key(
            at: point,
            in: bounds.size,
            whiteKeys: whiteKeys,
            keyWidth: keyWidth
        )
    }
}
