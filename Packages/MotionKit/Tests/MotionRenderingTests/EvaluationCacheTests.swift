import Foundation
import Testing
import MotionModel
import MotionEvaluation

/// A cache only saves work: every scene comes out as it would without one,
/// across moments, modes and edits.
struct EvaluationCacheTests {
    @Test func aCachedSceneIsTheSceneWorkedOutAfresh() {
        var project = largeProject(layers: 300, frames: 6, actions: 60)
        let cache = EvaluationCache()
        for t in stride(from: 0.0, through: 4, by: 0.37) {
            #expect(evaluate(project, at: t, cache: cache) == evaluate(project, at: t))
        }
        #expect(evaluateDesign(project, cache: cache) == evaluateDesign(project))

        // An edit to a still layer deep in a frame, then one to a frame.
        guard case .group(var group) = project.layers[2].content else { Issue.record("no frame"); return }
        group.children[3].transform.position.x += 40
        group.children[4].opacity = 0.2
        project.layers[2].content = .group(group)
        #expect(evaluate(project, at: 1, cache: cache) == evaluate(project, at: 1))
        project.layers[1].transform.rotation = 30
        project.layers[1].isVisible = false
        #expect(evaluate(project, at: 1, cache: cache) == evaluate(project, at: 1))
        #expect(evaluateDesign(project, cache: cache) == evaluateDesign(project))

        // Actions changing, and layers going.
        project.actions.removeFirst(10)
        project.layers.removeLast()
        #expect(evaluate(project, at: 2, cache: cache) == evaluate(project, at: 2))
    }

    /// A template with no bar is a still group, but videos in its slots play
    /// round with the scene: the cache must not hand back an earlier moment.
    @Test func videosInAStillTemplateKeepPlaying() {
        let video = MediaAsset(id: UUID(), kind: .video, fileName: "v.mov", originalName: "v.mov", contentHash: "v",
                               pixelWidth: 640, pixelHeight: 360, duration: 4, hasAudio: false)
        let slot = Layer(name: "Slot", content: .video(VideoContent(mediaID: video.id)), size: Size2(100, 100), position: .zero)
        var frame = Layer(name: "T", content: .group(GroupContent(frame: FrameStyle(), template: TemplateSetup(kind: .ringStream))),
                          size: Size2(1280, 720), position: Vec2(640, 360))
        frame.templateSlotLayers = Array(repeating: slot, count: 4).map { $0.duplicated() }
        let project = Project(composition: Composition(width: 1280, height: 720), layers: [frame], media: [video])
        func times(_ scene: ResolvedScene) -> Set<Double> {
            Set(scene.layers.compactMap { if case .video(_, let t, _) = $0.content { t } else { nil } })
        }
        let cache = EvaluationCache()
        for t in [0.0, 1.0, 2.5, 1.0] {
            let cached = evaluate(project, at: t, cache: cache)
            #expect(cached == evaluate(project, at: t))
            #expect(times(cached) == [t])
        }
    }
}
