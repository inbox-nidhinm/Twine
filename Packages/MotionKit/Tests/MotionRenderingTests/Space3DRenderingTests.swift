import Foundation
import Testing
import QuartzCore
import ImageIO
import Metal
import ObjectiveC
import MotionModel
@testable import MotionEvaluation
@testable import MotionRendering

/// The templates spike (docs/templates.md, milestone 1): cards placed in one
/// shared 3D space and drawn through the renderer exports use, the same on
/// screen, and two ways of bending a card round a curve, checked and timed.
/// Nothing here reaches the app yet: the scenes are evaluated flat and then
/// placed by hand, as milestone 2 will have `evaluate` do.
@Suite(.serialized) struct Space3DRenderingTests {
    // MARK: Pixels

    struct Pixel: Equatable {
        var r, g, b, a: Int
        func near(_ c: RGBA, _ tolerance: Int = 40) -> Bool {
            a > 200 && abs(r - Int(c.r * 255)) < tolerance && abs(g - Int(c.g * 255)) < tolerance
                && abs(b - Int(c.b * 255)) < tolerance
        }
    }

    /// Every pixel of `image` drawn at `width` by `height`, top row first.
    static func pixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    /// Writes RGBA pixels as a PNG into `TWINE_SPIKE_OUT`, when set, to look at.
    static func save(_ bytes: [UInt8], width: Int, height: Int, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["TWINE_SPIKE_OUT"] else { return }
        var copy = bytes
        let context = CGContext(data: &copy, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        guard let image = context.makeImage(),
              let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(out, image, nil)
        CGImageDestinationFinalize(out)
    }

    static func pixel(_ bytes: [UInt8], width: Int, _ x: Int, _ y: Int) -> Pixel {
        let i = (y * width + x) * 4
        return Pixel(r: Int(bytes[i]), g: Int(bytes[i + 1]), b: Int(bytes[i + 2]), a: Int(bytes[i + 3]))
    }

    // MARK: A ring of cards

    static let side = 400.0
    static let card = Size2(60, 80)
    static let radius = 140.0
    static let camera = Camera3D(distance: 600, vanishingPoint: Vec2(side / 2, side / 2))
    static func hue(_ i: Int, of count: Int) -> RGBA {
        // Card 0 red, and half way round blue, so the front and back of the
        // ring are easy to tell apart.
        let colors = [RGBA(1, 0, 0), RGBA(1, 0.5, 0), RGBA(1, 1, 0), RGBA(0.5, 1, 0), RGBA(0, 1, 0), RGBA(0, 1, 0.5),
                      RGBA(0, 0, 1), RGBA(0.5, 0, 1), RGBA(1, 0, 1), RGBA(1, 0, 0.5), RGBA(0.5, 0.5, 0.5), RGBA(0, 0.5, 0.5)]
        return colors[i % colors.count]
    }

    /// Where card `i` of `count` sits on the ring, turned `turn` degrees,
    /// the ring tipped `tip` degrees about its level middle line: facing out
    /// from the middle, card 0 at the front at a turn of 0.
    static func pose(_ i: Int, of count: Int, turn: Double, tip: Double = 0) -> Pose3D {
        let angle = turn + Double(i) * 360 / Double(count)
        let a = angle * .pi / 180
        let middle = Vec3(side / 2, side / 2, 0)
        return Pose3D.layer(position: Vec2(radius * sin(a), 0), z: radius * cos(a),
                            anchor: Vec2(card.width / 2, card.height / 2), tilt: Vec2(0, angle))
            .then(.turnX(degrees: tip))
            .then(.translation(middle))
    }

    /// A 400 square scene holding a group of `count` cards, placed on the
    /// ring. They are listed so that, unsorted, each card after the first
    /// would be drawn over it.
    static func ring(count: Int = 12, turn: Double, tip: Double = 0, background: RGBA? = nil) -> ResolvedScene {
        var cards: [Layer] = []
        for i in 0..<count {
            cards.append(Layer(name: "C\(i)", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                           fills: [Fill(paint: .color(hue(i, of: count)))])),
                               size: card, position: Vec2(0, 0)))
        }
        let group = Layer(name: "Ring", content: .group(GroupContent(children: cards)), size: Size2(side, side),
                          position: Vec2(side / 2, side / 2))
        let project = Project(composition: Composition(width: Int(side), height: Int(side),
                                                       background: background.map { Background(color: $0) }
                                                           ?? Background(isTransparent: true)),
                              layers: [group])
        let flat = evaluate(project, at: 0)
        let index = Dictionary(uniqueKeysWithValues: cards.enumerated().map { ($1.id, $0) })
        let placed = flat.layers.map { layer -> ResolvedLayer in
            guard let i = index[layer.id] else { return layer }
            var l = layer
            l.placed = Placed3D(pose(i, of: count, turn: turn, tip: tip), camera: camera,
                                middle: Vec2(card.width / 2, card.height / 2))
            return l
        }
        return ResolvedScene(time: 0, size: flat.size, background: flat.background, layers: placed)
    }

    @Test func theNearCardIsDrawnOverTheFarOne() throws {
        let renderer = try #require(OffscreenRenderer(pixelWidth: Int(Self.side), pixelHeight: Int(Self.side)))
        let width = Int(Self.side)
        // Card 0 at the front, card 6 straight behind it and listed later:
        // only ordering by depth puts red in the middle.
        let front = Self.pixels(try #require(renderer.image(of: Self.ring(turn: 0))), width: width, height: width)
        #expect(Self.pixel(front, width: width, 200, 200).near(Self.hue(0, of: 12)))
        // Half a turn on, card 6 is in front.
        let back = Self.pixels(try #require(renderer.image(of: Self.ring(turn: 180))), width: width, height: width)
        #expect(Self.pixel(back, width: width, 200, 200).near(Self.hue(6, of: 12)))
        // The front card's right edge lands where the camera says, with the
        // card behind it showing just past it.
        let projection = Self.camera.projection(of: Self.pose(0, of: 12, turn: 0))
        let edge = Int(try #require(projection.apply(Vec2(Self.card.width, Self.card.height / 2))).x)
        #expect(Self.pixel(front, width: width, edge - 2, 200).near(Self.hue(0, of: 12)))
        #expect(Self.pixel(front, width: width, edge + 3, 200).near(Self.hue(5, of: 12)))
    }

    @Test func aTippedRingStillSortsAsItTurns() throws {
        let renderer = try #require(OffscreenRenderer(pixelWidth: Int(Self.side), pixelHeight: Int(Self.side)))
        let width = Int(Self.side)
        // At every step of a turn, the card nearest the viewer at the
        // middle of the view is the one drawn there.
        for turn in stride(from: 0.0, to: 360, by: 15) {
            let scene = Self.ring(turn: turn, tip: -20)
            let bytes = Self.pixels(try #require(renderer.image(of: scene)), width: width, height: width)
            let nearest = (0..<12).max { Self.pose($0, of: 12, turn: turn, tip: -20).origin.z
                < Self.pose($1, of: 12, turn: turn, tip: -20).origin.z }!
            let p = try #require(Self.camera.projection(of: Self.pose(nearest, of: 12, turn: turn, tip: -20))
                .apply(Vec2(Self.card.width / 2, Self.card.height / 2)))
            #expect(Self.pixel(bytes, width: width, Int(p.x), Int(p.y)).near(Self.hue(nearest, of: 12)),
                    "at \(turn)° card \(nearest) is nearest")
        }
    }

    // MARK: Through the model

    /// A ring of 12 as a frame in 3D: each card's design place, Z and tilt,
    /// as a person would set them, evaluated as any project is.
    static func modelRing(turn: Double) -> Project {
        var cards: [Layer] = []
        for i in 0..<12 {
            let angle = turn + Double(i) * 30, a = angle * .pi / 180
            var c = Layer(name: "C\(i)", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                     fills: [Fill(paint: .color(hue(i, of: 12)))])),
                          size: card, position: Vec2(side / 2 + radius * sin(a), side / 2))
            c.transform.z = radius * cos(a)
            c.transform.tilt = Tilt(x: 0, y: angle)
            cards.append(c)
        }
        let frame = Layer(name: "Ring", content: .group(GroupContent(children: cards,
                                                                     frame: FrameStyle(space: Space3D(distance: 600)))),
                          size: Size2(side, side), position: Vec2(side / 2, side / 2))
        return Project(composition: Composition(width: Int(side), height: Int(side), background: Background(isTransparent: true)),
                       layers: [frame])
    }

    @Test func aFrameIn3DDrawsItsNearestCardOnTop() throws {
        let renderer = try #require(OffscreenRenderer(pixelWidth: Int(Self.side), pixelHeight: Int(Self.side)))
        let width = Int(Self.side)
        for (turn, front) in [(0.0, 0), (180.0, 6), (90.0, 9)] {
            let bytes = Self.pixels(try #require(renderer.image(of: evaluate(Self.modelRing(turn: turn), at: 0))),
                                    width: width, height: width)
            #expect(Self.pixel(bytes, width: width, 200, 200).near(Self.hue(front, of: 12)), "at \(turn)°")
        }
        // The same as the spike's ring placed by hand.
        let byHand = Self.pixels(try #require(renderer.image(of: Self.ring(turn: 0))), width: width, height: width)
        let model = Self.pixels(try #require(renderer.image(of: evaluate(Self.modelRing(turn: 0), at: 0))),
                                width: width, height: width)
        #expect(byHand == model)
    }

    @Test func layersAtTheSameDepthKeepTheirOrder() throws {
        // Switching a frame to 3D must not shuffle layers that sit flat:
        // each later one is still drawn over the one before.
        var layers: [Layer] = []
        for i in 0..<12 {
            layers.append(Layer(name: "L\(i)", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                           fills: [Fill(paint: .color(Self.hue(i, of: 12)))])),
                                size: Size2(200, 200), position: Vec2(100 + Double(i) * 10, 200)))
        }
        let frame = Layer(name: "F", content: .group(GroupContent(children: layers, frame: FrameStyle(space: Space3D()))),
                          size: Size2(Self.side, Self.side), position: Vec2(Self.side / 2, Self.side / 2))
        let project = Project(composition: Composition(width: Int(Self.side), height: Int(Self.side),
                                                       background: Background(isTransparent: true)), layers: [frame])
        let renderer = try #require(OffscreenRenderer(pixelWidth: Int(Self.side), pixelHeight: Int(Self.side)))
        let width = Int(Self.side)
        let bytes = Self.pixels(try #require(renderer.image(of: evaluate(project, at: 0))), width: width, height: width)
        // Each strip between one layer's left edge and the next shows that layer.
        for i in 0..<11 {
            let x = i * 10 + 5
            #expect(Self.pixel(bytes, width: width, x, 200).near(Self.hue(i, of: 12)), "layer \(i)")
        }
        #expect(Self.pixel(bytes, width: width, 250, 200).near(Self.hue(11, of: 12)))
    }

    @Test func aBentFrameCurvesEverythingInIt() throws {
        // A frame of eight upright bands, bent a quarter turn across: each
        // band lands where the curve says, through the renderer exports use.
        let size = Self.bendSize
        let bands = Self.bands.enumerated().map { i, c -> Layer in
            let w = size.width / Double(Self.bands.count)
            return Layer(name: "B\(i)", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                     fills: [Fill(paint: .color(c))])),
                         size: Size2(w, size.height), position: Vec2((Double(i) + 0.5) * w, size.height / 2))
        }
        var frame = Layer(name: "F", content: .group(GroupContent(children: bands, clipsContent: true,
                                                                  frame: FrameStyle(cornerRadii: CornerRadii(all: 24)))),
                          size: size, position: Vec2(300, 300))
        frame.transform.bend = Vec2(90, 0)
        frame.transform.tilt = Tilt(x: 0, y: 30, depth: 800)
        let project = Project(composition: Composition(width: 600, height: 600, background: Background(isTransparent: true)),
                              layers: [frame])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 600, pixelHeight: 600))
        let bytes = Self.pixels(try #require(renderer.image(of: evaluate(project, at: 0))), width: 600, height: 600)
        Self.save(bytes, width: 600, height: 600, "bent-frame")
        // The same curve and camera the spike's own check uses.
        let bend = Bend(size: size, radius: size.width / (.pi / 2),
                        pose: .turnY(degrees: 30).then(.translation(Vec3(300, 300, 0))))
        let faintest = Self.check(bytes, width: 600, bend: bend, camera: Self.bendCamera, name: "bent-frame")
        #expect(faintest > 250)
        // Its rounded corner is cut where the curve puts it.
        let corner = try #require(Self.bendCamera.project(bend.point(2, 2)))
        #expect(Self.pixel(bytes, width: 600, Int(corner.x.rounded()), Int(corner.y.rounded())).a < 40)
    }

    // MARK: The same on screen

    /// Saves `layer`, the very tree just drawn off screen, with that
    /// drawing beside it, into `TWINE_SPIKE_OUT`, for
    /// `Tools/Spike3D/show-on-screen.swift` to put in a window (the canvas's
    /// path: the window server draws it, not CARenderer), capture and
    /// compare. A test process cannot show a window of its own: one made
    /// here was never drawn.
    static func archive(_ layer: CALayer, exported: [UInt8], size: Int, _ name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["TWINE_SPIKE_OUT"] else { return }
        save(exported, width: size, height: size, "\(name)-export")
        let data = try NSKeyedArchiver.archivedData(withRootObject: layer, requiringSecureCoding: false)
        try data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).layers"))
    }

    @Test func aMeshBendsEverythingInsideTheLayer() throws {
        // No picture of its own: the card is a rounded clip whose bands
        // are sublayers, as a frame's children are. The mesh must carry
        // them, and the rounding, along the curve. A layer's own clip is
        // applied after its mesh, in its flat box, so the clip goes one
        // layer in, under the bent one.
        let renderer = try #require(RawRenderer(width: 600, height: 600))
        let holder = CALayer()
        holder.actions = Node.noActions
        holder.anchorPoint = .zero
        let clip = CALayer()
        clip.actions = Node.noActions
        clip.frame = CGRect(x: 0, y: 0, width: Self.bendSize.width, height: Self.bendSize.height)
        clip.masksToBounds = true
        clip.cornerRadius = 24
        holder.addSublayer(clip)
        clip.sublayers = Self.bands.enumerated().map { i, c in
            let band = CALayer()
            band.actions = Node.noActions
            band.backgroundColor = CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
            let w = Self.bendSize.width / Double(Self.bands.count)
            band.frame = CGRect(x: Double(i) * w, y: 0, width: w, height: Self.bendSize.height)
            return band
        }
        Self.update(holder, mesh: Self.sampleBend, columns: 16, rows: 4, camera: Self.bendCamera)
        renderer.set([holder])
        let bytes = renderer.image()
        _ = Self.check(bytes, width: 600, bend: Self.sampleBend, camera: Self.bendCamera, name: "mesh-sublayers")
        // The top-left corner is rounded off where the curve puts it.
        let corner = try #require(Self.bendCamera.project(Self.sampleBend.point(2, 2)))
        #expect(Self.pixel(bytes, width: 600, Int(corner.x.rounded()), Int(corner.y.rounded())).a < 40)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TWINE_SPIKE_OUT"] != nil))
    func savedForTheScreen() throws {
        let width = Int(Self.side)
        let scene = Self.ring(turn: 20, tip: -20, background: RGBA(1, 1, 1))
        let offscreen = try #require(OffscreenRenderer(pixelWidth: width, pixelHeight: width))
        let exported = Self.pixels(try #require(offscreen.image(of: scene)), width: width, height: width)
        // The canvas's own renderer, which draws pictures the right way up
        // for a window, as the canvas does.
        let canvas = CoreAnimationRenderer()
        canvas.contentsScale = 2
        canvas.render(scene)
        try Self.archive(canvas.rootLayer, exported: exported, size: width, "ring")
        // The model's ring as a project, for the test copy of the app to open.
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TWINE_SPIKE_OUT"]!)
            .appendingPathComponent("Ring.twine")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ProjectFormat.encode(Self.modelRing(turn: 20)).write(to: folder.appendingPathComponent(ProjectFormat.documentFileName))

        let picture = Self.picture(width: 240, height: 320)
        for (name, layers) in [
            ("strips", Self.strips(Self.sampleBend, count: 16, camera: Self.bendCamera, picture: picture)),
            ("mesh", [Self.meshCard(Self.sampleBend, columns: 16, rows: 4, camera: Self.bendCamera, picture: picture)]),
        ] {
            let raw = try #require(RawRenderer(width: 600, height: 600))
            raw.set(layers)
            let exported = raw.image()
            let holder = CALayer()
            holder.frame = CGRect(x: 0, y: 0, width: 600, height: 600)
            holder.sublayers = layers
            try Self.archive(holder, exported: exported, size: 600, name)
        }
    }

    // MARK: Bending a card

    /// A card picture of eight upright bands, left to right through the
    /// hues, so where each part of the card went can be read off its colour.
    static let bands = (0..<8).map { i -> RGBA in
        let colors = [RGBA(1, 0, 0), RGBA(1, 0.6, 0), RGBA(0.9, 0.9, 0), RGBA(0, 0.8, 0),
                      RGBA(0, 0.8, 0.8), RGBA(0, 0, 1), RGBA(0.6, 0, 1), RGBA(1, 0, 0.7)]
        return colors[i]
    }

    static func picture(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (i, c) in bands.enumerated() {
            context.setFillColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1))
            let w = CGFloat(width) / CGFloat(bands.count)
            context.fill(CGRect(x: CGFloat(i) * w, y: 0, width: w, height: CGFloat(height)))
        }
        return context.makeImage()!
    }

    /// A card `size` wide bent round an upright cylinder of `radius`, its
    /// middle nearest (convex): its own point (u, v) in the space, with its
    /// middle at the origin, before `pose` places it.
    struct Bend {
        var size: Size2
        var radius: Double
        var pose: Pose3D

        func point(_ u: Double, _ v: Double) -> Vec3 {
            let phi = (u - size.width / 2) / radius
            return pose.apply(Vec3(radius * sin(phi), v - size.height / 2, radius * (cos(phi) - 1)))
        }
    }

    /// The card cut into `count` upright strips, each flat across its
    /// chord of the curve, each showing its slice of the picture.
    static func strips(_ bend: Bend, count: Int, camera: Camera3D, picture: CGImage) -> [CALayer] {
        (0..<count).map { i in
            let layer = CALayer()
            layer.actions = Node.noActions
            layer.anchorPoint = .zero
            layer.contents = picture
            // Smoothed, each strip's sides let the background through
            // where two strips meet; only the card's own outline is.
            var edges: CAEdgeAntialiasingMask = [.layerTopEdge, .layerBottomEdge]
            if i == 0 { edges.insert(.layerLeftEdge) }
            if i == count - 1 { edges.insert(.layerRightEdge) }
            layer.edgeAntialiasingMask = edges
            update(layer, strip: i, of: count, bend: bend, camera: camera)
            return layer
        }
    }

    static func update(_ layer: CALayer, strip i: Int, of count: Int, bend: Bend, camera: Camera3D) {
        let w = bend.size.width / Double(count)
        let u0 = Double(i) * w, u1 = u0 + w
        let a = bend.point(u0, 0), b = bend.point(u1, 0), down = bend.point(u0, 1) - a
        let across = (b - a) * (1 / w)
        let pose = Pose3D(u: across, v: down, w: across.cross(down), origin: a)
        layer.bounds = CGRect(x: 0, y: 0, width: w, height: bend.size.height)
        layer.contentsRect = CGRect(x: CGFloat(i) / CGFloat(count), y: 0, width: 1 / CGFloat(count), height: 1)
        layer.transform = camera.projection(of: pose).caTransform
        layer.zPosition = CGFloat(bend.point((u0 + u1) / 2, bend.size.height / 2).z)
    }

    /// Core Animation's private mesh warp: a grid laid over the layer,
    /// each point of it moved somewhere else, the picture stretched along.
    enum Mesh {
        struct Vertex {
            var from: CGPoint
            var to: (CGFloat, CGFloat, CGFloat)
        }
        struct Face {
            var indices: (UInt32, UInt32, UInt32, UInt32)
            var w: (Float, Float, Float, Float)
        }
        typealias Make = @convention(c) (AnyObject, Selector, UInt, UnsafeRawPointer, UInt, UnsafeRawPointer,
                                         NSString) -> AnyObject?

        static let make: Make? = {
            let selector = NSSelectorFromString("meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:")
            guard let kind = NSClassFromString("CAMeshTransform"),
                  let method = class_getClassMethod(kind, selector) else { return nil }
            return unsafeBitCast(method_getImplementation(method), to: Make.self)
        }()

        /// A grid of `columns` by `rows`, each point at `place(fraction across,
        /// fraction down)`, in the layer's own pixels of `size`.
        static func warp(columns: Int, rows: Int, size: Size2, place: (Double, Double) -> Vec2) -> AnyObject? {
            guard let make, let kind = NSClassFromString("CAMeshTransform") else { return nil }
            var vertices: [Vertex] = []
            for j in 0...rows {
                for i in 0...columns {
                    let s = Double(i) / Double(columns), t = Double(j) / Double(rows)
                    let p = place(s, t)
                    vertices.append(Vertex(from: CGPoint(x: s, y: t),
                                           to: (CGFloat(p.x / size.width), CGFloat(p.y / size.height), 0)))
                }
            }
            var faces: [Face] = []
            for j in 0..<rows {
                for i in 0..<columns {
                    let a = UInt32(j * (columns + 1) + i), b = a + 1
                    let c = UInt32((j + 1) * (columns + 1) + i + 1), d = c - 1
                    faces.append(Face(indices: (a, b, c, d), w: (0, 0, 0, 0)))
                }
            }
            return vertices.withUnsafeBytes { v in
                faces.withUnsafeBytes { f in
                    make(kind, NSSelectorFromString("meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:"),
                         UInt(vertices.count), v.baseAddress!, UInt(faces.count), f.baseAddress!, "none")
                }
            }
        }
    }

    static func meshCard(_ bend: Bend, columns: Int, rows: Int, camera: Camera3D, picture: CGImage) -> CALayer {
        let layer = CALayer()
        layer.actions = Node.noActions
        layer.anchorPoint = .zero
        layer.contents = picture
        update(layer, mesh: bend, columns: columns, rows: rows, camera: camera)
        return layer
    }

    static func update(_ layer: CALayer, mesh bend: Bend, columns: Int, rows: Int, camera: Camera3D) {
        // The layer stays square on to its parent at the origin; the mesh
        // carries every point of it to where the camera sees it.
        layer.bounds = CGRect(x: 0, y: 0, width: bend.size.width, height: bend.size.height)
        let warp = Mesh.warp(columns: columns, rows: rows, size: bend.size) { s, t in
            camera.project(bend.point(s * bend.size.width, t * bend.size.height)) ?? .zero
        }
        layer.setValue(warp, forKey: "meshTransform")
        layer.zPosition = CGFloat(bend.point(bend.size.width / 2, bend.size.height / 2).z)
    }

    /// Draws raw layers through CARenderer into Metal, as `OffscreenRenderer`
    /// does for scenes.
    final class RawRenderer {
        let width: Int, height: Int
        let texture: MTLTexture
        let queue: MTLCommandQueue
        let caRenderer: CARenderer
        let root = CALayer()

        init?(width: Int, height: Int) {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                                      height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            (self.width, self.height, self.texture, self.queue) = (width, height, texture, queue)
            caRenderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue,
                                                                   kCARendererColorSpace as String: CGColorSpace(name: CGColorSpace.sRGB)!])
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.frame = CGRect(x: 0, y: 0, width: width, height: height)
            root.actions = Node.noActions
            CATransaction.commit()
            caRenderer.layer = root
            caRenderer.bounds = root.bounds
            CATransaction.flush()
        }

        func set(_ layers: [CALayer]) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.sublayers = layers
            CATransaction.commit()
        }

        func draw() {
            CATransaction.flush()
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
            if let fence = queue.makeCommandBuffer() {
                fence.commit()
                fence.waitUntilCompleted()
            }
        }

        func image() -> [UInt8] {
            draw()
            var bgra = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&bgra, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            // To RGBA, as `pixels` gives.
            for i in stride(from: 0, to: bgra.count, by: 4) { bgra.swapAt(i, i + 2) }
            return bgra
        }
    }

    static let bendSize = Size2(240, 320)
    static let bendCamera = Camera3D(distance: 800, vanishingPoint: Vec2(300, 300))
    /// A quarter turn of curve, the card turned 30° away on its right.
    static let sampleBend = Bend(size: bendSize, radius: bendSize.width / (.pi / 2),
                                 pose: .turnY(degrees: 30).then(.translation(Vec3(300, 300, 0))))

    /// Checks each band's middle lands where the curve says, and returns
    /// the faintest pixel found down the joins between bands' halves (where
    /// strips meet, at 16 strips), which shows a seam as a dip below 255.
    static func check(_ bytes: [UInt8], width: Int, bend: Bend, camera: Camera3D, name: String) -> Int {
        save(bytes, width: width, height: width, name)
        for (i, band) in bands.enumerated() {
            let u = (Double(i) + 0.5) * bend.size.width / Double(bands.count)
            for v in [0.25, 0.5, 0.75].map({ $0 * bend.size.height }) {
                guard let p = camera.project(bend.point(u, v)) else { continue }
                let found = pixel(bytes, width: width, Int(p.x.rounded()), Int(p.y.rounded()))
                #expect(found.near(band, 60), "\(name): band \(i) at (\(Int(p.x)), \(Int(p.y))) is \(found)")
            }
        }
        var faintest = 255
        for k in 1..<16 {
            let u = Double(k) * bend.size.width / 16
            for v in stride(from: 20.0, to: bend.size.height - 20, by: 7) {
                guard let p = camera.project(bend.point(u, v)) else { continue }
                faintest = min(faintest, pixel(bytes, width: width, Int(p.x.rounded()), Int(p.y.rounded())).a)
            }
        }
        return faintest
    }

    @Test func aCardBentInStripsFollowsTheCurve() throws {
        let renderer = try #require(RawRenderer(width: 600, height: 600))
        let picture = Self.picture(width: 240, height: 320)
        renderer.set(Self.strips(Self.sampleBend, count: 16, camera: Self.bendCamera, picture: picture))
        let faintest = Self.check(renderer.image(), width: 600, bend: Self.sampleBend, camera: Self.bendCamera,
                                  name: "strips")
        print("SPIKE strips, faintest pixel down the joins: \(faintest) of 255")
        #expect(faintest > 250, "no seams where the strips meet")
    }

    @Test func aCardBentByAMeshFollowsTheCurve() throws {
        #expect(Mesh.make != nil, "the system has Core Animation's mesh warp")
        let renderer = try #require(RawRenderer(width: 600, height: 600))
        let picture = Self.picture(width: 240, height: 320)
        renderer.set([Self.meshCard(Self.sampleBend, columns: 16, rows: 4, camera: Self.bendCamera, picture: picture)])
        let faintest = Self.check(renderer.image(), width: 600, bend: Self.sampleBend, camera: Self.bendCamera,
                                  name: "mesh")
        print("SPIKE mesh, faintest pixel down the joins: \(faintest) of 255")
        #expect(faintest > 250, "one picture has no joins to show")
    }

    // MARK: Timing

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TWINE_BENCH"] != nil))
    func timings() throws {
        let frames = 60
        func ms(_ seconds: Double) -> String { String(format: "%.3f ms", seconds * 1000 / Double(frames)) }

        // Placing 24 cards on a ring every frame: the maths `evaluate` will
        // add, and the layer tree's update and an export frame through the
        // real renderer.
        var place = 0.0, update = 0.0, draw = 0.0
        let renderer = CoreAnimationRenderer()
        let offscreen = try #require(OffscreenRenderer(pixelWidth: 1920, pixelHeight: 1080))
        for f in 0..<frames {
            let t0 = CACurrentMediaTime()
            let scene = Self.ring(count: 24, turn: Double(f) * 3, tip: -20)
            let t1 = CACurrentMediaTime()
            renderer.render(scene)
            let t2 = CACurrentMediaTime()
            _ = offscreen.image(of: scene)
            let t3 = CACurrentMediaTime()
            (place, update, draw) = (place + t1 - t0, update + t2 - t1, draw + t3 - t2)
        }
        print("SPIKE BENCH ring of 24 flat cards: evaluate and place \(ms(place)), layer tree \(ms(update)), 1080p export frame \(ms(draw))")

        // Templates, which make their cards afresh every frame.
        for kind in [TemplateKind.ringStream, .globe, .tunnel, .curvedWall, .diveIn, .fanWall, .threeActs] {
            let setup = TemplateSetup(kind: kind)
            let frame = Layer(name: "T", content: .group(GroupContent(clipsContent: true, frame: FrameStyle(), template: setup)),
                              size: Size2(1920, 1080), position: Vec2(960, 540))
            let bar = Action(target: frame.id, start: 0, duration: 10, easing: .linear, spec: .template(TemplatePlay()))
            let project = Project(composition: Composition(width: 1920, height: 1080, duration: 10), layers: [frame], actions: [bar])
            let tree = CoreAnimationRenderer()
            let cache = EvaluationCache()
            var made = 0.0, built = 0.0, drawn = 0.0
            for f in 0..<frames {
                let t0 = CACurrentMediaTime()
                let scene = evaluate(project, at: Double(f) / 60, cache: cache)
                let t1 = CACurrentMediaTime()
                tree.render(scene)
                let t2 = CACurrentMediaTime()
                _ = offscreen.image(of: scene)
                let t3 = CACurrentMediaTime()
                (made, built, drawn) = (made + t1 - t0, built + t2 - t1, drawn + t3 - t2)
            }
            print("SPIKE BENCH template \(kind.rawValue): evaluate \(ms(made)), layer tree \(ms(built)), 1080p export frame \(ms(drawn))")
        }

        // 24 bent cards on a ring of their own, the camera turning it, each
        // way of bending.
        let picture = Self.picture(width: 480, height: 640)
        let camera = Camera3D(distance: 1400, vanishingPoint: Vec2(960, 540))
        func bend(_ i: Int, turn: Double) -> Bend {
            let angle = turn + Double(i) * 15
            let a = angle * .pi / 180
            let size = Size2(200, 260), ring = 760.0
            return Bend(size: size, radius: ring,
                        pose: Pose3D.turnY(degrees: angle)
                            .then(.translation(Vec3(ring * sin(a), 0, ring * cos(a) - ring)))
                            .then(.turnX(degrees: -15))
                            .then(.translation(Vec3(960, 540, -300))))
        }
        let raw = try #require(RawRenderer(width: 1920, height: 1080))
        for (name, count) in [("strips of 8", 8), ("strips of 16", 16), ("strips of 32", 32)] {
            var layers: [[CALayer]] = (0..<24).map { Self.strips(bend($0, turn: 0), count: count, camera: camera, picture: picture) }
            raw.set(layers.flatMap { $0 })
            var update = 0.0, draw = 0.0
            for f in 0..<frames {
                let t0 = CACurrentMediaTime()
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for c in 0..<24 {
                    for s in 0..<count { Self.update(layers[c][s], strip: s, of: count, bend: bend(c, turn: Double(f)), camera: camera) }
                }
                CATransaction.commit()
                let t1 = CACurrentMediaTime()
                raw.draw()
                let t2 = CACurrentMediaTime()
                (update, draw) = (update + t1 - t0, draw + t2 - t1)
            }
            layers = []
            print("SPIKE BENCH 24 bent cards, \(name) (\(24 * count) layers): update \(ms(update)), 1080p frame \(ms(draw))")
        }
        for (columns, rows) in [(8, 2), (16, 4), (32, 8)] {
            let cards = (0..<24).map { Self.meshCard(bend($0, turn: 0), columns: columns, rows: rows, camera: camera, picture: picture) }
            raw.set(cards)
            var update = 0.0, draw = 0.0
            for f in 0..<frames {
                let t0 = CACurrentMediaTime()
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for c in 0..<24 { Self.update(cards[c], mesh: bend(c, turn: Double(f)), columns: columns, rows: rows, camera: camera) }
                CATransaction.commit()
                let t1 = CACurrentMediaTime()
                raw.draw()
                let t2 = CACurrentMediaTime()
                (update, draw) = (update + t1 - t0, draw + t2 - t1)
            }
            print("SPIKE BENCH 24 bent cards, mesh \(columns) by \(rows): update \(ms(update)), 1080p frame \(ms(draw))")
        }
    }
}
