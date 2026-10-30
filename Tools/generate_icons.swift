// Régénère les icônes : swift Tools/generate_icons.swift (depuis la racine du projet).
import AppKit

let assets = "ShowMode/Assets.xcassets"

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
}

func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

/// Dessin sur une grille de 18 points : deux écrans qui ne se touchent que par un coin.
func drawMenuBarGlyph(active: Bool) {
    let main = rounded(1.5, 7.5, 9.5, 8.5, 1.8)
    let external = rounded(11, 2, 5.5, 5.5, 1.3)
    for path in [main, external] {
        if active {
            path.fill()
        } else {
            path.lineWidth = 1.4
            path.stroke()
        }
    }
}

func withShadow(blur: Double, dy: Double, alpha: Double, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: dy)
    shadow.shadowColor = NSColor(white: 0, alpha: alpha)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// Écran blanc nuancé, avec une ombre douce.
func drawScreen(_ path: NSBezierPath) {
    withShadow(blur: 20, dy: -8, alpha: 0.5) {
        color(0xE6E7EC).setFill()
        path.fill()
    }
    NSGradient(starting: color(0xD9DBE2), ending: color(0xFFFFFF))!.draw(in: path, angle: 90)
}

/// Dessin sur une grille de 512 points : les deux écrans de la barre des menus, sur fond graphite.
func drawAppIcon() {
    let tile = rounded(46, 46, 420, 420, 94)
    NSGradient(starting: color(0x08080B), ending: color(0x2A2B31))!.draw(in: tile, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: NSColor(white: 1, alpha: 0.10), ending: NSColor(white: 1, alpha: 0))!
        .draw(in: NSRect(x: 0, y: 0, width: 512, height: 512), relativeCenterPosition: NSPoint(x: -0.25, y: 0.7))
    NSColor(white: 1, alpha: 0.10).setStroke()
    let edge = rounded(47, 47, 418, 418, 93)
    edge.lineWidth = 2
    edge.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let scale = 14.5
    drawScreen(rounded(256 - 7.5 * scale, 256 - 1.5 * scale, 9.5 * scale, 8.5 * scale, 1.9 * scale))
    drawScreen(rounded(256 + 2.35 * scale, 256 - 7 * scale, 5.15 * scale, 5.15 * scale, 1.2 * scale))
}

func writePNG(pixels: Int, scale: Double, to path: String, draw: () -> Void) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

var appIconEntries: [String] = []
for (size, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let pixels = size * scale
        let name = "icon_\(size)@\(scale)x.png"
        try writePNG(pixels: pixels, scale: Double(pixels) / 512, to: "\(assets)/AppIcon.appiconset/\(name)", draw: drawAppIcon)
        appIconEntries.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(size)x\#(size)"}"#)
    }
}
try #"{"images":[\#(appIconEntries.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
    .write(toFile: "\(assets)/AppIcon.appiconset/Contents.json", atomically: true, encoding: .utf8)

for (folder, active) in [("MenuBarIcon", false), ("MenuBarIconActive", true)] {
    var entries: [String] = []
    for scale in [1, 2] {
        let name = "\(folder)@\(scale)x.png"
        try writePNG(pixels: 18 * scale, scale: Double(scale), to: "\(assets)/\(folder).imageset/\(name)") {
            NSColor.black.set()
            drawMenuBarGlyph(active: active)
        }
        entries.append(#"{"filename":"\#(name)","idiom":"universal","scale":"\#(scale)x"}"#)
    }
    try #"{"images":[\#(entries.joined(separator: ","))],"info":{"author":"xcode","version":1},"properties":{"template-rendering-intent":"template"}}"#
        .write(toFile: "\(assets)/\(folder).imageset/Contents.json", atomically: true, encoding: .utf8)
}
