import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

private func square() -> Layer {
    var layer = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 100, maxY: 100), name: "S", duration: 5)
    layer.effects = [Effect(kind: .dropShadow(DropShadow())), Effect(kind: .layerBlur(LayerBlur()))]
    if case .shape(var s) = layer.content {
        s.strokes = [Stroke(paint: .color(.black), width: 2)]
        layer.content = .shape(s)
    }
    return layer
}

private let animate = EditContext(time: 1, mode: .animate, frameDuration: 1.0 / 60)
private let design = EditContext(time: 1, mode: .design, frameDuration: 1.0 / 60)

@Suite struct PropertyAccessTests {
    @Test func everyListedPropertyCanBeReadAndWrittenBack() {
        let layer = square()
        let ids = LayerProperties.all(of: layer)
        #expect(ids.contains(.position) && ids.contains(PropertyID(.cornerRadii)))
        #expect(ids.contains { $0.kind == .fillColor } && ids.contains { $0.kind == .trimEnd })
        #expect(ids.contains { $0.kind == .shadowOffset } && ids.contains { $0.kind == .blurRadius })
        for id in ids {
            // Keying every property at t=1 and reading it back proves both
            // halves of the accessor agree about where each property lives.
            var edited = layer
            LayerProperties.update(id, on: &edited) { $0.keyed(at: 1, tolerance: 0) }
            #expect(LayerProperties.get(id, of: edited)?.isAnimated == true, "\(id.kind)")
            #expect(LayerProperties.animated(of: edited) == [id], "\(id.kind)")
        }
    }

    @Test func titlesExistForEveryKind() {
        for kind in PropertyID.Kind.allCases { #expect(!LayerProperties.title(PropertyID(kind)).isEmpty) }
    }
}

@Suite struct KeyframingTests {
    @Test func stopwatchOnKeysTheCurrentValueAndOffHoldsIt() {
        var layer = square()
        layer = Keyframing.toggleStopwatch(.opacity, on: layer, at: 2)
        #expect(layer.opacity.keyframes.map(\.time) == [2])
        layer.opacity = layer.opacity.edited(to: 0.25, in: EditContext(time: 3, mode: .animate, frameDuration: 1.0 / 60))
        #expect(layer.opacity.keyframes.map(\.time) == [2, 3])
        layer = Keyframing.toggleStopwatch(.opacity, on: layer, at: 3)
        #expect(!layer.opacity.isAnimated)
        #expect(layer.opacity.value == 0.25)
    }

    @Test func animateModeKeysAndUpdatesAtThePlayhead() {
        let p = AnimatableProperty(0.0, keyframes: [Keyframe(time: 0, value: 0)])
        let keyed = p.edited(to: 5, in: animate)
        #expect(keyed.keyframes.map(\.time) == [0, 1])
        // Within half a frame of an existing keyframe updates it rather than
        // adding a second one beside it.
        let nudged = EditContext(time: 1.004, mode: .animate, frameDuration: 1.0 / 60)
        let updated = keyed.edited(to: 7, in: nudged)
        #expect(updated.keyframes.count == 2 && updated.keyframes[1].value == 7)
    }

    @Test func staticPropertiesStayStaticInEitherMode() {
        #expect(!AnimatableProperty(1.0).edited(to: 2, in: animate).isAnimated)
        #expect(!AnimatableProperty(RGBA.white).set(.black, in: animate).isAnimated)
    }

    @Test func designModeShiftsAndColoursKey() {
        let p = AnimatableProperty(0.0, keyframes: [Keyframe(time: 0, value: 0, easing: .linear), Keyframe(time: 2, value: 10)])
        #expect(p.edited(to: 15, in: design).keyframes.map(\.value) == [10, 20])
        let color = AnimatableProperty(RGBA.white, keyframes: [Keyframe(time: 0, value: .white)])
        #expect(color.set(.black, in: design).keyframes.count == 2)
    }

    @Test func movingAnAnimatedLayerInAnimateModeKeysIt() {
        var layer = square()
        layer.transform.position = AnimatableProperty(.zero, keyframes: [Keyframe(time: 0, value: Vec2(50, 50))])
        let moved = layer.moved(by: Vec2(10, 0), in: animate)
        #expect(moved.transform.position.keyframes.map(\.value) == [Vec2(50, 50), Vec2(60, 50)])
        let shifted = layer.moved(by: Vec2(10, 0), in: design)
        #expect(shifted.transform.position.keyframes.map(\.value) == [Vec2(60, 50)])
    }

