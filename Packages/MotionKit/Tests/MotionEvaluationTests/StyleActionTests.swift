import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// A 100 by 100 rectangle with a white fill and a 2 px black stroke.
private func card(effects: [Effect] = [], fills: [Fill] = [Fill(paint: .solid(.white))]) -> Layer {
    var layer = Layer(name: "Card", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: fills,
                                                                 strokes: [Stroke(paint: .solid(.black), width: 2)])),
                      size: Size2(100, 100), position: Vec2(500, 500))
    layer.effects = effects
    return layer
}

private func action(_ layer: Layer, _ spec: ActionSpec, at start: Double = 1, for duration: Double = 2) -> Action {
    Action(target: layer.id, start: start, duration: duration, easing: .linear, spec: spec)
}

private func resolved(_ layer: Layer, _ actions: [Action], at time: Double) -> ResolvedLayer {
    evaluate(Project(layers: [layer], actions: actions), at: time).layers[0]
}

private func shape(_ layer: ResolvedLayer) -> ResolvedShape? {
    if case .shape(let s) = layer.content { return s }
    return nil
}

private let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1)

private func gradient(_ colors: [RGBA], radial: Bool = false) -> Paint {
    let stops = colors.enumerated().map { i, c in
        GradientStop(position: colors.count > 1 ? Double(i) / Double(colors.count - 1) : 0, color: c)
    }
    let g = Gradient(stops: stops)
    return radial ? .radialGradient(g) : .linearGradient(g)
}

@Suite struct ColourActionTests {
    @Test func aColourBlendsTheFirstFill() {
        let layer = card()
        let a = action(layer, .color(ColorAction(end: .solid(red))))
        #expect(shape(resolved(layer, [a], at: 0))?.fills == [.solid(.white)])
        #expect(shape(resolved(layer, [a], at: 3))?.fills == [.solid(red)])
        guard case .solid(let mid) = shape(resolved(layer, [a], at: 2))?.fills.first else {
            Issue.record("the middle should still be a colour")
            return
        }
        // Half way from white to red: still fully red in its red channel,
        // and part way in the others.
        #expect(mid.r > 0.99 && mid.g > 0.2 && mid.g < 0.9)
    }

    @Test func aLayerWithNoFillIgnoresIt() {
        let layer = card(fills: [])
        let a = action(layer, .color(ColorAction(end: .solid(red))))
        #expect(shape(resolved(layer, [a], at: 3))?.fills == [])
    }

    @Test func gradientsWithDifferentStopCountsBlendSmoothly() {
        let two = gradient([red, blue]), three = gradient([red, .white, blue])
        // The ends are exactly what was asked for, stop counts and all.
        #expect(Paint.interpolate(two, three, 0) == two)
        #expect(Paint.interpolate(two, three, 1) == three)
        // In between both are sampled at every stop position either has.
        guard case .linearGradient(let mid) = Paint.interpolate(two, three, 0.5) else {
            Issue.record("the middle should be a linear gradient")
            return
        }
        #expect(mid.stops.map(\.position) == [0, 0.5, 1])
        // At 0.5 the two-stop gradient is purple and the three-stop one is
        // white, so the blend of the middle stop is lighter than purple.
        #expect(mid.stops[1].color.g > 0.2)
        // Very close to the end, the middle is very close to white.
        guard case .linearGradient(let late) = Paint.interpolate(two, three, 0.999) else { return }
        #expect(late.stops[1].color.g > 0.99)
    }

    @Test func aColourBecomesAGradientThroughItsShape() {
        let target = gradient([red, blue])
        guard case .linearGradient(let g) = Paint.interpolate(.solid(.white), target, 0.25) else {
            Issue.record("a colour heading for a gradient should already be one")
            return
        }
        #expect(g.stops.count == 2)
        #expect(g.stops[0].color.r > 0.99 && g.stops[1].color.r > 0.5)
    }

    @Test func linearAndRadialSwapHalfWay() {
        let linear = gradient([red, blue]), radial = gradient([red, blue], radial: true)
        #expect(!Paint.interpolate(linear, radial, 0.4).isRadialGradient)
        #expect(Paint.interpolate(linear, radial, 0.6).isRadialGradient)
    }

