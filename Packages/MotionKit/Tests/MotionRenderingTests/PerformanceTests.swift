import Foundation
import Testing
import QuartzCore
import CoreVideo
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// A heavy scene for measuring: `count` layers of every kind the app draws,
/// each with several actions on different eases, some in groups, some with
/// gradients, strokes, shadows and blurs. Deterministic, so runs compare.
func stressProject(layers count: Int = 160) -> Project {
    var rng = SeededRandom(seed: 7)
    var layers: [Layer] = []
    var actions: [Action] = []
    let eases: [Easing] = [.default, .preset(.overshoot, intensity: 0.6), .preset(.spring, intensity: 0.5),
                           .preset(.slowDown, intensity: 0.5), .linear]

    func shape(_ i: Int) -> Layer {
        let geometry: ShapeGeometry
        switch i % 4 {
        case 0: geometry = .rectangle(cornerRadii: CornerRadii(all: 12))
        case 1: geometry = .ellipse(arc: .full)
        case 2: geometry = .star(points: 5, innerRadius: 0.5, cornerRadius: 4)
        default: geometry = .polygon(sides: 6)
        }
        let color = RGBA(rng.next(), rng.next(), rng.next())
        let paint: Paint = i % 5 == 0
            ? .linearGradient(Gradient(stops: [GradientStop(position: 0, color: color), GradientStop(position: 1, color: .white)]))
            : .solid(color)
        let strokes = i % 3 == 0 ? [Stroke(paint: .solid(.black), width: 4)] : []
        var layer = Layer(name: "Shape \(i)", content: .shape(ShapeContent(geometry: geometry, fills: [Fill(paint: paint)],
                                                                            strokes: strokes)),
                          size: Size2(60 + rng.next() * 140, 60 + rng.next() * 140),
                          position: Vec2(rng.next() * 1920, rng.next() * 1080))
        if i % 8 == 0 { layer.effects.append(Effect(kind: .dropShadow(DropShadow(color: .black, offset: Vec2(0, 8), blur: 24, opacity: 0.3)))) }
        if i % 16 == 5 { layer.effects.append(Effect(kind: .layerBlur(LayerBlur(radius: 8)))) }
        if i % 32 == 9 { layer.effects.append(Effect(kind: .backgroundBlur(BackgroundBlur(radius: 20)))) }
        return layer
    }

    func animate(_ layer: Layer, text: Bool = false) {
        let t = rng.next() * 6
        let ease = eases[Int(rng.next() * Double(eases.count)) % eases.count]
        actions.append(Action(target: layer.id, start: t, duration: 1, easing: ease,
                              spec: .move(MoveAction(mode: .by, end: Vec2(rng.next() * 400 - 200, rng.next() * 400 - 200)))))
        actions.append(Action(target: layer.id, start: t + 0.3, duration: 0.8, easing: ease,
                              spec: .scale(ScaleAction(mode: .to, end: Vec2(1.3, 1.3)))))
        actions.append(Action(target: layer.id, start: t + 0.5, duration: 1.2, easing: .default,
                              spec: .rotate(RotateAction(mode: .by, end: 90))))
        actions.append(Action(target: layer.id, start: t + 1.5, duration: 0.6, easing: .default,
                              spec: .opacity(OpacityAction(initial: 1, end: 0.4))))
        if !text {
            actions.append(Action(target: layer.id, start: t + 1, duration: 1, easing: .default,
                                  spec: .color(ColorAction(end: .solid(RGBA(rng.next(), rng.next(), rng.next()))))))
        }
    }

    var i = 0
    while layers.count < count {
        if i % 16 == 15 {
            // A group of four.
            let children = (0..<4).map { shape(i * 10 + $0) }
            for c in children { animate(c) }
            var group = Layer(name: "Group \(i)", content: .group(GroupContent(children: children)),
                              size: Size2(1920, 1080), position: .zero)
            group.transform.anchor = .zero
            animate(group)
            layers.append(group)
        } else if i % 8 == 7 {
            let text = Layer(name: "Text \(i)", content: .text(TextContent(text: "Title \(i)", fontSize: 40)),
                             size: Size2(200, 50), position: Vec2(rng.next() * 1920, rng.next() * 1080))
            animate(text, text: true)
            layers.append(text)
        } else {
            let s = shape(i)
            animate(s)
            layers.append(s)
        }
        i += 1
    }
    return Project(composition: Composition(width: 1920, height: 1080, frameRate: .fps60, duration: 10),
                   layers: layers, actions: actions)
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    /// 0 to 1.
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// Timings for the heavy scene, run only when asked for with
/// `TWINE_BENCH=1 swift test --filter PerformanceTests`. Prints
/// milliseconds per frame for each stage; `TWINE_BENCH_OUT` also writes
/// the scene's document, to open in the app.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TWINE_BENCH"] != nil))
struct PerformanceTests {
    private func ms(_ seconds: Double, frames: Int) -> String { String(format: "%.3f ms", seconds / Double(frames) * 1000) }

    @Test func stages() throws {
        let project = stressProject()
        let all = project.allLayers.count
        print("BENCH scene: \(all) layers, \(project.actions.count) actions")
        if let out = ProcessInfo.processInfo.environment["TWINE_BENCH_OUT"] {
            try ProjectFormat.encode(project).write(to: URL(fileURLWithPath: out))
        }
        let frames = 240
        let times = (0..<frames).map { Double($0) / 60 * 2.5 }

        var start = CACurrentMediaTime()
        for _ in 0..<50 { _ = ActionTracks(project.actions) }
        print("BENCH ActionTracks build: \(ms(CACurrentMediaTime() - start, frames: 50))")

        start = CACurrentMediaTime()
        var scenes: [ResolvedScene] = []
        for t in times { scenes.append(evaluate(project, at: t)) }
        print("BENCH evaluate: \(ms(CACurrentMediaTime() - start, frames: frames))")

        let tracks = ActionTracks(project.actions)
        start = CACurrentMediaTime()
        for t in times { for layer in project.allLayers { _ = tracks.state(of: layer, at: t) } }
        print("BENCH states only: \(ms(CACurrentMediaTime() - start, frames: frames))")

        start = CACurrentMediaTime()
        _ = evaluateDesign(project)
        print("BENCH evaluateDesign once: \(ms(CACurrentMediaTime() - start, frames: 1))")

        let renderer = CoreAnimationRenderer()
        renderer.render(scenes[0])
        start = CACurrentMediaTime()
        for scene in scenes { renderer.render(scene) }
        print("BENCH layer tree update: \(ms(CACurrentMediaTime() - start, frames: frames))")

        let offscreen = try #require(OffscreenRenderer(pixelWidth: 1920, pixelHeight: 1080))
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1920, 1080, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary, &buffer)
        let pixels = try #require(buffer)
        offscreen.render(scenes[0], into: pixels)
        start = CACurrentMediaTime()
        for scene in scenes.prefix(60) { offscreen.render(scene, into: pixels) }
        print("BENCH offscreen 1080p frame: \(ms(CACurrentMediaTime() - start, frames: 60))")
    }
}
