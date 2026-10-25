import AppKit

/// Borderless panels refuse key status by default; Divvy needs it for Esc and in-panel shortcuts.
final class KeyPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Buttons and the shortcut recorder get first pick, then the panel's own keys.
        super.performKeyEquivalent(with: event) || keyHandler?(event) == true
    }
}

/// The front of the panel: app icon and name, the grid, close and settings buttons.
final class GridFaceView: NSView {
    static let size = NSSize(width: 320, height: 280)

    let closeButton = GlyphButton(.close)
    let settingsButton = GlyphButton(.gear)
    let grid = GridView(frame: NSRect(x: 20, y: 20, width: 280, height: 196))
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(origin: .zero, size: GridFaceView.size))
        closeButton.frame = NSRect(x: 5, y: 255, width: 20, height: 20)
        settingsButton.frame = NSRect(x: 295, y: 255, width: 20, height: 20)
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.cell?.wraps = false
        title.cell?.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        [closeButton, settingsButton, grid, icon, title].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ text: String, icon image: NSImage?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.6)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        title.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: Theme.title,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ])
        icon.image = image
        icon.isHidden = image == nil

        let iconSize: CGFloat = image == nil ? 0 : 28
        let gap: CGFloat = image == nil ? 0 : 8
        let textSize = title.attributedStringValue.size()
        let textWidth = min(ceil(textSize.width) + 4, bounds.width - 80 - iconSize - gap)
        let textHeight = ceil(textSize.height)
        let x = (bounds.width - iconSize - gap - textWidth) / 2
        let centerY: CGFloat = 245
        icon.frame = NSRect(x: x, y: centerY - iconSize / 2, width: iconSize, height: iconSize)
        title.frame = NSRect(x: x + iconSize + gap, y: centerY - textHeight / 2, width: textWidth, height: textHeight)
    }
}

final class DivvyPanelController: NSObject, NSWindowDelegate {
    private enum Face { case grid, settings }

    let model: SettingsModel
    private let panel: KeyPanel
    private let container = ContainerView()
    private let gridFace = GridFaceView()
    private var settingsFace: SettingsView?
    private let preview = PreviewWindow()
    private var face: Face = .grid
    private var shown = false

    private(set) var target: TargetWindow?
    /// The app that was frontmost when the panel opened, refocused on close when there is no target window.
    private var previousApp: NSRunningApplication?
    /// When the panel last hid itself, so a click that dismissed it doesn't immediately reopen it.
    private(set) var lastClosed = Date.distantPast
    /// The screen the panel is on; windows arranged from the panel land here.
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var columns = 6
    private var rows = 6

    var isVisible: Bool { shown }
    var onAbout: (() -> Void)?
    var onHelp: (() -> Void)?

    init(model: SettingsModel) {
        self.model = model
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: GridFaceView.size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        panel.contentView = container

        gridFace.closeButton.onAction { [weak self] _ in self?.close(refocus: true) }
        gridFace.settingsButton.onAction { [weak self] _ in self?.flip(to: .settings) }
        gridFace.grid.onSelectionChange = { [weak self] in self?.showPreview(for: $0) }
        gridFace.grid.onCommit = { [weak self] in self?.commit($0) }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    // MARK: Showing and hiding

    func show(for target: TargetWindow?, settings: Bool = false) {
        self.target = target
        if !shown, let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        loadGridSize()
        updateGrid()
        updateTitle()

        // Like Divvy, the panel opens on the screen with the mouse, and windows go to that screen.
        let mouse = NSEvent.mouseLocation
        screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? target?.screen ?? screen

        setFace(settings ? .settings : .grid, animated: false)
        let wasShown = shown
        shown = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        if !wasShown && model.config.enableAnimations {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        } else {
            panel.alphaValue = 1
        }
    }

    /// Hides the panel; when `refocus` is set, hands focus back to the window being arranged.
    func close(refocus: Bool) {
        guard shown else { return }
        shown = false
        lastClosed = Date()
        // Ends any text editing (saving it) and stops a shortcut recorder, which re-enables hotkeys.
        panel.makeFirstResponder(nil)
        preview.orderOut(nil)
        if model.config.enableAnimations {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }) { [weak self] in
                guard let self, !self.shown else { return }
                self.panel.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
        }
        if refocus { (target?.app ?? previousApp)?.activate() }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere dismisses the panel unless it is pinned open.
        if !model.config.keepPanelOpen { close(refocus: false) }
    }

    /// With "Keep panel open", the panel follows whichever app you switch to.
    @objc private func appActivated(_ note: Notification) {
        guard shown, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = WindowMover.frontmostWindow()
        else { return }
        target = window
        updateTitle()
    }

