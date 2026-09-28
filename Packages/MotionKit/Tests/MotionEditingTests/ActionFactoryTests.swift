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
        var stroked = square
        if case .shape(var shape) = stroked.content {
            shape.strokes = [Stroke(paint: .solid(.black), width: 2)]
            stroked.content = .shape(shape)
        }
        let text = LayerFactory.text(at: .zero, name: "T")
        let ellipse = LayerFactory.shape(.ellipse, in: Box(minX: 0, minY: 0, maxX: 100, maxY: 100), name: "E")
        let star = LayerFactory.shape(.star, in: Box(minX: 0, minY: 0, maxX: 100, maxY: 100), name: "S")
        let video = Layer(name: "V", content: .video(VideoContent(mediaID: UUID())), size: Size2(10, 10), position: .zero)
        let pen = PathEditing.reshaped(star, to: PathEditing.path(of: star)!).layer
        let layers = [stroked, text, ellipse, star, video, pen]
        // Between them, every kind is offered somewhere.
        #expect(Set(layers.flatMap { ActionFactory.kinds(for: $0, hasSound: true) }) == Set(ActionKind.allCases))
        for layer in layers {
            // Volume is heard, not seen; it has a test of its own.
            for kind in ActionFactory.kinds(for: layer) where kind != .volume {
                let a = ActionFactory.make(kind, for: layer, at: 1, state: LayerState(design: layer),
                                           frameRate: .fps60, rowOrder: 0)
                let p = Project(layers: [layer], actions: [a])
                let before = evaluate(p, at: 0.5), after = evaluate(p, at: 5)
                #expect(before != after, "\(kind) on \(layer.name) changes nothing")
            }
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
        // A filled rectangle with no stroke: everything but Stroke and Trim.
        #expect(ActionFactory.kinds(for: square) == [.move, .scale, .rotate, .opacity, .resize, .visibility,
                                                     .color, .cornerRadius, .shadow, .layerBlur, .backgroundBlur])
        #expect(!ActionFactory.kinds(for: group).contains(.resize))
        #expect(ActionFactory.kinds(for: audio) == [.play, .volume])
        let project = Project(layers: [square, group])
        #expect(ActionFactory.kinds(for: [square, group], in: project) == ActionFactory.kinds(for: group))
        #expect(ActionFactory.kinds(for: [], in: project).isEmpty)
        // A sound selected with layers that draw is left out; alone, it keeps its own.
        #expect(ActionFactory.kinds(for: [square, audio], in: project) == ActionFactory.kinds(for: square))
        #expect(ActionFactory.kinds(for: [audio, audio], in: project) == [.play, .volume])
    }

    @Test func aNewVolumeFadesOutOrIn() {
        let sound = Layer(name: "A", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)
        var state = LayerState(design: sound)
        let out = ActionFactory.make(.volume, for: sound, at: 0, state: state, frameRate: .fps60, rowOrder: 0)
        #expect(out.spec == .volume(VolumeAction(end: 0)))
        #expect(out.duration == 1)
        state.volume = 0
        let back = ActionFactory.make(.volume, for: sound, at: 0, state: state, frameRate: .fps60, rowOrder: 0)
        #expect(back.spec == .volume(VolumeAction(end: 1)))
    }

    @Test func newRowsGoAfterEveryOther() {
        var project = Project(layers: [square])
        #expect(ActionFactory.nextRowOrder(in: project) == 0)
        project.actions = [make(.move), make(.scale)]
        #expect(ActionFactory.nextRowOrder(in: project) == 4)
    }
}
