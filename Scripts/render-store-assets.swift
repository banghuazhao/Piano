#!/usr/bin/env swift

// Render App Store artwork from real, unmodified app screenshots.
// Build: swiftc Scripts/render-store-assets.swift -o /tmp/render-store-assets
// Run:   /tmp/render-store-assets path/to/manifest.json
// Refresh only the contact sheet: add --preview-only before the manifest path.
//
// Manifest paths are relative to the manifest file. Output dimensions are exact pixels.
// `creative` is always text-free; use it only for artwork with confirmed dimensions.
// `duo` accepts one screenshot or two screenshots shown side by side.
// `portrait` keeps a portrait app capture large below the headline.
// {
//   "outputDirectory": "RenderedStoreAssets",
//   "previewFile": "preview.jpg",
//   "assets": [
//     {
//       "name": "01-play",
//       "subdirectory": "en-US/iPhone",
//       "style": "landscape",
//       "width": 2622,
//       "height": 1206,
//       "screenshot": "captures/keyboard.png",
//       "headline": "A piano that feels alive",
//       "subhead": "Play, record, and make every note your own.",
//       "footer": "REAL PIANO SOUND"
//     },
//     {
//       "name": "duo-practice",
//       "style": "duo",
//       "width": 2034,
//       "height": 1398,
//       "screenshots": ["captures/practice.png", "captures/library.png"],
//       "headline": "Practice with purpose",
//       "subhead": "Your next piece is ready."
//     },
//     {
//       "name": "search-artwork",
//       "style": "creative",
//       "width": 3840,
//       "height": 2560,
//       "screenshot": "captures/keyboard.png"
//     }
//   ]
// }

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum RenderError: LocalizedError {
    case usage
    case invalidManifest(String)
    case unreadableImage(String)
    case canvasFailed
    case imageEncodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: render-store-assets [--preview-only] path/to/manifest.json"
        case .invalidManifest(let detail):
            "Invalid manifest: \(detail)"
        case .unreadableImage(let path):
            "Could not decode PNG screenshot: \(path)"
        case .canvasFailed:
            "Could not allocate an RGB canvas."
        case .imageEncodingFailed(let path):
            "Could not write PNG: \(path)"
        }
    }
}

private struct Manifest: Decodable {
    let outputDirectory: String?
    let previewFile: String?
    let assets: [Asset]
}

private struct Asset: Decodable {
    enum Style: String, Decodable {
        case portraitPhone
        case portrait
        case landscape
        case duo
        case creative
    }

    let name: String
    let subdirectory: String?
    let style: Style
    let width: Int
    let height: Int
    let screenshot: String?
    let screenshots: [String]?
    let headline: String?
    let subhead: String?
    let footer: String?
    let eyebrow: String?
    let textFree: Bool?

    var sourcePaths: [String] {
        if let screenshots { return screenshots }
        return screenshot.map { [$0] } ?? []
    }

    var isTextFree: Bool { style == .creative || textFree == true }
}

private struct PaletteColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: [red, green, blue, alpha])!
    }
}

private enum Palette {
    static let espresso = PaletteColor(red: 22 / 255, green: 19 / 255, blue: 15 / 255)
    static let espressoLight = PaletteColor(red: 39 / 255, green: 31 / 255, blue: 23 / 255)
    static let espressoDeep = PaletteColor(red: 13 / 255, green: 12 / 255, blue: 10 / 255)
    static let ivory = PaletteColor(red: 245 / 255, green: 237 / 255, blue: 221 / 255)
    static let brass = PaletteColor(red: 214 / 255, green: 173 / 255, blue: 103 / 255)
}

private final class Canvas {
    let width: CGFloat
    let height: CGFloat
    let context: CGContext

    init(width: Int, height: Int) throws {
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { throw RenderError.canvasFailed }
        self.context = context
    }

