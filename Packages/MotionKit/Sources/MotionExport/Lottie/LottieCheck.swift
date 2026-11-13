import Foundation
import MotionModel
import MotionEvaluation

/// What a Lottie leaves out of a scene, gathered layer by layer.
struct LottieOmissions {
    var found = Set<LottieOmission>()

    /// What was found, in a fixed order.
    var names: [String] { LottieOmission.allCases.filter(found.contains).map(\.rawValue) }

    /// Notes what a layer has that a Lottie cannot draw.
    mutating func note(_ layer: ResolvedLayer) {
        if !layer.shadows.isEmpty || !layer.innerShadows.isEmpty { found.insert(.shadows) }
        if layer.blur > 0 { found.insert(.blur) }
        if layer.backgroundBlur != nil { found.insert(.backgroundBlur) }
        if layer.glass != .none { found.insert(.glass) }
        if layer.curl != .none { found.insert(.pageCurls) }
        if layer.motion != .none { found.insert(.motionBlur) }
        if layer.placed != .none || layer.warp.tilt.isTilted || layer.warp.bend != .zero { found.insert(.depth) }
        if layer.blendMode == .linearBurn { found.insert(.linearBurn) }
        switch layer.content {
        case .video: found.insert(.video)
        case .text(let t):
            for unit in t.units {
                if unit.blur > 0 { found.insert(.blur) }
                if unit.motion != .none { found.insert(.motionBlur) }
                if !unit.transform.isAffine { found.insert(.depth) }
            }
        case .shape, .group: break
        }
        if let look = layer.look {
            for paint in look.fills { note(paint) }
            for stroke in look.strokes {
                if case .image = stroke.paint { found.insert(.pictureStrokes) } else { note(stroke.paint) }
            }
        }
    }

    mutating func note(_ paint: ResolvedPaint) {
        switch paint {
        case .angular: found.insert(.angularGradients)
        case .radial(_, _, _, let aspect): if abs(aspect - 1) > 1e-6 { found.insert(.ovalGradients) }
        case .image(let image): if image.tiles { found.insert(.tiledPictures) }
        case .solid, .linear: break
        }
    }
}

/// A quick look, before exporting, at what a Lottie of a project would leave
/// out: the same rules as the export, over a frame every so often rather
/// than every frame, so the export panel can say so as soon as Lottie is
/// chosen. An effect that shows only between the frames looked at goes
/// unnamed until the export itself.
public enum LottieCheck {
    /// At most this many frames are looked at.
    public static let samples = 120

    public static func leftOut(_ project: Project, frames: Range<Int>? = nil) -> [String] {
        let timing = ExportTiming(project.composition, frames: frames)
        let count = timing.frameCount
        guard count > 0 else { return [] }
        let step = max(1, Int((Double(count) / Double(samples)).rounded(.up)))
        let cache = EvaluationCache()
        var omissions = LottieOmissions()
        var firstOrder: [UUID]?
        for f in Set(Array(stride(from: 0, to: count, by: step)) + [count - 1]).sorted() {
            let scene = evaluate(project, at: timing.time(ofFrame: f), cache: cache)
            for layer in scene.layers { omissions.note(layer) }
            for mask in scene.masks { omissions.note(mask) }
            let order = scene.drawingOrder().map { scene.layers[$0].id }
            if let firstOrder {
                if order != firstOrder.filter(Set(order).contains) { omissions.found.insert(.order) }
            } else {
                firstOrder = order
            }
        }
        return omissions.names
    }
}
