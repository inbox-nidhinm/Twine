import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// A 100 by 100 square at (500, 500), 100%, unturned, fully opaque.
private func square(_ name: String = "Square") -> Layer {
    Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                   fills: [Fill(paint: .color(.white))])),
          size: Size2(100, 100), position: Vec2(500, 500))
}

private func move(_ layer: Layer, _ mode: ActionMode = .by, from initial: Vec2? = nil, to end: Vec2,
                  at start: Double, for duration: Double, row: Int = 0) -> Action {
    Action(target: layer.id, start: start, duration: duration, easing: .linear, rowOrder: row,
           spec: .move(MoveAction(mode: mode, initial: initial, end: end)))
}

private func fade(_ layer: Layer, from initial: Double? = nil, to end: Double, at start: Double, for duration: Double) -> Action {
    Action(target: layer.id, start: start, duration: duration, easing: .linear,
           spec: .opacity(OpacityAction(initial: initial, end: end)))
}

private func state(_ layer: Layer, _ actions: [Action], at time: Double) -> LayerState {
    ActionTracks(actions).state(of: layer, at: time)
}

private func near(_ a: Vec2, _ b: Vec2, _ tolerance: Double = 1e-9) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
}

@Suite struct StartingValueTests {
    @Test func anEmptyInitialValueInheritsTheDesignState() {
        let layer = square()
        let a = fade(layer, to: 0, at: 1, for: 2)
        #expect(state(layer, [a], at: 1).opacity == 1)
        #expect(state(layer, [a], at: 2).opacity == 0.5)
        #expect(state(layer, [a], at: 3).opacity == 0)
    }

    @Test func anExplicitInitialValueIsWhereItStarts() {
        let layer = square()
        let a = fade(layer, from: 0.2, to: 0.6, at: 1, for: 2)
        #expect(abs(state(layer, [a], at: 1).opacity - 0.2) < 1e-12)
        #expect(abs(state(layer, [a], at: 2).opacity - 0.4) < 1e-12)
    }

    @Test func anExplicitInitialValueJumpsInWhenSomethingEarlierMovedIt() {
        let layer = square()
        let first = fade(layer, to: 0.5, at: 0, for: 1)
        let second = fade(layer, from: 1, to: 0, at: 2, for: 1)
        // Between them the first one's end holds; at the second's start the
        // value jumps to its own initial value.
        #expect(state(layer, [first, second], at: 1.99).opacity == 0.5)
        #expect(state(layer, [first, second], at: 2).opacity == 1)
    }

    @Test func theInspectorCanAskWhatAnActionWouldInherit() {
        let layer = square()
        let first = move(layer, to: Vec2(100, 0), at: 0, for: 1)
        let second = move(layer, to: Vec2(0, 50), at: 2, for: 1)
        let tracks = ActionTracks([first, second])
        #expect(tracks.inheritedState(for: first, of: layer).position == Vec2(500, 500))
        #expect(tracks.inheritedState(for: second, of: layer).position == Vec2(600, 500))
    }
}

@Suite struct EntranceTests {
    @Test func aFadeInKeepsTheLayerInvisibleUntilItStarts() {
        let layer = square()
        let a = fade(layer, from: 0, to: 1, at: 2, for: 1)
        #expect(state(layer, [a], at: 0).opacity == 0)
        #expect(state(layer, [a], at: 1.999).opacity == 0)
        #expect(state(layer, [a], at: 2.5).opacity == 0.5)
    }

    @Test func withoutAnInitialValueNothingHappensBeforeTheStart() {
        let layer = square()
        let a = fade(layer, to: 0, at: 2, for: 1)
        #expect(state(layer, [a], at: 1).opacity == 1)
    }

    @Test func onlyTheFirstActionOnAChannelHoldsFromTheStart() {
        let layer = square()
        let first = fade(layer, to: 0.5, at: 1, for: 1)
        let later = fade(layer, from: 0, to: 1, at: 3, for: 1)
        // Before the first starts, the later one's initial value has no say.
        #expect(state(layer, [first, later], at: 0).opacity == 1)
    }
}