    /// A rectangle measured from the top edge of the output image.
    func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: self.height - top - height, width: width, height: height)
    }

    func background() {
        context.setFillColor(Palette.espresso.cgColor())
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let colors = [
            Palette.espressoLight.cgColor(),
            Palette.espresso.cgColor(),
            Palette.espressoDeep.cgColor()
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.55, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: 0, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // A quiet glow gives the captured screen depth without inventing app UI.
        let glowColors = [Palette.brass.cgColor(alpha: 0.10),
                          Palette.brass.cgColor(alpha: 0)] as CFArray
        if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: glowColors, locations: [0, 1]) {
            let radius = max(width, height) * 0.63
            let center = CGPoint(x: width * 0.56, y: height * 0.46)
            context.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
        }
    }

    func text(_ value: String, in bounds: CGRect, fontName: String,
              preferredSize: CGFloat, minimumSize: CGFloat,
              color: CGColor, tracking: CGFloat = 0) throws {
        guard !value.isEmpty else { return }
        var size = preferredSize
        while size >= minimumSize {
            let font = CTFontCreateWithName(fontName as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTKernAttributeName as String): tracking
            ]
            let attributed = NSAttributedString(string: value, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: 0),
                CGPath(rect: bounds, transform: nil), nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.location + visible.length >= attributed.length {
                context.saveGState()
                context.textMatrix = .identity
                CTFrameDraw(frame, context)
                context.restoreGState()
                return
            }
            size -= max(1, preferredSize * 0.025)
        }
        throw RenderError.invalidManifest("Text does not fit: \"\(value)\"")
    }

    func rule(x: CGFloat, top: CGFloat, width: CGFloat, thickness: CGFloat = 2) {
        context.setFillColor(Palette.brass.cgColor(alpha: 0.82))
        context.fill(rect(x: x, top: top, width: width, height: thickness))
    }

    func screenshot(_ image: CGImage, in available: CGRect) {
        let shortEdge = min(width, height)
        let padding = max(10, shortEdge * 0.010)
        let imageBounds = available.insetBy(dx: padding, dy: padding)
        let fitted = aspectFit(
            CGSize(width: image.width, height: image.height), in: imageBounds
        )
        let frame = fitted.insetBy(dx: -padding, dy: -padding)
        let cornerRadius = max(18, shortEdge * 0.023)
        let framePath = CGPath(roundedRect: frame, cornerWidth: cornerRadius,
                               cornerHeight: cornerRadius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -shortEdge * 0.018),
                          blur: shortEdge * 0.04,
                          color: Palette.espressoDeep.cgColor(alpha: 0.72))
        context.setFillColor(Palette.espressoDeep.cgColor())
        context.addPath(framePath)
        context.fillPath()
        context.restoreGState()

        context.draw(image, in: fitted) // Complete source pixels; no crop or fake screen content.
        context.setStrokeColor(Palette.ivory.cgColor(alpha: 0.15))
        context.setLineWidth(max(1.5, shortEdge * 0.0011))
        context.stroke(fitted)
        context.setStrokeColor(Palette.brass.cgColor(alpha: 0.48))
        context.setLineWidth(max(2, shortEdge * 0.0013))
        context.addPath(framePath)
        context.strokePath()
    }

    private func aspectFit(_ source: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: bounds.midX - size.width / 2,
                      y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

private func render(_ asset: Asset, images: [CGImage]) throws -> CGImage {
    let canvas = try Canvas(width: asset.width, height: asset.height)
    canvas.background()
    let w = canvas.width
    let h = canvas.height
    let short = min(w, h)
    let title = asset.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let subhead = asset.subhead?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let footer = asset.footer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if !asset.isTextFree {
        let eyebrow = (asset.eyebrow ?? "PIANOFLOW").uppercased()
        let margin = w * (asset.style == .portraitPhone ? 0.075 : 0.055)
        let top = h * (asset.style == .portraitPhone ? 0.065 : 0.018)
        try canvas.text(eyebrow, in: canvas.rect(x: margin, top: top,
                                                width: w * 0.52, height: h * 0.045),
                        fontName: "AvenirNext-DemiBold",
                        preferredSize: short * 0.023, minimumSize: short * 0.014,
                        color: Palette.brass.cgColor(), tracking: short * 0.003)
        canvas.rule(x: margin, top: top + h * 0.051, width: w * 0.075,
                    thickness: max(2, short * 0.0016))
    }

    switch asset.style {
    case .portraitPhone:
        if !asset.isTextFree {
            try canvas.text(title, in: canvas.rect(x: w * 0.075, top: h * 0.155,
                                                   width: w * 0.85, height: h * 0.16),
                            fontName: "Georgia-Bold", preferredSize: short * 0.084,
                            minimumSize: short * 0.049,
                            color: Palette.ivory.cgColor())
            try canvas.text(subhead, in: canvas.rect(x: w * 0.075, top: h * 0.305,
                                                     width: w * 0.82, height: h * 0.075),
                            fontName: "AvenirNext-Medium", preferredSize: short * 0.031,
                            minimumSize: short * 0.021,
                            color: Palette.ivory.cgColor(alpha: 0.82))
        }
        canvas.screenshot(images[0], in: canvas.rect(x: w * 0.055, top: h * 0.405,
                                                     width: w * 0.89, height: h * 0.38))
        if !asset.isTextFree && !footer.isEmpty {
            canvas.rule(x: w * 0.075, top: h * 0.835, width: w * 0.14,
                        thickness: max(2, short * 0.0016))
            try canvas.text(footer, in: canvas.rect(x: w * 0.075, top: h * 0.86,
                                                    width: w * 0.85, height: h * 0.075),
                            fontName: "AvenirNext-DemiBold", preferredSize: short * 0.032,
                            minimumSize: short * 0.019,
                            color: Palette.ivory.cgColor(alpha: 0.9))
        }

    case .portrait:
        if !asset.isTextFree {
            try canvas.text(title, in: canvas.rect(x: w * 0.075, top: h * 0.082,
                                                   width: w * 0.85, height: h * 0.082),
                            fontName: "Georgia-Bold", preferredSize: short * 0.077,
                            minimumSize: short * 0.046,
                            color: Palette.ivory.cgColor())
            try canvas.text(subhead, in: canvas.rect(x: w * 0.075, top: h * 0.158,
                                                     width: w * 0.85, height: h * 0.05),
                            fontName: "AvenirNext-Medium", preferredSize: short * 0.029,
                            minimumSize: short * 0.019,
                            color: Palette.ivory.cgColor(alpha: 0.82))
        }
        canvas.screenshot(images[0], in: canvas.rect(x: w * 0.035, top: h * 0.22,
                                                     width: w * 0.93, height: h * 0.755))

    case .landscape:
        if !asset.isTextFree {
            try canvas.text(title, in: canvas.rect(x: w * 0.055, top: h * 0.078,
                                                   width: w * 0.89, height: h * 0.095),
                            fontName: "Georgia-Bold", preferredSize: short * 0.079,
                            minimumSize: short * 0.043,
                            color: Palette.ivory.cgColor())
            try canvas.text(subhead, in: canvas.rect(x: w * 0.055, top: h * 0.163,
                                                     width: w * 0.87, height: h * 0.052),
                            fontName: "AvenirNext-Medium", preferredSize: short * 0.031,
                            minimumSize: short * 0.020,
                            color: Palette.ivory.cgColor(alpha: 0.82))
        }
        let heroHeight = footer.isEmpty || asset.isTextFree ? h * 0.76 : h * 0.69
        canvas.screenshot(images[0], in: canvas.rect(x: w * 0.042, top: h * 0.22,
                                                     width: w * 0.916, height: heroHeight))
        if !asset.isTextFree && !footer.isEmpty {
            try canvas.text(footer, in: canvas.rect(x: w * 0.055, top: h * 0.922,
                                                    width: w * 0.89, height: h * 0.045),
                            fontName: "AvenirNext-DemiBold", preferredSize: short * 0.024,
                            minimumSize: short * 0.016,
                            color: Palette.brass.cgColor())
        }

    case .duo:
        if !asset.isTextFree {
            try canvas.text(title, in: canvas.rect(x: w * 0.055, top: h * 0.09,
                                                   width: w * 0.89, height: h * 0.105),
                            fontName: "Georgia-Bold", preferredSize: short * 0.085,
                            minimumSize: short * 0.044,
                            color: Palette.ivory.cgColor())
            try canvas.text(subhead, in: canvas.rect(x: w * 0.055, top: h * 0.19,
                                                     width: w * 0.89, height: h * 0.055),
                            fontName: "AvenirNext-Medium", preferredSize: short * 0.031,
                            minimumSize: short * 0.020,
                            color: Palette.ivory.cgColor(alpha: 0.82))
        }
        if images.count == 1 {
            canvas.screenshot(images[0], in: canvas.rect(x: w * 0.05, top: h * 0.26,
                                                         width: w * 0.90, height: h * 0.715))
        } else {
            canvas.screenshot(images[0], in: canvas.rect(x: w * 0.055, top: h * 0.275,
                                                         width: w * 0.43, height: h * 0.665))
            canvas.screenshot(images[1], in: canvas.rect(x: w * 0.515, top: h * 0.275,
                                                         width: w * 0.43, height: h * 0.665))
        }

    case .creative:
        // Keep all text out of Apple creative artwork. The central composition
        // leaves wide dark margins for editorial placement and safe cropping.
        canvas.screenshot(images[0], in: canvas.rect(x: w * 0.09, top: h * 0.12,
                                                     width: w * 0.82, height: h * 0.76))
        canvas.context.setStrokeColor(Palette.brass.cgColor(alpha: 0.35))
        canvas.context.setLineWidth(max(2, short * 0.0012))
        canvas.context.move(to: CGPoint(x: w * 0.19, y: h * 0.07))
        canvas.context.addLine(to: CGPoint(x: w * 0.81, y: h * 0.07))
        canvas.context.strokePath()
    }

    guard let image = canvas.context.makeImage() else { throw RenderError.canvasFailed }
    return image
}

private func loadPNG(at url: URL) throws -> CGImage {
    guard url.pathExtension.lowercased() == "png",
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetType(source) as String? == UTType.png.identifier,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw RenderError.unreadableImage(url.path)
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw RenderError.imageEncodingFailed(url.path) }
    // ImageIO's PNG encoder losslessly compresses the 8-bit opaque RGB bitmap.
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw RenderError.imageEncodingFailed(url.path)
    }
}

