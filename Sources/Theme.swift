import AppKit

/// Colors and metrics recovered from Divvy 1.5.2's drawing code and default preferences.
enum Theme {
    static let panelFill = NSColor(calibratedWhite: 0, alpha: 0.6)
    static let panelRim = NSColor(calibratedWhite: 1, alpha: 0.25)
    static let panelInnerLine = NSColor(calibratedWhite: 0, alpha: 0.85)

    static let cellFill = NSColor(calibratedWhite: 0, alpha: 0.3)
    static let cellSelected = NSColor(calibratedWhite: 1, alpha: 0.25)
    static let cellBorderLight = NSColor(calibratedWhite: 1, alpha: 0.45)
    static let cellBorderDark = NSColor(calibratedWhite: 0, alpha: 0.35)
    static let miniUnselected = NSColor.black

    static let previewFill = NSColor(calibratedRed: 0.3843, green: 0.6196, blue: 1, alpha: 0.35)
    static let previewStroke = NSColor(calibratedWhite: 1, alpha: 0.55)

    static let title = NSColor(calibratedWhite: 0.8, alpha: 1)
    static let boxBorder = NSColor(calibratedWhite: 0.73, alpha: 0.42)
    static let chrome = NSColor(calibratedWhite: 0.75, alpha: 1)

    static let radius: CGFloat = 8
    static let smallRadius: CGFloat = 2
}

/// The translucent black rounded panel with a light rim and a dark inner line.
final class ContainerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rim = bounds.insetBy(dx: 2, dy: 2)
        let inner = bounds.insetBy(dx: 2.5, dy: 2.5)
        Theme.panelFill.setFill()
        NSBezierPath(roundedRect: inner, xRadius: Theme.radius, yRadius: Theme.radius).fill()

        let rimPath = NSBezierPath(roundedRect: rim, xRadius: Theme.radius, yRadius: Theme.radius)
        rimPath.lineWidth = 3
        Theme.panelRim.setStroke()
        rimPath.stroke()

        let innerPath = NSBezierPath(roundedRect: inner, xRadius: Theme.radius, yRadius: Theme.radius)
        innerPath.lineWidth = 1
        Theme.panelInnerLine.setStroke()
        innerPath.stroke()
    }
}

/// The small grey glyph buttons in the panel corners.
final class GlyphButton: NSButton {
    enum Glyph { case close, gear, back }

    let glyph: Glyph

    init(_ glyph: Glyph) {
        self.glyph = glyph
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let color = isHighlighted ? NSColor(calibratedWhite: 0.55, alpha: 1) : Theme.chrome
        let box = bounds.insetBy(dx: 1, dy: 1)
        switch glyph {
        case .close:
            color.setFill()
            NSBezierPath(ovalIn: box.insetBy(dx: 1.5, dy: 1.5)).fill()
            let cross = NSBezierPath()
            let c = box.insetBy(dx: 6, dy: 6)
            cross.move(to: NSPoint(x: c.minX, y: c.minY))
            cross.line(to: NSPoint(x: c.maxX, y: c.maxY))
            cross.move(to: NSPoint(x: c.minX, y: c.maxY))
            cross.line(to: NSPoint(x: c.maxX, y: c.minY))
            cross.lineWidth = 2
            cross.lineCapStyle = .round
            NSColor.white.setStroke()
            cross.stroke()
        case .gear, .back:
            let name = glyph == .gear ? "gearshape.fill" : "arrowshape.turn.up.left.fill"
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                .applying(.init(paletteColors: [color]))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return }
            let size = image.size
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }
}

/// Divvy's dark pill-shaped HUD push button.
final class HUDButton: NSButton {
    init(_ title: String, keyEquivalent: String = "") {
        super.init(frame: NSRect(x: 0, y: 0, width: 75, height: 19))
        self.title = title
        self.keyEquivalent = keyEquivalent
        isBordered = false
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        let top = NSColor(calibratedWhite: isHighlighted ? 0.5 : 0.35, alpha: 0.85)
        let bottom = NSColor(calibratedWhite: isHighlighted ? 0.35 : 0.1, alpha: 0.85)
        NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: isFlipped ? 90 : -90)
        NSColor(calibratedWhite: 1, alpha: 0.6).setStroke()
        path.lineWidth = 1
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isEnabled ? NSColor.white : NSColor(white: 1, alpha: 0.4),
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }
}