    @Test func gradientGeometryTravels() {
        let a = Paint.linearGradient(Gradient(stops: [GradientStop(position: 0, color: red)], start: Vec2(0, 0), end: Vec2(1, 0)))
        let b = Paint.linearGradient(Gradient(stops: [GradientStop(position: 0, color: red)], start: Vec2(0, 1), end: Vec2(1, 1)))
        guard case .linearGradient(let mid) = Paint.interpolate(a, b, 0.5) else { return }
        #expect(mid.start == Vec2(0, 0.5) && mid.end == Vec2(1, 0.5))
    }
}

@Suite struct StrokeAndTrimActionTests {
    @Test func strokeWidthAndPaintTravelTogether() {
        let layer = card()
        let a = action(layer, .stroke(StrokeAction(end: StrokeLook(width: 10, paint: .solid(red)))))
        let mid = shape(resolved(layer, [a], at: 2))?.strokes.first
        #expect(mid?.width == 6)
        #expect(shape(resolved(layer, [a], at: 3))?.strokes.first?.paint == .solid(red))
    }

    @Test func trimDrawsOnAndHoldsItsStartBeforehand() {
        let layer = card()
        let a = action(layer, .trim(TrimAction(initial: TrimRange(start: 0, end: 0), end: .whole)))
        // The entrance rule: nothing drawn before it starts.
        #expect(shape(resolved(layer, [a], at: 0))?.strokes.first?.trimEnd == 0)
        #expect(shape(resolved(layer, [a], at: 2))?.strokes.first?.trimEnd == 0.5)
        #expect(shape(resolved(layer, [a], at: 3))?.strokes.first?.trimEnd == 1)
    }

    @Test func cornersRoundOver() {
        let layer = card()
        let a = action(layer, .cornerRadius(CornerRadiusAction(end: CornerRadii(all: 20))))
        let design = LayerState(design: layer)
        #expect(design.cornerRadii == .zero)
        #expect(ActionTracks([a]).state(of: layer, at: 2).cornerRadii == CornerRadii(all: 10))
        // The drawn path follows: a rounded corner leaves the very corner empty.
        let path = shape(resolved(layer, [a], at: 3))?.path
        #expect(path != shape(resolved(layer, [], at: 3))?.path)
    }
}

@Suite struct ShadowAndBlurActionTests {
    @Test func aShadowAnimatesInFromNothingInItsOwnColour() {
        let layer = card()
        let end = DropShadow(color: red, offset: Vec2(0, 20), blur: 40, opacity: 0.5)
        let a = action(layer, .shadow(ShadowAction(end: end)))
        #expect(resolved(layer, [a], at: 0).shadow == nil)
        let mid = resolved(layer, [a], at: 2).shadow
        #expect(mid?.color == red)
        #expect(mid?.opacity == 0.25 && mid?.offset == Vec2(0, 10) && mid?.blur == 20)
        #expect(resolved(layer, [a], at: 3).shadow?.opacity == 0.5)
    }

    @Test func aDesignedShadowIsWhereItStarts() {
        let layer = card(effects: [Effect(kind: .dropShadow(DropShadow(color: .black, offset: Vec2(0, 4), blur: 8, opacity: 1)))])
        let a = action(layer, .shadow(ShadowAction(end: DropShadow(color: .black, offset: Vec2(0, 12), blur: 8, opacity: 1, spread: 4))))
        let mid = resolved(layer, [a], at: 2).shadow
        #expect(mid?.offset == Vec2(0, 8) && mid?.spread == 2)
    }

    @Test func aSwitchedOffShadowCountsAsNone() {
        let layer = card(effects: [Effect(isEnabled: false, kind: .dropShadow(DropShadow(opacity: 1)))])
        #expect(LayerState(design: layer).shadow == .noShadow)
        #expect(resolved(layer, [], at: 0).shadow == nil)
    }

