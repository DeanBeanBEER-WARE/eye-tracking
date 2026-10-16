import AppKit
import Foundation

private struct IconVariant {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

private let variants: [IconVariant] = [16, 32, 128, 256, 512].flatMap { points in
    [IconVariant(points: points, scale: 1), IconVariant(points: points, scale: 2)]
}

private let backgroundInsetRatio: CGFloat = 100.0 / 1024.0
private let cornerRadiusRatio: CGFloat = 185.4 / 1024.0
private let glyphRatio: CGFloat = 0.6

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func render(glyph: NSImage, pixels: Int) -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        fail("Could not allocate bitmap of \(pixels) px")
    }
    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fail("Could not create graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let size = CGFloat(pixels)
    let inset = size * backgroundInsetRatio
    let background = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = size * cornerRadiusRatio
    NSColor.white.setFill()
    NSBezierPath(roundedRect: background, xRadius: radius, yRadius: radius).fill()

    let glyphSize = size * glyphRatio
    let glyphRect = NSRect(
        x: (size - glyphSize) / 2,
        y: (size - glyphSize) / 2,
        width: glyphSize,
        height: glyphSize
    )
    glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fail("Could not encode PNG of \(pixels) px")
    }
    return png
}

private func contentsJSON() -> Data {
    let images: [[String: String]] = variants.map { variant in
        [
            "filename": variant.filename,
            "idiom": "mac",
            "scale": "\(variant.scale)x",
            "size": "\(variant.points)x\(variant.points)",
        ]
    }
    let root: [String: Any] = [
        "images": images,
        "info": ["author": "xcode", "version": 1],
    ]
    guard
        let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    else {
        fail("Could not encode Contents.json")
    }
    return data
}

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let svgURL = root.appendingPathComponent("assets/icon.svg")
private let outputURL = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
private let menuBarURL = root.appendingPathComponent("App/Resources/Assets.xcassets/MenuBarIcon.imageset/icon.svg")

guard let glyph = NSImage(contentsOf: svgURL) else {
    fail("Could not load \(svgURL.path); run from the repository root")
}

do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    for variant in variants {
        try render(glyph: glyph, pixels: variant.pixels).write(to: outputURL.appendingPathComponent(variant.filename))
    }
    try contentsJSON().write(to: outputURL.appendingPathComponent("Contents.json"))
    if FileManager.default.fileExists(atPath: menuBarURL.path) {
        try FileManager.default.removeItem(at: menuBarURL)
    }
    try FileManager.default.copyItem(at: svgURL, to: menuBarURL)
} catch {
    fail("Writing icons failed: \(error)")
}

print("Wrote \(variants.count) app icon images to \(outputURL.path)")
