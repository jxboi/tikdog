import AppKit

let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(srgbRed: 1, green: 136.0/255, blue: 77.0/255, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let symbol = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)!
let configuration = NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 1)])
let paw = symbol.withSymbolConfiguration(configuration)!
paw.draw(in: NSRect(x: 220, y: 240, width: 584, height: 584))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "TikDog/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
