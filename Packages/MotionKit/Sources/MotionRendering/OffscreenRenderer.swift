import Foundation
import Accelerate
import QuartzCore
import Metal
import CoreGraphics
import CoreVideo
import MotionEvaluation

/// Renders scenes off screen, through the same `CoreAnimationRenderer` the
/// canvas uses, into a Metal texture. Thumbnails and stills read it back as an
/// image; movie export copies it straight into each frame's pixel buffer.
///
/// `CARenderer` draws the layer tree on the GPU without a window, and does so
/// only when asked, so the output depends on the scene and never on a clock.
public final class OffscreenRenderer {
    public let pixelWidth: Int
    public let pixelHeight: Int

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let texture: MTLTexture
    private let caRenderer: CARenderer
    private let root = CALayer()
    let renderer = CoreAnimationRenderer()

    /// Where image and video layers get their pictures.
    public var media: MediaProvider? {
        get { renderer.media }
        set { renderer.media = newValue }
    }

    /// Nil when there is no GPU to render with.
    public init?(pixelWidth: Int, pixelHeight: Int) {
        guard pixelWidth > 0, pixelHeight > 0,
              let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pixelWidth,
                                                                  height: pixelHeight, mipmapped: false)
        // CARenderer writes into the texture from a compute pass as well as a
        // render pass. Without `.shaderWrite` it draws nothing at all.
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.device = device
        self.queue = queue
        self.texture = texture
        caRenderer = CARenderer(mtlTexture: texture, options: [
            kCARendererMetalCommandQueue as String: queue,
            kCARendererColorSpace as String: CGColorSpace(name: CGColorSpace.sRGB)!,
        ])

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        // No flip here. Layers lay out with y up, but a Metal texture stores
        // its rows top first, and the two cancel: the composition's top-left
        // lands on the image's top-left as it is.
        root.addSublayer(renderer.rootLayer)
        renderer.contentsScale = 1
        renderer.flipsContents = true
        CATransaction.commit()
        caRenderer.layer = root
        caRenderer.bounds = root.bounds
        CATransaction.flush()
    }

    /// Draws `scene` scaled to fill the output and returns the pixels, with
    /// alpha kept where the background is transparent.
    public func image(of scene: ResolvedScene) -> CGImage? {
        let bytesPerRow = pixelWidth * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        bytes.withUnsafeMutableBytes { frame(of: scene, into: $0.baseAddress!, bytesPerRow: bytesPerRow) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Draws `scene` into `buffer`, which must be 32-bit BGRA at this
    /// renderer's size. The pixels are premultiplied, as Core Animation
    /// draws them, with the top row first.
    public func render(_ scene: ResolvedScene, into buffer: CVPixelBuffer) {
        precondition(CVPixelBufferGetWidth(buffer) == pixelWidth && CVPixelBufferGetHeight(buffer) == pixelHeight
                     && CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
                     "the pixel buffer must match the renderer")
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        frame(of: scene, into: base, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
    }

    /// Draws `scene` and copies its pixels to `base`. With motion blur worked
    /// out exactly, it draws the scene at every moment across the shutter
    /// and averages them in full precision, rounding once at the end: Core
    /// Animation's own copies are each rounded to a whole step of 255 first,
    /// which added a light card up to white.
    private func frame(of scene: ResolvedScene, into base: UnsafeMutableRawPointer, bytesPerRow: Int) {
        let region = MTLRegionMake2D(0, 0, pixelWidth, pixelHeight)
        guard let moments = scene.shutterScenes else {
            draw(scene)
            texture.getBytes(base, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
            return
        }
        let rowBytes = pixelWidth * 4, length = rowBytes * pixelHeight
        var pixels = [UInt8](repeating: 0, count: length)
        var values = [Float](repeating: 0, count: length)
        var sum = [Float](repeating: 0, count: length)
        for moment in moments {
            draw(moment)
            texture.getBytes(&pixels, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
            vDSP_vfltu8(pixels, 1, &values, 1, vDSP_Length(length))
            vDSP_vadd(sum, 1, values, 1, &sum, 1, vDSP_Length(length))
        }
        var share = 1 / Float(moments.count)
        vDSP_vsmul(sum, 1, &share, &sum, 1, vDSP_Length(length))
        vDSP_vfixru8(sum, 1, &pixels, 1, vDSP_Length(length))
        pixels.withUnsafeBytes { from in
            for row in 0..<pixelHeight {
                (base + row * bytesPerRow).copyMemory(from: from.baseAddress! + row * rowBytes, byteCount: rowBytes)
            }
        }
    }

    private func draw(_ scene: ResolvedScene) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.render(scene)
        let sx = scene.size.width > 0 ? Double(pixelWidth) / scene.size.width : 1
        let sy = scene.size.height > 0 ? Double(pixelHeight) / scene.size.height : 1
        renderer.contentsScale = max(sx, sy)
        renderer.rootLayer.transform = CATransform3DMakeScale(sx, sy, 1)
        CATransaction.commit()
        // Off the main thread nothing flushes transactions on its own, and
        // CARenderer only sees what has been flushed.
        CATransaction.flush()

        // Start from transparent, so a transparent background stays so.
        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = texture
        clear.colorAttachments[0].loadAction = .clear
        clear.colorAttachments[0].storeAction = .store
        clear.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        if let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: clear) {
            encoder.endEncoding()
            buffer.commit()
        }

        caRenderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        caRenderer.addUpdate(caRenderer.bounds)
        caRenderer.render()
        caRenderer.endFrame()

        // CARenderer encodes onto the same queue, so an empty buffer committed
        // after it completes only once the frame is on the texture.
        if let fence = queue.makeCommandBuffer() {
            fence.commit()
            fence.waitUntilCompleted()
        }
    }
}
