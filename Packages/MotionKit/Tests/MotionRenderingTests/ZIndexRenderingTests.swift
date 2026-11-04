import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// A Z-Index drawn: the renderer exports use puts the layer in front of or
/// behind its siblings, from the action's start.
@Suite(.serialized) struct ZIndexRenderingTests {
    @Test func theLayerIsDrawnWhereItsNumberSays() throws {
        let side = 200
        let red = RGBA(hex: "FF0000")!, blue = RGBA(hex: "0000FF")!, green = RGBA(hex: "00FF00")!
        func square(_ c: RGBA, x: Double, y: Double = 100) -> Layer {
            Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .solid(c))])),
                  size: Size2(100, 100), position: Vec2(x, y))
        }
        // Red at the back of the list, overlapping blue; green inside a
        // group beside them, overlapping both.
        let back = square(red, x: 80), front = square(blue, x: 120)
        let inner = square(green, x: 100, y: 140)
        let group = Layer(name: "G", content: .group(GroupContent(children: [inner])), size: Size2(200, 200), position: Vec2(100, 100))
        let actions = [Action(target: back.id, start: 1, duration: 0, spec: .zIndex(ZIndexAction(index: 1))),
                       Action(target: group.id, start: 2, duration: 0, spec: .zIndex(ZIndexAction(index: -1)))]
        let project = Project(composition: Composition(width: side, height: side, background: Background(isTransparent: true)),
                              layers: [back, front, group], actions: actions)
        let renderer = try #require(OffscreenRenderer(pixelWidth: side, pixelHeight: side))
        func colour(at time: Double, _ x: Int, _ y: Int) throws -> Space3DRenderingTests.Pixel {
            let bytes = Space3DRenderingTests.pixels(try #require(renderer.image(of: evaluate(project, at: time))), width: side, height: side)
            return Space3DRenderingTests.pixel(bytes, width: side, x, y)
        }
        // Red is 30 to 130 across, blue 70 to 170, both 50 to 150 down;
        // green 50 to 150 across, 90 to 190 down. Where only red and blue
        // overlap, blue is in front, then red once its number is 1.
        #expect(try colour(at: 0.5, 100, 70).near(blue))
        #expect(try colour(at: 1.5, 100, 70).near(red))
        // The group with green is last in the list, so in front of both,
        // until red's 1 beats its 0.
        #expect(try colour(at: 0.5, 100, 120).near(green))
        #expect(try colour(at: 1.5, 100, 120).near(red))
        // Where green and blue overlap, green is in front until its group's
        // own number, -1, sends it behind.
        #expect(try colour(at: 1.5, 140, 120).near(green))
        #expect(try colour(at: 2.5, 140, 120).near(blue))
    }
}
