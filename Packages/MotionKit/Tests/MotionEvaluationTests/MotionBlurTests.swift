import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

private func square(at position: Vec2 = .zero) -> Layer {
    var layer = Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                              fills: [Fill(paint: .color(.white))])),
                      size: Size2(10, 10), position: position)
    layer.transform.anchor = .zero
    return layer
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

/// A 10 fps composition, so a frame lasts a tenth of a second.
private func project(_ layers: [Layer], _ actions: [Action]) -> Project {
    Project(composition: Composition(width: 400, height: 400, frameRate: FrameRate(frames: 10)), layers: layers, actions: actions)
}

@Suite struct MotionBlurTests {
    /// A Move of 100 px a second, from x 0 to 100.
    private func move(_ layer: Layer, blur: Double?) -> Action {
        var action = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                            spec: .move(MoveAction(mode: .to, end: Vec2(100, 0))))
        action.motionBlur = blur
        return action
    }

    @Test func aBlurredMoveSpreadsAcrossItsShutter() throws {
        let layer = square()
        let scene = evaluate(project([layer], [move(layer, blur: 0.5)]), at: 0.5)
        let resolved = try #require(scene.layer(layer.id))
        guard case .spread(let start, let step, let count) = resolved.motion else { Issue.record("no spread"); return }
        // Half a frame open, centred on the moment: 0.475 s to 0.525 s, so
        // the first copy is at x 47.5 and each next one a seventh of 5 px on.
        #expect(count == 8)
        #expect(near(start.tx, 47.5) && near(start.ty, 0))
        #expect(near(step.tx, 5.0 / 7) && near(step.ty, 0) && near(step.a, 1) && near(step.d, 1))
        // An export works out each of its sixteen moments exactly, from
        // 0.475 s to 0.525 s.
        guard case .exact(let moments) = evaluate(project([layer], [move(layer, blur: 0.5)]), at: 0.5, motionBlur: .export)
            .layer(layer.id)?.motion else { Issue.record("not exact"); return }
        #expect(moments.count == 16 && near(moments[0].tx, 47.5) && near(moments[15].tx, 52.5) && near(moments[5].tx, 49.1666666667))
        // The layer itself is still where it is at the moment.
        #expect(near(resolved.position.x, 50))
    }

    @Test func onlyWhatMovesWhileItPlaysBlurs() throws {
        let layer = square()
        // Without it, nothing spreads.
        #expect(evaluate(project([layer], [move(layer, blur: nil)]), at: 0.5).layer(layer.id)?.motion == MotionSpread.none)
        // Long before and after, nothing moves, so nothing spreads.
        let blurred = project([layer], [move(layer, blur: 0.5)])
        #expect(evaluate(blurred, at: 3).layer(layer.id)?.motion == MotionSpread.none)
        // A fade has nothing to smear.
        var fade = Action(target: layer.id, start: 0, duration: 1, spec: .opacity(OpacityAction(initial: 0, end: 1)))
        fade.motionBlur = 0.5
        #expect(evaluate(project([layer], [fade]), at: 0.5).layer(layer.id)?.motion == MotionSpread.none)
        // Design mode never blurs.
        #expect(evaluateDesign(blurred).layer(layer.id)?.motion == MotionSpread.none)
    }

    @Test func motionThatIsNotSteadyIsDrawnSharp() throws {
        let layer = square()
        // A second Move with a From of its own jumps there when it starts, at
        // 2 s: across that shutter the layer is in two places, and one step
        // repeated would throw copies far past both.
        var jump = Action(target: layer.id, start: 2, duration: 1, easing: .linear,
                          spec: .move(MoveAction(mode: .to, initial: Vec2(300, 300), end: Vec2(300, 0))))
        jump.motionBlur = 1
        let blurred = project([layer], [move(layer, blur: 1), jump])
        #expect(evaluate(blurred, at: 2).layer(layer.id)?.motion == MotionSpread.none)
        // Either side of it, where it glides, it blurs.
        #expect(evaluate(blurred, at: 2.5).layer(layer.id)?.motion != MotionSpread.none)
        // A tilt that starts edge-on turns fastest there, far from steady:
        // no copy may land far from where the layer really goes.
        var tilt = Action(target: layer.id, start: 0, duration: 1, easing: .preset(.slowDown, intensity: 0.5),
                          spec: .tilt(TiltAction(mode: .by, initial: Tilt(x: 90, y: 90, depth: 1200), end: Tilt(x: -90, y: -90, depth: 1200))))
        tilt.motionBlur = 1
        for frame in 0..<10 {
            let t = Double(frame) / 10
            guard case .spread(let start, let step, let count) = evaluate(project([layer], [tilt]), at: t).layer(layer.id)?.motion
            else { continue }
            var reached = start
            for _ in 1..<count { reached = step.then(reached) }
            let corner = try #require(reached.apply(Vec2(10, 10)))
            #expect(abs(corner.x) < 60 && abs(corner.y) < 60, "copies thrown to \(corner) at \(t)")
        }
    }

    @Test func aTurnByAnotherActionStaysSharp() throws {
        let layer = square()
        let turn = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                          spec: .rotate(RotateAction(mode: .to, end: 90)))
        let scene = evaluate(project([layer], [move(layer, blur: 0.5), turn]), at: 0.5)
        guard case .spread(let start, let step, _) = scene.layer(layer.id)?.motion else { Issue.record("no spread"); return }
        // The first copy is turned as the layer is at 0.5 s (45°), not at
        // 0.475 s, and the steps only move it.
        #expect(near(start.a, cos(.pi / 4)) && near(start.b, sin(.pi / 4)))
        #expect(near(step.a, 1) && near(step.b, 0) && near(step.c, 0) && near(step.d, 1))
    }

    @Test func aTextPresetBlursEachLetterByItsOwnMotion() throws {
        let text = Layer(name: "T", content: .text(TextContent(text: "abc")), size: Size2(100, 40), position: .zero)
        var settings = PresetRecipe.defaults(.slideIn)
        settings.unit = .letters
        var action = Action(target: text.id, start: 0, duration: 1, easing: .linear, spec: .preset(settings))
        action.motionBlur = 1
        guard case .text(let drawn) = evaluate(project([text], [action]), at: 0.2).layer(text.id)?.content
        else { Issue.record("no text"); return }
        #expect(drawn.units.count == 3)
        // The first letter is sliding, so it spreads.
        #expect(drawn.units.first?.motion != MotionSpread.none)
    }

    @Test func motionBlurIsLeftOutOfFilesWhenOff() throws {
        let layer = square()
        let off = try String(decoding: JSONEncoder().encode(move(layer, blur: nil)), as: UTF8.self)
        #expect(!off.contains("motionBlur"))
        let on = move(layer, blur: 0.75)
        #expect(try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(on)).motionBlur == 0.75)
    }
}
