import AppKit
import Carbon

/// A key plus modifiers, written in config.json as e.g. {"key": "left", "modifiers": ["ctrl", "cmd"]}.
struct KeyCombo: Codable, Equatable {
    var key: String
    var modifiers: [String]

    var keyCode: UInt32? { KeyCodes.code(for: key) }

    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        for m in modifiers {
            switch m.lowercased() {
            case "cmd", "command": mask |= UInt32(cmdKey)
            case "shift": mask |= UInt32(shiftKey)
            case "opt", "option", "alt": mask |= UInt32(optionKey)
            case "ctrl", "control": mask |= UInt32(controlKey)
            default: break
            }
        }
        return mask
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        let mask = carbonModifiers
        if mask & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if mask & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if mask & UInt32(optionKey) != 0 { flags.insert(.option) }
        if mask & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// Human-readable form, e.g. "⌃⌘←".
    var display: String {
        let mask = carbonModifiers
        var s = ""
        if mask & UInt32(controlKey) != 0 { s += "⌃" }
        if mask & UInt32(optionKey) != 0 { s += "⌥" }
        if mask & UInt32(shiftKey) != 0 { s += "⇧" }
        if mask & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyCodes.symbol(for: key)
    }

    /// Builds a combo from a key press, or nil for keys we have no name for.
    init?(event: NSEvent) {
        guard let name = KeyCodes.name(for: UInt32(event.keyCode)) else { return nil }
        let flags = event.modifierFlags
        var modifiers: [String] = []
        if flags.contains(.control) { modifiers.append("ctrl") }
        if flags.contains(.option) { modifiers.append("opt") }
        if flags.contains(.shift) { modifiers.append("shift") }
        if flags.contains(.command) { modifiers.append("cmd") }
        self.init(key: name, modifiers: modifiers)
    }

    init(key: String, modifiers: [String]) {
        self.key = key
        self.modifiers = modifiers
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let code = keyCode, UInt32(event.keyCode) == code else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return event.modifierFlags.intersection(relevant) == cocoaModifiers
    }
}

/// A saved window position: a selection of cells on a columns x rows grid (row 0 is the top).
struct Shortcut: Codable {
    var name: String
    var columns: Int
    var rows: Int
    var startColumn: Int
    var startRow: Int
    var endColumn: Int
    var endRow: Int
    var hotkey: KeyCombo?
    /// Global shortcuts work anywhere; non-global ones only while the Divvy panel is open.
    var global: Bool
    var enabled: Bool

    var selection: GridSelection {
        get { GridSelection(startColumn: startColumn, startRow: startRow, endColumn: endColumn, endRow: endRow) }
        set {
            startColumn = newValue.startColumn
            startRow = newValue.startRow
            endColumn = newValue.endColumn
            endRow = newValue.endRow
        }
    }
}

/// Gaps applied around resized windows when margins are enabled.
struct Margins {
    var left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat
    /// Space between neighbouring windows.
    var windowWidth: CGFloat, windowHeight: CGFloat
}

struct Config: Codable {
    /// Grid size from Appearance > Grid Settings.
    var gridColumns = 6
    var gridRows = 6
    /// Grid size the panel last used; it reopens with this unless `useDefaultGridOnActivation` is set.
    var lastGridColumns = 6
    var lastGridRows = 6
    var useDefaultGridOnActivation = false

    /// No shortcuts ship by default, as in the original Divvy; users record their own in Settings.
    var panelHotkey: KeyCombo?
    var useGlobalHotkey = true
    var showMenuIcon = true
    var keepPanelOpen = false
    var cycleScreens = false

    var enableAnimations = true
    var showResizePreview = true
    var enableMargins = false
    var windowMarginWidth = 10
    var windowMarginHeight = 10
    var screenMarginLeft = 10
    var screenMarginRight = 10
    var screenMarginTop = 10
    var screenMarginBottom = 10

    var shortcuts: [Shortcut] = []

    var margins: Margins? {
        guard enableMargins else { return nil }
        return Margins(left: CGFloat(screenMarginLeft), right: CGFloat(screenMarginRight),
                       top: CGFloat(screenMarginTop), bottom: CGFloat(screenMarginBottom),
                       windowWidth: CGFloat(windowMarginWidth), windowHeight: CGFloat(windowMarginHeight))
    }

    init() {}

