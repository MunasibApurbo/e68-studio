import Foundation

/// Keycap colour group, used only for drawing.
enum Tone {
    case alpha, mod, accent
}

/// One physical position on the board: a switch, or one of the knob's three actions.
struct Slot: Identifiable, Hashable {
    let row: Int
    let col: Int
    let x: Double
    let y: Double
    let w: Double
    let tone: Tone

    /// Index into a layer's 8 × 16 matrix.
    var index: Int { row * VIA.cols + col }
    var id: Int { index }
}

/// Physical layout of the E68, transcribed from FuryCube's VIA definition (units of one keycap).
enum Layout {
    static let width = 16.25
    static let height = 5.125

    static let knobCCW = Slot(row: 7, col: 0, x: 15.25, y: 0, w: 1, tone: .mod)
    static let knobPress = Slot(row: 1, col: 14, x: 15.25, y: 0, w: 1, tone: .mod)
    static let knobCW = Slot(row: 7, col: 1, x: 15.25, y: 0, w: 1, tone: .mod)
    static let knob = [knobCCW, knobPress, knobCW]
    static let del = Slot(row: 1, col: 15, x: 15.25, y: 1, w: 1, tone: .mod)

    static let keys: [Slot] = {
        var out = [Slot]()
        func run(y: Double, x: Double, _ items: [(Int, Int, Double, Tone)]) {
            var cursor = x
            for (row, col, w, tone) in items {
                out.append(Slot(row: row, col: col, x: cursor, y: y, w: w, tone: tone))
                cursor += w
            }
        }
        run(y: 0, x: 0, [(1, 0, 1, .accent)] + (1...12).map { (1, $0, 1, .alpha) } + [(1, 13, 2, .mod)])
        run(y: 1, x: 0, [(2, 0, 1.5, .mod)] + (1...12).map { (2, $0, 1, .alpha) } + [(2, 13, 1.5, .alpha)])
        run(y: 1, x: 15.25, [(1, 15, 1, .mod)])
        run(y: 2, x: 0, [(3, 0, 1.75, .mod)] + (1...11).map { (3, $0, 1, .alpha) } + [(3, 13, 2.25, .accent)])
        run(y: 2, x: 15.25, [(3, 14, 1, .mod)])
        run(y: 3, x: 0, [(4, 0, 2.25, .mod)] + (2...11).map { (4, $0, 1, .alpha) } + [(4, 13, 1.75, .mod)])
        run(y: 3.125, x: 14.125, [(4, 14, 1, .mod)])
        run(y: 3, x: 15.25, [(3, 15, 1, .mod)])
        run(y: 4, x: 0, [(5, 0, 1.25, .mod), (5, 1, 1.25, .mod), (5, 2, 1.25, .mod), (5, 5, 6.25, .alpha),
                         (5, 9, 1, .mod), (5, 10, 1, .mod), (5, 12, 1, .mod)])
        run(y: 4.125, x: 13.125, [(5, 13, 1, .mod), (5, 14, 1, .mod), (5, 15, 1, .mod)])
        return out
    }()

    /// Every remappable position: 67 switches plus knob left, press and right.
    static let all: [Slot] = keys + knob

    private static let slotTable: [Int: Slot] = Dictionary(uniqueKeysWithValues: all.map { ($0.index, $0) })
    private static let positionNameTable: [Int: String] = Dictionary(uniqueKeysWithValues: all.map { slot in
        let name: String
        switch slot {
        case knobCCW: name = "Knob · turn left"
        case knobPress: name = "Knob · press"
        case knobCW: name = "Knob · turn right"
        default: name = "Row \(slot.row) · column \(slot.col)"
        }
        return (slot.index, name)
    })

    static func slot(at index: Int) -> Slot? {
        slotTable[index]
    }

    static func positionName(_ slot: Slot) -> String {
        positionNameTable[slot.index] ?? "Row \(slot.row) · column \(slot.col)"
    }
}

enum LayerInfo {
    static func title(_ layer: Int) -> String {
        switch layer {
        case 0: return "Mac"
        case 1: return "Fn"
        case 2: return "Windows"
        default: return "Layer \(layer)"
        }
    }

    static func detail(_ layer: Int) -> String {
        switch layer {
        case 0: return "Base layer with the Mac bottom row (Control, Option, Command)."
        case 1: return "Active while Fn is held. Shared by the Mac and Windows layers."
        case 2: return "Base layer with the Windows bottom row (Ctrl, Win, Alt)."
        default: return "Spare layer. Nothing switches to it until you assign a layer key."
        }
    }
}
