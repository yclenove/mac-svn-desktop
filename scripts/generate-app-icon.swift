#!/usr/bin/env swift

import AppKit
import Foundation

private enum IconGenerationError: Error {
    case bitmapCreationFailed(Int)
    case pngEncodingFailed(Int)
    case iconutilFailed(Int32)
}

private let canvasSize: CGFloat = 1024

private func circle(center: NSPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(
        ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    ).fill()
}

private func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconGenerationError.bitmapCreationFailed(size)
    }

    bitmap.size = NSSize(width: size, height: size)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let scale = CGFloat(size) / canvasSize
    context.cgContext.scaleBy(x: scale, y: scale)
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

    let tile = NSBezierPath(
        roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
        xRadius: 205,
        yRadius: 205
    )
    NSColor(calibratedRed: 0.08, green: 0.48, blue: 0.38, alpha: 1).setFill()
    tile.fill()

    let backSheet = NSBezierPath(
        roundedRect: NSRect(x: 225, y: 250, width: 574, height: 550),
        xRadius: 78,
        yRadius: 78
    )
    NSColor(calibratedRed: 0.82, green: 0.91, blue: 0.87, alpha: 1).setFill()
    backSheet.fill()

    let sheet = NSBezierPath(
        roundedRect: NSRect(x: 205, y: 210, width: 614, height: 570),
        xRadius: 82,
        yRadius: 82
    )
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    sheet.fill()

    let ink = NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.15, alpha: 1)
    let branch = NSBezierPath()
    branch.lineWidth = 42
    branch.lineCapStyle = .round
    branch.lineJoinStyle = .round
    branch.move(to: NSPoint(x: 390, y: 640))
    branch.line(to: NSPoint(x: 390, y: 405))
    branch.curve(
        to: NSPoint(x: 630, y: 315),
        controlPoint1: NSPoint(x: 390, y: 325),
        controlPoint2: NSPoint(x: 545, y: 315)
    )
    ink.setStroke()
    branch.stroke()

    let merge = NSBezierPath()
    merge.lineWidth = 42
    merge.lineCapStyle = .round
    merge.move(to: NSPoint(x: 630, y: 570))
    merge.line(to: NSPoint(x: 630, y: 315))
    ink.setStroke()
    merge.stroke()

    let coral = NSColor(calibratedRed: 0.86, green: 0.31, blue: 0.23, alpha: 1)
    circle(center: NSPoint(x: 390, y: 640), radius: 54, color: coral)
    circle(center: NSPoint(x: 390, y: 405), radius: 54, color: ink)
    circle(center: NSPoint(x: 630, y: 570), radius: 54, color: coral)
    circle(center: NSPoint(x: 630, y: 315), radius: 54, color: ink)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.pngEncodingFailed(size)
    }
    return data
}

private let output = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "Packaging/SVNStudio/SVNStudio.icns"
).standardizedFileURL
private let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("SVNStudio-\(UUID().uuidString).iconset", isDirectory: true)

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

let files: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in files {
    try drawIcon(size: size).write(to: iconset.appendingPathComponent(name), options: .atomic)
}

try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw IconGenerationError.iconutilFailed(process.terminationStatus)
}

print("generated \(output.path)")
