import Foundation
import AppKit
import ImageIO
import MotionModel
import MotionEvaluation

/// Drawing SVG the system's way, for the parts of a file Twine cannot make
/// editable. AppKit reads SVG into an image natively; it draws text, clips
/// and masks, though not filters.
enum SVGPictures {
    /// `svg` drawn at `scale` times `size`, trimmed to what it draws: the
    /// PNG, and the box it covers in the SVG's own units. Nil when it draws
    /// nothing.
    static func draw(_ svg: String, size: Size2, scale: Double) -> (png: Data, box: Box)? {
        // One drawing at a time: the system's SVG drawing asks the font
        // service for every text's font, and many threads asking at once
        // (the tests, in parallel) left them all waiting on it for good.
        drawing.lock()
        defer { drawing.unlock() }
        guard size.width.isFinite, size.height.isFinite, scale.isFinite, let image = NSImage(data: Data(svg.utf8)) else { return nil }
        let s = drawingScale(size: size, scale: scale)
        let w = Int((size.width * s).rounded(.up)), h = Int((size.height * s).rounded(.up))
        guard w > 0, h > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let full = context.makeImage(), let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        // What it covers: rows run from the top in memory.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = bytes + y * w * 4
            for x in 0..<w where row[x * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let trimmed = full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, trimmed, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let box = Box(minX: Double(minX) / s, minY: Double(minY) / s, maxX: Double(maxX + 1) / s, maxY: Double(maxY + 1) / s)
        return (data as Data, box)
    }

    /// At most 8192 pixels a side, however large the drawing.
    private static func drawingScale(size: Size2, scale: Double) -> Double {
        min(scale, 8192 / max(size.width, size.height, 1))
    }

    /// How many pixels `draw` covers for a drawing `size` at `scale`.
    static func pixels(size: Size2, scale: Double) -> Double {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite else { return 0 }
        let s = drawingScale(size: size, scale: scale)
        return (size.width * s).rounded(.up) * (size.height * s).rounded(.up)
    }

    private static let drawing = NSLock()

    /// A picture file's size in pixels, the way round it shows.
    static func pixelSize(of data: Data) -> Size2? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var w = properties[kCGImagePropertyPixelWidth] as? Int, var h = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        if let o = properties[kCGImagePropertyOrientation] as? Int, o >= 5 { swap(&w, &h) }
        return Size2(Double(w), Double(h))
    }
}
