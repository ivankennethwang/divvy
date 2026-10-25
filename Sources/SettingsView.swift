import AppKit
import ServiceManagement

/// The back of the panel: General / Appearance / Shortcuts, laid out with the frames from Divvy's
/// Preferences.nib (origin at the bottom-left of each parent).
final class SettingsView: NSView {
    static let size = NSSize(width: 380, height: 335)

    enum Tab: Int { case general, appearance, shortcuts }

    private let model: SettingsModel
    var onClose: (() -> Void)?
    var onBack: (() -> Void)?
    var onAbout: (() -> Void)?
    var onHelp: (() -> Void)?

    private let closeButton = GlyphButton(.close)
    private let backButton = GlyphButton(.back)
    private let tabBar = TabBar(titles: ["General", "Appearance", "Shortcuts"], selected: 0)
    private var page: NSView?
    private(set) var tab: Tab = .general
    private var selectedShortcut: Int?

    init(model: SettingsModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: SettingsView.size))

        closeButton.frame = NSRect(x: 5, y: 310, width: 20, height: 20)
        closeButton.onAction { [weak self] _ in self?.onClose?() }
        backButton.frame = NSRect(x: 355, y: 310, width: 20, height: 20)
        backButton.onAction { [weak self] _ in self?.onBack?() }
        tabBar.frame = NSRect(x: 59, y: 306, width: 263, height: 24)
        tabBar.onSelect = { [weak self] in self?.show(Tab(rawValue: $0) ?? .general) }
        [closeButton, backButton, tabBar].forEach(addSubview)
        show(.general)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ tab: Tab) {
        self.tab = tab
        tabBar.selected = tab.rawValue
        tabBar.isHidden = false
        backButton.isHidden = false
        switch tab {
        case .general: setPage(generalPage())
        case .appearance: setPage(appearancePage())
        case .shortcuts: setPage(shortcutsPage())
        }
    }

    /// Swaps the area under the tab bar.
    private func setPage(_ newPage: NSView) {
        // Commit edits and stop any recorder on the outgoing page before it disappears.
        window?.makeFirstResponder(nil)
        page?.removeFromSuperview()
        page = newPage
        addSubview(newPage)
    }

    /// The TabView-sized page with Divvy's outlined box; `content` is the box interior (332 x 268).
    private func makePage() -> (page: NSView, content: NSView) {
        let page = NSView(frame: NSRect(x: 3, y: 0, width: 374, height: 305))
        let box = BoxView(frame: NSRect(x: 20, y: 35, width: 334, height: 270))
        let content = NSView(frame: NSRect(x: 1, y: 1, width: 332, height: 268))
        box.addSubview(content)
        page.addSubview(box)
        return (page, content)
    }

    private func button(_ title: String, x: CGFloat, in page: NSView, key: String = "",
                        _ handler: @escaping () -> Void) -> HUDButton {
        let button = HUDButton(title, keyEquivalent: key)
        button.frame = NSRect(x: x, y: 9, width: 75, height: 19)
        button.onAction { _ in handler() }
        page.addSubview(button)
        return button
    }

    // MARK: General

    private func generalPage() -> NSView {
        let (page, c) = makePage()
        let config = model.config

        var loginBox: NSButton?
        loginBox = UI.checkbox("Start Divvy at login", NSRect(x: 6, y: 237, width: 300, height: 18),
                               on: SettingsView.launchesAtLogin) { on in
            SettingsView.setLaunchAtLogin(on)
            loginBox?.state = SettingsView.launchesAtLogin ? .on : .off
        }
        c.addSubview(loginBox!)
        c.addSubview(UI.checkbox("Show Divvy in the menu bar", NSRect(x: 6, y: 217, width: 300, height: 18),
                                 on: config.showMenuIcon) { [model] on in model.update { $0.showMenuIcon = on } })
        c.addSubview(UI.checkbox("Keep panel open until dismissed", NSRect(x: 6, y: 197, width: 300, height: 18),
                                 on: config.keepPanelOpen) { [model] on in model.update { $0.keepPanelOpen = on } })
        c.addSubview(UI.checkbox("Cycle between screens when using shortcuts", NSRect(x: 6, y: 177, width: 320, height: 18),
                                 on: config.cycleScreens) { [model] on in model.update { $0.cycleScreens = on } })

        c.addSubview(UI.checkbox("Use global shortcut to display panel", NSRect(x: 6, y: 90, width: 300, height: 18),
                                 on: config.useGlobalHotkey) { [model] on in model.update { $0.useGlobalHotkey = on } })
        let recorder = ShortcutRecorder(frame: NSRect(x: 74, y: 62, width: 182, height: 22))
        recorder.combo = config.panelHotkey
        recorder.onChange = { [model] combo in model.update { $0.panelHotkey = combo } }
        c.addSubview(recorder)

        _ = button("About", x: 20, in: page) { [weak self] in self?.onAbout?() }
        _ = button("Help", x: 150, in: page) { [weak self] in self?.onHelp?() }
        _ = button("Quit", x: 279, in: page) { NSApp.terminate(nil) }
        return page
    }

    private static var launchesAtLogin: Bool {
        [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
    }

    private static func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Divvy: launch at login: \(error)")
            NSSound.beep()
        }
        // macOS may ask the user to allow the login item before it takes effect.
        if on && SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: Appearance

    private func appearancePage() -> NSView {
        let (page, c) = makePage()
        let config = model.config

        c.addSubview(UI.checkbox("Enable animations", NSRect(x: 13, y: 237, width: 150, height: 18),
                                 on: config.enableAnimations) { [model] on in model.update { $0.enableAnimations = on } })
        c.addSubview(UI.checkbox("Show resize preview", NSRect(x: 169, y: 237, width: 155, height: 18),
                                 on: config.showResizePreview) { [model] on in model.update { $0.showResizePreview = on } })

        let margins = BoxView(frame: NSRect(x: 12, y: 93, width: 308, height: 133))
        c.addSubview(margins)
        margins.addSubview(UI.label("Margin Settings", NSRect(x: 8, y: 110, width: 110, height: 17), bold: true))
        var marginControls: [NSControl] = []
        margins.addSubview(UI.checkbox("Enable margins", NSRect(x: 186, y: 108, width: 118, height: 18),
                                       on: config.enableMargins, size: 12) { [model] on in
            model.update { $0.enableMargins = on }
            marginControls.forEach { $0.isEnabled = on }
        })
        margins.addSubview(UI.label("Window:", NSRect(x: 13, y: 82, width: 60, height: 14), size: 11))
        margins.addSubview(UI.label("width:", NSRect(x: 81, y: 82, width: 40, height: 14), size: 11))
        margins.addSubview(UI.label("height:", NSRect(x: 189, y: 82, width: 49, height: 14), size: 11))
        margins.addSubview(UI.label("Screen Edges:", NSRect(x: 13, y: 32, width: 80, height: 14), size: 11))
        margins.addSubview(UI.label("left:", NSRect(x: 93, y: 46, width: 28, height: 14), size: 11))
        margins.addSubview(UI.label("right:", NSRect(x: 200, y: 46, width: 36, height: 14), size: 11))
        margins.addSubview(UI.label("top:", NSRect(x: 93, y: 20, width: 28, height: 14), size: 11))
        margins.addSubview(UI.label("bottom:", NSRect(x: 186, y: 20, width: 48, height: 14), size: 11))

        let marginFields: [(Int, NSPoint, WritableKeyPath<Config, Int>)] = [
            (config.windowMarginWidth, NSPoint(x: 123, y: 79), \.windowMarginWidth),
            (config.windowMarginHeight, NSPoint(x: 237, y: 79), \.windowMarginHeight),
            (config.screenMarginLeft, NSPoint(x: 123, y: 43), \.screenMarginLeft),
            (config.screenMarginRight, NSPoint(x: 237, y: 43), \.screenMarginRight),
            (config.screenMarginTop, NSPoint(x: 123, y: 17), \.screenMarginTop),
            (config.screenMarginBottom, NSPoint(x: 237, y: 16), \.screenMarginBottom),
        ]
        for (value, origin, keyPath) in marginFields {
            marginControls += UI.stepper(value: value, range: 0...200,
                       field: NSRect(x: origin.x, y: origin.y, width: 34, height: 22),
                       stepper: NSRect(x: origin.x + 38, y: origin.y - 2, width: 19, height: 27),
                       in: margins) { [model] v in model.update { $0[keyPath: keyPath] = v } }
        }
        marginControls.forEach { $0.isEnabled = config.enableMargins }

        let grid = BoxView(frame: NSRect(x: 12, y: 15, width: 308, height: 70))
        c.addSubview(grid)
        grid.addSubview(UI.label("Grid Settings", NSRect(x: 8, y: 47, width: 100, height: 17), bold: true))
        var gridControls: [NSControl] = []
        grid.addSubview(UI.checkbox("Use these settings on activation", NSRect(x: 100, y: 45, width: 204, height: 18),
                                    on: config.useDefaultGridOnActivation, size: 12) { [model] on in
            model.update { $0.useDefaultGridOnActivation = on }
            gridControls.forEach { $0.isEnabled = on }
        })
        grid.addSubview(UI.label("Rows:", NSRect(x: 32, y: 18, width: 41, height: 17)))
        grid.addSubview(UI.label("Columns:", NSRect(x: 159, y: 18, width: 64, height: 17)))
        gridControls += UI.stepper(value: config.gridRows, range: 1...20,
                   field: NSRect(x: 78, y: 16, width: 27, height: 22), stepper: NSRect(x: 111, y: 14, width: 19, height: 27),
                   in: grid) { [model] v in model.update { $0.gridRows = v; $0.lastGridRows = v } }
        gridControls += UI.stepper(value: config.gridColumns, range: 1...20,
                   field: NSRect(x: 228, y: 16, width: 27, height: 22), stepper: NSRect(x: 260, y: 14, width: 19, height: 27),
                   in: grid) { [model] v in model.update { $0.gridColumns = v; $0.lastGridColumns = v } }
        gridControls.forEach { $0.isEnabled = config.useDefaultGridOnActivation }
        return page
    }

    // MARK: Shortcuts

    private func shortcutsPage() -> NSView {
        let (page, c) = makePage()
        let list = ShortcutListView(shortcuts: model.config.shortcuts, width: c.bounds.width - 15)
        list.selectedIndex = selectedShortcut
        list.onOpen = { [weak self] in self?.edit(index: $0) }

        let scroll = NSScrollView(frame: c.bounds.insetBy(dx: 0, dy: 2))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.documentView = list
        c.addSubview(scroll)

        let delete = button("Delete", x: 19, in: page) { [weak self] in
            guard let self, let index = self.selectedShortcut, index < self.model.config.shortcuts.count else { return }
            self.model.update { $0.shortcuts.remove(at: index) }
            self.selectedShortcut = nil
            self.show(.shortcuts)
        }
        delete.isEnabled = selectedShortcut != nil
        list.onSelect = { [weak self] index in
            self?.selectedShortcut = index
            delete.isEnabled = index != nil
            delete.needsDisplay = true
        }
        _ = button("New", x: 279, in: page) { [weak self] in self?.edit(index: nil) }
        return page
    }

    /// The shortcut editor: name, key combination, cells, and Enable / Global switches.
    func edit(index: Int?) {
        let config = model.config
        var draft = index.map { config.shortcuts[$0] } ?? Shortcut(
            name: "", columns: config.lastGridColumns, rows: config.lastGridRows,
            startColumn: 0, startRow: 0, endColumn: config.lastGridColumns - 1, endRow: config.lastGridRows - 1,
            hotkey: nil, global: true, enabled: true)

        tabBar.isHidden = true
        backButton.isHidden = true
        let (page, c) = makePage()

        let name = PillTextField(frame: NSRect(x: 15, y: 239, width: 144, height: 22))
        name.stringValue = draft.name
        name.field.placeholderString = "Shortcut Name"
        c.addSubview(name)

        let recorder = ShortcutRecorder(frame: NSRect(x: 173, y: 239, width: 144, height: 22))
        recorder.combo = draft.hotkey
        recorder.onChange = { draft.hotkey = $0 }
        c.addSubview(recorder)

        let grid = GridView(frame: NSRect(x: 27, y: 35, width: 278, height: 196))
        grid.columns = draft.columns
        grid.rows = draft.rows
        grid.selection = draft.selection
        grid.onCommit = { draft.selection = $0 }
        c.addSubview(grid)

        c.addSubview(UI.checkbox("Enable Shortcut", NSRect(x: 27, y: 9, width: 140, height: 18), on: draft.enabled) {
            draft.enabled = $0
        })
        c.addSubview(UI.checkbox("Global Shortcut", NSRect(x: 185, y: 9, width: 140, height: 18), on: draft.global) {
            draft.global = $0
        })

        _ = button("Cancel", x: 20, in: page, key: "\u{1b}") { [weak self] in self?.show(.shortcuts) }
        _ = button("Accept", x: 279, in: page, key: "\r") { [weak self] in
            guard let self else { return }
            draft.name = name.stringValue
            self.model.update { config in
                if let index { config.shortcuts[index] = draft } else { config.shortcuts.append(draft) }
            }
            self.selectedShortcut = index ?? self.model.config.shortcuts.count - 1
            self.show(.shortcuts)
        }
        setPage(page)
        window?.makeFirstResponder(name.field)
    }
}

