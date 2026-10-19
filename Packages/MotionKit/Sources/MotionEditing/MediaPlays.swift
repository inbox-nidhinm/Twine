import Foundation
import MotionModel

/// A sound or video layer and its Play bars are one thing: the bar is where
/// the layer is found and timed, so a layer is never left without one.
/// Deleting its last bar deletes the layer (deleting the layer already takes
/// its bars), and a project that has one without a bar gets one back.
public enum MediaPlays {
    /// Sound and video layers: the ones a Play bar plays.
    public static func plays(_ layer: Layer) -> Bool {
        switch layer.content {
        case .audio, .video: return true
        default: return false
        }
    }

    /// Deletes actions, and any sound or video layer whose every Play bar
    /// goes with them.
    public static func deleting(_ ids: Set<UUID>, in project: Project) -> EditorCommand {
        let deleted = project.actions.filter { ids.contains($0.id) }
        let touched = Set(deleted.filter(\.isPlay).map(\.targetLayerID))
        let emptied = touched.filter { id in
            guard let layer = project.layer(withID: id), plays(layer) else { return false }
            return !project.actions.contains { $0.targetLayerID == id && $0.isPlay && !ids.contains($0.id) }
        }
        let delete = EditorCommand.deleteActions(ids)
        guard !emptied.isEmpty else { return delete }
        return .batch([delete, .deleteLayers(emptied)], name: "Delete")
    }

    /// The project with a Play bar for every sound or video that has none,
    /// from the start, as long as its file, at the bottom of the timeline,
    /// as an import makes one.
    public static func withPlayBars(_ project: Project) -> Project {
        let playing = Set(project.actions.filter(\.isPlay).map(\.targetLayerID))
        // A template's slots play in its cards, never on their own.
        let slots = project.templateSlotIDs
        let missing = project.allLayers.filter { plays($0) && !playing.contains($0.id) && !slots.contains($0.id) }
        guard !missing.isEmpty else { return project }
        let rate = project.composition.frameRate
        var row = ActionFactory.nextRowOrder(in: project)
        var p = project
        for layer in missing {
            let length = layer.mediaIDs.first.flatMap { id in project.media.first { $0.id == id } }?.duration
            p.actions.append(Action(target: layer.id, start: 0,
                                    duration: max(rate.snapped(length ?? 1), rate.frameDuration),
                                    name: "Play", rowOrder: row, spec: .play(PlayAction())))
            row += 1
        }
        return p
    }
}

extension Action {
    var isPlay: Bool {
        if case .play = spec { return true }
        return false
    }
}
