import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct ActionFactoryTests {
    private let square = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 100, maxY: 50), name: "S")

    private func make(_ kind: ActionKind, at time: Double = 1, state: LayerState? = nil) -> Action {
        ActionFactory.make(kind, for: square, at: time, state: state ?? LayerState(design: square),
                           frameRate: .fps60, rowOrder: 3)
    }

    @Test func newActionsStartAtThePlayheadAndRunHalfASecond() {
        let a = make(.move, at: 1.004)
        #expect(a.start == 1)          // landed on a frame
        #expect(a.duration == 0.5)
        #expect(a.targetLayerID == square.id)
        #expect(a.rowOrder == 3)
        #expect(a.easing == .default)
        #expect(a.name == "Move")
    }

    @Test func everyKindVisiblyDoesSomething() {
        let project = Project(layers: [square])
        for kind in ActionKind.allCases {
            let a = make(kind)
            let p = Project(layers: project.layers, actions: [a])
            let before = evaluate(p, at: 0.5), after = evaluate(p, at: 5)
            #expect(before != after, "\(kind) changes nothing")
        }
    }

    @Test func resizeGrowsFromTheCurrentSize() {
        var state = LayerState(design: square)
        state.size = Size2(200, 100)
        guard case .resize(let r) = make(.resize, state: state).spec else { Issue.record("not a resize"); return }
        #expect(r.end == Size2(240, 120))
    }

    @Test func hideOrShowIsWhicheverIsNotAlreadySo() {
        let hide = make(.visibility)
        #expect(hide.spec == .visibility(VisibilityAction(isVisible: false)))
        #expect(hide.name == "Hide" && hide.duration == 0)
        var hidden = LayerState(design: square)
        hidden.isShown = false
        let show = make(.visibility, state: hidden)
        #expect(show.spec == .visibility(VisibilityAction(isVisible: true)))
        #expect(show.name == "Show")
    }

    @Test func kindsFollowTheLayer() {
        let group = LayerFactory.group(in: Box(minX: 0, minY: 0, maxX: 1, maxY: 1), children: [], name: "G")
        let audio = Layer(name: "A", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)
        #expect(ActionFactory.kinds(for: square) == ActionKind.allCases)
        #expect(!ActionFactory.kinds(for: group).contains(.resize))
        #expect(ActionFactory.kinds(for: audio).isEmpty)
        #expect(ActionFactory.kinds(for: [square, group]) == ActionFactory.kinds(for: group))
        #expect(ActionFactory.kinds(for: []).isEmpty)
    }

    @Test func rowOrderGoesAfterTheLayersOthers() {
        var project = Project(layers: [square])
        #expect(ActionFactory.nextRowOrder(on: square.id, in: project) == 0)
        project.actions = [make(.move), make(.scale)]
        #expect(ActionFactory.nextRowOrder(on: square.id, in: project) == 4)
    }
}
