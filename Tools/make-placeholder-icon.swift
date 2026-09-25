// Draws eMotion's placeholder app icon and writes it as an .icns.
//
//     swift Tools/make-placeholder-icon.swift eMotion/Resources/AppIcon.icns
//
// A stand-in until the real artwork exists: the macOS icon grid (an 824pt
// rounded square inside a 1024pt canvas), filled with the accent, carrying a
// dot with two fading echoes behind it, which is about as literal as "motion"
// gets. Replace the drawing, not the pipeline, when the real icon arrives.
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-placeholder-icon.swift <output.icns>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: args[1])

func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

let canvas: CGFloat = 1024
let ctx = context(Int(canvas))
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// The tile, with the soft drop shadow macOS icons carry.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(srgbRed: 0x4C / 255, green: 0x9F / 255, blue: 0xEF / 255, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Lighter at the top, as if lit from above.
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [CGColor(srgbRed: 0.55, green: 0.78, blue: 1, alpha: 1),
                                   CGColor(srgbRed: 0.18, green: 0.47, blue: 0.86, alpha: 1)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// A dot in motion: the dot, and two echoes trailing to its left.
let y: CGFloat = 512
for (x, radius, alpha) in [(330.0, 70.0, 0.28), (450.0, 92.0, 0.55), (610.0, 128.0, 1.0)] {
    ctx.setFillColor(CGColor(gray: 1, alpha: alpha))
    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
}

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
