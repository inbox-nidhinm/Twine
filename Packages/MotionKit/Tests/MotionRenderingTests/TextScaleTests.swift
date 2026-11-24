import Foundation
import Testing
import QuartzCore
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// Text is a picture drawn at a scale: how big it is drawn, and when it is
/// drawn again.
@Suite(.serialized) struct TextScaleTests {
    /// The widths in pixels of every picture in the layer tree.
    private func pictures(in layer: CALayer) -> [Int] {
        var widths: [Int] = []
        if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            widths.append((contents as! CGImage).width)
        }
        for sub in layer.sublayers ?? [] { widths += pictures(in: sub) }
        return widths
    }

    private func scene(_ words: String = "Title", fontSize: Double = 40) -> ResolvedScene {
        let text = Layer(name: "Text", content: .text(TextContent(text: words, fontSize: fontSize)),
                         size: Size2(200, fontSize * 1.2), position: Vec2(300, 200))
        return evaluateDesign(Project(composition: Composition(width: 600, height: 400), layers: [text]))
    }

    /// A pinch changes the scale on every step: texts keep the pictures
    /// they have until the zoom rests, then are drawn once at the new scale.
    @Test func textsKeepTheirPicturesWhileTheScaleIsChanging() throws {
        let renderer = CoreAnimationRenderer()
        renderer.contentsScale = 2
        let scene = scene()
        renderer.render(scene)
        let before = try #require(pictures(in: renderer.rootLayer).max())

        renderer.holdsTextScale = true
        for scale in [2.3, 2.9, 3.6, 4.0] as [CGFloat] {
            renderer.contentsScale = scale
            renderer.render(scene)
            #expect(pictures(in: renderer.rootLayer).max() == before)
        }
        renderer.holdsTextScale = false
        renderer.render(scene)
        let after = try #require(pictures(in: renderer.rootLayer).max())
        #expect(abs(Double(after) - Double(before) * 2) <= 2)

        // Not held, a new scale draws the text again at once, as an export's does.
        renderer.contentsScale = 2
        renderer.render(scene)
        #expect(pictures(in: renderer.rootLayer).max() == before)
    }

    /// However far the canvas is zoomed, a text's picture is no longer than
    /// `TextImage.maxSide` on its longer side (give or take its margin).
    @Test func aTextsPictureIsHeldToItsLongestSide() {
        let renderer = CoreAnimationRenderer()
        renderer.contentsScale = 16
        // A headline a thousand points or so long: at 16 pixels a point it
        // asks for twice the limit.
        let wide = scene("A headline long enough to matter here", fontSize: 64)
        #expect(wide.layers[0].size.width > 600)
        renderer.render(wide)
        let widest = pictures(in: renderer.rootLayer).max() ?? 0
        #expect(widest > 0 && Double(widest) <= TextImage.maxSide * 1.1)
        // And an ordinary text is drawn at the full scale.
        let layer = wide.layers[0]
        #expect(CoreAnimationRenderer.textZoom(of: layer, in: scene(), scale: 2) == 1)
        #expect(CoreAnimationRenderer.textZoom(of: layer, in: wide, scale: 16) < 1)
    }
}