@Suite struct ChainingTests {
    @Test func aSecondMoveContinuesFromWhereTheFirstEnded() {
        let layer = square()
        let a = move(layer, to: Vec2(100, 0), at: 0, for: 1)
        let b = move(layer, to: Vec2(0, 100), at: 2, for: 1)
        #expect(state(layer, [a, b], at: 1.5).position == Vec2(600, 500))
        #expect(state(layer, [a, b], at: 2.5).position == Vec2(600, 550))
        #expect(state(layer, [a, b], at: 9).position == Vec2(600, 600))
    }

    @Test func theEndValueHoldsAfterTheEnd() {
        let layer = square()
        let a = move(layer, .to, to: Vec2(0, 0), at: 0, for: 1)
        #expect(state(layer, [a], at: 100).position == .zero)
    }

    @Test func orderInTheListDoesNotMatter() {
        let layer = square()
        let a = move(layer, to: Vec2(100, 0), at: 0, for: 1)
        let b = move(layer, to: Vec2(0, 100), at: 2, for: 1)
        #expect(state(layer, [b, a], at: 2.5) == state(layer, [a, b], at: 2.5))
    }

    @Test func actionsOnDifferentChannelsRunTogether() {
        let layer = square()
        let m = move(layer, to: Vec2(100, 0), at: 0, for: 2)
        let f = fade(layer, to: 0, at: 1, for: 2)
        let s = state(layer, [m, f], at: 1.5)
        #expect(s.position == Vec2(575, 500))
        #expect(s.opacity == 0.75)
    }
}

@Suite struct OverlapTests {
    @Test func theLaterActionTakesOverFromTheValueAtItsStart() {
        let layer = square()
        let a = move(layer, .to, to: Vec2(600, 500), at: 0, for: 2)
        let b = move(layer, .to, to: Vec2(550, 600), at: 1, for: 1)
        // At 1 s the first is halfway, at (550, 500): the second starts there.
        #expect(state(layer, [a, b], at: 1).position == Vec2(550, 500))
        #expect(state(layer, [a, b], at: 1.5).position == Vec2(550, 550))
        // The first would have ended at (600, 500) at 2 s; it no longer counts.
        #expect(state(layer, [a, b], at: 2).position == Vec2(550, 600))
        #expect(state(layer, [a, b], at: 5).position == Vec2(550, 600))
    }

    @Test func actionsThatStartTogetherGoInRowOrder() {
        let layer = square()
        let a = move(layer, .to, to: Vec2(0, 0), at: 1, for: 1, row: 1)
        let b = move(layer, .to, to: Vec2(900, 900), at: 1, for: 1, row: 0)
        // b (row 0) starts first and a (row 1) takes over at once.
        #expect(state(layer, [a, b], at: 2).position == .zero)
    }
}

@Suite struct InstantTests {
    @Test func aZeroLengthActionJumpsAtItsStart() {
        let layer = square()
        let a = move(layer, .to, to: Vec2(0, 0), at: 1, for: 0)
        #expect(state(layer, [a], at: 0.999).position == Vec2(500, 500))
        #expect(state(layer, [a], at: 1).position == .zero)
    }

    @Test func instantActionsIgnoreEasing() {
        let layer = square()
        var a = fade(layer, to: 0, at: 1, for: 0)
        a.easing = .preset(.overshoot, intensity: 1)
        #expect(state(layer, [a], at: 1).opacity == 0)
    }

    @Test func aLayerWhoseFirstVisibilityActionIsShowIsHiddenUntilIt() {
        let layer = square()
        let show = Action(target: layer.id, start: 2, duration: 0, spec: .visibility(VisibilityAction(isVisible: true)))
        #expect(!state(layer, [show], at: 0).isShown)
        #expect(!state(layer, [show], at: 1.99).isShown)
        #expect(state(layer, [show], at: 2).isShown)
    }

