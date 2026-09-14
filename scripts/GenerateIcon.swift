import AppKit

// A code-native waveform mark, drawn at App Store resolution.
let dimension = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: dimension, pixelsHigh: dimension,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 0.035, green: 0.065, blue: 0.115, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()
NSColor(red: 0.10, green: 0.17, blue: 0.27, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 160, y: 160, width: 704, height: 704), xRadius: 170, yRadius: 170).fill()
let signal = NSBezierPath()
signal.move(to: NSPoint(x: 220, y: 492))
signal.line(to: NSPoint(x: 340, y: 492))
signal.line(to: NSPoint(x: 410, y: 670))
signal.line(to: NSPoint(x: 502, y: 328))
signal.line(to: NSPoint(x: 596, y: 735))
signal.line(to: NSPoint(x: 679, y: 492))
signal.line(to: NSPoint(x: 806, y: 492))
signal.lineWidth = 48
signal.lineCapStyle = .round
signal.lineJoinStyle = .round
NSColor(red: 0.42, green: 0.70, blue: 1, alpha: 1).setStroke()
signal.stroke()
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: "IncidentAI/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
