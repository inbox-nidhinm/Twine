import Foundation
import Testing
import MotionModel
import MotionEvaluation
import CoreGraphics
import ImageIO
@testable import MotionExport

@Suite struct LottiePartsTests {
    /// Any flat transform comes apart into Lottie's pieces and goes back
    /// together the same, mirrored ones included.
    @Test func transformsComeApartAndBackTogether() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &generator) }
            let t = Affine.layer(position: Vec2(r(-500...500), r(-500...500)), anchor: Vec2(r(0...100), r(0...100)),
                                 scale: Vec2(r(-3...3), r(0.05...3)), rotation: r(-720...720),
                                 skew: Vec2(r(-40...40), r(-40...40)))
            let back = LottieTransform(t).affine
            for p in [Vec2(0, 0), Vec2(100, 0), Vec2(0, 100), Vec2(37, -12)] {
                let a = t.apply(p), b = back.apply(p)
                #expect(abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6)
            }
        }
    }

    /// A turn that passes 180° keeps going rather than jumping back a
    /// whole turn.
    @Test func turnsKeepGoingPastAHalfTurn() {
        var last: Double?
        var angles: [Double] = []
        for degrees in stride(from: 0.0, through: 720, by: 15) {
            let made = LottieTransform(.rotation(degrees: degrees), previousRotation: last)
            angles.append(made.rotation)
            last = made.rotation
        }
        #expect(abs(angles.last! - 720) < 1e-9)
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $1 > $0 })
    }

    @Test func numbersAreShortAndExact() {
        #expect(LottieJSON.format(1) == "1")
        #expect(LottieJSON.format(-0.0001) == "0")
        #expect(LottieJSON.format(0.5) == "0.5")
        #expect(LottieJSON.format(1.23456) == "1.235")
        #expect(LottieJSON.format(.nan) == "0")
        let json = LottieJSON.object([("a", .string("q\"\n")), ("b", .numbers([1, 2.5]))])
        #expect(String(decoding: json.data, as: UTF8.self) == #"{"a":"q\"\n","b":[1,2.5]}"#)
    }

    /// The value a run of keyframes gives at a frame, joined by straight
    /// lines, as a Lottie player reads them.
    private func value(_ keys: [Series.Keyframe], at f: Int) -> [Double] {
        let i = keys.lastIndex { $0.frame <= f }!
        guard i + 1 < keys.count, !keys[i].holds else { return keys[i].value }
        let a = keys[i], b = keys[i + 1]
        let t = Double(f - a.frame) / Double(b.frame - a.frame)
        return zip(a.value, b.value).map { $0 + ($1 - $0) * t }
    }

    @Test func stillAndSteadyValuesNeedFewKeyframes() {
        #expect(Series(values: Array(repeating: [3, 4], count: 60), tolerance: 0.01).keyframes().count == 1)
        let steady = Series(values: (0..<60).map { [Double($0) * 2.5] }, tolerance: 0.01)
        #expect(steady.keyframes().count == 2)
        // Still, then moving steadily, then still again: three, the last value held to the end.
        let ramp = Series(values: (0..<90).map { [Double(min(max($0 - 30, 0), 30))] }, tolerance: 0.01)
        #expect(ramp.keyframes().map(\.frame) == [0, 30, 60])
    }

    /// A curve keeps enough keyframes that every frame is within reach.
    @Test func curvesStayWithinTolerance() {
        let values = (0..<120).map { f -> [Double] in
            let t = Double(f) / 30
            return [100 * (1 - exp(-4 * t) * cos(9 * t)), 40 * sin(t * 3)]
        }
        let series = Series(values: values, tolerance: 0.01)
        let keys = series.keyframes()
        #expect(keys.count < 120)
        for f in 0..<120 {
            let got = value(keys, at: f)
            #expect(abs(got[0] - values[f][0]) <= 0.0100001 && abs(got[1] - values[f][1]) <= 0.0100001)
        }
    }

    /// A path that changes how many points it has holds until it changes,
    /// as Lottie cannot blend between them.
    @Test func changesOfShapeHold() {
        let values: [[Double]] = [[0, 0], [1, 1], [0, 0, 0], [0, 0, 0]]
        let keys = Series(values: values, shapes: [1, 1, 2, 2], tolerance: 0.01).keyframes()
        #expect(keys.map(\.frame) == [0, 1, 2])
        #expect(keys[1].holds)
    }

    @Test func zipsAreReadable() throws {
        var zip = ZipWriter()
        let text = Data(String(repeating: "Twine ", count: 500).utf8)
        zip.add("a/text.txt", text, compress: true)
        zip.add("b.bin", Data([1, 2, 3]), compress: false)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Twine-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.zip")
        try zip.finish().write(to: url)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", url.path, "-d", folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
        #expect(try Data(contentsOf: folder.appendingPathComponent("a/text.txt")) == text)
        #expect(try Data(contentsOf: folder.appendingPathComponent("b.bin")) == Data([1, 2, 3]))
    }
}

