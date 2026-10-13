#!/usr/bin/env swift
import AppKit
import Foundation

struct IconFile {
    let filename: String
    let pointSize: Int
    let scale: Int
    var pixels: Int { pointSize * scale }
}
let files = [
    IconFile(filename: "icon_16.png", pointSize: 16, scale: 1),
    IconFile(filename: "icon_16@2x.png", pointSize: 16, scale: 2),
    IconFile(filename: "icon_32.png", pointSize: 32, scale: 1),
    IconFile(filename: "icon_32@2x.png", pointSize: 32, scale: 2),
    IconFile(filename: "icon_128.png", pointSize: 128, scale: 1),
    IconFile(filename: "icon_128@2x.png", pointSize: 128, scale: 2),
    IconFile(filename: "icon_256.png", pointSize: 256, scale: 1),
    IconFile(filename: "icon_256@2x.png", pointSize: 256, scale: 2),
    IconFile(filename: "icon_512.png", pointSize: 512, scale: 1),
    IconFile(filename: "icon_512@2x.png", pointSize: 512, scale: 2)
]
let root = URL(fileURLWithPath: #filePath).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()
let branding = root.appendingPathComponent("docs/branding", isDirectory: true)
let catalog = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let preview = root.appendingPathComponent("Assets.xcassets/BrandIcon.imageset", isDirectory: true)
let sourceURL = branding.appendingPathComponent("BrandArtwork.png")
func error(_ message: String) -> NSError {
    NSError(domain: "BotPlusIconExporter", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
}
guard let source = NSImage(contentsOf: sourceURL),
      let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    throw error("Cannot read \(sourceURL.path)")
}
guard image.width == 1254, image.height == 1254 else {
    throw error("BrandArtwork.png must be the checked-in 1254 × 1254 master.")
}
for directory in [branding, catalog, preview] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

func render(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
              pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw error("Cannot create a \(size)px bitmap.")
    }
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    // Normalize the artwork to the macOS icon grid. A deterministic rounded
    // silhouette excludes extraction flecks while retaining the source alpha.
    let tile = CGRect(x: 72, y: 72, width: 880, height: 880)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 128, cornerHeight: 128,
                          transform: nil))
    context.clip()
    let ratio: CGFloat = 880 / 1008
    let inset: CGFloat = 72 - 122 * ratio
    context.draw(image, in: CGRect(x: inset, y: inset,
                                  width: 1254 * ratio, height: 1254 * ratio))
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw error("Cannot encode PNG.")
    }
    return png
}
func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object,
                                          options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}
for file in files {
    try render(size: file.pixels).write(to: catalog.appendingPathComponent(file.filename),
                                       options: .atomic)
}
try render(size: 1024).write(to: branding.appendingPathComponent("AppIcon.png"), options: .atomic)
try render(size: 512).write(to: preview.appendingPathComponent("BrandIcon.png"), options: .atomic)
try render(size: 1024).write(to: preview.appendingPathComponent("BrandIcon@2x.png"), options: .atomic)
try writeJSON([
    "images": files.map { ["filename": $0.filename, "idiom": "mac",
                            "scale": "\($0.scale)x", "size": "\($0.pointSize)x\($0.pointSize)"] },
    "info": ["author": "xcode", "version": 1]
], to: catalog.appendingPathComponent("Contents.json"))
try writeJSON([
    "images": [
        ["filename": "BrandIcon.png", "idiom": "mac", "scale": "1x"],
        ["filename": "BrandIcon@2x.png", "idiom": "mac", "scale": "2x"]
    ],
    "info": ["author": "xcode", "version": 1]
], to: preview.appendingPathComponent("Contents.json"))
print("Exported AppIcon.png, all 10 macOS AppIcon sizes, and BrandIcon preview assets.")
