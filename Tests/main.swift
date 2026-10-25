// Logic checks for grid maths, config loading and key handling. Run with `./build.sh test`.
import AppKit

var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String) {
    if cond() { print("ok   \(msg)") } else { failures += 1; print("FAIL \(msg)") }
}

let screen = NSScreen.screens[0]
let vf = screen.visibleFrame
let config = Config()
// Sample shortcuts on a 6x6 grid: left half, right half, top half, and a panel-only full screen.
func shortcut(_ name: String, _ c0: Int, _ r0: Int, _ c1: Int, _ r1: Int, _ key: String, global: Bool = true) -> Shortcut {
    Shortcut(name: name, columns: 6, rows: 6, startColumn: c0, startRow: r0, endColumn: c1, endRow: r1,
             hotkey: KeyCombo(key: key, modifiers: ["ctrl", "cmd"]), global: global, enabled: true)
}
let sample = [shortcut("Left", 0, 0, 2, 5, "left"), shortcut("Right", 3, 0, 5, 5, "right"),
              shortcut("Top", 0, 0, 5, 2, "up"), shortcut("Full", 0, 0, 5, 5, "a", global: false)]

// Grid maths
let left = sample[0]
let r = WindowMover.rect(for: left.selection, columns: 6, rows: 6, on: screen, margins: nil)
check(abs(r.minX - vf.minX) <= 1 && abs(r.width - vf.width / 2) <= 1 && abs(r.height - vf.height) <= 1, "Left = left half of visible frame \(r) vs \(vf)")
let top = sample[2]
let t = WindowMover.rect(for: top.selection, columns: 6, rows: 6, on: screen, margins: nil)
check(abs(t.maxY - vf.maxY) <= 1 && abs(t.height - vf.height / 2) <= 1, "Top = top half \(t)")
let reversed = GridSelection(startColumn: 5, startRow: 5, endColumn: 3, endRow: 0)
check(WindowMover.rect(for: reversed, columns: 6, rows: 6, on: screen, margins: nil) ==
      WindowMover.rect(for: sample[1].selection, columns: 6, rows: 6, on: screen, margins: nil), "dragging backwards selects the same block")

let m = Margins(left: 10, right: 10, top: 10, bottom: 10, windowWidth: 10, windowHeight: 10)
let ml = WindowMover.rect(for: left.selection, columns: 6, rows: 6, on: screen, margins: m)
let mr = WindowMover.rect(for: sample[1].selection, columns: 6, rows: 6, on: screen, margins: m)
check(abs(ml.minX - (vf.minX + 10)) <= 1 && abs(mr.maxX - (vf.maxX - 10)) <= 1, "screen edge margins applied")
check(abs((mr.minX - ml.maxX) - 10) <= 1, "10pt gap between neighbouring windows (\(mr.minX - ml.maxX))")
let huge = Margins(left: 5000, right: 5000, top: 5000, bottom: 5000, windowWidth: 5000, windowHeight: 5000)
let h = WindowMover.rect(for: left.selection, columns: 6, rows: 6, on: screen, margins: huge)
check(h.width >= 1 && h.height >= 1 && h.width.isFinite, "huge margins stay positive \(h)")
let z = WindowMover.rect(for: left.selection, columns: 0, rows: 0, on: screen, margins: nil)
check(z.width.isFinite && z.height.isFinite, "zero grid size doesn't produce NaN \(z)")

// Coordinate flip round-trips
let cocoa = CGRect(x: 100, y: 200, width: 300, height: 400)
check(WindowMover.flip(WindowMover.flip(cocoa)) == cocoa, "flip is its own inverse")

// Config decoding
let old = #"{"gridColumns":6,"gridRows":6,"panelHotkey":{"key":"w","modifiers":["ctrl","cmd"]},"showMenuIcon":true,"shortcuts":[]}"#
let decodedOld = try! JSONDecoder().decode(Config.self, from: Data(old.utf8))
check(decodedOld.enableAnimations && decodedOld.lastGridRows == 6 && decodedOld.panelHotkey?.key == "w", "old config fills new keys with defaults")
let cleared = #"{"gridColumns":6,"gridRows":6,"showMenuIcon":true,"shortcuts":[]}"#
check(try! JSONDecoder().decode(Config.self, from: Data(cleared.utf8)).panelHotkey == nil, "cleared panel hotkey stays cleared")
let bad = #"{"gridColumns":0,"gridRows":-3,"lastGridColumns":99,"windowMarginWidth":-5,"shortcuts":[{"name":"x","columns":0,"rows":0,"startColumn":9,"startRow":-1,"endColumn":9,"endRow":9,"global":true,"enabled":true}]}"#
let fixed = try! JSONDecoder().decode(Config.self, from: Data(bad.utf8))
check(fixed.gridColumns == 1 && fixed.gridRows == 1 && fixed.lastGridColumns == 20 && fixed.windowMarginWidth == 0, "grid sizes and margins clamped")
check(fixed.shortcuts[0].columns == 1 && fixed.shortcuts[0].endColumn == 0 && fixed.shortcuts[0].startRow == 0, "shortcut selection clamped to grid")
check(config.shortcuts.isEmpty && config.panelHotkey == nil, "no shortcuts ship by default")
var custom = config
custom.shortcuts = sample
custom.panelHotkey = KeyCombo(key: "w", modifiers: ["ctrl", "cmd"])
let roundTrip = try! JSONDecoder().decode(Config.self, from: JSONEncoder().encode(custom))
check(roundTrip.shortcuts.count == 4 && roundTrip.shortcuts[3].hotkey?.display == "⌃⌘A" && !roundTrip.shortcuts[3].global
      && roundTrip.panelHotkey?.key == "w", "shortcuts round-trip through JSON")

// Keys
check(KeyCombo(key: "left", modifiers: ["ctrl", "cmd"]).display == "⌃⌘←", "display string")
check(KeyCodes.name(for: 13) == "w" && KeyCodes.code(for: "W") == 13, "key name round-trip")
let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .command], timestamp: 0, windowNumber: 0,
                             context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
check(sample[3].hotkey!.matches(event), "⌃⌘A event matches Full")
check(!sample[0].hotkey!.matches(event), "⌃⌘A does not match Left")
check(KeyCombo(event: event) == KeyCombo(key: "a", modifiers: ["ctrl", "cmd"]), "recorder builds combo from event")

// Grid hit-testing outside the view clamps to edge cells
let grid = GridView(frame: NSRect(x: 0, y: 0, width: 280, height: 196))
var committed: GridSelection?
grid.onCommit = { committed = $0 }
let window = NSWindow(contentRect: grid.frame, styleMask: .borderless, backing: .buffered, defer: true)
window.contentView = grid
func mouse(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                       context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
grid.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 5, y: 190)))      // top-left cell (window coords are unflipped)
grid.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 9999, y: -9999)))
grid.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 9999, y: -9999)))
check(committed == GridSelection(startColumn: 0, startRow: 0, endColumn: 5, endRow: 5), "drag past the edge clamps to the last cell \(String(describing: committed))")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