/// A scene with a little of everything: a square on a spring that turns and
/// fades, a half-transparent group of a dashed, gradient-filled circle, a
/// text, and an oval masked by a rectangle.
private func scene() -> (project: Project, square: UUID, group: UUID) {
    var square = Layer(name: "Square", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                    fills: [Fill(paint: .color(RGBA(1, 0, 0)))])),
                       size: Size2(40, 40), position: Vec2(40, 60))
    square.transform.anchor = Vec2(20, 20)
    var circleShape = ShapeContent(geometry: .ellipse(arc: .full),
                                   fills: [Fill(paint: .linearGradient(Gradient(stops: [
                                       GradientStop(position: 0, color: RGBA(0, 0, 1)),
                                       GradientStop(position: 1, color: RGBA(0, 1, 0, 0.5)),
                                   ])))])
    var stroke = Stroke(paint: .color(RGBA(0, 0, 0)))
    stroke.width = 3
    stroke.alignment = .center
    stroke.dashPattern = [6, 3]
    circleShape.strokes = [stroke]
    let circle = Layer(name: "Circle", content: .shape(circleShape), size: Size2(30, 30), position: Vec2(15, 15))
    var group = Layer(name: "Group", content: .group(GroupContent(children: [circle])), size: Size2(30, 30),
                      position: Vec2(140, 30))
    group.opacity = 0.5
    let text = Layer(name: "Text", content: .text(TextContent(text: "Hi", fontSize: 24, color: RGBA(0, 0, 0))),
                     size: Size2(30, 30), position: Vec2(150, 90))
    var mask = Layer(name: "Mask", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                fills: [Fill(paint: .color(RGBA(1, 1, 1)))])),
                     size: Size2(20, 40), position: Vec2(20, 20))
    mask.isMask = true
    let oval = Layer(name: "Oval", content: .shape(ShapeContent(geometry: .ellipse(arc: .full),
                                                                fills: [Fill(paint: .color(RGBA(0.2, 0.4, 0.6)))])),
                     size: Size2(40, 40), position: Vec2(20, 20))
    let masked = Layer(name: "Masked", content: .group(GroupContent(children: [mask, oval])), size: Size2(40, 40),
                       position: Vec2(60, 100))
    let actions = [
        Action(target: square.id, start: 0, duration: 1, easing: .preset(.spring, intensity: 0.5),
               spec: .move(MoveAction(mode: .by, end: Vec2(100, 0)))),
        Action(target: square.id, start: 0.2, duration: 0.6, easing: .linear, spec: .rotate(RotateAction(end: 200))),
        Action(target: square.id, start: 0.5, duration: 0.5, easing: .linear, spec: .opacity(OpacityAction(end: 0.3))),
        Action(target: group.id, start: 0, duration: 1, easing: .linear, spec: .rotate(RotateAction(end: 90))),
    ]
    let project = Project(composition: Composition(width: 200, height: 120, frameRate: .fps30, duration: 1,
                                                   background: Background(color: .white, isTransparent: true)),
                          layers: [square, group, text, masked], actions: actions)
    return (project, square.id, group.id)
}

