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

let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = projectRoot.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func renderIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "BotPlusIconExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create a bitmap context."])
    }
    let cg = graphics.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    cg.translateBy(x: 0, y: 1024)
    cg.scaleBy(x: 1, y: -1)

    cg.setFillColor(color(0.105, 0.115, 0.135))
    cg.addPath(roundedRect(CGRect(x: 14, y: 14, width: 996, height: 996), radius: 210))
    cg.fillPath()

    let paper = roundedRect(CGRect(x: 196, y: 112, width: 632, height: 800), radius: 76)
    cg.setFillColor(color(0.17, 0.19, 0.22)); cg.addPath(paper); cg.fillPath()
    cg.setStrokeColor(color(0.58, 0.62, 0.69, 0.72)); cg.setLineWidth(18); cg.addPath(paper); cg.strokePath()

    cg.setFillColor(color(0.68, 0.16, 0.20))
    cg.addPath(roundedRect(CGRect(x: 196, y: 112, width: 330, height: 112), radius: 44)); cg.fillPath()
    cg.setStrokeColor(color(0.88, 0.27, 0.30)); cg.setLineWidth(12); cg.setLineCap(.round)
    cg.move(to: CGPoint(x: 264, y: 286)); cg.addLine(to: CGPoint(x: 524, y: 286)); cg.strokePath()

    cg.setStrokeColor(color(0.72, 0.76, 0.82, 0.8)); cg.setLineCap(.butt)
    for index in 0..<11 {
        let x = CGFloat(548 + index * 22)
        let top: CGFloat = index.isMultiple(of: 5) ? 650 : (index.isMultiple(of: 2) ? 666 : 680)
        cg.setLineWidth(index.isMultiple(of: 5) ? 7 : 4)
        cg.move(to: CGPoint(x: x, y: top)); cg.addLine(to: CGPoint(x: x, y: 728)); cg.strokePath()
    }
    cg.setStrokeColor(color(0.72, 0.76, 0.82, 0.72)); cg.setLineWidth(5)
    cg.move(to: CGPoint(x: 548, y: 728)); cg.addLine(to: CGPoint(x: 782, y: 728)); cg.strokePath()

    let badge = roundedRect(CGRect(x: 270, y: 352, width: 484, height: 360), radius: 76)
    cg.setFillColor(color(0, 0, 0, 0.27)); cg.addPath(roundedRect(CGRect(x: 270, y: 368, width: 484, height: 360), radius: 76)); cg.fillPath()
    cg.setFillColor(color(0.25, 0.29, 0.35)); cg.addPath(badge); cg.fillPath()
    cg.setStrokeColor(color(1, 1, 1, 0.14)); cg.setLineWidth(5); cg.addPath(badge); cg.strokePath()

    // Draw a geometric B and plus sign so the exported icon has no font dependency.
    cg.setStrokeColor(color(0.94, 0.95, 0.97)); cg.setLineWidth(44); cg.setLineCap(.round); cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: 414, y: 620)); cg.addLine(to: CGPoint(x: 414, y: 444)); cg.strokePath()
    cg.setLineWidth(36)
    cg.addPath(roundedRect(CGRect(x: 414, y: 536, width: 84, height: 84), radius: 28)); cg.strokePath()
    cg.addPath(roundedRect(CGRect(x: 414, y: 444, width: 94, height: 92), radius: 30)); cg.strokePath()
    cg.setStrokeColor(color(0.94, 0.95, 0.97)); cg.setLineWidth(28)
    cg.move(to: CGPoint(x: 608, y: 542)); cg.addLine(to: CGPoint(x: 704, y: 542)); cg.strokePath()
    cg.move(to: CGPoint(x: 656, y: 494)); cg.addLine(to: CGPoint(x: 656, y: 590)); cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BotPlusIconExporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG data."])
    }
    return data
}

for file in files {
    try renderIcon(size: file.pixels).write(to: outputDirectory.appendingPathComponent(file.filename), options: .atomic)
}

let images: [[String: String]] = files.map { file in
    ["filename": file.filename, "idiom": "mac", "scale": "\(file.scale)x", "size": "\(file.pointSize)x\(file.pointSize)"]
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"), options: .atomic)
print("Wrote 10 AppIcon PNG variants and Contents.json to \(outputDirectory.path)")
