import Foundation
import MotionModel

/// A template frame's cards at one moment, as ordinary layers its frame
/// holds in its 3D space: each a rounded rectangle filled with its slot's
/// picture (or a plain colour for an empty slot), fitted into the cell its
/// recipe gives, and placed, turned and bent as the recipe says. They are
/// made afresh at every moment and never stored; their ids are worked out
/// from the frame's and the card's place, so each card stays the same card
/// from one moment to the next (`TemplateCards.id`).
public enum TemplateCards {
    /// The frame's camera and cards at `phase`, in a frame of `size`.
    /// `pictures` gives the slots' pictures' shapes, for Auto cards.
    public static func make(_ frame: Layer, _ setup: TemplateSetup, phase: Double, size: Size2,
                            pictures: [UUID: Size2]) -> (space: Space3D, cards: [Layer]) {
        let scene = TemplateRecipes.scene(setup, phase: phase, size: size)
        let slots = setup.slots.isEmpty ? [nil] : Array(setup.slots.prefix(maxSlots))
        let cards = scene.cards.map { card -> Layer in
            let media = slots[card.index % slots.count]
            let aspect = setup.ratio.aspect
                ?? media.flatMap { pictures[$0] }.map { $0.height > 0 ? $0.width / $0.height : 1 }
                ?? (card.cell.height > 0 ? card.cell.width / card.cell.height : 1)
            let box = fitted(aspect, in: card.cell)
            let corner = min(max(setup.cornerRadius, 0), 0.5) * min(box.width, box.height)
            let paint: Paint = media.map { .image(ImagePaint(mediaID: $0, mode: .fill)) } ?? .color(placeholder(card.index))
            var layer = Layer(id: id(of: card.index, in: frame.id), name: "Card \(card.index + 1)",
                              content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: CornerRadii(all: corner)),
                                                           fills: [Fill(paint: paint)])),
                              size: box, position: card.position)
            layer.transform.z = card.z
            layer.transform.rotation = card.rotation
            layer.transform.tilt = Tilt(x: card.tilt.x, y: card.tilt.y)
            layer.transform.scale = Vec2(card.scale, card.scale)
            layer.transform.bend = Vec2(bend(box.width, card.curve.x), bend(box.height, card.curve.y))
            layer.opacity = min(max(card.opacity, 0), 1)
            if setup.shadow {
                let shadow = DropShadow(color: .black, offset: Vec2(0, box.height * 0.04), blur: box.height * 0.12, opacity: 0.35)
                layer.effects = [Effect(kind: .dropShadow(shadow))]
            }
            return layer
        }
        return (scene.space, cards)
    }

    /// The most slots a template draws from.
    public static let maxSlots = 200

    /// The degrees of a circle's turn a card `length` long covers on a
    /// circle of `radius`; 0 when flat.
    static func bend(_ length: Double, _ radius: Double) -> Double {
        guard abs(radius) > 1e-6 else { return 0 }
        return length / radius * 180 / .pi
    }

    /// The largest box of shape `aspect` (width over height) in `cell`.
    static func fitted(_ aspect: Double, in cell: Size2) -> Size2 {
        guard aspect > 0, cell.width > 0, cell.height > 0 else { return cell }
        return cell.width / cell.height > aspect ? Size2(cell.height * aspect, cell.height) : Size2(cell.width, cell.width / aspect)
    }

    /// Card `index`'s id in the frame `frame`: steady from one moment to
    /// the next, and different for every card.
    public static func id(of index: Int, in frame: UUID) -> UUID {
        var u = frame.uuid
        u.10 ^= 0x5A
        u.11 ^= 0xC3
        u.14 ^= UInt8(truncatingIfNeeded: index)
        u.15 ^= UInt8(truncatingIfNeeded: index >> 8)
        return UUID(uuid: u)
    }

    /// Whether `id` is one of a template frame's cards, made by `id(of:in:)`.
    public static func isCard(_ id: UUID, of frame: UUID) -> Bool {
        let a = id.uuid, b = frame.uuid
        return a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3 && a.4 == b.4 && a.5 == b.5 && a.6 == b.6
            && a.7 == b.7 && a.8 == b.8 && a.9 == b.9 && a.10 == b.10 ^ 0x5A && a.11 == b.11 ^ 0xC3
            && a.12 == b.12 && a.13 == b.13
    }

    /// The plain colours empty slots show, soft greys and slates in turn.
    static func placeholder(_ index: Int) -> RGBA {
        let tones: [RGBA] = [RGBA(0.62, 0.64, 0.68), RGBA(0.42, 0.45, 0.50), RGBA(0.78, 0.79, 0.81),
                             RGBA(0.33, 0.37, 0.44), RGBA(0.55, 0.58, 0.62), RGBA(0.70, 0.72, 0.75)]
        return tones[index % tones.count]
    }
}
