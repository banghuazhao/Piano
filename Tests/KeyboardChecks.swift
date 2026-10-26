import Foundation

@main
struct KeyboardChecks {
    static func main() {
        expect(PianoKey(note: .C, octave: 8).nextBlackKey() == nil,
               "The 88-key piano ends at C8 without a phantom C-sharp key")
        let keys = [PianoKey(note: .C, octave: 4), PianoKey(note: .D, octave: 4), PianoKey(note: .E, octave: 4)]
        func hit(_ x: CGFloat, _ y: CGFloat, width: CGFloat = 50, size: CGSize = CGSize(width: 152, height: 200)) -> PianoKey? {
            KeyboardHitTester.key(at: CGPoint(x: x, y: y), in: size, whiteKeys: keys, keyWidth: width)
        }
        expect(hit(20, 180)?.note == .C, "White key lower surface")
        expect(hit(51, 20)?.note == .CSharp, "Black keys take precedence at the boundary")
        expect(hit(51, 180)?.note == .D, "The same boundary selects white below black key")
        expect(hit(-1, 20) == nil && hit(20, 200) == nil, "Outside touches do not play")
        expect(hit(20, 20, width: .nan) == nil, "Invalid preferences cannot reach integer conversion")
        expect(hit(.infinity, 20) == nil && hit(.nan, 20) == nil, "Invalid touch coordinates are ignored")
        expect(hit(20, 20, width: -1) == nil && hit(20, 20, width: 0) == nil, "Invalid widths are ignored")
        expect(hit(1e100, 20, size: CGSize(width: 1e101, height: 200))?.note == .E,
               "Finite extreme geometry cannot overflow index conversion")
        print("Keyboard checks passed: white/black hit regions, boundaries, invalid and extreme geometry")
    }

    private static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }
}
