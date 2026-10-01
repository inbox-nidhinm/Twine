import Foundation
import Testing
@testable import MotionModel

@Suite struct ProjectStatsTests {
    private func rectangle(_ fills: [Paint] = [.color(.white)]) -> Layer {
        Layer(name: "R", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: fills.map { Fill(paint: $0) })),
              size: Size2(10, 10), position: Vec2(0, 0))
    }

    @Test func countsLayersInsideGroupsAndFramesByKind() {
        let picture = rectangle([.image(ImagePaint(mediaID: UUID()))])
        let text = Layer(name: "T", content: .text(TextContent(text: "Hi")), size: Size2(10, 10), position: Vec2(0, 0))
        let sound = Layer(name: "S", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: Vec2(0, 0))
        let group = Layer(name: "G", content: .group(GroupContent(children: [rectangle(), text])), size: Size2(10, 10), position: Vec2(0, 0))
        let frame = Layer(name: "F", content: .group(GroupContent(children: [group, picture], frame: FrameStyle())),
                          size: Size2(10, 10), position: Vec2(0, 0))
        let s = Project(layers: [frame, sound]).stats
        #expect(s.layers == 6)
        #expect(s.shapes == 1 && s.pictures == 1 && s.texts == 1 && s.sounds == 1 && s.groups == 1 && s.frames == 1)
        #expect(s.actions == 0 && s.lastActionEnds == nil)
    }

    @Test func countsActionsPresetsAndWhereTheyEnd() {
        let layer = rectangle()
        let fade = Action(target: layer.id, start: 1, duration: 2, spec: .opacity(OpacityAction(end: 0)))
        var off = Action(target: layer.id, start: 0, duration: 0.5, spec: .opacity(OpacityAction(end: 1)))
        off.isEnabled = false
        let preset = Action(target: layer.id, start: 3.5, duration: 1, spec: .preset(PresetAction(preset: .fadeIn)))
        let project = Project(layers: [layer], actions: [fade, off, preset],
                              scenes: [TimelineScene(name: "Scene 1", actionIDs: [fade.id, off.id])])
        let s = project.stats
        #expect(s.actions == 3 && s.presets == 1 && s.switchedOff == 1 && s.scenes == 1)
        #expect(s.lastActionEnds == 4.5)
    }
}
