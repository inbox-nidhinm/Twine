import Foundation
import MotionModel
import MotionEvaluation

/// New actions, set up the way the action menu adds them: at the playhead,
/// half a second long, with an end value that visibly does something.
public enum ActionFactory {
    /// How long a new action runs, before landing on a frame.
    public static let defaultDuration = 0.5

    /// The actions that make sense on `layer`. Audio has nothing to move or
    /// fade; a group's size is its children's, so it scales rather than
    /// resizes.
    public static func kinds(for layer: Layer) -> [ActionKind] {
        switch layer.content {
        case .audio: return []
        case .group: return ActionKind.allCases.filter { $0 != .resize }
        default: return ActionKind.allCases
        }
    }

    /// Kinds offered for several layers at once: those every one of them takes.
    public static func kinds(for layers: [Layer]) -> [ActionKind] {
        guard let first = layers.first else { return [] }
        return layers.dropFirst().reduce(kinds(for: first)) { shared, layer in
            let allowed = Set(kinds(for: layer))
            return shared.filter(allowed.contains)
        }
    }

    /// A new action of `kind` on `layer`, starting at `time`. `state` is the
    /// layer at that moment, which sets defaults that depend on it: a Resize
    /// grows from the current size, and Hide/Show does whichever is not
    /// already the case. `rowOrder` should put it after the layer's others.
    public static func make(_ kind: ActionKind, for layer: Layer, at time: Double, state: LayerState,
                            frameRate: FrameRate, rowOrder: Int) -> Action {
        let start = frameRate.snapped(max(time, 0))
        let duration = frameRate.snapped(defaultDuration)
        let spec: ActionSpec
        var name: String?
        switch kind {
        case .move:
            spec = .move(MoveAction(mode: .by, end: Vec2(100, 0)))
        case .scale:
            spec = .scale(ScaleAction(mode: .to, end: Vec2(1.2, 1.2)))
        case .rotate:
            spec = .rotate(RotateAction(mode: .by, end: 90))
        case .opacity:
            spec = .opacity(OpacityAction(end: 0))
        case .resize:
            let s = state.size
            spec = .resize(ResizeAction(end: Size2((s.width * 1.2).rounded(), (s.height * 1.2).rounded()), isLinked: true))
        case .visibility:
            spec = .visibility(VisibilityAction(isVisible: !state.isShown))
            name = state.isShown ? "Hide" : "Show"
        }
        return Action(target: layer.id, start: start, duration: kind == .visibility ? 0 : duration,
                      name: name, rowOrder: rowOrder, spec: spec)
    }

    /// The row order that puts a new action after every other on its layer.
    public static func nextRowOrder(on layerID: UUID, in project: Project) -> Int {
        (project.actions(on: layerID).map(\.rowOrder).max() ?? -1) + 1
    }
}
