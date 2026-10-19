import Foundation
import MotionModel
import MotionEvaluation

/// A template's slots as layers: its frame's children, each a picture
/// layer, a video layer or an empty one, which the layers panel lists and
/// the inspector edits as any picture or video. They are never drawn,
/// played or animated themselves: the template draws its cards from them
/// (`Layer.templateSlots`).
public enum TemplateSlots {
    /// The name an empty slot goes by.
    public static let emptyName = "Empty slot"
    /// How big a slot layer is, within the frame: it is never drawn, so this
    /// only keeps it a sensible size if it is ever moved out.
    static let side = 200.0

    /// A slot showing `asset`, a picture or a video, or an empty one when
    /// nil, in the middle of a frame of `size`.
    public static func layer(_ asset: MediaAsset?, in size: Size2) -> Layer {
        let middle = Vec2(size.width / 2, size.height / 2)
        guard let asset, asset.kind != .audio else {
            return Layer(name: emptyName, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero))),
                         size: Size2(side, side), position: middle)
        }
        let name = (asset.originalName as NSString).deletingPathExtension
        var box = Size2(side, side)
        if let w = asset.pixelWidth, let h = asset.pixelHeight, w > 0, h > 0 {
            box = w >= h ? Size2(side, side * Double(h) / Double(w)) : Size2(side * Double(w) / Double(h), side)
        }
        // A slot's video is never heard: the cards play it silently.
        let content: LayerContent = asset.kind == .video ? .video(VideoContent(mediaID: asset.id, isMuted: true))
            : .shape(LayerFactory.picture(asset.id))
        return Layer(name: name.isEmpty ? "Picture" : name, content: content, size: box, position: middle)
    }

    /// Whether `layer` shows nothing of its own.
    public static func isEmpty(_ layer: Layer) -> Bool { layer.slotMedia == nil }

    /// `project` with every template's slot list from before slots were
    /// layers (`TemplateSetup.legacySlots`) made its frame's children.
    public static func converted(_ project: Project) -> Project {
        let assets = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        func convert(_ layers: [Layer]) -> [Layer] {
            layers.map { layer in
                var layer = layer
                if var setup = layer.template, let legacy = setup.legacySlots {
                    if layer.children.isEmpty {
                        layer.templateSlotLayers = legacy.prefix(TemplateCards.maxSlots).map { id in
                            Self.layer(id.flatMap { assets[$0] }, in: layer.size)
                        }
                    }
                    setup.legacySlots = nil
                    layer.template = setup
                    changed = true
                } else if layer.isGroup {
                    layer.children = convert(layer.children)
                }
                return layer
            }
        }
        var p = project
        p.layers = convert(project.layers)
        return changed ? p : project
    }
}