@Suite struct LottieExportTests {
    private func export(_ project: Project, as format: ExportFormat) throws -> (url: URL, outcome: ExportOutcome) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Twine-lottie-\(UUID().uuidString).\(format.fileExtension)")
        let outcome = try Exporter.export(project, settings: ExportSettings(format: format), to: url)
        return (url, outcome)
    }

    /// A property's value at a frame, as a player reads straight-line
    /// keyframes.
    private func value(_ property: Any?, at f: Double) -> [Double] {
        let p = property as! [String: Any]
        if (p["a"] as? Int ?? 0) == 0 {
            if let n = p["k"] as? Double { return [n] }
            return p["k"] as! [Double]
        }
        let keys = p["k"] as! [[String: Any]]
        let i = keys.lastIndex { ($0["t"] as! Double) <= f } ?? 0
        let a = keys[i]
        let s = a["s"] as! [Double]
        guard i + 1 < keys.count, (a["h"] as? Int ?? 0) == 0 else { return s }
        let b = keys[i + 1]
        let t = (f - (a["t"] as! Double)) / ((b["t"] as! Double) - (a["t"] as! Double))
        return zip(s, b["s"] as! [Double]).map { $0 + ($1 - $0) * t }
    }

    private func transform(of layer: [String: Any], at f: Double) -> (Affine, Double) {
        let ks = layer["ks"] as! [String: Any]
        let p = value(ks["p"], at: f), s = value(ks["s"], at: f)
        let made = LottieTransform(Affine.identity)
        var t = made
        t.position = Vec2(p[0], p[1])
        t.scale = Vec2(s[0], s[1])
        t.rotation = value(ks["r"], at: f)[0]
        t.skew = value(ks["sk"], at: f)[0]
        return (t.affine, value(ks["o"], at: f)[0] / 100)
    }

    @Test func movesMatchTwineAtEveryFrame() throws {
        let (project, squareID, _) = scene()
        let (url, outcome) = try export(project, as: .lottie)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(outcome.leftOut.isEmpty)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        #expect(json["w"] as? Int == 200 && json["h"] as? Int == 120)
        #expect(json["fr"] as? Int == 30 && json["op"] as? Int == 30)
        let layers = json["layers"] as! [[String: Any]]
        let square = try #require(layers.first { $0["nm"] as? String == "Square" })
        // A spring needs more than two keyframes, but far fewer than a frame each.
        let position = (square["ks"] as! [String: Any])["p"] as! [String: Any]
        let count = (position["k"] as! [Any]).count
        #expect(count > 2 && count < 30)
        for f in 0..<30 {
            let scene = evaluate(project, at: Double(f) / 30)
            let twine = try #require(scene.worldTransform(of: squareID))
            let (lottie, opacity) = transform(of: square, at: Double(f))
            for corner in Box(origin: .zero, size: Size2(40, 40)).corners {
                let a = twine.apply(corner), b = lottie.apply(corner)
                #expect(abs(a.x - b.x) < 0.05 && abs(a.y - b.y) < 0.05, "frame \(f)")
            }
            #expect(abs(opacity - scene.layer(squareID)!.opacity) < 0.002)
        }
    }

    @Test func groupsMasksAndTextBecomeLottiesOwn() throws {
        let (project, _, _) = scene()
        let (url, _) = try export(project, as: .lottie)
        defer { try? FileManager.default.removeItem(at: url) }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let layers = json["layers"] as! [[String: Any]]
        let assets = json["assets"] as! [[String: Any]]
        // The half-transparent group is drawn as one picture.
        let group = try #require(layers.first { $0["nm"] as? String == "Group" })
        #expect(group["ty"] as? Int == 0)
        #expect(value((group["ks"] as! [String: Any])["o"], at: 0) == [50])
        let comp = try #require(assets.first { $0["id"] as? String == group["refId"] as? String })
        let circle = try #require((comp["layers"] as! [[String: Any]]).first)
        let items = ((circle["shapes"] as! [[String: Any]])[0]["it"] as! [[String: Any]]).map { $0["ty"] as! String }
        // Front first: the stroke over the gradient fill.
        #expect(items == ["sh", "st", "gf", "tr"])
        // Every matte sits straight above the layer it cuts.
        for list in [layers] + assets.compactMap({ $0["layers"] as? [[String: Any]] }) {
            for (i, layer) in list.enumerated() where layer["tt"] != nil {
                #expect(i > 0 && list[i - 1]["td"] as? Int == 1)
            }
        }
        #expect(layers.contains { $0["tt"] as? Int == 1 })
        // The text is its letters' outlines, standing still.
        let text = try #require(layers.first { $0["nm"] as? String == "Text" })
        #expect(text["ty"] as? Int == 4)
        #expect(((text["ks"] as! [String: Any])["p"] as! [String: Any])["a"] as? Int == 0)
        let paths = ((text["shapes"] as! [[String: Any]])[0]["it"] as! [[String: Any]]).filter { $0["ty"] as? String == "sh" }
        #expect(paths.count >= 2)
    }

    @Test func whatLottieCannotDrawIsNamed() throws {
        var (project, squareID, _) = scene()
        _ = project.updateLayer(squareID) { $0.effects.append(Effect(kind: .dropShadow(DropShadow()))) }
        let (url, outcome) = try export(project, as: .lottie)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(outcome.leftOut == ["Shadows"])
    }

    @Test func dotLottieHoldsTheAnimation() throws {
        let (project, _, _) = scene()
        let (url, _) = try export(project, as: .dotLottie)
        defer { try? FileManager.default.removeItem(at: url) }
        let folder = url.deletingPathExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", url.path, "-d", folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        #expect(unzip.terminationStatus == 0)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as! [String: Any]
        #expect((manifest["animations"] as! [[String: Any]]).first?["id"] as? String == "animation")
        let animation = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("animations/animation.json"))) as! [String: Any]
        #expect((animation["layers"] as! [Any]).count > 0)
    }
}

