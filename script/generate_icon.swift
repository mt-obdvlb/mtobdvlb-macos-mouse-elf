import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210)
        NSColor(srgbRed: 0.04, green: 0.39, blue: 0.36, alpha: 1).setFill(); tile.fill()
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: 330, y: 770)); pointer.line(to: NSPoint(x: 330, y: 285))
        pointer.line(to: NSPoint(x: 457, y: 390)); pointer.line(to: NSPoint(x: 559, y: 218))
        pointer.line(to: NSPoint(x: 652, y: 273)); pointer.line(to: NSPoint(x: 551, y: 440))
        pointer.line(to: NSPoint(x: 719, y: 460)); pointer.close()
        NSColor.white.setFill(); pointer.fill()
        let sparkle = NSBezierPath()
        sparkle.move(to: NSPoint(x: 718, y: 815)); sparkle.line(to: NSPoint(x: 745, y: 738))
        sparkle.line(to: NSPoint(x: 823, y: 710)); sparkle.line(to: NSPoint(x: 745, y: 682))
        sparkle.line(to: NSPoint(x: 718, y: 605)); sparkle.line(to: NSPoint(x: 690, y: 682))
        sparkle.line(to: NSPoint(x: 613, y: 710)); sparkle.line(to: NSPoint(x: 690, y: 738)); sparkle.close()
        NSColor(srgbRed: 0.65, green: 0.93, blue: 0.68, alpha: 1).setFill(); sparkle.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