/// Rows of shortcuts with their key combination and a thumbnail of their cells.
final class ShortcutListView: NSView {
    static let rowHeight: CGFloat = 64

    var selectedIndex: Int? { didSet { needsDisplay = true } }
    var onSelect: ((Int?) -> Void)?
    var onOpen: ((Int) -> Void)?

    private let count: Int

    init(shortcuts: [Shortcut], width: CGFloat) {
        count = shortcuts.count
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: max(1, CGFloat(shortcuts.count) * Self.rowHeight)))
        for (i, shortcut) in shortcuts.enumerated() {
            let top = CGFloat(i) * Self.rowHeight
            let name = UI.label(shortcut.name.isEmpty ? " " : shortcut.name,
                                NSRect(x: 8, y: top + 8, width: width - 100, height: 22), size: 16, bold: true)
            addSubview(name)
            let combo = UI.label(shortcut.hotkey?.display ?? "", NSRect(x: 8, y: top + 34, width: 80, height: 18))
            addSubview(combo)
            if shortcut.global {
                addSubview(UI.label("(global)", NSRect(x: 90, y: top + 34, width: 80, height: 18)))
            }
            if !shortcut.enabled {
                [name, combo].forEach { $0.textColor = NSColor(white: 1, alpha: 0.4) }
            }
            let thumb = GridView(frame: NSRect(x: width - 78, y: top + 7, width: 66, height: 50))
            thumb.mini = true
            thumb.spacing = 1
            thumb.isInteractive = false
            thumb.columns = shortcut.columns
            thumb.rows = shortcut.rows
            thumb.selection = shortcut.selection
            addSubview(thumb)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let index = selectedIndex else { return }
        NSColor(calibratedWhite: 1, alpha: 0.15).setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: CGFloat(index) * Self.rowHeight + 2,
                                         width: bounds.width - 4, height: Self.rowHeight - 4),
                     xRadius: 4, yRadius: 4).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        let index = Int(y / Self.rowHeight)
        let hit = index < count ? index : nil
        selectedIndex = hit
        onSelect?(hit)
        if event.clickCount == 2, let hit { onOpen?(hit) }
    }
}
