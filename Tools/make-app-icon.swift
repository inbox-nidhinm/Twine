// Makes the app icon from the designer's artwork and writes it as an .icns.
//
//     swift Tools/make-app-icon.swift Artwork/AppIcon.png Twine/Resources/AppIcon.icns
//
// The artwork is a full-bleed square. It is set into the macOS icon grid, an
// 824 pt rounded square inside a 1024 pt canvas, with the soft shadow Mac
// icons carry, so it sits in the Dock and Finder like every other app.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-app-icon.swift <artwork.png> <output.icns>\n".utf8))
    exit(1)
}
let artworkURL = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
guard let source = CGImageSourceCreateWithURL(artworkURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(artworkURL.path)\n".utf8))
    exit(1)
}

func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

let canvas: CGFloat = 1024
let ctx = context(Int(canvas))
ctx.interpolationQuality = .high
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// The tile's shadow, cast by a filled tile drawn under the artwork.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// The artwork, filling the tile and clipped to its corners.
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.draw(artwork, in: tile)
ctx.restoreGState()

guard let master = ctx.makeImage() else { exit(1) }

let iconset = output.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let pixels = points * scale
    let c = context(pixels)
    c.interpolationQuality = .high
    c.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    let dest = CGImageDestinationCreateWithURL(iconset.appendingPathComponent(name) as CFURL,
                                               "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, c.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("wrote \(output.path)")
