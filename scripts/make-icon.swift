import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels)/1024); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 58,y: 58,width: 908,height: 908), xRadius: 200,yRadius: 200)
        NSGradient(starting: NSColor(srgbRed: 0.08,green: 0.2,blue: 0.3,alpha: 1), ending: NSColor(srgbRed: 0.04,green: 0.08,blue: 0.15,alpha: 1))!.draw(in: background, angle: -90)
        NSColor(srgbRed: 0.22,green: 0.68,blue: 0.73,alpha: 0.7).setFill()
        NSBezierPath(roundedRect: NSRect(x: 216,y: 292,width: 632,height: 468), xRadius: 56,yRadius: 56).fill()
        NSColor(srgbRed: 0.85,green: 0.96,blue: 0.95,alpha: 1).setFill()
        let card = NSBezierPath(roundedRect: NSRect(x: 158,y: 232,width: 632,height: 468), xRadius: 56,yRadius: 56); card.fill()
        NSGraphicsContext.saveGraphicsState(); card.addClip()
        NSColor(srgbRed: 0.1,green: 0.48,blue: 0.52,alpha: 1).setFill()
        let mountain = NSBezierPath(); mountain.move(to: NSPoint(x: 158,y: 232)); mountain.line(to: NSPoint(x: 370,y: 532)); mountain.line(to: NSPoint(x: 515,y: 368)); mountain.line(to: NSPoint(x: 631,y: 485)); mountain.line(to: NSPoint(x: 790,y: 295)); mountain.line(to: NSPoint(x: 790,y: 232)); mountain.close(); mountain.fill()
        NSColor(srgbRed: 0.95,green: 0.66,blue: 0.28,alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 591,y: 535,width: 91,height: 91)).fill()
        NSGraphicsContext.restoreGraphicsState(); NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
