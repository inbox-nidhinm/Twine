import Foundation
import MotionModel
import MotionEvaluation

/// Use as Mask and Remove Mask, as Figma has them (4 October 2026).
public enum Masking {
    public enum Refusal: Error, Equatable {
        /// The layer that would be the mask is a group or a sound, which
        /// cannot be drawn as one.
        case cannotMask(UUID)
        /// The layers are in different groups or frames.
        case apart
    }

    /// One layer becomes a mask where it is, masking the layers in front of
    /// it in its group or frame. Several, which must share a parent as for
    /// Group, go into a Mask group in their order, the one at the back
    /// becoming its mask. One undo step either way.
    public static func useAsMask(_ ids: [UUID], in project: Project) throws -> EditorCommand {
        let located = ids.compactMap { id in project.location(of: id).map { (id: id, at: $0) } }
        guard !located.isEmpty, located.count == ids.count else { throw EditorError.invalidValue }
        guard located.allSatisfy({ $0.at.parentID == located[0].at.parentID }) else { throw Refusal.apart }
        let back = located.min { $0.at.index < $1.at.index }!.id
        guard var mask = project.layer(withID: back), mask.canMask else { throw Refusal.cannotMask(back) }
        if ids.count == 1 {
            mask.isMask = true
            return .batch([.updateLayers([mask])], name: "Use as Mask")
        }
        let (grouping, _) = try Arrangement.group(ids, in: project, name: MaskConversion.groupName)
        // The mask as it is once grouped, moved into the group's space.
        var draft = project
        try grouping.apply(to: &draft)
        guard var grouped = draft.layer(withID: back) else { throw EditorError.notFound(back) }
        grouped.isMask = true
        return .batch([grouping, .updateLayers([grouped])], name: "Use as Mask")
    }

    /// The layer stops being a mask; its group stays, as in Figma.
    public static func removeMask(_ id: UUID, in project: Project) throws -> EditorCommand {
        guard var layer = project.layer(withID: id), layer.isMask else { throw EditorError.notFound(id) }
        layer.isMask = false
        return .batch([.updateLayers([layer])], name: "Remove Mask")
    }
}
