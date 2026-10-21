import Foundation
import Testing
import CoreGraphics
import ImageIO
import IOSurface
import QuartzCore
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
    /// `glass` (none when nil), over the stripes or the dark ground, turned
    /// by `turn` degrees, and with a green bar over its left side when
    /// `front`. `drawn` (the default) draws what is behind the glass as the
    /// canvas and exports do (`GlassBehind`); without it, glass sees through
    /// backdrops, as exports did until 21 October 2026.
    private func scene(_ glass: Glass?, geometry: ShapeGeometry = .rectangle(cornerRadii: CornerRadii(all: 40)),
                       dark: Bool = false, visible: CGRect? = nil, drawn: Bool = true, turn: Double = 0,
                       front: Bool = false, name: String) throws -> CGImage {
        var card = Layer(name: "Card", content: .shape(ShapeContent(geometry: geometry, fills: [])),
                         size: Size2(200, 150), position: Vec2(200, 150))
        card.transform.rotation = turn
        if let glass { card.effects = [Effect(kind: .glass(glass))] }
        let bar = Layer(name: "Bar", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                  fills: [Fill(paint: .color(RGBA(0.1, 0.8, 0.2)))])),
                        size: Size2(12, 300), position: Vec2(140, 150))
        let project = Project(composition: Composition(width: 400, height: 300, background: Background(color: .white)),
                              layers: ground(dark: dark) + [card] + (front ? [bar] : []))
        let renderer = try #require(OffscreenRenderer(pixelWidth: 400, pixelHeight: 300))
        renderer.renderer.visibleArea = visible
        renderer.renderer.drawsGlassBehind = drawn
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

    @Test func glassDrawsOnlyWhatTheCanvasShowsAndLooksTheSame() throws {
        // Zoomed in, the canvas shows a part of the scene (here x 150 to
        // 400): the glass's picture covers only that and its reach, so it
        // costs no more than the screen, and where it shows it is the glass
        // drawn whole.
        guard GlassKit.bends else { return }
        let glass = Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0.5, frost: 3)
        let whole = try scene(glass, name: "bent")
        let part = try scene(glass, visible: CGRect(x: 150, y: 0, width: 250, height: 300), name: "cut")
        // A step of 255 apart at most: the picture starts elsewhere, which
        // moves the GPU's rounding.
        for y in [80, 120, 150, 200, 220] {
            let apart = (150..<400).filter { x in
                let a = pixel(whole, x, y), b = pixel(part, x, y)
                return abs(a.r - b.r) > 2 || abs(a.g - b.g) > 2 || abs(a.b - b.b) > 2
            }
            #expect(apart.isEmpty, "row \(y): \(apart)")
        }
    }

    @Test func depthStopsAtTheMiddleOfTheShape() throws {
        // On the 200 by 150 card, any depth past 75 draws as 75 does: deeper,
        // the bend turned the middle inside out and, on screen, pulled in
        // whatever was hundreds of points away, past the window too.
        guard GlassKit.bends else { return }
        let half = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 75, dispersion: 0.5, frost: 0), name: "half")
        let deep = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 639, dispersion: 0.5, frost: 0), name: "deep")
        for y in [80, 120, 150, 200] { #expect(differences(half, deep, y: y, from: 0, to: 400) == 0) }
        #expect(GlassKit.fitted(Glass(depth: 90), to: Size2(120, 300)).depth == 60)
        #expect(Glass(depth: 639).held.depth == Glass.maxDepth, "and never past 100")
        #expect(GlassKit.margin(GlassKit.fitted(Glass(depth: 100, frost: 1000), to: Size2(248, 300))) == 708, "and the frost reaches as far as its blur")
    }

    /// How many pixels of the two pictures differ by more than `tolerance`
    /// in any channel.
    private func pixelsApart(_ a: CGImage, _ b: CGImage, tolerance: Int = 12) -> Int {
        func bytes(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return data
        }
        let x = bytes(a), y = bytes(b)
        return stride(from: 0, to: x.count, by: 4).filter { o in
            (0..<3).contains { abs(Int(x[o + $0]) - Int(y[o + $0])) > tolerance }
        }.count
    }

    @Test func glassDrawingWhatIsBehindItMatchesTheBackdrops() throws {
        // The canvas draws what is behind glass itself; exports see it
        // through backdrops. The two must look the same: bend, colours,
        // frost, light, outlines that are not boxes, and turned layers.
        guard GlassKit.bends else { return }
        let looks: [(String, Glass, ShapeGeometry, Double)] = [
            ("bend", Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0, frost: 0), .rectangle(cornerRadii: CornerRadii(all: 40)), 0),
            ("figma", Glass(), .rectangle(cornerRadii: CornerRadii(all: 40)), 0),
            ("split", Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 1, frost: 0), .rectangle(cornerRadii: CornerRadii(all: 40)), 0),
            ("frost", Glass(lightIntensity: 0, refraction: 0.5, depth: 20, dispersion: 0, frost: 12), .rectangle(cornerRadii: CornerRadii(all: 40)), 0),
            ("star", Glass(lightIntensity: 0, refraction: 1, depth: 16, dispersion: 0, frost: 0), .star(points: 5, innerRadius: 0.5, cornerRadius: 0), 0),
            ("turned", Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0.3, frost: 0), .rectangle(cornerRadii: CornerRadii(all: 40)), 30),
        ]
        for (name, glass, geometry, turn) in looks {
            let seen = try scene(glass, geometry: geometry, drawn: false, turn: turn, name: "match-\(name)-backdrop")
            let drawn = try scene(glass, geometry: geometry, drawn: true, turn: turn, name: "match-\(name)-drawn")
            let bare = try scene(nil, geometry: geometry, turn: turn, name: "match-\(name)-bare")
            let changed = pixelsApart(bare, seen)
            #expect(changed > 200, "\(name): the glass does something")
            let apart = pixelsApart(seen, drawn)
            #expect(apart < max(changed / 20, 40), "\(name): drawn as the backdrops see it, \(apart) apart of \(changed)")
        }
    }

    @Test func glassDrawingWhatIsBehindItNeverSeesWhatIsInFront() throws {
        // A green bar in front of the glass's left side: drawn over the
        // glass, never bent into it, so beside the bar the glass is as it
        // is without one.
        guard GlassKit.bends else { return }
        let glass = Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0, frost: 0)
        let with = try scene(glass, drawn: true, front: true, name: "front-drawn")
        let without = try scene(glass, drawn: true, name: "front-none")
        // The bar covers x 134 to 146.
        #expect(differences(with, without, y: 150, from: 101, to: 131) == 0)
        #expect(differences(with, without, y: 150, from: 149, to: 299) == 0)
        #expect(pixel(with, 140, 150) == pixel(with, 140, 40), "the bar is the same over the glass as away from it")
    }

    /// How far in from the card's left edge (x 100) the bend and light
    /// reach along the middle row, in the scene's points, drawn at `scale`
    /// pixels a point.
    private func reach(_ glass: Glass, scale: Int, dark: Bool = false) throws -> Double {
        var card = Layer(name: "Card", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: CornerRadii(all: 40)), fills: [])),
                         size: Size2(200, 150), position: Vec2(200, 150))
        card.effects = [Effect(kind: .glass(glass))]
        let bareProject = Project(composition: Composition(width: 400, height: 300, background: Background(color: .white)),
                                  layers: ground(dark: dark))
        var project = bareProject
        project.layers.append(card)
        let renderer = try #require(OffscreenRenderer(pixelWidth: 400 * scale, pixelHeight: 300 * scale))
        let bent = try #require(renderer.image(of: evaluate(project, at: 0)))
        let bare = try #require(renderer.image(of: evaluate(bareProject, at: 0)))
        let y = 150 * scale
        let changed = (100 * scale..<200 * scale).filter { pixel(bent, $0, y) != pixel(bare, $0, y) }
        return Double((changed.max() ?? 100 * scale) - 100 * scale) / Double(scale)
    }

    @Test func glassLooksTheSameAtEveryScale() throws {
        // A 4K export is the 1080p one drawn finer, and the canvas zoomed in
        // the same glass bigger: the bend and the light reach as far into the
        // card, in its own points, at 1 and 2 pixels a point.
        guard GlassKit.bends else { return }
        let bend = Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0, frost: 0)
        let one = try reach(bend, scale: 1), two = try reach(bend, scale: 2)
        #expect(abs(one - two) <= 2, "the bend reaches \(one) points in at 1x, \(two) at 2x")
        let light = Glass(lightAngle: -90, lightIntensity: 1, refraction: 0, depth: 24, dispersion: 0, frost: 0)
        let lit1 = try reach(light, scale: 1, dark: true), lit2 = try reach(light, scale: 2, dark: true)
        #expect(abs(lit1 - lit2) <= 1.5, "the light reaches \(lit1) points in at 1x, \(lit2) at 2x")
    }

    @Test func thinShapesNeverTurnInsideOut() throws {
        // A star's points are far thinner than its box: at Depth 100 the
        // bend reached across them and scrambled its middle. Depth now stops
        // at the outline's own thickness, so any depth past it draws as it.
        guard GlassKit.bends else { return }
        let star = ShapeGeometry.star(points: 5, innerRadius: 0.5, cornerRadius: 0)
        let path = star.bezierPath(size: Size2(200, 150)).cgPath
        let thickness = GlassField.thickness(of: path)
        #expect(thickness > 15 && thickness < 50, "a 200 by 150 star is \(thickness) thick")
        let deep = try scene(Glass(lightIntensity: 0, refraction: 1, depth: 100, dispersion: 0, frost: 0), geometry: star, name: "star-deep")
        let held = try scene(Glass(lightIntensity: 0, refraction: 1, depth: thickness, dispersion: 0, frost: 0), geometry: star, name: "star-held")
        for y in [100, 130, 150, 180] { #expect(differences(deep, held, y: y, from: 90, to: 310) == 0) }
        // A rectangle is half its shorter side thick.
        #expect(abs(GlassField.thickness(of: CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 60), transform: nil)) - 30) < 1.5)
    }

    @Test func glassInAFadedGroupStillSeesWhatIsBehind() throws {
        // In a group at 50%, the glass is half there: halfway between the
        // glass at full strength and no glass. Through a backdrop it saw
        // nothing behind it, its group drawn on its own, and came out white.
        guard GlassKit.bends else { return }
        let glass = Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0.4, frost: 2)
        var card = Layer(name: "Card", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: CornerRadii(all: 40)), fills: [])),
                         size: Size2(200, 150), position: Vec2(200, 150))
        card.effects = [Effect(kind: .glass(glass))]
        var group = Layer(name: "Group", content: .group(GroupContent(children: [card])), size: Size2(400, 300), position: Vec2(200, 150))
        group.opacity = 0.5
        let project = Project(composition: Composition(width: 400, height: 300, background: Background(color: .white)),
                              layers: ground(dark: false) + [group])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 400, pixelHeight: 300))
        let faded = try #require(renderer.image(of: evaluate(project, at: 0)))
        let full = try scene(glass, name: "group-full"), bare = try scene(nil, name: "group-bare")
        for x in stride(from: 101, to: 299, by: 3) {
            let f = pixel(full, x, 150), b = pixel(bare, x, 150), h = pixel(faded, x, 150)
            #expect(abs(h.r - (f.r + b.r) / 2) <= 3 && abs(h.g - (f.g + b.g) / 2) <= 3 && abs(h.b - (f.b + b.b) / 2) <= 3,
                    "at \(x): \(h) is not halfway between \(f) and \(b)")
        }
    }

    @Test func glassSeesOnlyWhatIsBehindItInDepth() throws {
        // In a 3D frame the nearer layer is drawn in front, whatever the
        // list says: a bar listed before the glass but nearer the camera
        // lies over the glass and is never bent into it.
        guard GlassKit.bends else { return }
        let glass = Glass(lightIntensity: 0, refraction: 1, depth: 24, dispersion: 0, frost: 0)
        func frame(bar: Bool) throws -> CGImage {
            var card = Layer(name: "Card", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: CornerRadii(all: 40)), fills: [])),
                             size: Size2(200, 150), position: Vec2(200, 150))
            card.effects = [Effect(kind: .glass(glass))]
            var near = Layer(name: "Bar", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                       fills: [Fill(paint: .color(RGBA(0.1, 0.8, 0.2)))])),
                             size: Size2(8, 300), position: Vec2(112, 150))
            near.transform.z = 60
            let children = ground(dark: false) + (bar ? [near] : []) + [card]
            let frame = Layer(name: "F", content: .group(GroupContent(children: children, frame: FrameStyle(space: Space3D()))),
                              size: Size2(400, 300), position: Vec2(200, 150))
            let project = Project(composition: Composition(width: 400, height: 300, background: Background(color: .white)), layers: [frame])
            let renderer = try #require(OffscreenRenderer(pixelWidth: 400, pixelHeight: 300))
            return try #require(renderer.image(of: evaluate(project, at: 0)))
        }
        let with = try frame(bar: true), without = try frame(bar: false)
        // Where the two differ is the bar itself, green, and nothing else:
        // bent into the glass, green came out beside it too.
        let apart = (90..<140).filter { pixel(with, $0, 150) != pixel(without, $0, 150) }
        #expect(!apart.isEmpty)
        #expect((apart.max() ?? 0) - (apart.min() ?? 0) <= 14, "the bar and nothing more differs: \(apart)")
        for x in apart { let p = pixel(with, x, 150); #expect(p.g > p.r && p.g > p.b, "at \(x): \(p) is not the bar") }
    }

    @Test func fadingGlassKeepsItsLight() throws {
        // To no glass and back, the light fades where it is rather than
        // swinging round to no glass's -45°, and the depth stays.
        let mine = Glass(lightAngle: 262, lightIntensity: 0.3, refraction: 1, depth: 100, dispersion: 0.04, frost: 0)
        for t in [0.25, 0.5, 0.75] {
            let out = Glass.interpolate(mine, .noGlass, t), into = Glass.interpolate(.noGlass, mine, t)
            #expect(out.lightAngle == 262 && into.lightAngle == 262)
            #expect(out.depth == 100 && into.depth == 100)
        }
        // Two lit ends still turn the shorter way round.
        #expect(Glass.interpolate(Glass(lightAngle: 170), Glass(lightAngle: -170), 0.5).lightAngle == 180)
    }

    @Test func aPictureOfWhatIsBehindRedrawnLargerIsWhole() throws {
        // Zoomed in, the picture is drawn again larger: drawn by the
        // renderer that drew it smaller, it filled only its old size,
        // magnified, with the rest black (21 October 2026).
        let project = Project(composition: Composition(width: 400, height: 300, background: Background(color: .white)),
                              layers: ground(dark: false))
        let scene = evaluate(project, at: 0)
        func bytes(_ surface: IOSurface) -> [UInt8] {
            surface.lock(options: .readOnly, seed: nil)
            defer { surface.unlock(options: .readOnly, seed: nil) }
            var out: [UInt8] = []
            for y in stride(from: 0, to: surface.height, by: 37) {
                let row = surface.baseAddress.advanced(by: y * surface.bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in stride(from: 0, to: surface.width * 4, by: 52) { out.append(row[x]) }
            }
            return out
        }
        let reused = GlassBehind()
        _ = reused.draw(scene, transform: .identity, width: 200, height: 150, contentsScale: 1, media: nil)
        let big = Projective(.scale(Vec2(2, 2)))
        // Inside a transaction, as a pan redraws the glass from the canvas's
        // layout: a flush there on this thread commits nothing.
        CATransaction.begin()
        let again = try #require(reused.draw(scene, transform: big, width: 800, height: 600, contentsScale: 2, media: nil))
        CATransaction.commit()
        let fresh = try #require(GlassBehind().draw(scene, transform: big, width: 800, height: 600, contentsScale: 2, media: nil))
        #expect(bytes(again) == bytes(fresh))
    }

    @Test func aPictureOfWhatIsBehindTakesAnyWidth() throws {
        // Widths whose rows are not whole steps of 16 bytes (2,254 pixels,
        // zoomed in on the user's circle) stopped the app.
        let scene = ResolvedScene(time: 0, size: Size2(400, 300), background: RGBA(1, 1, 1), layers: [])
        for width in [255, 2254, 1] {
            let surface = GlassBehind().draw(scene, transform: .identity, width: width, height: 101, contentsScale: 1, media: nil)
            #expect(surface?.width == width, "\(width) wide")
        }
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