    @Test func springsPlaceTheNextKeyframeAtTheirSettleTime() {
        var layer = square()
        layer.transform.rotation = AnimatableProperty(0, keyframes: [
            Keyframe(time: 0, value: 0), Keyframe(time: 1, value: 90), Keyframe(time: 3, value: 0),
        ])
        let first = layer.transform.rotation.keyframes[0].id
        let spring = Spring(stiffness: 200, damping: 12)
        let ref = KeyframeRef(layerID: layer.id, property: .rotation, keyframeID: first)
        let edited = Keyframing.setEasing(.spring(spring), for: [ref], in: layer)
        let times = edited.transform.rotation.keyframes.map(\.time)
        #expect(abs(times[1] - spring.settleDuration) < 1e-9)
        // The keyframe after moves by the same amount, keeping its spacing.
        #expect(abs((times[2] - times[1]) - 2) < 1e-9)
        #expect(edited.transform.rotation.keyframes[0].easing == .spring(spring))
    }

    @Test func retimingAndDeletingByReference() {
        var layer = square()
        layer.opacity = AnimatableProperty(1, keyframes: [Keyframe(time: 0, value: 0), Keyframe(time: 1, value: 1)])
        let ids = layer.opacity.keyframes.map(\.id)
        let moved = Keyframing.retime([KeyframeRef(layerID: layer.id, property: .opacity, keyframeID: ids[0]): 2], in: layer)
        // Retiming past a neighbour keeps the list sorted.
        #expect(moved.opacity.keyframes.map(\.time) == [1, 2])
        let deleted = Keyframing.delete([KeyframeRef(layerID: layer.id, property: .opacity, keyframeID: ids[1])], in: layer)
        #expect(deleted.opacity.keyframes.map(\.id) == [ids[0]])
    }

    @Test func togglingAKeyframeAtThePlayhead() {
        var layer = square()
        layer.opacity = AnimatableProperty(1, keyframes: [Keyframe(time: 0, value: 1)])
        layer = Keyframing.toggleKeyframe(.opacity, on: layer, at: 2, tolerance: 0.01)
        #expect(layer.opacity.keyframes.map(\.time) == [0, 2])
        layer = Keyframing.toggleKeyframe(.opacity, on: layer, at: 2.005, tolerance: 0.01)
        #expect(layer.opacity.keyframes.map(\.time) == [0])
    }

    @Test func shiftingALayerInTimeMovesEverything() {
        var child = square()
        child.opacity = AnimatableProperty(1, keyframes: [Keyframe(time: 1, value: 0)])
        var group = Layer(name: "G", content: .group(GroupContent(children: [child])), size: Size2(1, 1),
                          position: .zero, inPoint: 0, outPoint: 5)
        group.transform.rotation = AnimatableProperty(0, keyframes: [Keyframe(time: 2, value: 45)])
        let moved = group.shiftedInTime(by: 0.5)
        #expect(moved.inPoint == 0.5 && moved.outPoint == 5.5)
        #expect(moved.transform.rotation.keyframes[0].time == 2.5)
        #expect(moved.children[0].opacity.keyframes[0].time == 1.5)
        #expect(moved.children[0].inPoint == 0.5)
    }

    @Test func keyframesCopyAndPasteOntoAnotherLayerAtThePlayhead() throws {
        var a = square(), b = square()
        a.opacity = AnimatableProperty(1, keyframes: [Keyframe(time: 1, value: 0), Keyframe(time: 2, value: 1)])
        guard case .shape(let sa) = a.content else { return }
        let fillID = sa.fills[0].id
        a = Keyframing.toggleStopwatch(PropertyID(.fillColor, target: fillID), on: a, at: 1)
        let refs = Set(a.opacity.keyframes.map { KeyframeRef(layerID: a.id, property: .opacity, keyframeID: $0.id) }
                       + [KeyframeRef(layerID: a.id, property: PropertyID(.fillColor, target: fillID),
                                      keyframeID: LayerProperties.get(PropertyID(.fillColor, target: fillID), of: a)!.marks[0].id)])
        let clipboard = try #require(KeyframeClipboard.copy(refs, from: Project(layers: [a, b])))
        let pasted = clipboard.paste(onto: b, at: 3)
        #expect(pasted.opacity.keyframes.map(\.time) == [3, 4])
        #expect(pasted.opacity.keyframes.map(\.id) != a.opacity.keyframes.map(\.id))
        // The fill colour lands on b's own fill, which has a different id.
        #expect(LayerProperties.animated(of: pasted).contains { $0.kind == .fillColor })
    }
}
