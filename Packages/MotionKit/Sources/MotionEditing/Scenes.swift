import Foundation
import MotionModel

/// Gathering actions into timeline scenes, and moving a scene's actions as
/// one: the maths behind Group into Scene and a scene's span bar.
public enum Scenes {
    /// The scenes with `ids` gathered into a new one, named the first free
    /// `Scene N`, taken out of any scene they were in (which goes if left
    /// empty). Nil when none of `ids` is an action of the project.
    public static func grouping(_ ids: Set<UUID>, in project: Project) -> (scenes: [TimelineScene], made: TimelineScene)? {
        let members = ActionEditing.timeline(in: project).map(\.id).filter(ids.contains)
        guard !members.isEmpty else { return nil }
        var scenes = removing(Set(members), from: project.scenes)
        let taken = Set(project.scenes.map(\.name))
        var n = project.scenes.count + 1
        while taken.contains("Scene \(n)") { n += 1 }
        let made = TimelineScene(name: "Scene \(n)", actionIDs: members)
        scenes.append(made)
        return (scenes, made)
    }

    /// The scenes without the ones holding any of `ids`: those actions go
    /// back to being rows of their own.
    public static func ungrouping(_ ids: Set<UUID>, in project: Project) -> [TimelineScene] {
        project.scenes.filter { $0.actionIDs.allSatisfy { !ids.contains($0) } }
    }

    /// `ids` taken out of every scene; a scene left empty goes.
    public static func removing(_ ids: Set<UUID>, from scenes: [TimelineScene]) -> [TimelineScene] {
        scenes.compactMap { scene in
            var kept = scene
            kept.actionIDs.removeAll(where: ids.contains)
            return kept.actionIDs.isEmpty ? nil : kept
        }
    }

    /// From the earliest start to the latest end of `actions`.
    public static func span(of actions: [Action]) -> ClosedRange<Double>? {
        guard let start = actions.map(\.start).min(), let end = actions.map(\.end).max() else { return nil }
        return start...max(end, start)
    }

    /// `actions` stretched or squeezed from `span` to `new`, each start and
    /// end keeping its share of the way along it, so their spacing and
    /// overlaps scale together. Instant actions stay instant; times land on
    /// frames. A span of no length only moves.
    public static func stretched(_ actions: [Action], from span: ClosedRange<Double>, to new: ClosedRange<Double>,
                                 rate: FrameRate) -> [Action] {
        let length = span.upperBound - span.lowerBound
        let scale = length > 1e-9 ? (new.upperBound - new.lowerBound) / length : 1
        func place(_ t: Double) -> Double { new.lowerBound + (t - span.lowerBound) * scale }
        return actions.map { action in
            var a = action
            let start = rate.snapped(max(place(action.start), 0))
            a.start = start
            if !action.isInstant {
                a.duration = max(rate.snapped(place(action.end)) - start, rate.frameDuration)
            }
            return a
        }
    }
}
