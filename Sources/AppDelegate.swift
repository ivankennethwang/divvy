import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SettingsModel(config: Config.load())
    private var statusItem: NSStatusItem?
    private lazy var panel = DivvyPanelController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainMenu()
        setUpStatusItem()
        model.onChange = { [weak self] config in
            config.save()
            self?.statusItem?.isVisible = config.showMenuIcon
            self?.registerHotKeys()
        }
        panel.onAbout = { [weak self] in self?.showAbout() }
        panel.onHelp = { [weak self] in self?.showHelp() }
        ShortcutRecorder.recordingChanged = { [weak self] recording in
            if recording { HotKeyCenter.shared.unregisterAll() } else { self?.registerHotKeys() }
        }
        registerHotKeys()
        if !WindowMover.isTrusted { WindowMover.promptForAccess() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again shows the settings, which is the way back if the menu icon is hidden.
        panel.show(for: WindowMover.frontmostWindow(), settings: true)
        return false
    }

    // MARK: Menus

    /// Accessory apps have no visible menu bar, but its key equivalents still drive copy/paste in text fields.
    private func setUpMainMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Divvy")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.isVisible = model.config.showMenuIcon
        statusItem = item
    }

    /// Like Divvy, clicking the menu bar icon opens the grid for the frontmost window.
    /// Right-click (or ⌃-click) opens settings instead.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsSettings = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if panel.isVisible {
            panel.close(refocus: true)
        } else if Date().timeIntervalSince(panel.lastClosed) > 0.3 {
            panel.show(for: WindowMover.frontmostWindow(), settings: wantsSettings)
        }
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        let hotKeys = HotKeyCenter.shared
        hotKeys.unregisterAll()
        let config = model.config
        if config.useGlobalHotkey, let combo = config.panelHotkey {
            hotKeys.register(combo) { [weak self] in self?.togglePanel() }
        }
        for shortcut in config.shortcuts where shortcut.enabled && shortcut.global {
            guard let combo = shortcut.hotkey else { continue }
            hotKeys.register(combo) { [weak self] in self?.apply(shortcut) }
        }
    }

    private func togglePanel() {
        if panel.isVisible {
            panel.close(refocus: true)
        } else if ensureAccess() {
            panel.show(for: WindowMover.frontmostWindow())
        }
    }

    private func apply(_ shortcut: Shortcut) {
        if panel.isVisible {
            panel.apply(shortcut)
            return
        }
        guard ensureAccess(), let window = WindowMover.frontmostWindow() else { return }
        let config = model.config
        var screen = window.screen
        // Pressing a shortcut again on a window already in place moves it to the next display.
        if config.cycleScreens, NSScreen.screens.count > 1, let frame = window.frame {
            let here = WindowMover.flip(WindowMover.rect(for: shortcut.selection, columns: shortcut.columns,
                                                         rows: shortcut.rows, on: screen, margins: config.margins))
            if abs(frame.minX - here.minX) < 3, abs(frame.minY - here.minY) < 3,
               abs(frame.width - here.width) < 3, abs(frame.height - here.height) < 3 {
                screen = WindowMover.nextScreen(after: screen)
            }
        }
        WindowMover.apply(shortcut, to: window, on: screen, margins: config.margins)
    }

    private func ensureAccess() -> Bool {
        if WindowMover.isTrusted { return true }
        WindowMover.promptForAccess()
        return false
    }

    // MARK: About and Help

    private func showAbout() {
        panel.close(refocus: false)
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Divvy Native",
            .credits: NSAttributedString(string: "A native Apple Silicon rebuild of Mizage's Divvy window manager."),
        ])
    }

    private func showHelp() {
        panel.close(refocus: false)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Using Divvy"
        alert.informativeText = """
        Open the panel from the menu bar icon or your global shortcut, then drag across the grid to size the \
        frontmost window. The window moves to the screen the panel is on.

        In the panel:
        ⌘+ / ⌘−  add or remove a row
        ⌘⇧+ / ⌘⇧−  add or remove a column
        ⌘,  settings
        Esc  close

        Settings are saved to:
        \(Config.fileURL.path)
        """
        alert.runModal()
    }
}