    @Test func layerBlurStartsFromNoneAndOthersAddOn() {
        let layer = card(effects: [Effect(kind: .layerBlur(LayerBlur(radius: 4))), Effect(kind: .layerBlur(LayerBlur(radius: 2)))])
        #expect(resolved(layer, [], at: 0).blur == 6)
        let a = action(layer, .layerBlur(LayerBlurAction(end: 12)))
        // The action drives the first; the second adds on.
        #expect(resolved(layer, [a], at: 2).blur == 8 + 2)
        let bare = card()
        let b = action(bare, .layerBlur(LayerBlurAction(end: 10)))
        #expect(resolved(bare, [b], at: 2).blur == 5)
    }

    @Test func backgroundBlurIsForShapesOnly() {
        let layer = card()
        let a = action(layer, .backgroundBlur(BackgroundBlurAction(end: BackgroundBlur(radius: 20, blend: 1))))
        #expect(resolved(layer, [a], at: 0).backgroundBlur == nil)
        #expect(resolved(layer, [a], at: 2).backgroundBlur == BackgroundBlur(radius: 10, blend: 1))

        var group = Layer(name: "G", content: .group(GroupContent()), size: Size2(10, 10), position: .zero)
        group.effects = [Effect(kind: .backgroundBlur(BackgroundBlur()))]
        #expect(evaluate(Project(layers: [group]), at: 0).layers[0].backgroundBlur == nil)
    }

    @Test func overshootNeverMakesAColourOrBlurInvalid() {
        let layer = card()
        var a = action(layer, .layerBlur(LayerBlurAction(initial: 4, end: 0)))
        a.easing = .preset(.overshoot, intensity: 1)
        let values = stride(from: 1.0, through: 3.0, by: 0.05).map { resolved(layer, [a], at: $0).blur }
        #expect(values.allSatisfy { $0 >= 0 })
        var c = action(layer, .color(ColorAction(end: .solid(red))))
        c.easing = .preset(.overshoot, intensity: 1)
        for t in stride(from: 1.0, through: 3.0, by: 0.05) {
            guard case .solid(let color) = shape(resolved(layer, [c], at: t))?.fills.first else { continue }
            #expect([color.r, color.g, color.b, color.a].allSatisfy { $0 >= 0 && $0 <= 1 })
        }
    }
}

@Suite struct PathActionTests {
    private let triangle = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(100, 0)),
                                                                  PathPoint(Vec2(0, 100))], isClosed: true)])

    private func pen() -> Layer {
        Layer(name: "Pen", content: .shape(ShapeContent(geometry: .path(triangle), fills: [Fill(paint: .solid(.white))])),
              size: Size2(100, 100), position: Vec2(500, 500))
    }

    @Test func aPathMorphsPointByPoint() {
        let layer = pen()
        var end = triangle
        end.subpaths[0].points[1].position = Vec2(200, 0)
        let a = action(layer, .path(PathAction(end: end)))
        #expect(shape(resolved(layer, [a], at: 0))?.path == triangle)
        #expect(shape(resolved(layer, [a], at: 2))?.path.subpaths[0].points[1].position == Vec2(150, 0))
        #expect(shape(resolved(layer, [a], at: 5))?.path == end)
    }

    @Test func aPathWithOtherPointsHoldsUntilTheEnd() {
        let layer = pen()
        let square = BezierPath(subpaths: [Subpath(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)].map { PathPoint($0) },
                                                   isClosed: true)])
        let a = action(layer, .path(PathAction(end: square)))
        #expect(shape(resolved(layer, [a], at: 2))?.path == triangle)
        #expect(shape(resolved(layer, [a], at: 3))?.path == square)
    }

    @Test func resizeStretchesAPenPath() {
        let layer = pen()
        let a = action(layer, .resize(ResizeAction(end: Size2(200, 50))))
        let p = shape(resolved(layer, [a], at: 5))?.path
        #expect(p?.subpaths[0].points.map(\.position) == [Vec2(0, 0), Vec2(200, 0), Vec2(0, 50)])
    }
}

@Suite struct VolumeActionTests {
    private let asset = MediaAsset(kind: .audio, fileName: "a.wav", originalName: "a.wav", contentHash: "a", duration: 10)