private func renderPreview(_ items: [(label: String, url: URL)], to url: URL) throws {
    let columns = 3
    let tileWidth = 550
    let tileHeight = 430
    let gap = 30
    let rows = (items.count + columns - 1) / columns
    let canvas = try Canvas(width: gap + columns * (tileWidth + gap),
                            height: gap + rows * (tileHeight + gap))
    canvas.background()

    for (index, item) in items.enumerated() {
        let column = index % columns
        let row = index / columns
        let x = CGFloat(gap + column * (tileWidth + gap))
        let top = CGFloat(gap + row * (tileHeight + gap))
        let tile = canvas.rect(x: x, top: top, width: CGFloat(tileWidth),
                               height: CGFloat(tileHeight))
        let path = CGPath(roundedRect: tile, cornerWidth: 15,
                          cornerHeight: 15, transform: nil)
        canvas.context.setFillColor(Palette.espressoDeep.cgColor(alpha: 0.65))
        canvas.context.addPath(path)
        canvas.context.fillPath()
        canvas.context.setStrokeColor(Palette.brass.cgColor(alpha: 0.35))
        canvas.context.setLineWidth(1.5)
        canvas.context.addPath(path)
        canvas.context.strokePath()

        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 900,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw RenderError.unreadableImage(item.url.path)
        }
        let available = canvas.rect(x: x + 16, top: top + 16,
                                    width: CGFloat(tileWidth - 32),
                                    height: CGFloat(tileHeight - 62))
        let scale = min(available.width / CGFloat(image.width),
                        available.height / CGFloat(image.height))
        let imageWidth = CGFloat(image.width) * scale
        let imageHeight = CGFloat(image.height) * scale
        let fitted = CGRect(x: available.midX - imageWidth / 2,
                            y: available.midY - imageHeight / 2,
                            width: imageWidth, height: imageHeight)
        canvas.context.draw(image, in: fitted)
        try canvas.text(item.label, in: canvas.rect(x: x + 18,
                                                    top: top + CGFloat(tileHeight - 40),
                                                    width: CGFloat(tileWidth - 36), height: 28),
                        fontName: "AvenirNext-DemiBold", preferredSize: 18,
                        minimumSize: 12, color: Palette.ivory.cgColor(alpha: 0.88))
    }

    guard let image = canvas.context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
          ) else { throw RenderError.imageEncodingFailed(url.path) }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: 0.82
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw RenderError.imageEncodingFailed(url.path)
    }
    print("\(url.path) (contact sheet, \(items.count) assets)")
}

