// Shows layer trees saved by the 3D spike's tests in a window, as the canvas
// shows the renderer's, captures each and compares it with the same tree
// drawn off screen, as exports are.
//
//     cd Packages/MotionKit && TWINE_SPIKE_OUT=/some/folder swift test --filter Space3DRenderingTests/savedForTheScreen
//     swiftc -O Tools/Spike3D/show-on-screen.swift -o /some/folder/show && /some/folder/show /some/folder ring strips mesh
//
// For each NAME it reads NAME.layers and NAME-export.png and writes
// NAME-screen.png. The window floats over the others for a second without
// taking the keyboard: the window server does not draw a hidden window.
import AppKit

final class Flipped: NSView { override var isFlipped: Bool { true } }

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
var names = Array(CommandLine.arguments.dropFirst(2))
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

func image(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// RGBA in sRGB at `size`, laid over white.
func pixels(_ image: CGImage, size: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    let context = CGContext(data: &bytes, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return bytes
}

func next() {
    guard let name = names.first else { exit(0) }
    names.removeFirst()
    let exportURL = folder.appendingPathComponent("\(name)-export.png")
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).layers")),
          let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data),
          let export = image(exportURL) else { print("\(name): nothing saved"); next(); return }
    unarchiver.requiresSecureCoding = false
    guard let layer = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? CALayer else {
        print("\(name): not a layer"); next(); return
    }
    let size = export.width
    let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: size, height: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.backgroundColor = .white
    let view = Flipped(frame: NSRect(x: 0, y: 0, width: size, height: size))
    view.wantsLayer = true
    view.layerUsesCoreImageFilters = true
    window.contentView = view
    view.layer?.addSublayer(layer)
    window.level = .floating
    window.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        let shotURL = folder.appendingPathComponent("\(name)-screen.png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l\(window.windowNumber)", shotURL.path]
        try? capture.run()
        capture.waitUntilExit()
        window.orderOut(nil)
        guard let shot = image(shotURL) else { print("\(name): no capture"); next(); return }
        let a = pixels(export, size: size), b = pixels(shot, size: size)
        var differing = 0, total = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            let d = (0..<3).map { abs(Int(a[i + $0]) - Int(b[i + $0])) }
            total += d.reduce(0, +)
            if d.contains(where: { $0 > 24 }) { differing += 1 }
        }
        let share = Double(differing) / Double(size * size) * 100
        print(String(format: "%@: %.2f%% of pixels differ by more than 24 of 255, mean difference %.2f",
                     name, share, Double(total) / Double(size * size * 3)))
        next()
    }
}

DispatchQueue.main.async { next() }
app.run()