    private func sound(volume: Double = 1) -> Layer {
        Layer(name: "Sound", content: .audio(AudioContent(mediaID: asset.id, volume: volume)), size: Size2(0, 0), position: .zero)
    }

    private func clip(_ layer: Layer, _ actions: [Action]) -> AudioClip? {
        let play = Action(target: layer.id, start: 0, duration: 10, spec: .play(PlayAction()))
        return audioClips(Project(composition: Composition(width: 10, height: 10, frameRate: .fps30, duration: 10),
                                  layers: [layer], actions: [play] + actions, media: [asset])).first
    }

    @Test func aFadeFollowsItsEasing() throws {
        let layer = sound()
        let fade = Action(target: layer.id, start: 2, duration: 2, easing: .preset(.slowDown, intensity: 0.6),
                          spec: .volume(VolumeAction(end: 0)))
        let c = try #require(clip(layer, [fade]))
        #expect(c.volume(at: 1) == 1)
        #expect(c.volume(at: 5) == 0)
        // Slowing down, it has dropped well past half way by the middle.
        let eased = 1 - Easing.preset(.slowDown, intensity: 0.6).progress(0.5)
        #expect(abs(c.volume(at: 3) - eased) < 0.02)
        #expect(c.volume(at: 3) < 0.4)
    }

    @Test func aSilentSoundFadingInIsStillHeard() throws {
        let layer = sound(volume: 0)
        let fadeIn = Action(target: layer.id, start: 1, duration: 1, easing: .linear, spec: .volume(VolumeAction(end: 1)))
        let c = try #require(clip(layer, [fadeIn]))
        #expect(c.volume(at: 0.5) == 0)
        #expect(abs(c.volume(at: 1.5) - 0.5) < 0.02)
        // With no fade it makes no sound at all, so no clip.
        #expect(clip(layer, []) == nil)
    }

    @Test func anInstantChangeIsAStep() throws {
        let layer = sound()
        let cut = Action(target: layer.id, start: 3, duration: 0, spec: .volume(VolumeAction(end: 0.2)))
        let c = try #require(clip(layer, [cut]))
        #expect(abs(c.volume(at: 2.99) - 1) < 1e-6)
        #expect(abs(c.volume(at: 3.01) - 0.2) < 1e-6)
    }
}

@Suite struct ShadowListTests {
    private func square(_ effects: [EffectKind]) -> Layer {
        var l = Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .color(.white))])),
                      size: Size2(10, 10), position: .zero)
        l.effects = effects.map { Effect(kind: $0) }
        return l
    }

    @Test func everyShadowResolvesAndTheActionDrivesTheFirst() {
        let a = DropShadow(color: .black, offset: Vec2(1, 1), blur: 2, opacity: 0.5)
        let b = DropShadow(color: RGBA(1, 0, 0), offset: Vec2(0, 8), blur: 16, opacity: 0.2)
        let layer = square([.dropShadow(a), .innerShadow(a), .dropShadow(b)])
        let action = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                            spec: .shadow(ShadowAction(end: DropShadow(color: .black, offset: Vec2(9, 9), blur: 2, opacity: 0.5))))
        let resolved = evaluate(Project(layers: [layer], actions: [action]), at: 1).layers[0]
        #expect(resolved.shadows.map(\.offset) == [Vec2(9, 9), Vec2(0, 8)])
        #expect(resolved.innerShadows.map(\.offset) == [Vec2(1, 1)])
    }

    @Test func textHasNoInnerShadows() {
        var text = Layer(name: "T", content: .text(TextContent(text: "Hi")), size: Size2(10, 10), position: .zero)
        text.effects = [Effect(kind: .innerShadow(DropShadow()))]
        #expect(evaluateDesign(Project(layers: [text])).layers[0].innerShadows.isEmpty)
    }

    @Test func blendModesReachTheScene() {
        var layer = square([])
        layer.blendMode = .screen
        #expect(evaluateDesign(Project(layers: [layer])).layers[0].blendMode == .screen)
    }
}
