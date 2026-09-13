import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var images: [[String: String]] = []
func render(_ pixels: Int, name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    if !name.hasPrefix("mac-") {
        NSColor.white.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    }
    let tile = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 210, yRadius: 210)
    NSGraphicsContext.saveGraphicsState()
    if name.hasPrefix("mac-") {
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -5); shadow.set()
    }
    NSColor.white.setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    // A small ink mark on a generous white field. Pixel-aware strokes remain clear at 16 pt.
    let orbit = NSBezierPath(); orbit.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 215, startAngle: 76, endAngle: 377)
    orbit.lineWidth = max(22, 1024 / CGFloat(pixels) * 0.8); orbit.lineCapStyle = .round
    NSColor(calibratedWhite: 0.08, alpha: 1).setStroke(); orbit.stroke()
    let check = NSBezierPath(); check.move(to: NSPoint(x: 419, y: 518)); check.line(to: NSPoint(x: 496, y: 438)); check.line(to: NSPoint(x: 664, y: 625)); check.lineWidth = max(37, 1024 / CGFloat(pixels) * 1.0); check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let file = "mac-\(size)@\(scale)x.png"; try render(size * scale, name: file)
        images.append(["idiom":"mac", "size":"\(size)x\(size)", "scale":"\(scale)x", "filename":file])
    }
}
try render(1024, name: "ios-1024.png")
images.append(["idiom":"universal", "platform":"ios", "size":"1024x1024", "filename":"ios-1024.png"])
let manifest: [String: Any] = ["images": images, "info": ["author":"xcode", "version":1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
