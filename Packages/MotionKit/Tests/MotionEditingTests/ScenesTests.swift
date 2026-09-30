import Foundation
import Testing
import MotionModel
@testable import MotionEditing

@Suite struct ScenesTests {
    private func project() -> (Project, [Action]) {
        let layer = Layer(name: "L", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero))),
                          size: Size2(10, 10), position: .zero)
        let a = Action(target: layer.id, start: 1, duration: 1, rowOrder: 0, spec: .opacity(OpacityAction(end: 0)))
        let b = Action(target: layer.id, start: 1.5, duration: 1.5, rowOrder: 1, spec: .opacity(OpacityAction(end: 1)))
        let c = Action(target: layer.id, start: 4, duration: 0, rowOrder: 2, spec: .visibility(VisibilityAction(isVisible: false)))
        return (Project(composition: Composition(frameRate: .fps30, duration: 10), layers: [layer], actions: [a, b, c]), [a, b, c])
    }

    @Test func groupingNamesTheSceneAndTakesActionsOutOfOthers() throws {
        var (p, actions) = project()
        let first = try #require(Scenes.grouping([actions[0].id, actions[1].id], in: p))
        #expect(first.made.name == "Scene 1")
        #expect(first.made.actionIDs == [actions[0].id, actions[1].id])
        p.scenes = first.scenes
        let second = try #require(Scenes.grouping([actions[1].id, actions[2].id], in: p))
        #expect(second.made.name == "Scene 2")
        #expect(second.scenes.count == 2)
        #expect(second.scenes[0].actionIDs == [actions[0].id])
        p.scenes = second.scenes
        #expect(Scenes.ungrouping([actions[2].id], in: p).map(\.name) == ["Scene 1"])
    }

    @Test func deletingAnActionTakesItOutOfItsSceneAndAnEmptySceneGoes() throws {
        var (p, actions) = project()
        p.scenes = try #require(Scenes.grouping([actions[0].id], in: p)).scenes
        try EditorCommand.deleteActions([actions[0].id]).apply(to: &p)
        #expect(p.scenes.isEmpty)
    }

    @Test func stretchingKeepsEveryonesShareOfTheSpan() throws {
        let (_, actions) = project()
        let span = try #require(Scenes.span(of: actions))
        #expect(span == 1...4)
        // Twice as long, starting at 2: 1...4 becomes 2...8.
        let out = Scenes.stretched(actions, from: span, to: 2...8, rate: .fps30)
        #expect(abs(out[0].start - 2) < 1e-9 && abs(out[0].end - 4) < 1e-9)
        #expect(abs(out[1].start - 3) < 1e-9 && abs(out[1].end - 6) < 1e-9)
        #expect(abs(out[2].start - 8) < 1e-9 && out[2].isInstant)
        // Moving keeps lengths.
        let moved = Scenes.stretched(actions, from: span, to: 3...6, rate: .fps30)
        #expect(abs(moved[1].duration - 1.5) < 1e-9 && abs(moved[1].start - 3.5) < 1e-9)
    }

    @Test func scenesSurviveAFileAndAreLeftOutWhenThereAreNone() throws {
        var (p, actions) = project()
        let empty = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        #expect(!empty.contains("scenes"))
        p.scenes = try #require(Scenes.grouping([actions[0].id], in: p)).scenes
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(back.scenes == p.scenes)
    }
}
