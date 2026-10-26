import Foundation

enum KeyboardHitTester {
    static func key(
        at point: CGPoint,
        in size: CGSize,
        whiteKeys: [PianoKey],
        keyWidth: CGFloat
    ) -> PianoKey? {
        guard !whiteKeys.isEmpty,
              point.x.isFinite, point.y.isFinite,
              size.width.isFinite, size.height.isFinite,
              keyWidth.isFinite, keyWidth >= 1,
              point.x >= 0, point.x < size.width,
              point.y >= 0, point.y < size.height else { return nil }

        let cellWidth = keyWidth + 1
        let cell = min(CGFloat(whiteKeys.count), point.x / cellWidth)
        let boundary = Int(cell.rounded())
        if point.y < size.height * 0.62,
           boundary > 0, boundary < whiteKeys.count,
           abs(point.x - CGFloat(boundary) * cellWidth) <= keyWidth * 0.31,
           let blackKey = whiteKeys[boundary - 1].nextBlackKey() {
            return blackKey
        }

        let whiteIndex = min(whiteKeys.count - 1, Int(cell))
        return whiteKeys[whiteIndex]
    }
}