    private func setFace(_ newFace: Face, animated: Bool) {
        panel.makeFirstResponder(nil)
        face = newFace
        preview.orderOut(nil)
        let view: NSView
        switch newFace {
        case .grid:
            settingsFace = nil
            gridFace.grid.selection = nil
            view = gridFace
        case .settings:
            let settings = SettingsView(model: model)
            settings.onClose = { [weak self] in self?.close(refocus: true) }
            settings.onBack = { [weak self] in self?.flip(to: .grid) }
            settings.onAbout = { [weak self] in self?.onAbout?() }
            settings.onHelp = { [weak self] in self?.onHelp?() }
            settingsFace = settings
            view = settings
        }

        if animated {
            container.wantsLayer = true
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.2
            container.layer?.add(transition, forKey: "flip")
        }
        container.subviews.forEach { $0.removeFromSuperview() }

        let size = view.frame.size
        let center = shown ? NSPoint(x: panel.frame.midX, y: panel.frame.midY)
                           : NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        panel.setFrame(NSRect(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: true)
        view.setFrameOrigin(.zero)
        container.frame = NSRect(origin: .zero, size: size)
        container.addSubview(view)
        container.needsDisplay = true
        panel.invalidateShadow()
    }

    private func flip(to newFace: Face) {
        if newFace == .grid {
            // Grid Settings may have changed while the settings were showing.
            loadGridSize()
            updateGrid()
        }
        setFace(newFace, animated: model.config.enableAnimations)
        panel.makeKey()
    }

    private func updateTitle() {
        if let target {
            gridFace.setTitle(target.app.localizedName ?? target.title, icon: target.app.icon)
        } else {
            gridFace.setTitle(WindowMover.isTrusted ? "No Window" : "Needs Accessibility", icon: nil)
        }
    }

    private func loadGridSize() {
        let config = model.config
        columns = config.useDefaultGridOnActivation ? config.gridColumns : config.lastGridColumns
        rows = config.useDefaultGridOnActivation ? config.gridRows : config.lastGridRows
    }

    private func updateGrid() {
        gridFace.grid.columns = columns
        gridFace.grid.rows = rows
        gridFace.grid.selection = nil
    }

    // MARK: Arranging

    func apply(_ shortcut: Shortcut) {
        guard let target else { return NSSound.beep() }
        WindowMover.apply(shortcut, to: target, on: screen, margins: model.config.margins)
        finishArranging()
    }

    private func rect(for selection: GridSelection) -> CGRect {
        WindowMover.rect(for: selection, columns: columns, rows: rows, on: screen, margins: model.config.margins)
    }

    private func showPreview(for selection: GridSelection?) {
        guard model.config.showResizePreview, let selection, target != nil else {
            preview.orderOut(nil)
            return
        }
        preview.setFrame(rect(for: selection), display: true)
        preview.orderFront(nil)
        panel.orderFront(nil)
    }

    private func commit(_ selection: GridSelection) {
        guard let target else {
            gridFace.grid.selection = nil
            if !WindowMover.isTrusted { WindowMover.promptForAccess() } else { NSSound.beep() }
            return
        }
        target.setFrame(WindowMover.flip(rect(for: selection)))
        finishArranging()
    }

    private func finishArranging() {
        preview.orderOut(nil)
        if model.config.keepPanelOpen {
            gridFace.grid.selection = nil
            target?.app.activate()
        } else {
            close(refocus: true)
        }
    }

    /// Divvy's in-panel keys: ⌘+/⌘− rows, ⌘⇧+/⌘⇧− columns, ⌘, settings, Esc closes.
    private func changeGrid(rows dr: Int, columns dc: Int) {
        rows = max(1, min(20, rows + dr))
        columns = max(1, min(20, columns + dc))
        updateGrid()
        let (r, c) = (rows, columns)
        model.update { $0.lastGridRows = r; $0.lastGridColumns = c }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.keyCode == 53 && mods.isEmpty { // Escape
            close(refocus: true)
            return true
        }
        if event.keyCode == 43 && mods == .command { // ⌘,
            flip(to: face == .grid ? .settings : .grid)
            return true
        }
        guard face == .grid else { return false }

        let plus = event.keyCode == 24 || event.keyCode == 69   // = / keypad +
        let minus = event.keyCode == 27 || event.keyCode == 78  // - / keypad -
        if (plus || minus) && (mods == .command || mods == [.command, .shift]) {
            let delta = plus ? 1 : -1
            if mods.contains(.shift) { changeGrid(rows: 0, columns: delta) } else { changeGrid(rows: delta, columns: 0) }
            return true
        }
        if let shortcut = model.config.shortcuts.first(where: { $0.enabled && ($0.hotkey?.matches(event) ?? false) }) {
            apply(shortcut)
            return true
        }
        return false
    }
}