    @Test func hideAndShowSwitchInTurn() {
        let layer = square()
        let hide = Action(target: layer.id, start: 1, duration: 0.5, spec: .visibility(VisibilityAction(isVisible: false)))
        let show = Action(target: layer.id, start: 3, duration: 0, spec: .visibility(VisibilityAction(isVisible: true)))
        #expect(hide.isInstant)
        #expect(state(layer, [hide, show], at: 0).isShown)
        // A Hide with a length still happens at once.
        #expect(!state(layer, [hide, show], at: 1).isShown)
        #expect(!state(layer, [hide, show], at: 2.9).isShown)
        #expect(state(layer, [hide, show], at: 3).isShown)
    }

    @Test func aHiddenGroupHidesItsChildren() {
        let child = square("Child")
        let group = Layer(name: "G", content: .group(GroupContent(children: [child])), size: Size2(10, 10), position: .zero)
        let hide = Action(target: group.id, start: 1, duration: 0, spec: .visibility(VisibilityAction(isVisible: false)))
        let project = Project(layers: [group], actions: [hide])
        #expect(evaluate(project, at: 0).layers.count == 2)
        #expect(evaluate(project, at: 1).layers.isEmpty)
    }
}

@Suite struct ModeTests {
    @Test func moveByAddsToWhereverTheLayerIs() {
        var layer = square()
        let a = move(layer, to: Vec2(100, -50), at: 0, for: 1)
        #expect(state(layer, [a], at: 1).position == Vec2(600, 450))
        // Moving the design position carries the whole animation with it.
        layer.transform.position = Vec2(0, 0)
        #expect(state(layer, [a], at: 1).position == Vec2(100, -50))
    }

    @Test func moveToGoesToTheSamePlaceWhereverItStarts() {
        var layer = square()
        let a = move(layer, .to, to: Vec2(10, 20), at: 0, for: 1)
        #expect(state(layer, [a], at: 1).position == Vec2(10, 20))
        layer.transform.position = Vec2(0, 0)
        #expect(state(layer, [a], at: 1).position == Vec2(10, 20))
    }

    @Test func aByMoveWithAnInitialValueRunsFromIt() {
        let layer = square()
        let a = move(layer, from: Vec2(0, 0), to: Vec2(100, 0), at: 0, for: 1)
        #expect(state(layer, [a], at: 1).position == Vec2(100, 0))
    }

    @Test func scaleByMultiplies() {
        var layer = square()
        layer.transform.scale = Vec2(0.5, 0.5)
        let by = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                        spec: .scale(ScaleAction(mode: .by, end: Vec2(2, 3))))
        let to = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                        spec: .scale(ScaleAction(mode: .to, end: Vec2(2, 3))))
        #expect(state(layer, [by], at: 1).scale == Vec2(1, 1.5))
        #expect(state(layer, [to], at: 1).scale == Vec2(2, 3))
    }

    @Test func rotationIsNeverWrapped() {
        var layer = square()
        layer.transform.rotation = 30
        let to = Action(target: layer.id, start: 0, duration: 1, easing: .linear, spec: .rotate(RotateAction(end: 720)))
        let by = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                        spec: .rotate(RotateAction(mode: .by, end: -400)))
        #expect(state(layer, [to], at: 0.5).rotation == 375)
        #expect(state(layer, [to], at: 1).rotation == 720)
        #expect(state(layer, [by], at: 1).rotation == -370)
    }
}

@Suite struct DisabledTests {
    @Test func aDisabledActionDoesNothing() {
        let layer = square()
        var a = fade(layer, from: 0, to: 0.5, at: 1, for: 1)
        a.isEnabled = false
        #expect(state(layer, [a], at: 0).opacity == 1)
        #expect(state(layer, [a], at: 5).opacity == 1)
    }

    @Test func aDisabledActionIsSkippedInAChain() {
        let layer = square()
        var a = move(layer, to: Vec2(100, 0), at: 0, for: 1)
        a.isEnabled = false
        let b = move(layer, to: Vec2(0, 100), at: 2, for: 1)
        #expect(state(layer, [a, b], at: 3).position == Vec2(500, 600))
    }
}

