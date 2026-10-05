import Foundation

enum KeyboardHitTester {
    static func key(
        at point: CGPoint,
        in size: CGSize,
        whiteKeys: [PianoKey],
        keyWidth: CGFloat
    ) -> PianoKey? {
        guard !whiteKeys.isEmpty,
              point.x >= 0, point.x < size.width,
              point.y >= 0, point.y < size.height else { return nil }

        let cellWidth = keyWidth + 1
        let boundary = Int((point.x / cellWidth).rounded())
        if point.y < size.height * 0.62,
           boundary > 0, boundary < whiteKeys.count,
           abs(point.x - CGFloat(boundary) * cellWidth) <= keyWidth * 0.31,
           let blackKey = whiteKeys[boundary - 1].nextBlackKey() {
            return blackKey
        }

        let whiteIndex = min(whiteKeys.count - 1, Int(point.x / cellWidth))
        return whiteKeys[whiteIndex]
    }
}
