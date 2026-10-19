import Foundation
import Testing
@testable import MotionModel

/// A project that uses every layer kind, paint, geometry, action, easing and
/// effect, so a round trip exercises every hand-written coder.
func kitchenSinkProject() -> Project {
    let image = MediaAsset(kind: .image, fileName: "a.png", originalName: "photo.png",
                           contentHash: "abc", pixelWidth: 640, pixelHeight: 480)
    let clip = MediaAsset(kind: .video, fileName: "b.mov", originalName: "clip.mov",
                          contentHash: "def", pixelWidth: 1920, pixelHeight: 1080, duration: 3.5, hasAudio: true)
    let song = MediaAsset(kind: .audio, fileName: "c.m4a", originalName: "song.m4a",
                          contentHash: "ghi", duration: 12)

    var rect = Layer(name: "Rect", content: .shape(ShapeContent(
        geometry: .rectangle(cornerRadii: CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)),
        fills: [Fill(paint: .color(RGBA(0.2, 0.4, 0.6, 0.8)))],
        strokes: [Stroke(paint: .color(.black), width: 3, alignment: .inside, cap: .round, join: .bevel,
                         dashPattern: [4, 2], dashOffset: 1)])),
        size: Size2(200, 100), position: Vec2(300, 200))
    rect.blendMode = .colorDodge
    rect.effects = [Effect(kind: .dropShadow(DropShadow(spread: 3))), Effect(isEnabled: false, kind: .layerBlur(LayerBlur(radius: 12))),
                    Effect(kind: .innerShadow(DropShadow(color: .white, offset: Vec2(0, -2), blur: 3, opacity: 0.4, spread: 1))),
                    Effect(kind: .backgroundBlur(BackgroundBlur(radius: 20, blend: 0.6))),
                    Effect(kind: .glass(Glass(lightAngle: 30, lightIntensity: 0.5, refraction: 0.7, depth: 12, dispersion: 0.2,
                                              frost: 3, splay: 0.4)))]

    let ellipse = Layer(name: "Ellipse", content: .shape(ShapeContent(
        geometry: .ellipse(arc: EllipseArc(start: -90, end: 180, innerRadius: 0.6)),
        fills: [Fill(paint: .linearGradient(Gradient(stops: [
            GradientStop(position: 0, color: .white), GradientStop(position: 1, color: .black),
        ])))])), size: Size2(50, 50), position: Vec2(10, 10))

    var star = Layer(name: "Star", content: .shape(ShapeContent(
        geometry: .star(points: 5, innerRadius: 0.4, cornerRadius: 4),
        fills: [Fill(paint: .radialGradient(Gradient(stops: [GradientStop(position: 0.5, color: .clear)],
                                                    start: Vec2(0.5, 0.5), end: Vec2(1, 0.5))))])),
        size: Size2(80, 80), position: Vec2(0, 0))
    star.isMask = true

    let polygon = Layer(name: "Poly", content: .shape(ShapeContent(geometry: .polygon(sides: 6, cornerRadius: 0))),
                        size: Size2(10, 10), position: .zero)
    let line = Layer(name: "Line", content: .shape(ShapeContent(geometry: .line)),
                     size: Size2(100, 0), position: .zero)
    let path = Layer(name: "Path", content: .shape(ShapeContent(geometry: .path(BezierPath(subpaths: [
        Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(10, 10), inHandle: Vec2(-2, 0), outHandle: Vec2(2, 0))],
                isClosed: false),
    ])))), size: Size2(10, 10), position: .zero)

    let text = Layer(name: "Title", content: .text(TextContent(
        text: "Hello\nworld", fontFamily: "Inter", fontWeight: 700, fontSize: 72, color: .black,
        alignment: .center, letterSpacing: -1.5, lineHeight: 80, sizing: .fixedWidth)),
        size: Size2(400, 200), position: Vec2(960, 540))

    var video = Layer(name: "Clip", content: .video(VideoContent(mediaID: clip.id, volume: 0.5, isMuted: true, fit: .fit)),
                      size: Size2(1920, 1080), position: Vec2(960, 540))
    video.isLocked = true
    let audio = Layer(name: "Song", content: .audio(AudioContent(mediaID: song.id)),
                      size: Size2(0, 0), position: .zero)
    let picture = Layer(name: "Photo", content: .shape(ShapeContent(
        geometry: .rectangle(cornerRadii: CornerRadii(all: 12)),
        fills: [Fill(paint: .image(ImagePaint(mediaID: image.id, mode: .crop,
                                              crop: ImageCrop(x: -0.25, y: 0, width: 1.5, height: 1.125),
                                              quarterTurns: 1, tileScale: 0.5, opacity: 0.75))),
                Fill(paint: .image(ImagePaint(mediaID: image.id, mode: .tile, tileScale: 0.25)))])),
        size: Size2(640, 480), position: Vec2(320, 240))

    let frame = Layer(name: "Frame", content: .group(GroupContent(children: [], clipsContent: true, frame: FrameStyle(
        fills: [Fill(paint: .color(.white))], strokes: [Stroke(paint: .color(.black), width: 2)],
        cornerRadii: CornerRadii(topLeft: 8, topRight: 8, bottomRight: 0, bottomLeft: 0)))),
        size: Size2(300, 200), position: Vec2(150, 100))
    var group = Layer(name: "Group", content: .group(GroupContent(children: [ellipse, star, frame], clipsContent: true)),
                      size: Size2(500, 500), position: Vec2(250, 250))
    group.isSoloed = true

    let actions = [
        Action(target: rect.id, start: 0.5, duration: 1, easing: .linear,
               spec: .move(MoveAction(mode: .to, initial: Vec2(0, 0), end: Vec2(10.25, -4),
                                      curve: MotionCurve(startHandle: Vec2(5, -20), endHandle: Vec2(-5, 20))))),
        Action(target: rect.id, start: 0, duration: 2, easing: .custom(CubicBezier(0.1, 0.2, 0.3, 1.4)),
               name: "Grow", rowOrder: 3, spec: .scale(ScaleAction(mode: .by, end: Vec2(1.5, 1.2), isLinked: false))),
        Action(target: rect.id, start: 1, duration: 0.5, easing: .preset(.spring, intensity: 0.8),
               spec: .rotate(RotateAction(initial: -90, end: 720))),
        Action(target: text.id, start: 1, duration: 0.25, isEnabled: false,
               spec: .opacity(OpacityAction(initial: 0, end: 1))),
        Action(target: picture.id, start: 2, duration: 1, easing: .preset(.overshoot, intensity: 0.3),
               spec: .resize(ResizeAction(end: Size2(320, 240), isLinked: true))),
        Action(target: group.id, start: 3, duration: 0, spec: .visibility(VisibilityAction(isVisible: false))),
        Action(target: rect.id, start: 1, duration: 1, spec: .color(ColorAction(
            initial: .solid(.white), end: .radialGradient(Gradient(stops: [GradientStop(position: 0.2, color: .black)]))))),
        Action(target: rect.id, start: 1, duration: 1, spec: .stroke(StrokeAction(
            end: StrokeLook(width: 8, paint: .linearGradient(Gradient(stops: [])))))),
        Action(target: rect.id, start: 1, duration: 1, spec: .trim(TrimAction(initial: TrimRange(amount: 0), end: .whole))),
        Action(target: rect.id, start: 1, duration: 1, spec: .cornerRadius(CornerRadiusAction(
            end: CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4), isLinked: false))),
        Action(target: rect.id, start: 1, duration: 1, spec: .shadow(ShadowAction(initial: .noShadow, end: DropShadow(spread: -2)))),
        Action(target: rect.id, start: 1, duration: 1, spec: .innerShadow(ShadowAction(end: DropShadow(color: .white, blur: 3)))),
        Action(target: group.id, start: 1, duration: 1, spec: .layerBlur(LayerBlurAction(initial: 2, end: 10))),
        Action(target: text.id, start: 1, duration: 1, spec: .letterSpacing(LetterSpacingAction(initial: 0, end: 4))),
        Action(target: text.id, start: 1, duration: 1, spec: .lineHeight(LineHeightAction(end: 90))),
        Action(target: rect.id, start: 2, duration: 1, spec: .volume(VolumeAction(initial: 0.25, end: 0.8))),
        Action(target: rect.id, start: 1, duration: 1, spec: .path(PathAction(
            initial: BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(5, 5), outHandle: Vec2(1, 0))],
                                                   isClosed: false)]),
            end: BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0), inHandle: Vec2(-2, 1)), PathPoint(Vec2(9, 3))],
                                               isClosed: true)])))),
        Action(target: text.id, start: 1, duration: 1, spec: .counter(CounterAction(from: 1, to: 9, step: 2, transition: .slide))),
        Action(target: text.id, start: 1, duration: 1, spec: .changeText(ChangeTextAction(
            text: "Bye", transitionOut: .scale, transitionIn: .none, overlaps: true))),
        Action(target: ellipse.id, start: 1, duration: 1, spec: .arc(ArcAction(initial: .full, end: EllipseArc(end: 90)))),
        Action(target: star.id, start: 1, duration: 1, spec: .star(StarAction(end: StarShape(points: 7, innerRadius: 0.5, cornerRadius: 2)))),
        Action(target: video.id, start: 0.5, duration: 2, spec: .play(PlayAction(trimStart: 1.25))),
        Action(target: rect.id, start: 1, duration: 1, spec: .backgroundBlur(BackgroundBlurAction(end: BackgroundBlur(radius: 4, blend: 0.5)))),
        Action(target: rect.id, start: 2, duration: 1, spec: .glass(GlassAction(initial: .noGlass, end: Glass(depth: 30)))),
    ]

    return Project(
        composition: Composition(width: 1080, height: 1920, frameRate: .fps29_97, duration: 7.25,
                                 background: Background(color: RGBA(0.1, 0.2, 0.3), isTransparent: true)),
        layers: [rect, polygon, line, path, text, video, audio, picture, group],
        actions: actions,
        media: [image, clip, song])
}