    /// Missing keys fall back to defaults, so older config files keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        gridColumns = value(.gridColumns, d.gridColumns)
        gridRows = value(.gridRows, d.gridRows)
        lastGridColumns = value(.lastGridColumns, gridColumns)
        lastGridRows = value(.lastGridRows, gridRows)
        useDefaultGridOnActivation = value(.useDefaultGridOnActivation, d.useDefaultGridOnActivation)
        panelHotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .panelHotkey)) ?? nil
        useGlobalHotkey = value(.useGlobalHotkey, d.useGlobalHotkey)
        showMenuIcon = value(.showMenuIcon, d.showMenuIcon)
        keepPanelOpen = value(.keepPanelOpen, d.keepPanelOpen)
        cycleScreens = value(.cycleScreens, d.cycleScreens)
        enableAnimations = value(.enableAnimations, d.enableAnimations)
        showResizePreview = value(.showResizePreview, d.showResizePreview)
        enableMargins = value(.enableMargins, d.enableMargins)
        windowMarginWidth = value(.windowMarginWidth, d.windowMarginWidth)
        windowMarginHeight = value(.windowMarginHeight, d.windowMarginHeight)
        screenMarginLeft = value(.screenMarginLeft, d.screenMarginLeft)
        screenMarginRight = value(.screenMarginRight, d.screenMarginRight)
        screenMarginTop = value(.screenMarginTop, d.screenMarginTop)
        screenMarginBottom = value(.screenMarginBottom, d.screenMarginBottom)
        shortcuts = value(.shortcuts, d.shortcuts)
        sanitize()
    }

    static let gridRange = 1...20

    /// Clamps hand-edited values so a bad config can't divide by zero or select cells off the grid.
    private mutating func sanitize() {
        func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { min(r.upperBound, max(r.lowerBound, v)) }
        gridColumns = clamp(gridColumns, Config.gridRange)
        gridRows = clamp(gridRows, Config.gridRange)
        lastGridColumns = clamp(lastGridColumns, Config.gridRange)
        lastGridRows = clamp(lastGridRows, Config.gridRange)
        for keyPath: WritableKeyPath<Config, Int> in [\.windowMarginWidth, \.windowMarginHeight, \.screenMarginLeft,
                                                     \.screenMarginRight, \.screenMarginTop, \.screenMarginBottom] {
            self[keyPath: keyPath] = clamp(self[keyPath: keyPath], 0...200)
        }
        for i in shortcuts.indices {
            var s = shortcuts[i]
            s.columns = clamp(s.columns, Config.gridRange)
            s.rows = clamp(s.rows, Config.gridRange)
            s.startColumn = clamp(s.startColumn, 0...(s.columns - 1))
            s.endColumn = clamp(s.endColumn, 0...(s.columns - 1))
            s.startRow = clamp(s.startRow, 0...(s.rows - 1))
            s.endRow = clamp(s.endRow, 0...(s.rows - 1))
            shortcuts[i] = s
        }
    }

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Divvy Native", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }

    /// Loads config.json, writing the defaults first if it does not exist yet.
    static func load() -> Config {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let config = Config()
            config.save()
            return config
        }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            // Keep the unreadable file so the next save doesn't silently discard the user's edits.
            let backup = url.appendingPathExtension("invalid")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            NSLog("Divvy: could not read \(url.path): \(error); using defaults, saved a copy to \(backup.path)")
            return Config()
        }
    }

    func save() {
        let url = Config.fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: url)
        } catch {
            NSLog("Divvy: could not write \(url.path): \(error)")
        }
    }
}

/// Shared, observable settings: the panel edits them and the app delegate persists and applies them.
final class SettingsModel {
    private(set) var config: Config
    var onChange: ((Config) -> Void)?

    init(config: Config) { self.config = config }

    func update(_ change: (inout Config) -> Void) {
        change(&config)
        onChange?(config)
    }
}

enum KeyCodes {
    private static let table: [String: UInt32] = {
        var t: [String: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
            "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
            "delete": 51, "escape": 53,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "keypad+": 69, "keypad-": 78,
        ]
        let fkeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fkeys.enumerated() { t["f\(i + 1)"] = code }
        return t
    }()

    private static let names: [UInt32: String] = Dictionary(table.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

    static func code(for key: String) -> UInt32? { table[key.lowercased()] }

    static func name(for code: UInt32) -> String? { names[code] }

    static func symbol(for key: String) -> String {
        switch key.lowercased() {
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "return": return "↩"
        case "space": return "Space"
        case "tab": return "⇥"
        case "delete": return "⌫"
        case "escape": return "⎋"
        case "home": return "↖"
        case "end": return "↘"
        case "pageup": return "⇞"
        case "pagedown": return "⇟"
        case "keypad+": return "+"
        case "keypad-": return "−"
        default: return key.uppercased()
        }
    }
}