private func resolve(_ path: String, relativeTo base: URL) -> URL {
    URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let previewOnly = arguments.first == "--preview-only"
    guard arguments.count == (previewOnly ? 2 : 1) else { throw RenderError.usage }
    let manifestURL = URL(fileURLWithPath: arguments[previewOnly ? 1 : 0]).standardizedFileURL
    let manifestDirectory = manifestURL.deletingLastPathComponent()
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    guard !manifest.assets.isEmpty else {
        throw RenderError.invalidManifest("Add at least one asset.")
    }
    let outputDirectory = resolve(manifest.outputDirectory ?? "RenderedStoreAssets",
                                  relativeTo: manifestDirectory)
    try FileManager.default.createDirectory(at: outputDirectory,
                                            withIntermediateDirectories: true)
    var usedNames = Set<String>()
    var previewItems: [(label: String, url: URL)] = []

    for asset in manifest.assets {
        let subdirectory = asset.subdirectory ?? ""
        let pathComponents = subdirectory.split(separator: "/", omittingEmptySubsequences: false)
        guard subdirectory.isEmpty || pathComponents.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".." && !component.contains("\\")
        }) else {
            throw RenderError.invalidManifest("Subdirectory must be a relative folder path without traversal.")
        }
        let stem = asset.name.lowercased().hasSuffix(".png")
            ? String(asset.name.dropLast(4)) : asset.name
        guard !stem.isEmpty, stem != ".", stem != "..",
              !stem.contains("/"), !stem.contains("\\"),
              usedNames.insert("\(subdirectory)/\(stem)".lowercased()).inserted else {
            throw RenderError.invalidManifest("Each asset needs a unique PNG filename, with no path separators.")
        }
        guard (256...12_000).contains(asset.width),
              (256...12_000).contains(asset.height),
              Int64(asset.width) * Int64(asset.height) <= 80_000_000 else {
            throw RenderError.invalidManifest("\(stem) has unsupported pixel dimensions.")
        }
        let paths = asset.sourcePaths
        guard !paths.isEmpty, paths.count <= (asset.style == .duo ? 2 : 1),
              asset.screenshot == nil || asset.screenshots == nil else {
            throw RenderError.invalidManifest("\(stem) needs one PNG screenshot (duo may use two).")
        }
        if asset.style == .creative {
            guard [asset.headline, asset.subhead, asset.footer, asset.eyebrow]
                .allSatisfy({ $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }) else {
                throw RenderError.invalidManifest("\(stem) creative artwork must be text-free.")
            }
        } else if !asset.isTextFree {
            guard !(asset.headline?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
                throw RenderError.invalidManifest("\(stem) needs a headline.")
            }
        }
        let images = try paths.map { try loadPNG(at: resolve($0, relativeTo: manifestDirectory)) }
        let destinationDirectory = outputDirectory.appendingPathComponent(subdirectory)
        try FileManager.default.createDirectory(at: destinationDirectory,
                                                withIntermediateDirectories: true)
        let outputURL = destinationDirectory.appendingPathComponent(stem).appendingPathExtension("png")
        if previewOnly {
            let existing = try loadPNG(at: outputURL)
            guard existing.width == asset.width, existing.height == asset.height else {
                throw RenderError.invalidManifest("\(stem) output dimensions differ from the manifest.")
            }
        } else {
            let rendered = try render(asset, images: images)
            try writePNG(rendered, to: outputURL)
        }
        previewItems.append((label: "\(subdirectory) / \(stem)", url: outputURL))
        print("\(outputURL.path) (\(asset.width)×\(asset.height), opaque RGB)")
    }

    if let previewFile = manifest.previewFile {
        guard !previewFile.isEmpty, !previewFile.contains("/"),
              !previewFile.contains("\\"),
              ["jpg", "jpeg"].contains(URL(fileURLWithPath: previewFile).pathExtension.lowercased()) else {
            throw RenderError.invalidManifest("previewFile must be a JPEG filename beside the manifest.")
        }
        try renderPreview(previewItems,
                          to: manifestDirectory.appendingPathComponent(previewFile))
    }
}

do {
    try run()
} catch {
    fputs("render-store-assets: \(error.localizedDescription)\n", stderr)
    exit(1)
}