@Suite struct ValueTypeTests {
    @Test func positionsTravelStraightOrAlongACurve() {
        let layer = square()
        let straight = move(layer, .to, from: Vec2(0, 0), to: Vec2(100, 0), at: 0, for: 1)
        #expect(state(layer, [straight], at: 0.5).position == Vec2(50, 0))

        var curved = straight
        curved.spec = .move(MoveAction(mode: .to, initial: Vec2(0, 0), end: Vec2(100, 0),
                                       curve: MotionCurve(startHandle: Vec2(0, -100), endHandle: Vec2(0, -100))))
        // Halfway along a symmetric arch: in the middle, lifted by 3/4 of the
        // handles' height.
        #expect(near(state(layer, [curved], at: 0.5).position, Vec2(50, -75)))
        #expect(near(state(layer, [curved], at: 1).position, Vec2(100, 0)))
    }

    @Test func sizesBlendAndTheLayerGrowsAroundItsAnchor() {
        let layer = square()   // anchor at its centre, (50, 50)
        let grow = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                          spec: .resize(ResizeAction(end: Size2(300, 100))))
        #expect(state(layer, [grow], at: 0.5).size == Size2(200, 100))

        let resolved = evaluate(Project(layers: [layer], actions: [grow]), at: 1).layers[0]
        #expect(resolved.size == Size2(300, 100))
        #expect(resolved.anchor == Vec2(150, 50))
        #expect(resolved.position == Vec2(500, 500))
        // The box still centres on the same point.
        let corners = resolved.transform.apply(.zero)
        #expect(corners == Vec2(350, 450))
    }

    @Test func overshootingOpacityIsClampedOnlyWhenDrawn() {
        let layer = square()
        var a = fade(layer, from: 0, to: 1, at: 0, for: 1)
        a.easing = .preset(.overshoot, intensity: 1)
        let peak = stride(from: 0.0, through: 1, by: 0.02).map { state(layer, [a], at: $0).opacity }.max()!
        #expect(peak > 1)
        let drawn = stride(from: 0.0, through: 1, by: 0.02).map {
            evaluate(Project(layers: [layer], actions: [a]), at: $0).layers[0].opacity
        }.max()!
        #expect(drawn == 1)
    }
}

@Suite struct ActionEvaluationTests {
    @Test func worksAtAnyFractionalTime() {
        let layer = square()
        let a = move(layer, to: Vec2(240, 0), at: 1, for: 1)
        // Subframes between 60 fps frames, as motion blur will ask for.
        let xs = [1.5, 1.5 + 1.0 / 240, 1.5 + 2.0 / 240].map { state(layer, [a], at: $0).position.x }
        #expect(xs[0] < xs[1] && xs[1] < xs[2])
        #expect(abs(xs[1] - xs[0] - 1) < 1e-9)
    }

    @Test func designModeIgnoresActions() {
        let layer = square()
        let project = Project(layers: [layer], actions: [move(layer, .to, to: .zero, at: 0, for: 0)])
        #expect(evaluate(project, at: 1).layers[0].position == .zero)
        #expect(evaluateDesign(project).layers[0].position == Vec2(500, 500))
    }

    @Test func actionsOnOneLayerLeaveOthersAlone() {
        let a = square("A"), b = square("B")
        let project = Project(layers: [a, b], actions: [move(a, .to, to: .zero, at: 0, for: 0)])
        let scene = evaluate(project, at: 1)
        #expect(scene.layer(a.id)?.position == .zero)
        #expect(scene.layer(b.id)?.position == Vec2(500, 500))
    }

    @Test func easingShapesTheMotion() {
        let layer = square()
        var a = move(layer, .to, from: .zero, to: Vec2(100, 0), at: 0, for: 1)
        a.easing = .preset(.accelerate, intensity: 1)
        #expect(state(layer, [a], at: 0.25).position.x < 25)
        a.easing = .preset(.slowDown, intensity: 1)
        #expect(state(layer, [a], at: 0.25).position.x > 25)
    }
}