/// The General / Appearance / Shortcuts segmented control.
final class TabBar: NSView {
    let titles: [String]
    var selected: Int { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?

    init(titles: [String], selected: Int) {
        self.titles = titles
        self.selected = selected
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var segmentWidth: CGFloat { bounds.width / CGFloat(titles.count) }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 2.5)
        let outline = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        NSGradient(starting: NSColor(calibratedWhite: 0.3, alpha: 0.85),
                   ending: NSColor(calibratedWhite: 0.1, alpha: 0.85))?.draw(in: outline, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        let selectedRect = NSRect(x: CGFloat(selected) * segmentWidth, y: r.minY, width: segmentWidth, height: r.height)
        NSGradient(starting: NSColor(calibratedWhite: 0.6, alpha: 0.85),
                   ending: NSColor(calibratedWhite: 0.4, alpha: 0.85))?.draw(in: selectedRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 1, alpha: 0.5).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        for i in 1..<titles.count {
            let x = (CGFloat(i) * segmentWidth).rounded() + 0.5
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: r.minY), to: NSPoint(x: x, y: r.maxY))
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white]
        for (i, title) in titles.enumerated() {
            let text = NSAttributedString(string: title, attributes: attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: CGFloat(i) * segmentWidth + (segmentWidth - size.width) / 2,
                                  y: r.midY - size.height / 2))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let index = max(0, min(titles.count - 1, Int(x / segmentWidth)))
        guard index != selected else { return }
        selected = index
        onSelect?(index)
    }
}

/// Divvy's light checkbox with a white label, which modern AppKit no longer draws on dark panels.
final class HUDCheckbox: NSButton {
    init(title: String, size: CGFloat) {
        super.init(frame: .zero)
        setButtonType(.switch)
        isBordered = false
        self.title = title
        font = .systemFont(ofSize: size)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isEnabled ? 1 : 0.45
        let box = NSRect(x: 2.5, y: ((bounds.height - 14) / 2).rounded() + 0.5, width: 14, height: 14)
        let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
        if state == .on {
            NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
            path.fill()
            // Points measured with y pointing up; mirror them when the view is flipped.
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: box.minX + x * box.width, y: isFlipped ? box.maxY - y * box.height : box.minY + y * box.height)
            }
            let check = NSBezierPath()
            check.move(to: point(0.24, 0.52))
            check.line(to: point(0.42, 0.3))
            check.line(to: point(0.76, 0.74))
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(alpha).setStroke()
            check.stroke()
        } else {
            NSColor(calibratedWhite: isHighlighted ? 0.8 : 1, alpha: alpha).setFill()
            path.fill()
            NSColor(calibratedWhite: 0.55, alpha: alpha).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        let text = NSAttributedString(string: title, attributes: [
            .font: font ?? .systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: box.maxX + 6, y: bounds.midY - size.height / 2))
    }
}

/// A rounded outline grouping settings, like Divvy's NSBox panels.
final class BoxView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        Theme.boxBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// A white pill containing a borderless text field (Divvy's shortcut name field).
final class PillTextField: NSView {
    let field = NSTextField()

    var stringValue: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = frame.height / 2
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .systemFont(ofSize: 13)
        field.textColor = .black
        field.appearance = NSAppearance(named: .aqua)
        field.frame = NSRect(x: 10, y: (frame.height - 17) / 2, width: frame.width - 20, height: 17)
        field.autoresizingMask = [.width]
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Click, then press a key combination to record it. The ⓧ clears it.
final class ShortcutRecorder: NSView {
    /// Global hotkeys would swallow the keys being recorded, so the app pauses them meanwhile.
    static var recordingChanged: ((Bool) -> Void)?

    var combo: KeyCombo? { didSet { needsDisplay = true } }
    var onChange: ((KeyCombo?) -> Void)?
    private(set) var isRecording = false { didSet { needsDisplay = true } }
    /// Only take focus when clicked, so opening the settings never starts recording on its own.
    private var clicked = false