@Suite struct FileFormatTests {
    @Test func defaultProjectRoundTrips() throws {
        let project = Project()
        let data = try ProjectFormat.encode(project)
        #expect(try ProjectFormat.decode(data) == project)
    }

    @Test func everyKindOfContentRoundTrips() throws {
        let project = kitchenSinkProject()
        let data = try ProjectFormat.encode(project)
        let decoded = try ProjectFormat.decode(data)
        #expect(decoded == project)
        // And the second trip writes exactly the same bytes, so saving an
        // unchanged file never shows up as a change.
        #expect(try ProjectFormat.encode(decoded) == data)
    }

    @Test func fileCarriesItsFormatVersion() throws {
        let data = try ProjectFormat.encode(Project())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["formatVersion"] as? Int == ProjectFormat.currentVersion)
        #expect(object["project"] is [String: Any])
    }

    @Test func actionsKeepEveryField() throws {
        let data = try ProjectFormat.encode(kitchenSinkProject())
        let text = try #require(String(data: data, encoding: .utf8))
        for key in ["\"actions\"", "\"targetLayerID\"", "\"rowOrder\"", "\"intensity\"", "\"curve\"", "\"isEnabled\""] {
            #expect(text.contains(key))
        }
    }

    @Test func shapesSavedBeforeArcsAndStarCornersStillOpen() throws {
        let ellipse = try JSONDecoder().decode(ShapeGeometry.self, from: Data(#"{"type": "ellipse"}"#.utf8))
        #expect(ellipse == .ellipse(arc: .full))
        let star = try JSONDecoder().decode(ShapeGeometry.self, from: Data(#"{"type": "star", "points": 5, "innerRadius": 0.4}"#.utf8))
        #expect(star == .star(points: 5, innerRadius: 0.4, cornerRadius: 0))
    }

    @Test func shadowsSavedBeforeSpreadStillOpen() throws {
        let json = #"{"color": {"r": 0, "g": 0, "b": 0, "a": 1}, "offset": {"x": 0, "y": 4}, "blur": 8, "opacity": 0.25}"#
        let shadow = try JSONDecoder().decode(DropShadow.self, from: Data(json.utf8))
        #expect(shadow == DropShadow())
    }

    @Test func fileFromBeforeActionsIsRefusedPlainly() throws {
        let json = #"{"formatVersion": 1, "project": {}}"#
        #expect(throws: ProjectFileError.olderVersion(1)) {
            try ProjectFormat.decode(Data(json.utf8))
        }
        #expect(ProjectFileError.olderVersion(1).errorDescription?.contains("earlier version") == true)
    }

    @Test func fileFromANewerVersionIsRefused() throws {
        let json = #"{"formatVersion": 99, "project": {}}"#
        #expect(throws: ProjectFileError.newerVersion(99)) {
            try ProjectFormat.decode(Data(json.utf8))
        }
    }

    @Test func garbageIsReportedAsUnreadable() {
        #expect {
            try ProjectFormat.decode(Data("not json".utf8))
        } throws: { error in
            if case ProjectFileError.unreadable = error { return true }
            return false
        }
    }

    @Test func layersSavedBeforeBlendModesStillOpenAsNormal() throws {
        var layer = Layer(name: "L", content: .shape(ShapeContent(geometry: .line)), size: Size2(1, 1), position: .zero)
        let data = try JSONEncoder().encode(layer)
        #expect(!String(data: data, encoding: .utf8)!.contains("blendMode"), "Normal is left out")
        #expect(try JSONDecoder().decode(Layer.self, from: data).blendMode == .normal)
        layer.blendMode = .multiply
        #expect(try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer)) == layer)
    }

    @Test func videoSavedBeforeFitStillOpens() throws {
        let id = UUID()
        let json = #"{"mediaID": "\#(id.uuidString)", "volume": 1, "isMuted": false}"#
        #expect(try JSONDecoder().decode(VideoContent.self, from: Data(json.utf8)) == VideoContent(mediaID: id))
    }

    /// Format 2 had picture layers; format 3 has rectangles filled with the
    /// picture. The layer keeps its id, so its actions and a layer it masks
    /// carry on, and one inside a group is found too.
    @Test func pictureLayersBecomeRectanglesFilledWithThePicture() throws {
        let asset = MediaAsset(kind: .image, fileName: "p.png", originalName: "p.png", contentHash: "p",
                               pixelWidth: 400, pixelHeight: 200)
        let fitting = UUID(), stretched = UUID(), masked = UUID(), group = UUID()
        func picture(_ id: UUID, _ w: Double, _ h: Double) -> String {
            #"{"id": "\#(id.uuidString)", "name": "p", "isVisible": true, "isLocked": false, "isSoloed": false,"#
            + #""transform": {"position": {"x": 0, "y": 0}, "anchor": {"x": 0, "y": 0}, "scale": {"x": 1, "y": 1}, "isScaleLinked": true, "rotation": 0},"#
            + #""size": {"width": \#(w), "height": \#(h)}, "opacity": 1, "effects": [],"#
            + #""content": {"type": "image", "image": {"mediaID": "\#(asset.id.uuidString)"}}}"#
        }
        let maskedLayer = #"{"id": "\#(masked.uuidString)", "name": "m", "isVisible": true, "isLocked": false, "isSoloed": false,"#
            + #""transform": {"position": {"x": 0, "y": 0}, "anchor": {"x": 0, "y": 0}, "scale": {"x": 1, "y": 1}, "isScaleLinked": true, "rotation": 0},"#
            + #""size": {"width": 10, "height": 10}, "opacity": 1, "effects": [], "mask": {"layerID": "\#(fitting.uuidString)", "isInverted": false},"#
            + #""content": {"type": "shape", "shape": {"geometry": {"type": "line"}, "fills": [], "strokes": []}}}"#
        let groupLayer = #"{"id": "\#(group.uuidString)", "name": "g", "isVisible": true, "isLocked": false, "isSoloed": false,"#
            + #""transform": {"position": {"x": 0, "y": 0}, "anchor": {"x": 0, "y": 0}, "scale": {"x": 1, "y": 1}, "isScaleLinked": true, "rotation": 0},"#
            + #""size": {"width": 10, "height": 10}, "opacity": 1, "effects": [],"#
            + #""content": {"type": "group", "group": {"clipsContent": false, "children": [\#(picture(stretched, 100, 100))]}}}"#
        let media = String(data: try JSONEncoder().encode([asset]), encoding: .utf8)!
        let action = Action(target: fitting, start: 0, duration: 1, spec: .opacity(OpacityAction(end: 0)))
        let actions = String(data: try JSONEncoder().encode([action]), encoding: .utf8)!
        let composition = String(data: try JSONEncoder().encode(Composition()), encoding: .utf8)!
        let json = #"{"formatVersion": 2, "project": {"composition": \#(composition), "media": \#(media), "actions": \#(actions),"#
            + #""layers": [\#(picture(fitting, 200, 100)), \#(maskedLayer), \#(groupLayer)]}}"#

        let project = try ProjectFormat.decode(Data(json.utf8))
        let converted = try #require(project.layer(withID: fitting))
        guard case .shape(let shape) = converted.content else { Issue.record("not a shape"); return }
        #expect(shape.geometry == .rectangle(cornerRadii: .zero))
        #expect(shape.fills.map(\.paint) == [.image(ImagePaint(mediaID: asset.id))])
        #expect(shape.strokes.isEmpty)
        // 100 by 100 is not the picture's shape, so its stretch is kept.
        #expect(project.layer(withID: stretched)?.picture?.paint.mode == .crop)
        #expect(project.layer(withID: stretched)?.picture?.paint.crop == .whole)
        #expect(project.layer(withID: masked)?.legacyMask?.layerID == fitting)
        #expect(project.actions == [action])
    }

    @Test func migrationsRunStepByStep() throws {
        // Proves the machinery with a made-up step: pretend version 2 kept
        // the composition at the top level and version 3 folded it in.
        let current = try JSONSerialization.jsonObject(with: ProjectFormat.encode(Project())) as! [String: Any]
        var project = current["project"] as! [String: Any]
        let composition = project.removeValue(forKey: "composition")!
        let old: [String: Any] = ["formatVersion": 2, "comp": composition, "project": project]
        let data = try JSONSerialization.data(withJSONObject: old)

        let migrator = FormatMigrator(steps: [2: { object in
            var body = object["project"] as! [String: Any]
            body["composition"] = object.removeValue(forKey: "comp")
            object["project"] = body
        }])
        let migrated = try migrator.migrate(data, from: 2, to: 3)
        let object = try #require(try JSONSerialization.jsonObject(with: migrated) as? [String: Any])
        #expect(object["formatVersion"] as? Int == 3)
        #expect((object["project"] as? [String: Any])?["composition"] != nil)
    }

    @Test func aMissingMigrationStepIsAnError() throws {
        let data = Data(#"{"formatVersion": 2, "project": {}}"#.utf8)
        #expect(throws: ProjectFileError.missingMigration(from: 2)) {
            try FormatMigrator(steps: [:]).migrate(data, from: 2, to: 3)
        }
    }
}
