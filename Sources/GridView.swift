import AppKit

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(range.upperBound, max(range.lowerBound, self)) }
}

struct GridSelection: Equatable {
    var startColumn: Int, startRow: Int, endColumn: Int, endRow: Int

    func contains(column: Int, row: Int) -> Bool {
        (min(startColumn, endColumn)...max(startColumn, endColumn)).contains(column)
            && (min(startRow, endRow)...max(startRow, endRow)).contains(row)
    }
}

/// Divvy's grid of rounded cells. Drag across it to select a block; `mini` draws the solid
/// thumbnail style used in the shortcut list.
final class GridView: NSView {
    var columns = 6 { didSet { needsDisplay = true } }
    var rows = 6 { didSet { needsDisplay = true } }
    var mini = false { didSet { needsDisplay = true } }
    var spacing: CGFloat = 3 { didSet { needsDisplay = true } }
    var isInteractive = true

    var selection: GridSelection? {
        didSet {
            needsDisplay = true
            if selection != oldValue, dragging { onSelectionChange?(selection) }
        }
    }

    var onSelectionChange: ((GridSelection?) -> Void)?
    var onCommit: ((GridSelection) -> Void)?

    private var dragging = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive ? super.hitTest(point) : nil
    }

    private var cellSize: NSSize {
        NSSize(width: (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
               height: (bounds.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
    }

    private func cell(at point: NSPoint) -> (column: Int, row: Int) {
        let size = cellSize
        let pitchX = max(1, size.width + spacing), pitchY = max(1, size.height + spacing)
        let column = Int((point.x / pitchX).rounded(.down).clamped(to: -1...CGFloat(columns)))
        let row = Int((point.y / pitchY).rounded(.down).clamped(to: -1...CGFloat(rows)))
        return (max(0, min(columns - 1, column)), max(0, min(rows - 1, row)))
    }

    private func cellRect(column: Int, row: Int) -> NSRect {
        let size = cellSize
        return NSRect(x: CGFloat(column) * (size.width + spacing), y: CGFloat(row) * (size.height + spacing),
                      width: size.width, height: size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard columns > 0, rows > 0 else { return }
        let radius = mini ? 1 : Theme.smallRadius
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = cellRect(column: column, row: row)
                let selected = selection?.contains(column: column, row: row) ?? false
                if mini {
                    (selected ? Theme.cellSelected : Theme.miniUnselected).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                    continue
                }
                (selected ? Theme.cellSelected : Theme.cellFill).setFill()
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

                let light = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
                light.lineWidth = 1
                Theme.cellBorderLight.setStroke()
                light.stroke()

                let dark = NSBezierPath(roundedRect: rect.insetBy(dx: 1.25, dy: 1.25), xRadius: radius, yRadius: radius)
                dark.lineWidth = 0.5
                Theme.cellBorderDark.setStroke()
                dark.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let c = cell(at: convert(event.locationInWindow, from: nil))
        dragging = true
        selection = GridSelection(startColumn: c.column, startRow: c.row, endColumn: c.column, endRow: c.row)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, var s = selection else { return }
        let c = cell(at: convert(event.locationInWindow, from: nil))
        s.endColumn = c.column
        s.endRow = c.row
        selection = s
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging, let s = selection else { return }
        dragging = false
        onCommit?(s)
    }
}

/// The translucent blue overlay on the real screen showing where the window will land.
final class PreviewWindow: NSWindow {
    private final class PreviewView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: Theme.radius, yRadius: Theme.radius)
            Theme.previewFill.setFill()
            path.fill()
            path.lineWidth = 3
            Theme.previewStroke.setStroke()
            path.stroke()
        }
    }

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .transient]
        contentView = PreviewView()
    }
}
