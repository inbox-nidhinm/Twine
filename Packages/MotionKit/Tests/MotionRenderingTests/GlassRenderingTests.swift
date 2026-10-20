import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// Figma's Glass drawn off screen, as exports are: what is behind bends
/// near the edge and only there, the rim catches the light from Figma's
/// angle, and outlines that are not boxes bend too. `TWINE_GLASS_OUT=folder`
/// writes each picture there to look at.
@Suite struct GlassRenderingTests {
    private struct Pixel: Equatable { var r: Int, g: Int, b: Int }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return Pixel(r: Int(bytes[0]), g: Int(bytes[1]), b: Int(bytes[2]))
    }

    private func brightness(_ p: Pixel) -> Int { p.r + p.g + p.b }

    /// Upright stripes, red and blue on white, 10 wide every 20, across a
    /// 400 by 300 scene; or, `dark`, a plain dark blue.
    private func ground(dark: Bool) -> [Layer] {
        guard !dark else {
            return [Layer(name: "Ground", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                      fills: [Fill(paint: .color(RGBA(0.15, 0.2, 0.3)))])),
                          size: Size2(400, 300), position: Vec2(200, 150))]
        }
        return stride(from: 0, to: 400, by: 20).map { x in
            Layer(name: "Stripe", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                               fills: [Fill(paint: .color(x % 40 == 0 ? RGBA(0.9, 0.2, 0.2) : RGBA(0.1, 0.3, 0.9)))])),
                  size: Size2(10, 300), position: Vec2(Double(x) + 5, 150))
        }
    }

    /// A 200 by 150 card with no fill in the middle of the scene, with
    /// `glass` (none when nil), over the stripes or the dark ground.
    private func scene(_ glass: Glass?, geometry: ShapeGeometry = .rectangle(cornerRadii: CornerRadii(all: 40)),
                       dark: Bool = false, name: String) throws -> CGImage {
        var card = Layer(name: "Card", content: .shape(ShapeContent(geometry: geometry, fills: [])),
                         size: Size2(200, 150), position: Vec2(200, 150))
        if let glass { card.effects = [Effect(kind: .glass(glass))] }
        let project = Project(composition: Composition(width: 400, height: 300, background: Background(color: .white)),
                              layers: ground(dark: dark) + [card])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 400, pixelHeight: 300))
        let image = try #require(renderer.image(of: evaluate(project, at: 0)))
        if let folder = ProcessInfo.processInfo.environment["TWINE_GLASS_OUT"],
           let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: folder).appendingPathComponent(name + ".png") as CFURL,
                                                             UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return image
    }

    /// How many of the pixels along row `y`, from `x0` to `x1`, differ.
    private func differences(_ a: CGImage, _ b: CGImage, y: Int, from x0: Int, to x1: Int) -> Int {
        (x0..<x1).filter { pixel(a, $0, y) != pixel(b, $0, y) }.count
    }

    @Test func glassBendsWhatIsBehindNearItsEdgeOnly() throws {
        guard GlassKit.bends else { return }
        let bare = try scene(nil, name: "bare")
        let bent = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0, frost: 0), name: "bent")
        // The card runs x 100 to 300, y 75 to 225.
        #expect(differences(bare, bent, y: 150, from: 101, to: 124) > 4, "the stripes bend inside the left edge")
        #expect(differences(bare, bent, y: 150, from: 277, to: 299) > 4, "and inside the right edge")
        #expect(differences(bare, bent, y: 150, from: 150, to: 250) == 0, "the middle is left as it is")
        #expect(differences(bare, bent, y: 150, from: 0, to: 96) == 0, "and so is everything outside")
    }

    @Test func dispersionSplitsTheBentEdgeIntoColours() throws {
        guard GlassKit.bends else { return }
        let bent = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0, frost: 0), name: "plain")
        let split = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 1, frost: 0), name: "split")
        #expect(differences(bent, split, y: 150, from: 101, to: 124) > 2)
        #expect(differences(bent, split, y: 150, from: 150, to: 250) == 0)
    }

    @Test func frostBlursTheWholeCard() throws {
        let bare = try scene(nil, name: "bare")
        let frosted = try scene(Glass(lightIntensity: 0, refraction: 0, depth: 0, dispersion: 0, frost: 12), name: "frosted")
        // In the middle of a stripe, and of a white gap, the colours run together.
        #expect(pixel(frosted, 205, 150) != pixel(bare, 205, 150))
        #expect(pixel(frosted, 195, 150) != pixel(bare, 195, 150))
        #expect(pixel(frosted, 205, 40) == pixel(bare, 205, 40), "nothing outside the card blurs")
    }

    @Test func theRimCatchesTheLightFromFigmasAngle() throws {
        guard GlassKit.bends else { return }
        let dark = try scene(nil, dark: true, name: "dark")
        // From the top left, Figma's own: brighter there than at the bottom
        // right, which takes only the softer opposite light, and the middle
        // stays dark.
        let lit = try scene(Glass(lightAngle: -45, lightIntensity: 1, refraction: 0, depth: 20, dispersion: 0, frost: 0),
                            dark: true, name: "lit")
        let topLeft = brightness(pixel(lit, 112, 90)), bottomRight = brightness(pixel(lit, 288, 210))
        #expect(topLeft > brightness(pixel(dark, 112, 90)) + 60)
        #expect(topLeft > bottomRight)
        #expect(brightness(pixel(lit, 200, 150)) < brightness(pixel(dark, 200, 150)) + 10)
        // Turned to the bottom right, the other way round.
        let turned = try scene(Glass(lightAngle: 135, lightIntensity: 1, refraction: 0, depth: 20, dispersion: 0, frost: 0),
                               dark: true, name: "turned")
        #expect(brightness(pixel(turned, 288, 210)) > brightness(pixel(turned, 112, 90)))
    }

    @Test func anOutlineThatIsNotABoxBendsAlongItself() throws {
        guard GlassKit.bends else { return }
        let star = ShapeGeometry.star(points: 5, innerRadius: 0.5, cornerRadius: 0)
        let bare = try scene(nil, geometry: star, name: "star-bare")
        let bent = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 16, dispersion: 0, frost: 0), geometry: star, name: "star")
        #expect(differences(bare, bent, y: 150, from: 100, to: 300) > 6)
        // An oval, which is no rounded box either.
        let oval = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0, frost: 0),
                             geometry: .ellipse(arc: .full), name: "oval")
        let ovalBare = try scene(nil, geometry: .ellipse(arc: .full), name: "oval-bare")
        #expect(differences(ovalBare, oval, y: 150, from: 101, to: 124) > 4)
        #expect(differences(ovalBare, oval, y: 150, from: 160, to: 240) == 0)
    }

    @Test func depthStopsAtTheMiddleOfTheShape() throws {
        // On the 200 by 150 card, any depth past 75 draws as 75 does: deeper,
        // the bend turned the middle inside out and, on screen, pulled in
        // whatever was hundreds of points away, past the window too.
        guard GlassKit.bends else { return }
        let half = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 75, dispersion: 0.5, frost: 0), name: "half")
        let deep = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 639, dispersion: 0.5, frost: 0), name: "deep")
        for y in [80, 120, 150, 200] { #expect(differences(half, deep, y: y, from: 0, to: 400) == 0) }
        #expect(GlassKit.fitted(Glass(depth: 639), to: Size2(248, 300)).depth == 124)
        #expect(GlassKit.margin(GlassKit.fitted(Glass(depth: 639, frost: 1000), to: Size2(248, 300))) == 196)
    }

    @Test func aFieldPictureFollowsTheZoom() throws {
        // A 60 point star shown at 8 pixels a point is worked out at 8
        // texels a point, not stretched from 1; a huge one stays within
        // the largest side.
        let star = CGPath(ellipseIn: CGRect(x: 10, y: 10, width: 40, height: 40), transform: nil)
        let fine = try #require(GlassField.picture(of: star, size: CGSize(width: 60, height: 60), range: 8, flips: false, texelsPerPoint: 8))
        #expect(fine.width == 480 && fine.height == 480)
        let huge = try #require(GlassField.picture(of: star, size: CGSize(width: 4000, height: 2000), range: 8, flips: false, texelsPerPoint: 8))
        #expect(huge.width == GlassField.largestSide && huge.height == GlassField.largestSide / 2)
    }

    @Test func aFieldPictureReadsTheDistanceAndTheWayOut() throws {
        // A 40 square inside a 60 picture, 10 from each side, held to 8.
        let path = CGPath(rect: CGRect(x: 10, y: 10, width: 40, height: 40), transform: nil)
        let image = try #require(GlassField.picture(of: path, size: CGSize(width: 60, height: 60), range: 8, flips: false))
        #expect(image.width == 60 && image.height == 60)
        let data = try #require(image.dataProvider?.data as Data?)
        func texel(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let o = (y * 60 + x) * 8
            func channel(_ c: Int) -> Double { Double(UInt16(data[o + c * 2]) | UInt16(data[o + c * 2 + 1]) << 8) / 65535 }
            return (channel(0), channel(1), channel(2))
        }
        // Deep inside: as far in as the field reaches, no way out to speak of.
        #expect(texel(30, 30).0 == 0)
        // Just inside the left side: about 2.5 in, the way out to the left.
        let left = texel(12, 30)
        #expect(abs((left.0 * 16 - 8) - -2.5) < 0.1)
        #expect(left.1 < 0.01 && abs(left.2 - 0.5) < 0.01)
        // Just outside the bottom: about 2.5 out, the way out downward.
        let below = texel(30, 52)
        #expect(abs((below.0 * 16 - 8) - 2.5) < 0.1)
        #expect(below.2 > 0.99)
    }
}
