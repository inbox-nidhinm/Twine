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

    /// `scenes` with each copy in `pairs` added to its original's scene, so
    /// duplicating or pasting keeps a scene's actions together. Scenes
    /// without an original among them are unchanged.
    public static func joining(_ pairs: [(original: UUID, copy: UUID)], in scenes: [TimelineScene]) -> [TimelineScene] {
        guard !scenes.isEmpty, !pairs.isEmpty else { return scenes }
        var copies: [UUID: [UUID]] = [:]
        for pair in pairs { copies[pair.original, default: []].append(pair.copy) }
        return scenes.map { scene in
            var joined = scene
            for id in scene.actionIDs { joined.actionIDs += copies[id] ?? [] }
            return joined
        }
    }

    /// The scenes every one of whose actions is among `ids`: copied whole.
    public static func whole(_ ids: Set<UUID>, in scenes: [TimelineScene]) -> [TimelineScene] {
        scenes.filter { !$0.actionIDs.isEmpty && $0.actionIDs.allSatisfy(ids.contains) }
    }

    /// `scenes` after copying actions (the user's choice, 1 October 2026):
    /// the copies of each scene in `whole`, one copied entire, make a scene
    /// of their own named after it ("Scene 1 copy"), one for each `group`
    /// (the layer a paste went onto, or nil for all of them), so a scene
    /// pasted onto two layers makes two; copies of only part of a scene
    /// join it, as `joining` does. `whole` may come from another project.
    public static func copying(_ pairs: [(original: UUID, copy: UUID, group: UUID?)], whole: [TimelineScene],
                               in scenes: [TimelineScene]) -> [TimelineScene] {
        var result = scenes
        var taken = Set(scenes.map(\.name))
        var inWhole = Set<UUID>()
        for scene in whole {
            let members = Set(scene.actionIDs)
            inWhole.formUnion(members)
            let rank = Dictionary(scene.actionIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            let copies = pairs.filter { members.contains($0.original) }
            // One scene per group, in the order the groups first come.
            var groups: [UUID?] = []
            for pair in copies where !groups.contains(pair.group) { groups.append(pair.group) }
            for group in groups {
                let ids = copies.filter { $0.group == group }
                    .sorted { rank[$0.original, default: 0] < rank[$1.original, default: 0] }
                    .map(\.copy)
                let base = copyBase(of: scene.name)
                var name = "\(base) copy"
                var n = 2
                while taken.contains(name) { name = "\(base) copy \(n)"; n += 1 }
                taken.insert(name)
                result.append(TimelineScene(name: name, actionIDs: ids))
            }
        }
        let rest = pairs.filter { !inWhole.contains($0.original) }.map { ($0.original, $0.copy) }
        return joining(rest, in: result)
    }

    /// A name without the " copy" or " copy N" a copy was given, so a copy
    /// of "Scene 1 copy" is "Scene 1 copy 2" rather than "Scene 1 copy copy".
    static func copyBase(of name: String) -> String {
        guard let range = name.range(of: #" copy( \d+)?$"#, options: .regularExpression) else { return name }
        return String(name[..<range.lowerBound])
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