/// Writes a scene with one of everything a Lottie carries, as a Lottie, a
/// dotLottie and Twine's own pictures of a few frames, into the folder
/// `TWINE_LOTTIE_OUT` names, to set beside a Lottie player's:
/// `TWINE_LOTTIE_OUT=/path swift test --filter LottieComparison`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TWINE_LOTTIE_OUT"] != nil))
struct LottieComparison {
    static let frames = [0, 8, 15, 22, 30, 45, 59]

    @Test func writeScene() throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TWINE_LOTTIE_OUT"]!)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A picture whose top-left corner is marked, to see its turns.
        let pictureURL = folder.appendingPathComponent("picture.png")
        let context = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 40))
        context.setFillColor(red: 0.2, green: 0.3, blue: 1, alpha: 1)
        context.fill(CGRect(x: 32, y: 0, width: 32, height: 40))
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 30, width: 10, height: 10))
        let destination = CGImageDestinationCreateWithURL(pictureURL as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        let asset = MediaAsset(kind: .image, fileName: "picture.png", originalName: "picture.png", contentHash: "x",
                               pixelWidth: 64, pixelHeight: 40)

        func shape(_ name: String, _ geometry: ShapeGeometry, _ fills: [Fill], size: Size2, at p: Vec2) -> Layer {
            Layer(name: name, content: .shape(ShapeContent(geometry: geometry, fills: fills)), size: size, position: p)
        }
        var skewed = shape("Skewed", .rectangle(cornerRadii: CornerRadii(all: 12)),
                           [Fill(paint: .radialGradient(Gradient(stops: [
                               GradientStop(position: 0, color: RGBA(1, 0.8, 0)),
                               GradientStop(position: 1, color: RGBA(0.8, 0, 0.4)),
                           ])))], size: Size2(80, 60), at: Vec2(70, 60))
        skewed.transform.skew = Vec2(20, 0)
        var picture = shape("Picture", .rectangle(cornerRadii: CornerRadii(all: 8)),
                            [Fill(paint: .image(ImagePaint(mediaID: asset.id, quarterTurns: 1)))],
                            size: Size2(60, 90), at: Vec2(180, 70))
        picture.transform.rotation = 10
        var inside = shape("Inside", .rectangle(cornerRadii: .zero), [Fill(paint: .color(RGBA(0.9, 0.9, 0.2)))],
                           size: Size2(60, 60), at: Vec2(290, 60))
        if case .shape(var s) = inside.content {
            s.strokes = [Stroke(paint: .color(RGBA(0, 0, 0)), width: 8, alignment: .inside)]
            inside.content = .shape(s)
        }
        var ring = shape("Ring", .ellipse(arc: .full), [], size: Size2(70, 70), at: Vec2(400, 60))
        if case .shape(var s) = ring.content {
            s.strokes = [Stroke(paint: .color(RGBA(0.1, 0.5, 0.2)), width: 6, alignment: .center, cap: .round)]
            ring.content = .shape(s)
        }
        let text = Layer(name: "Text", content: .text(TextContent(text: "Twine", fontWeight: 700, fontSize: 40,
                                                                 color: RGBA(0.1, 0.1, 0.1))),
                         size: Size2(120, 50), position: Vec2(90, 170))
        let ball = shape("Ball", .ellipse(arc: .full), [Fill(paint: .color(RGBA(0.2, 0.6, 1)))],
                         size: Size2(50, 50), at: Vec2(30, 40))
        var frame = Layer(name: "Frame", content: .group(GroupContent(children: [ball], clipsContent: true,
                                                                      frame: FrameStyle(fills: [Fill(paint: .color(RGBA(0.85, 0.85, 0.95)))],
                                                                                        cornerRadii: CornerRadii(all: 16)))),
                          size: Size2(100, 80), position: Vec2(260, 170))
        frame.transform.anchor = Vec2(50, 40)
        var mask = shape("Mask", .rectangle(cornerRadii: .zero), [Fill(paint: .color(.white))],
                         size: Size2(30, 70), at: Vec2(35, 35))
        mask.isMask = true
        let star = shape("Star", .star(points: 5, innerRadius: 0.45, cornerRadius: 0), [Fill(paint: .color(RGBA(1, 0.4, 0)))],
                         size: Size2(70, 70), at: Vec2(35, 35))
        let masked = Layer(name: "Masked", content: .group(GroupContent(children: [mask, star])),
                           size: Size2(70, 70), position: Vec2(400, 170))
        let revealed = shape("Revealed", .rectangle(cornerRadii: CornerRadii(all: 6)), [Fill(paint: .color(RGBA(0.5, 0.2, 0.8)))],
                             size: Size2(100, 50), at: Vec2(90, 260))

        var letters = PresetRecipe.defaults(.slideIn)
        letters.unit = .letters
        letters.direction = .bottom
        let actions = [
            Action(target: skewed.id, start: 0, duration: 2, easing: .preset(.smooth, intensity: 0.5),
                   spec: .move(MoveAction(mode: .by, end: Vec2(0, 30)))),
            Action(target: picture.id, start: 0, duration: 2, easing: .linear, spec: .rotate(RotateAction(end: 60))),
            Action(target: ring.id, start: 0, duration: 1.5, easing: .linear,
                   spec: .trim(TrimAction(initial: TrimRange(direction: .startToEnd, amount: 0),
                                          end: TrimRange(direction: .startToEnd, amount: 1)))),
            Action(target: text.id, start: 0, duration: 1.2, easing: .preset(.smooth, intensity: 0.5), spec: .preset(letters)),
            Action(target: ball.id, start: 0, duration: 2, easing: .linear, spec: .move(MoveAction(mode: .by, end: Vec2(80, 30)))),
            Action(target: frame.id, start: 0, duration: 2, easing: .linear, spec: .rotate(RotateAction(end: -20))),
            Action(target: mask.id, start: 0, duration: 2, easing: .linear, spec: .move(MoveAction(mode: .by, end: Vec2(40, 0)))),
            Action(target: revealed.id, start: 0.2, duration: 1, easing: .preset(.smooth, intensity: 0.5),
                   spec: .preset(PresetRecipe.defaults(.maskRevealIn))),
        ]
        let project = Project(composition: Composition(width: 480, height: 320, frameRate: .fps30, duration: 2,
                                                       background: Background(color: RGBA(0.96, 0.95, 0.93), isTransparent: false)),
                              layers: [skewed, picture, inside, ring, text, frame, masked, revealed], actions: actions,
                              media: [asset])
        let media = [asset.id: pictureURL]
        let json = try Exporter.export(project, settings: ExportSettings(format: .lottie),
                                       to: folder.appendingPathComponent("scene.json"), media: media)
        try Exporter.export(project, settings: ExportSettings(format: .dotLottie),
                            to: folder.appendingPathComponent("scene.lottie"), media: media)
        print("LOTTIE left out: \(json.leftOut)")
        for f in Self.frames {
            try Exporter.export(project, settings: ExportSettings(format: .png), at: Double(f) / 30,
                                to: folder.appendingPathComponent("twine-\(f).png"), media: media)
        }
    }
}
