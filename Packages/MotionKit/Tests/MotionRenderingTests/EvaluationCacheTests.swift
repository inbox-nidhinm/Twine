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
}
