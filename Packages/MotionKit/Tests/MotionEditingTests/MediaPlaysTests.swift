import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct MediaPlaysTests {
    private let sound = MediaAsset(kind: .audio, fileName: "s.wav", originalName: "s.wav", contentHash: "h", duration: 2.5)

    private func soundLayer() -> Layer {
        Layer(name: "S", content: .audio(AudioContent(mediaID: sound.id)), size: Size2(0, 0), position: .zero)
    }

    private func play(_ layer: Layer, at start: Double = 0) -> Action {
        Action(target: layer.id, start: start, duration: 1, spec: .play(PlayAction()))
    }

    @Test func deletingTheLastPlayBarDeletesTheSound() throws {
        let s = soundLayer()
        let bar = play(s)
        let fade = Action(target: s.id, start: 0, duration: 1, spec: .volume(VolumeAction(end: 0)))
        var project = Project(layers: [s], actions: [bar, fade], media: [sound])
        try MediaPlays.deleting([bar.id], in: project).apply(to: &project)
        #expect(project.layers.isEmpty)
        #expect(project.actions.isEmpty)
    }

    @Test func aSoundWithAnotherPlayBarStays() throws {
        let s = soundLayer()
        let first = play(s), second = play(s, at: 2)
        var project = Project(layers: [s], actions: [first, second], media: [sound])
        try MediaPlays.deleting([first.id], in: project).apply(to: &project)
        #expect(project.layers.map(\.id) == [s.id])
        #expect(project.actions.map(\.id) == [second.id])
    }

    @Test func otherActionsLeaveTheirLayers() throws {
        let box = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), name: "Box")
        let fade = Action(target: box.id, start: 0, duration: 1, spec: .opacity(OpacityAction(end: 0)))
        var project = Project(layers: [box], actions: [fade])
        try MediaPlays.deleting([fade.id], in: project).apply(to: &project)
        #expect(project.layers.count == 1)
        #expect(project.actions.isEmpty)
    }

    @Test func aSoundWithoutABarGetsOneAsLongAsItsFile() {
        let s = soundLayer()
        let project = MediaPlays.withPlayBars(Project(layers: [s], media: [sound]))
        #expect(project.actions.count == 1)
        let bar = project.actions[0]
        #expect(bar.targetLayerID == s.id && bar.start == 0 && bar.isPlay)
        #expect(abs(bar.duration - 2.5) < 1e-9)
        // A second pass adds nothing.
        #expect(MediaPlays.withPlayBars(project).actions.count == 1)
    }
}
