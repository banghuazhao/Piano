#!/usr/bin/env swift

// Render the Mac Catalyst app icon from the iOS app icon artwork.
// Build: swiftc Scripts/render-mac-app-icon.swift -o /tmp/render-mac-app-icon
// Run:   /tmp/render-mac-app-icon
//
// macOS icons are not full-bleed: the artwork sits in a rounded tile that leaves
// a transparent margin on the 1024 pt canvas. This reuses the shipped iOS artwork
// so both platforms stay in step, and writes every size the Mac App Store requires.
// Re-run it whenever the iOS icon changes, then commit the regenerated PNGs.

import AppKit
import Foundation

let iconSet = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Piano/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let sourceURL = iconSet.appendingPathComponent("appIcon-v2.png")

// Apple's macOS icon grid: an 824 pt tile centred on a 1024 pt canvas.
let canvas: CGFloat = 1024
let tile: CGFloat = 824
let cornerRadius: CGFloat = 185
let pixelSizes = [16, 32, 64, 128, 256, 512, 1024]

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("error: could not read \(sourceURL.path)\n".utf8))
    exit(1)
}

func master() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = (canvas - tile) / 2
    let tileRect = NSRect(x: inset, y: inset, width: tile, height: tile)
    let clip = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    clip.addClip()
    source.draw(in: tileRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let masterImage = NSImage(size: NSSize(width: canvas, height: canvas))
masterImage.addRepresentation(master())

for size in pixelSizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    masterImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero, operation: .copy, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: could not encode \(size)px icon\n".utf8))
        exit(1)
    }
    let output = iconSet.appendingPathComponent("appIcon-mac-\(size).png")
    try data.write(to: output)
    print("wrote \(output.lastPathComponent) (\(size)x\(size))")
}
