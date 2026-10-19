import Foundation
import MotionModel

/// A template frame's cards at one moment, as ordinary layers its frame
/// holds in its 3D space: each a rounded rectangle filled with its slot's
/// picture (or for an empty slot a sample, `TemplateSamples`), fitted into the cell its
/// recipe gives, and placed, turned and bent as the recipe says. They are
/// made afresh at every moment and never stored; their ids are worked out
/// from the frame's and the card's place, so each card stays the same card
/// from one moment to the next (`TemplateCards.id`).
public enum TemplateCards {
    /// The frame's camera and cards at `phase`, in a frame of `size`.
    /// `pictures` gives the slots' pictures' shapes, for Auto cards, and
    /// `videos` the slots' videos: a card showing one is a rounded frame
    /// clipping the video, muted, which `evaluate` keeps playing round.
    public static func make(_ frame: Layer, _ setup: TemplateSetup, phase: Double, size: Size2,
                            pictures: [UUID: Size2], videos: [UUID: VideoClip] = [:]) -> (space: Space3D, cards: [Layer]) {
        let listed = frame.templateSlots
        // A frame with no slots at all draws as a new one of its kind would.
        let scene = TemplateRecipes.scene(setup, phase: phase, size: size, slots: listed.isEmpty ? nil : min(listed.count, maxSlots))
        let slots = listed.isEmpty ? [nil] : Array(listed.prefix(maxSlots))
        let cards = scene.cards.map { card -> Layer in
            let slot = (card.slot ?? card.index) % slots.count
            // An empty slot shows one of the app's own sample pictures.
            let media = card.color == nil ? slots[(slot + slots.count) % slots.count] ?? TemplateSamples.sample(for: slot).id : nil
            let own = media.flatMap { pictures[$0] ?? videos[$0]?.size ?? TemplateSamples.sample(id: $0)?.size }
                .map { $0.height > 0 ? $0.width / $0.height : 1 }
            let aspect = setup.ratio.aspect ?? own ?? (card.cell.height > 0 ? card.cell.width / card.cell.height : 1)
            // A piece of a bigger picture, or a plain card, is its cell exactly.
            let box = card.area != nil || card.color != nil ? card.cell : fitted(aspect, in: card.cell)
            let corner = card.rounded ? min(max(setup.cornerRadius, 0), 0.5) * min(box.width, box.height) : 0
            let id = id(of: card.index, in: frame.id)
            let paint: Paint
            if let media, videos[media] != nil {
                // The video's own box: the card's, or for a piece of a
                // bigger picture the area it covers, clipped to the card.
                let clip = card.area.map { covering(own ?? 1, $0) } ?? Box(origin: .zero, size: box)
                let video = Layer(id: videoID(of: id), name: "Video",
                                  content: .video(VideoContent(mediaID: media, isMuted: true, fit: .fill)),
                                  size: Size2(clip.width, clip.height), position: clip.center)
                var layer = Layer(id: id, name: "Card \(card.index + 1)",
                                  content: .group(GroupContent(children: [video], clipsContent: true,
                                                               frame: FrameStyle(cornerRadii: CornerRadii(all: corner)))),
                                  size: box, position: card.position)
                placed(&layer, card, box, setup)
                return layer
            } else if let color = card.color {
                paint = .color(color)
            } else if let media, let area = card.area, box.width > 0, box.height > 0 {
                // The picture covering its area, given as fractions of the card.
                let cover = covering(own ?? 1, area)
                paint = .image(ImagePaint(mediaID: media, mode: .crop,
                                          crop: ImageCrop(x: cover.minX / box.width, y: cover.minY / box.height,
                                                          width: cover.width / box.width, height: cover.height / box.height)))
            } else {
                paint = .image(ImagePaint(mediaID: media ?? TemplateSamples.sample(for: slot).id, mode: .fill))
            }
            var layer = Layer(id: id, name: "Card \(card.index + 1)",
                              content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: CornerRadii(all: corner)),
                                                           fills: [Fill(paint: paint)])),
                              size: box, position: card.position)
            placed(&layer, card, box, setup)
            return layer
        }
        return (scene.space, cards)
    }

    /// A card's place, turns, bend, strength and shadow, as its recipe gives them.
    private static func placed(_ layer: inout Layer, _ card: TemplateCard, _ box: Size2, _ setup: TemplateSetup) {
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
    }

    /// The video inside card `card`'s frame: steady, and never taken for a card.
    public static func videoID(of card: UUID) -> UUID {
        var u = card.uuid
        u.9 ^= 0x3C
        return UUID(uuid: u)
    }

    /// Where a video in a card is, `time` seconds into the scene: going
    /// round from its start, so it plays on for as long as the template does.
    public static func videoTime(_ time: Double, length: Double) -> Double {
        guard length > 0, time.isFinite else { return 0 }
        let t = time.truncatingRemainder(dividingBy: length)
        return t < 0 ? t + length : t
    }

    /// The most slots a template draws from.
    public static let maxSlots = 200

    /// The degrees of a circle's turn a card `length` long covers on a
    /// circle of `radius`; 0 when flat.
    static func bend(_ length: Double, _ radius: Double) -> Double {
        guard abs(radius) > 1e-6 else { return 0 }
        return length / radius * 180 / .pi
    }

    /// The smallest box of shape `aspect` covering `area`, centred on it.
    static func covering(_ aspect: Double, _ area: Box) -> Box {
        guard aspect > 0, area.width > 0, area.height > 0 else { return area }
        let size = area.width / area.height > aspect ? Size2(area.width, area.width / aspect) : Size2(area.height * aspect, area.height)
        return Box(origin: Vec2(area.center.x - size.width / 2, area.center.y - size.height / 2), size: size)
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

    /// Which slot card `card` of template `frame` shows at `phase`, in slot
    /// order: worked out again from its recipe, as cards are never kept.
    public static func slot(of card: UUID, in frame: Layer, setup: TemplateSetup, phase: Double) -> Int? {
        guard isCard(card, of: frame.id) else { return nil }
        let a = card.uuid, f = frame.id.uuid
        let index = Int(a.14 ^ f.14) | Int(a.15 ^ f.15) << 8
        let count = min(frame.templateSlots.count, maxSlots)
        guard count > 0 else { return nil }
        let scene = TemplateRecipes.scene(setup, phase: phase, size: frame.size, slots: count)
        guard let made = scene.cards.first(where: { $0.index == index }) else { return nil }
        return (((made.slot ?? made.index) % count) + count) % count
    }

    /// Whether `id` is one of a template frame's cards, made by `id(of:in:)`.
    public static func isCard(_ id: UUID, of frame: UUID) -> Bool {
        let a = id.uuid, b = frame.uuid
        return a.0 == b.0 && a.1 == b.1 && a.2 == b.2 && a.3 == b.3 && a.4 == b.4 && a.5 == b.5 && a.6 == b.6
            && a.7 == b.7 && a.8 == b.8 && a.9 == b.9 && a.10 == b.10 ^ 0x5A && a.11 == b.11 ^ 0xC3
            && a.12 == b.12 && a.13 == b.13
    }
}
