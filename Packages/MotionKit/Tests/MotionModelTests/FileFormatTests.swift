import Foundation
import Testing
@testable import MotionModel

/// A project that uses every layer kind, paint, geometry, easing and effect, so
/// a round trip exercises every hand-written coder.
func kitchenSinkProject() -> Project {
    let image = MediaAsset(kind: .image, fileName: "a.png", originalName: "photo.png",
                           contentHash: "abc", pixelWidth: 640, pixelHeight: 480)
    let clip = MediaAsset(kind: .video, fileName: "b.mov", originalName: "clip.mov",
                          contentHash: "def", pixelWidth: 1920, pixelHeight: 1080, duration: 3.5, hasAudio: true)
    let song = MediaAsset(kind: .audio, fileName: "c.m4a", originalName: "song.m4a",
                          contentHash: "ghi", duration: 12)

    var rect = Layer(name: "Rect", content: .shape(ShapeContent(
        geometry: .rectangle(cornerRadii: AnimatableProperty(CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4))),
        fills: [Fill(paint: .color(RGBA(0.2, 0.4, 0.6, 0.8)))],
        strokes: [Stroke(paint: .color(.black), width: 3, alignment: .inside, cap: .round, join: .bevel,
                         dashPattern: [4, 2], dashOffset: 1)])),
        size: Size2(200, 100), position: Vec2(300, 200), outPoint: 5)
    rect.opacity = AnimatableProperty(1, keyframes: [
        Keyframe(time: 0, value: 0, easing: .linear),
        Keyframe(time: 1, value: 1, easing: .hold),
        Keyframe(time: 2, value: 0.5, easing: .bezier(CubicBezier(0.1, 0.2, 0.3, 1.4))),
        Keyframe(time: 3, value: 0.25, easing: .spring(Spring(stiffness: 200, damping: 10, mass: 2))),
    ])
    rect.transform.position = AnimatableProperty(Vec2(300, 200), keyframes: [
        Keyframe(time: 0.5, value: Vec2(0, 0)), Keyframe(time: 1.5, value: Vec2(10.25, -4)),
    ])
    rect.effects = [Effect(kind: .dropShadow(DropShadow())), Effect(isEnabled: false, kind: .layerBlur(LayerBlur(radius: 12)))]

    let ellipse = Layer(name: "Ellipse", content: .shape(ShapeContent(
        geometry: .ellipse,
        fills: [Fill(paint: .linearGradient(Gradient(stops: [
            GradientStop(position: 0, color: .white), GradientStop(position: 1, color: .black),
        ])))])), size: Size2(50, 50), position: Vec2(10, 10), outPoint: 5)

    var star = Layer(name: "Star", content: .shape(ShapeContent(
        geometry: .star(points: 5, innerRadius: AnimatableProperty(0.4)),
        fills: [Fill(paint: .radialGradient(Gradient(stops: [GradientStop(position: 0.5, color: .clear)],
                                                    start: Vec2(0.5, 0.5), end: Vec2(1, 0.5))))])),
        size: Size2(80, 80), position: Vec2(0, 0), outPoint: 5)
    star.mask = MaskReference(layerID: ellipse.id, isInverted: true)

    let polygon = Layer(name: "Poly", content: .shape(ShapeContent(geometry: .polygon(sides: 6))),
                        size: Size2(10, 10), position: .zero, outPoint: 1)
    let line = Layer(name: "Line", content: .shape(ShapeContent(geometry: .line)),
                     size: Size2(100, 0), position: .zero, outPoint: 1)
    let path = Layer(name: "Path", content: .shape(ShapeContent(geometry: .path(AnimatableProperty(BezierPath(subpaths: [
        Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(10, 10), inHandle: Vec2(-2, 0), outHandle: Vec2(2, 0))],
                isClosed: false),
    ]))))), size: Size2(10, 10), position: .zero, outPoint: 1)

    let text = Layer(name: "Title", content: .text(TextContent(
        text: "Hello\nworld", fontFamily: "Inter", fontWeight: 700, fontSize: 72, color: .black,
        alignment: .center, letterSpacing: -1.5, lineHeight: 80, sizing: .fixedWidth)),
        size: Size2(400, 200), position: Vec2(960, 540), inPoint: 1, outPoint: 4)

    var video = Layer(name: "Clip", content: .video(VideoContent(mediaID: clip.id, trimStart: 0.5)),
                      size: Size2(1920, 1080), position: Vec2(960, 540), outPoint: 3)
    video.isLocked = true
    let audio = Layer(name: "Song", content: .audio(AudioContent(mediaID: song.id)),
                      size: Size2(0, 0), position: .zero, outPoint: 5)
    let picture = Layer(name: "Photo", content: .image(ImageContent(mediaID: image.id)),
                        size: Size2(640, 480), position: Vec2(320, 240), outPoint: 5)

    var group = Layer(name: "Group", content: .group(GroupContent(children: [ellipse, star], clipsContent: true)),
                      size: Size2(500, 500), position: Vec2(250, 250), outPoint: 5)
    group.isSoloed = true

    return Project(
        composition: Composition(width: 1080, height: 1920, frameRate: .fps29_97, duration: 7.25,
                                 background: Background(color: RGBA(0.1, 0.2, 0.3), isTransparent: true)),
        layers: [rect, polygon, line, path, text, video, audio, picture, group],
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

    @Test func staticPropertiesOmitTheirKeyframes() throws {
        let data = try JSONEncoder().encode(AnimatableProperty(0.5))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("keyframes"))
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

    @Test func olderFilesAreMigratedStepByStep() throws {
        // Pretend version 0 kept the composition at the top level, and a
        // migration folded it into the project. The real history starts at 1;
        // this only proves the machinery runs the steps in order.
        let current = try JSONSerialization.jsonObject(with: ProjectFormat.encode(Project())) as! [String: Any]
        var project = current["project"] as! [String: Any]
        let composition = project.removeValue(forKey: "composition")!
        let old: [String: Any] = ["formatVersion": 0, "comp": composition, "project": project]
        let data = try JSONSerialization.data(withJSONObject: old)

        let migrator = FormatMigrator(steps: [0: { object in
            var body = object["project"] as! [String: Any]
            body["composition"] = object.removeValue(forKey: "comp")
            object["project"] = body
        }])
        #expect(try ProjectFormat.decode(data, migrator: migrator) == Project())
    }

    @Test func aMissingMigrationStepIsAnError() throws {
        let data = Data(#"{"formatVersion": 0, "project": {}}"#.utf8)
        #expect(throws: ProjectFileError.missingMigration(from: 0)) {
            try ProjectFormat.decode(data, migrator: FormatMigrator(steps: [:]))
        }
    }
}