    override var acceptsFirstResponder: Bool { clicked }
    override var canBecomeKeyView: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var clearRect: NSRect {
        NSRect(x: bounds.maxX - bounds.height + 2, y: 2, width: bounds.height - 4, height: bounds.height - 4)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        let text: String
        let color: NSColor
        if isRecording {
            text = "Type shortcut"
            color = .gray
        } else if let combo {
            text = combo.display
            color = .black
        } else {
            text = "Click to record shortcut"
            color = .gray
        }
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
        let size = string.size()
        string.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))

        if combo != nil && !isRecording {
            let circle = clearRect.insetBy(dx: 1, dy: 1)
            NSColor(calibratedWhite: 0.6, alpha: 1).setFill()
            NSBezierPath(ovalIn: circle).fill()
            let c = circle.insetBy(dx: 4.5, dy: 4.5)
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: c.minX, y: c.minY))
            cross.line(to: NSPoint(x: c.maxX, y: c.maxY))
            cross.move(to: NSPoint(x: c.minX, y: c.maxY))
            cross.line(to: NSPoint(x: c.maxX, y: c.minY))
            cross.lineWidth = 1.5
            NSColor.white.setStroke()
            cross.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if combo != nil && !isRecording && clearRect.contains(point) {
            combo = nil
            onChange?(nil)
            return
        }
        clicked = !isRecording
        window?.makeFirstResponder(isRecording ? nil : self)
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        ShortcutRecorder.recordingChanged?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        clicked = false
        isRecording = false
        ShortcutRecorder.recordingChanged?(false)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods.isEmpty && event.keyCode == 53 { // Escape cancels
            window?.makeFirstResponder(nil)
            return
        }
        if mods.isEmpty && event.keyCode == 51 { // Delete clears
            combo = nil
            onChange?(nil)
            window?.makeFirstResponder(nil)
            return
        }
        let isFunctionKey = event.specialKey.map { [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12].contains($0) } ?? false
        guard !mods.subtracting(.shift).isEmpty || isFunctionKey, let recorded = KeyCombo(event: event) else {
            NSSound.beep()
            return
        }
        combo = recorded
        onChange?(recorded)
        window?.makeFirstResponder(nil)
    }
}

/// Runs a closure when a control fires its action.
final class ActionHandler: NSObject {
    private let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}

private var actionHandlerKey: UInt8 = 0

extension NSControl {
    func onAction(_ handler: @escaping (NSControl) -> Void) {
        let h = ActionHandler(handler)
        objc_setAssociatedObject(self, &actionHandlerKey, h, .OBJC_ASSOCIATION_RETAIN)
        target = h
        action = #selector(ActionHandler.fire(_:))
    }
}

/// Small builders for the white-on-dark settings controls. Frames use Divvy's nib coordinates
/// (origin at the bottom-left of the parent).
enum UI {
    static func label(_ text: String, _ frame: NSRect, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.textColor = .white
        label.frame = frame
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    static func checkbox(_ title: String, _ frame: NSRect, on: Bool, size: CGFloat = 13,
                         _ handler: @escaping (Bool) -> Void) -> NSButton {
        let box = HUDCheckbox(title: title, size: size)
        box.frame = frame
        box.state = on ? .on : .off
        box.onAction { handler(($0 as! NSButton).state == .on) }
        return box
    }

    /// A number field with a stepper beside it, as in Divvy's margin and grid settings.
    @discardableResult
    static func stepper(value: Int, range: ClosedRange<Int>, field fieldFrame: NSRect, stepper stepperFrame: NSRect,
                        in parent: NSView, _ handler: @escaping (Int) -> Void) -> [NSControl] {
        let field = NSTextField(string: "\(value)")
        field.frame = fieldFrame
        field.alignment = .right
        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        formatter.allowsFloats = false
        field.formatter = formatter
        field.cell?.sendsActionOnEndEditing = true

        field.appearance = NSAppearance(named: .aqua)
        let stepper = NSStepper(frame: stepperFrame)
        stepper.appearance = NSAppearance(named: .aqua)
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.integerValue = value
        stepper.valueWraps = false

        stepper.onAction { _ in
            field.integerValue = stepper.integerValue
            handler(stepper.integerValue)
        }
        field.onAction { _ in
            let clamped = min(range.upperBound, max(range.lowerBound, field.integerValue))
            field.integerValue = clamped
            stepper.integerValue = clamped
            handler(clamped)
        }
        parent.addSubview(field)
        parent.addSubview(stepper)
        return [field, stepper]
    }
}
