import Foundation
import QuartzCore
import Metal
import IOSurface
import CoreGraphics
import MotionEvaluation

/// What is behind one glass, drawn by Twine itself rather than seen through a
/// `CABackdropLayer`. On screen a backdrop shows whatever the window server
/// has where it lies: other windows, the Dock and the menu bar all bent into
/// the glass near the window's edges, and under the title bar it saw behind
/// the window altogether (20 October 2026). Drawn here, the glass can only
/// ever show the composition, the same on the canvas as in an export.
///
/// The layers behind the glass are drawn by a `CoreAnimationRenderer` of its
/// own, through `CARenderer`, into a picture in the glass layer's own points
/// covering `GlassLayers`' area, which the glass shows and bends. The picture
/// is an `IOSurface`, so it goes to the screen without a copy; there are two,
/// drawn into in turn, so the screen never shows one half drawn and always
/// sees a new picture as new. A scene drawn as it was last time is not drawn
/// again.
final class GlassBehind {
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()

    private let root = CALayer()
    private let renderer = CoreAnimationRenderer()
    private var caRenderer: CARenderer?
    private var surfaces: [(surface: IOSurface, texture: MTLTexture)] = []
    private var shown = 0
    private var last: (scene: ResolvedScene, transform: Projective, width: Int, height: Int, scale: CGFloat)?

    /// The longest side a picture is drawn at; bigger glass is drawn coarser.
    static let largestSide = 4096

    init() {
        root.anchorPoint = .zero
        root.actions = Node.noActions
        root.addSublayer(renderer.rootLayer)
        renderer.flipsContents = true
    }

    /// The picture of `scene` (the layers behind the glass) seen through
    /// `transform`, which takes composition points to the picture's pixels,
    /// at `width` by `height` pixels; `contentsScale` is how finely pictures
    /// and text in it are drawn. Nil without a GPU.
    func draw(_ scene: ResolvedScene, transform: Projective, width: Int, height: Int, contentsScale: CGFloat,
              media: MediaProvider?) -> IOSurface? {
        // On a queue of its own, which the caller waits for: Core Animation's
        // transactions are the thread's, so flushing for CARenderer there
        // never flushes the canvas's, which SwiftUI may be in the middle of
        // (flushing during a view update once stopped the app).
        Self.work.sync { drawHere(scene, transform: transform, width: width, height: height,
                                  contentsScale: contentsScale, media: media) }
    }
    private static let work = DispatchQueue(label: "Twine.GlassBehind")

    private func drawHere(_ scene: ResolvedScene, transform: Projective, width: Int, height: Int, contentsScale: CGFloat,
                          media: MediaProvider?) -> IOSurface? {
        guard width > 0, height > 0 else { return nil }
        if let last, last.scene == scene, last.transform == transform, last.width == width, last.height == height,
           last.scale == contentsScale, !surfaces.isEmpty {
            return surfaces[shown].surface
        }
        guard let queue = Self.queue, prepare(width: width, height: height) else { return nil }
        last = (scene, transform, width, height, contentsScale)
        let next = (shown + 1) % surfaces.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.media = media
        if renderer.contentsScale != contentsScale { renderer.contentsScale = contentsScale }
        renderer.render(scene)
        renderer.rootLayer.transform = transform.caTransform
        CATransaction.commit()
        // CARenderer sees only what has been flushed.
        CATransaction.flush()

        guard let caRenderer else { return nil }
        caRenderer.setDestination(surfaces[next].texture)
        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = surfaces[next].texture
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
        // An empty buffer after CARenderer's own completes once the picture
        // is whole, before the screen is handed it.
        if let fence = queue.makeCommandBuffer() {
            fence.commit()
            fence.waitUntilCompleted()
        }
        shown = next
        return surfaces[shown].surface
    }

    /// Makes the pictures and the renderer for a size, keeping them while
    /// the size stays.
    private func prepare(width: Int, height: Int) -> Bool {
        if let first = surfaces.first, first.texture.width == width, first.texture.height == height, caRenderer != nil {
            return true
        }
        guard let device = Self.device, let queue = Self.queue else { return false }
        var made: [(IOSurface, MTLTexture)] = []
        // Metal takes a surface's rows only on whole steps of 16 bytes (a
        // 2,254 pixel wide picture, zoomed in, stopped the app); 64 suits
        // the GPU better still.
        let rowBytes = (width * 4 + 63) / 64 * 64
        for _ in 0..<2 {
            guard let surface = IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4, .bytesPerRow: rowBytes,
                .pixelFormat: kCVPixelFormatType_32BGRA,
            ]) else { return false }
            // Tagged, so the screen reads its colours as sRGB, as everything
            // else Twine draws.
            if let srgb = CGColorSpace(name: CGColorSpace.sRGB), let list = srgb.copyPropertyList() {
                IOSurfaceSetValue(surface, kIOSurfaceColorSpace, list)
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                      height: height, mipmapped: false)
            // CARenderer draws nothing at all without `.shaderWrite`.
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else { return false }
            made.append((surface, texture))
        }
        surfaces = made.map { (surface: $0.0, texture: $0.1) }
        shown = 0
        last = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(x: 0, y: 0, width: width, height: height)
        CATransaction.commit()
        let caRenderer = self.caRenderer ?? CARenderer(mtlTexture: made[0].1, options: [
            kCARendererMetalCommandQueue as String: queue,
            kCARendererColorSpace as String: CGColorSpace(name: CGColorSpace.sRGB)!,
        ])
        caRenderer.layer = root
        caRenderer.bounds = root.bounds
        self.caRenderer = caRenderer
        CATransaction.flush()
        return true
    }
}
