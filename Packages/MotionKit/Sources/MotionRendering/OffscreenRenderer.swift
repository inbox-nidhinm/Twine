import Foundation
import QuartzCore
import Metal
import CoreGraphics
import MotionEvaluation

/// Renders scenes off screen, through the same `CoreAnimationRenderer` the
/// canvas uses, into a Metal texture. Thumbnails use it now; export uses it
/// from milestone 5, adding a pixel buffer in place of the image at the end.
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
    private let renderer = CoreAnimationRenderer()

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
        CATransaction.commit()
        caRenderer.layer = root
        caRenderer.bounds = root.bounds
        CATransaction.flush()
    }

    /// Draws `scene` scaled to fill the output and returns the pixels, with
    /// alpha kept where the background is transparent.
    public func image(of scene: ResolvedScene) -> CGImage? {
        draw(scene)
        let bytesPerRow = pixelWidth * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
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
