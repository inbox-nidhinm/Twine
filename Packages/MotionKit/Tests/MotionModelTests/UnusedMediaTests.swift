import Foundation
import Testing
@testable import MotionModel

/// Which imported files a project no longer uses, and so may let go of
/// when it is opened. Wrong the other way, this loses someone's picture.
@Suite struct UnusedMediaTests {
    private func asset(_ name: String, _ kind: MediaKind = .image) -> MediaAsset {
        MediaAsset(kind: kind, fileName: "\(name).bin", originalName: name, contentHash: name)
    }

    private func shape(_ name: String, fill: UUID? = nil, stroke: UUID? = nil) -> Layer {
        var content = ShapeContent(geometry: .rectangle(cornerRadii: .zero))
        if let fill { content.fills = [Fill(paint: .image(ImagePaint(mediaID: fill)))] }
        if let stroke { content.strokes = [Stroke(paint: .image(ImagePaint(mediaID: stroke)))] }
        return Layer(name: name, content: .shape(content), size: Size2(10, 10), position: .zero)
    }

    @Test func everyWayOfUsingAFileKeepsIt() {
        let filled = asset("fill"), stroked = asset("stroke"), video = asset("video", .video), sound = asset("sound", .audio)
        let deep = asset("deep"), acted = asset("acted"), gone = asset("gone"), goneToo = asset("gone too", .video)
        let inner = Layer(name: "Inner", content: .group(GroupContent(children: [shape("Deep", fill: deep.id)])),
                          size: Size2(10, 10), position: .zero)
        let outer = Layer(name: "Outer", content: .group(GroupContent(children: [inner])), size: Size2(10, 10), position: .zero)
        let plain = shape("Plain")
        let layers = [
            shape("Filled", fill: filled.id), shape("Stroked", stroke: stroked.id), outer, plain,
            Layer(name: "Video", content: .video(VideoContent(mediaID: video.id)), size: Size2(10, 10), position: .zero),
            Layer(name: "Sound", content: .audio(AudioContent(mediaID: sound.id)), size: Size2(0, 0), position: .zero),
        ]
        // A picture only an action turns the fill into.
        let action = Action(target: plain.id, start: 0, duration: 1,
                            spec: .color(ColorAction(end: .image(ImagePaint(mediaID: acted.id)))))
        let project = Project(layers: layers, actions: [action],
                              media: [filled, stroked, video, sound, deep, acted, gone, goneToo])
        #expect(Set(project.unusedMedia.map(\.id)) == [gone.id, goneToo.id])

        // With nothing left over, nothing is let go.
        var tidy = project
        tidy.media.removeAll { $0.id == gone.id || $0.id == goneToo.id }
        #expect(tidy.unusedMedia.isEmpty)
        #expect(Project().unusedMedia.isEmpty)
    }
}
