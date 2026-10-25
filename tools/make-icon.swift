// Renders Resources/AppIcon.icns: a 6x6 grid with the left half highlighted.
import AppKit

let out = CommandLine.arguments[1]
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let body = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
               ending: NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1))!
        .draw(in: NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)
    let grid = body.insetBy(dx: s * 0.1, dy: s * 0.1)
    let n = 6
    let cell = grid.width / CGFloat(n)
    for row in 0..<n {
        for col in 0..<n {
            let r = NSRect(x: grid.minX + CGFloat(col) * cell, y: grid.minY + CGFloat(row) * cell,
                           width: cell, height: cell).insetBy(dx: cell * 0.08, dy: cell * 0.08)
            (col < 3 ? NSColor(calibratedRed: 0.25, green: 0.56, blue: 1, alpha: 1)
                     : NSColor(white: 1, alpha: 0.16)).setFill()
            NSBezierPath(roundedRect: r, xRadius: cell * 0.18, yRadius: cell * 0.18).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", out]
try! task.run()
task.waitUntilExit()
exit(task.terminationStatus)
