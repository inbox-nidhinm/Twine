import Foundation
import Testing
import QuartzCore
import MotionModel
@testable import MotionEditing

/// Timings for editing a very large project, run only when asked for with
/// `TWINE_BENCH=1 swift test -c release --filter LargeProjectTimings`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TWINE_BENCH"] != nil))
struct LargeProjectTimings {
    /// 50 frames of 100 layers each, one in eight a text.
    static func project() -> Project {
        var frames: [Layer] = []
        for f in 0..<50 {
            var children: [Layer] = []
            for i in 0..<100 {
                if i % 8 == 7 {
                    children.append(Layer(name: "Text \(i)", content: .text(TextContent(text: "Title \(f) \(i)", fontSize: 32)),
                                          size: Size2(200, 40), position: Vec2(Double(i * 17 % 1900), Double(i * 31 % 1000))))
                } else {
                    children.append(Layer(name: "Shape \(i)",
                                          content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: CornerRadii(all: 8)),
                                                                       fills: [Fill(paint: .solid(RGBA(0.2, 0.4, 0.8)))])),
                                          size: Size2(80, 60), position: Vec2(Double(i * 17 % 1900), Double(i * 31 % 1000))))
                }
            }
            var frame = Layer(name: "Frame \(f)", content: .group(GroupContent(children: children, clipsContent: true,
                                                                                frame: FrameStyle(fills: [Fill(paint: .solid(.white))]))),
                              size: Size2(1920, 1080), position: .zero)
            frame.transform.anchor = .zero
            frames.append(frame)
        }
        var project = Project(composition: Composition(width: 1920, height: 1080, frameRate: .fps60, duration: 10), layers: frames)
        // A fitted start, as every project is once edited.
        try? EditorCommand.batch([], name: "").apply(to: &project)
        return project
    }

    private func ms(_ seconds: Double, _ n: Int) -> String { String(format: "%.3f ms", seconds / Double(n) * 1000) }

    @MainActor @Test func editing() throws {
        let project = Self.project()
        print("BENCH editing: \(project.allLayers.count) layers")
        guard case .group(let group) = project.layers[20].content else { return }
        let target = group.children[3]

        var p = project
        var start = CACurrentMediaTime()
        for k in 0..<50 {
            var moved = target
            moved.transform.position.x += Double(k)
            try EditorCommand.updateLayers([moved]).apply(to: &p)
        }
        print("BENCH editing apply, one layer moved: \(ms(CACurrentMediaTime() - start, 50))")

        start = CACurrentMediaTime()
        var seen = 0
        for _ in 0..<50 { p.forEachLayer { if $0.isText { seen += 1 } } }
        print("BENCH editing forEachLayer: \(ms(CACurrentMediaTime() - start, 50)) \(seen)")
        start = CACurrentMediaTime()
        for _ in 0..<50 { p.forEachLayer { _ in seen += 1 } }
        print("BENCH editing forEachLayer, nothing: \(ms(CACurrentMediaTime() - start, 50)) \(seen)")
        start = CACurrentMediaTime()
        var ids = Set<UUID>()
        for _ in 0..<50 { ids.removeAll(keepingCapacity: true); p.forEachLayer { ids.insert($0.id) } }
        print("BENCH editing forEachLayer, ids: \(ms(CACurrentMediaTime() - start, 50)) \(ids.count)")

        start = CACurrentMediaTime()
        for _ in 0..<50 { _ = p.allLayers }
        print("BENCH editing allLayers: \(ms(CACurrentMediaTime() - start, 50))")

        start = CACurrentMediaTime()
        for _ in 0..<50 { _ = p.location(of: target.id) }
        print("BENCH editing location: \(ms(CACurrentMediaTime() - start, 50))")

        start = CACurrentMediaTime()
        for _ in 0..<50 { _ = p.ancestors(of: target.id) }
        print("BENCH editing ancestors: \(ms(CACurrentMediaTime() - start, 50))")

        start = CACurrentMediaTime()
        for _ in 0..<50 { _ = p.layer(withID: target.id) }
        print("BENCH editing layer(withID:): \(ms(CACurrentMediaTime() - start, 50))")

        start = CACurrentMediaTime()
        for _ in 0..<20 { _ = p.maskCandidates(for: target.id) }
        print("BENCH editing maskCandidates: \(ms(CACurrentMediaTime() - start, 20))")

        start = CACurrentMediaTime()
        for _ in 0..<20 { _ = p.documentColors(limit: 16) }
        print("BENCH editing documentColors: \(ms(CACurrentMediaTime() - start, 20))")

        start = CACurrentMediaTime()
        for _ in 0..<20 { _ = ProjectStore.cost(of: project, against: p) }
        print("BENCH editing undo cost: \(ms(CACurrentMediaTime() - start, 20))")

        start = CACurrentMediaTime()
        for _ in 0..<20 { _ = project == p }
        print("BENCH editing compare projects: \(ms(CACurrentMediaTime() - start, 20))")
    }
}
