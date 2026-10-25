import AppKit
import ApplicationServices

/// A window in another app, addressed through the Accessibility API.
struct TargetWindow {
    let app: NSRunningApplication
    let element: AXUIElement

    var title: String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        let title = (value as? String) ?? ""
        return title.isEmpty ? (app.localizedName ?? "Window") : title
    }

    /// Frame in Accessibility coordinates (origin at top-left of the primary screen).
    var frame: CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    /// The screen holding most of the window.
    var screen: NSScreen {
        guard let frame else { return NSScreen.main ?? NSScreen.screens[0] }
        let cocoa = WindowMover.flip(frame)
        let best = NSScreen.screens.max { a, b in
            a.frame.intersection(cocoa).area < b.frame.intersection(cocoa).area
        }
        return best ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func setFrame(_ rect: CGRect) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Apps with enhanced UI enabled animate AX resizes and can end up at the wrong size.
        let enhanced = "AXEnhancedUserInterface" as CFString
        var enhancedValue: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, enhanced, &enhancedValue)
        let wasEnhanced = (enhancedValue as? Bool) ?? false
        if wasEnhanced { AXUIElementSetAttributeValue(appElement, enhanced, kCFBooleanFalse) }

        var origin = rect.origin
        var size = rect.size
        let posValue = AXValueCreate(.cgPoint, &origin)!
        let sizeValue = AXValueCreate(.cgSize, &size)!
        // Size, move, size again: the first resize may be clamped by the old screen.
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)

        if wasEnhanced { AXUIElementSetAttributeValue(appElement, enhanced, kCFBooleanTrue) }
    }
}

enum WindowMover {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func frontmostWindow() -> TargetWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success, let value {
                return TargetWindow(app: app, element: value as! AXUIElement)
            }
        }
        return nil
    }

    /// Converts between Cocoa (bottom-left origin) and Accessibility (top-left origin) rects.
    /// The conversion is its own inverse.
    static func flip(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Cocoa rect on `screen` covered by the given cell selection (row 0 is the top).
    static func rect(for selection: GridSelection, columns: Int, rows: Int, on screen: NSScreen,
                     margins: Margins?) -> CGRect {
        var area = screen.visibleFrame
        if let m = margins {
            area = CGRect(x: area.minX + m.left, y: area.minY + m.bottom,
                          width: max(1, area.width - m.left - m.right), height: max(1, area.height - m.top - m.bottom))
        }
        let columns = max(1, columns), rows = max(1, rows)
        let c0 = max(0, min(selection.startColumn, selection.endColumn))
        let c1 = min(columns - 1, max(selection.startColumn, selection.endColumn))
        let r0 = max(0, min(selection.startRow, selection.endRow))
        let r1 = min(rows - 1, max(selection.startRow, selection.endRow))
        let cellW = area.width / CGFloat(columns)
        let cellH = area.height / CGFloat(rows)
        var left = area.minX + CGFloat(c0) * cellW
        var right = area.minX + CGFloat(c1 + 1) * cellW
        var top = area.maxY - CGFloat(r0) * cellH
        var bottom = area.maxY - CGFloat(r1 + 1) * cellH
        // Window margins split the gap between neighbours; screen edges already have their own margin.
        if let m = margins {
            if c0 > 0 { left += m.windowWidth / 2 }
            if c1 < columns - 1 { right -= m.windowWidth / 2 }
            if r0 > 0 { top -= m.windowHeight / 2 }
            if r1 < rows - 1 { bottom += m.windowHeight / 2 }
        }
        // Oversized margins can leave no room; keep the window at least a point in each direction.
        return CGRect(x: left.rounded(), y: bottom.rounded(),
                      width: max(1, (right - left).rounded()), height: max(1, (top - bottom).rounded()))
    }

    /// Moves `window` to the shortcut's cells on `screen` (the window's own screen by default).
    static func apply(_ shortcut: Shortcut, to window: TargetWindow, on screen: NSScreen? = nil, margins: Margins?) {
        let target = rect(for: shortcut.selection, columns: shortcut.columns, rows: shortcut.rows,
                          on: screen ?? window.screen, margins: margins)
        window.setFrame(flip(target))
    }

    /// The screen after `screen`, for cycling a shortcut across displays.
    static func nextScreen(after screen: NSScreen) -> NSScreen {
        let screens = NSScreen.screens
        guard let index = screens.firstIndex(of: screen) else { return screen }
        return screens[(index + 1) % screens.count]
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
