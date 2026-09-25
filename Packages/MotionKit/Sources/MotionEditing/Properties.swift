import Foundation
import MotionModel
import MotionEvaluation

/// Names one animatable property on a layer. Properties that belong to a fill,
/// a stroke or an effect carry that item's id as `target`, so a layer with two
/// fills has two distinct fill colours.
///
/// The kind names are stable strings because they are written to disk in
/// presets and to the clipboard.
public struct PropertyID: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case position, anchor, scale, rotation, opacity, size
        case cornerRadii, starInnerRadius, path
        case fillColor, fillStops
        case strokeColor, strokeStops, strokeWidth, trimStart, trimEnd
        case shadowColor, shadowOffset, shadowBlur, shadowOpacity
        case blurRadius
        case textColor
        case volume
    }

    public var kind: Kind
    public var target: UUID?

    public init(_ kind: Kind, target: UUID? = nil) {
        self.kind = kind
        self.target = target
    }

    public static let position = PropertyID(.position)
    public static let anchor = PropertyID(.anchor)
    public static let scale = PropertyID(.scale)
    public static let rotation = PropertyID(.rotation)
    public static let opacity = PropertyID(.opacity)
    public static let size = PropertyID(.size)
}

/// One keyframe, anywhere in the project.
public struct KeyframeRef: Hashable, Sendable {
    public var layerID: UUID
    public var property: PropertyID
    public var keyframeID: UUID

    public init(layerID: UUID, property: PropertyID, keyframeID: UUID) {
        self.layerID = layerID
        self.property = property
        self.keyframeID = keyframeID
    }
}

/// What the timeline needs to know about a keyframe without knowing what
/// kind of value it holds.
public struct KeyframeMark: Sendable, Equatable {
    public var id: UUID
    public var time: Double
    public var easing: Easing

    public init(id: UUID, time: Double, easing: Easing) {
        self.id = id
        self.time = time
        self.easing = easing
    }
}

/// Every operation the timeline and the inspector apply to a property,
/// whatever its value type. Implemented once, generically, by
/// `AnimatableProperty`.
public protocol AnyAnimatableProperty: Sendable {
    var isAnimated: Bool { get }
    var marks: [KeyframeMark] { get }
    /// Adds a keyframe holding the current value at `time`, unless one is
    /// already within `tolerance` of it.
    func keyed(at time: Double, tolerance: Double) -> Self
    /// Stopwatch off: no keyframes, holding the value it had at `time`.
    func unkeyed(at time: Double) -> Self
    func removing(_ ids: Set<UUID>) -> Self
    func retimed(_ times: [UUID: Double]) -> Self
    func withEasing(_ easing: Easing, for ids: Set<UUID>) -> Self
    func shiftedInTime(by delta: Double) -> Self
    /// The chosen keyframes, for the clipboard.
    func encodedKeyframes(_ ids: Set<UUID>) throws -> Data
    /// Keyframes from the clipboard, moved so the earliest lands on `time`,
    /// with new ids. Nil when the data holds a different kind of value.
    func pasting(_ data: Data, earliest: Double, at time: Double) -> Self?
}

extension AnimatableProperty: AnyAnimatableProperty where Value: Interpolatable {
    public var marks: [KeyframeMark] { keyframes.map { KeyframeMark(id: $0.id, time: $0.time, easing: $0.easing) } }

    public func keyed(at time: Double, tolerance: Double) -> AnimatableProperty {
        if keyframes.contains(where: { abs($0.time - time) <= tolerance }) { return self }
        return inserting(value(at: time), at: time)
    }

    public func unkeyed(at time: Double) -> AnimatableProperty {
        AnimatableProperty(value(at: time))
    }

    public func removing(_ ids: Set<UUID>) -> AnimatableProperty {
        var copy = self
        copy.setKeyframes(keyframes.filter { !ids.contains($0.id) })
        // The last keyframe gone means the property holds still at what it was.
        if copy.keyframes.isEmpty, let last = keyframes.first(where: { ids.contains($0.id) }) { copy.value = last.value }
        return copy
    }

    public func retimed(_ times: [UUID: Double]) -> AnimatableProperty {
        var copy = self
        copy.setKeyframes(keyframes.map { key in
            var k = key
            if let t = times[key.id] { k.time = t }
            return k
        })
        return copy
    }

    public func withEasing(_ easing: Easing, for ids: Set<UUID>) -> AnimatableProperty {
        var copy = self
        copy.setKeyframes(keyframes.map { key in
            var k = key
            if ids.contains(key.id) { k.easing = easing }
            return k
        })
        return copy
    }

    public func shiftedInTime(by delta: Double) -> AnimatableProperty {
        retimed(Dictionary(uniqueKeysWithValues: keyframes.map { ($0.id, $0.time + delta) }))
    }

    public func encodedKeyframes(_ ids: Set<UUID>) throws -> Data {
        try JSONEncoder().encode(keyframes.filter { ids.contains($0.id) })
    }

    public func pasting(_ data: Data, earliest: Double, at time: Double) -> AnimatableProperty? {
        guard let pasted = try? JSONDecoder().decode([Keyframe<Value>].self, from: data) else { return nil }
        var copy = self
        var keys = keyframes
        for key in pasted {
            let t = key.time - earliest + time
            keys.removeAll { abs($0.time - t) < 1e-9 }
            keys.append(Keyframe(time: t, value: key.value, easing: key.easing))
        }
        copy.setKeyframes(keys)
        return copy
    }

    /// A keyframe holding `new` at `time`, replacing one already there. A new
    /// keyframe takes the easing of the one before it, so adding a key in the
    /// middle of a curve keeps the motion's character.
    func inserting(_ new: Value, at time: Double, tolerance: Double = 1e-9) -> AnimatableProperty {
        var keys = keyframes
        if let i = keys.firstIndex(where: { abs($0.time - time) <= tolerance }) {
            keys[i].value = new
        } else {
            let before = keys.last { $0.time < time }
            keys.append(Keyframe(time: time, value: new, easing: before?.easing ?? .default))
        }
        var copy = self
        copy.setKeyframes(keys)
        return copy
    }
}

/// Finding and replacing a layer's properties by `PropertyID`.
public enum LayerProperties {
    /// Every property this layer has that can be animated, in the order the
    /// timeline lists them.
    public static func all(of layer: Layer) -> [PropertyID] {
        var ids: [PropertyID] = [.position, .anchor, .scale, .rotation, .opacity]
        switch layer.content {
        case .shape(let shape):
            ids.append(.size)
            switch shape.geometry {
            case .rectangle: ids.append(PropertyID(.cornerRadii))
            case .star: ids.append(PropertyID(.starInnerRadius))
            case .path: ids.append(PropertyID(.path))
            default: break
            }
            for fill in shape.fills {
                if case .solid = fill.paint { ids.append(PropertyID(.fillColor, target: fill.id)) }
                else { ids.append(PropertyID(.fillStops, target: fill.id)) }
            }
            for stroke in shape.strokes {
                if case .solid = stroke.paint { ids.append(PropertyID(.strokeColor, target: stroke.id)) }
                else { ids.append(PropertyID(.strokeStops, target: stroke.id)) }
                ids += [PropertyID(.strokeWidth, target: stroke.id), PropertyID(.trimStart, target: stroke.id),
                        PropertyID(.trimEnd, target: stroke.id)]
            }
        case .text:
            ids += [.size, PropertyID(.textColor)]
        case .image:
            ids.append(.size)
        case .video:
            ids += [.size, PropertyID(.volume)]
        case .audio:
            ids = [PropertyID(.volume)]
        case .group:
            break
        }
        for effect in layer.effects {
            switch effect.kind {
            case .dropShadow:
                ids += [PropertyID(.shadowColor, target: effect.id), PropertyID(.shadowOffset, target: effect.id),
                        PropertyID(.shadowBlur, target: effect.id), PropertyID(.shadowOpacity, target: effect.id)]
            case .layerBlur:
                ids.append(PropertyID(.blurRadius, target: effect.id))
            }
        }
        return ids
    }

    /// The properties that have keyframes.
    public static func animated(of layer: Layer) -> [PropertyID] {
        all(of: layer).filter { get($0, of: layer)?.isAnimated == true }
    }

    public static func title(_ id: PropertyID) -> String {
        switch id.kind {
        case .position: return "Position"
        case .anchor: return "Anchor"
        case .scale: return "Scale"
        case .rotation: return "Rotation"
        case .opacity: return "Opacity"
        case .size: return "Size"
        case .cornerRadii: return "Corner Radius"
        case .starInnerRadius: return "Inner Radius"
        case .path: return "Path"
        case .fillColor: return "Fill"
        case .fillStops: return "Fill Gradient"
        case .strokeColor: return "Stroke"
        case .strokeStops: return "Stroke Gradient"
        case .strokeWidth: return "Stroke Width"
        case .trimStart: return "Trim Start"
        case .trimEnd: return "Trim End"
        case .shadowColor: return "Shadow Colour"
        case .shadowOffset: return "Shadow Offset"
        case .shadowBlur: return "Shadow Blur"
        case .shadowOpacity: return "Shadow Opacity"
        case .blurRadius: return "Blur"
        case .textColor: return "Text Colour"
        case .volume: return "Volume"
        }
    }

    public static func get(_ id: PropertyID, of layer: Layer) -> (any AnyAnimatableProperty)? {
        let t = layer.transform
        switch id.kind {
        case .position: return t.position
        case .anchor: return t.anchor
        case .scale: return t.scale
        case .rotation: return t.rotation
        case .opacity: return layer.opacity
        case .size: return layer.size
        case .cornerRadii:
            if case .rectangle(let r) = layer.shapeGeometry { return r }
        case .starInnerRadius:
            if case .star(_, let r) = layer.shapeGeometry { return r }
        case .path:
            if case .path(let p) = layer.shapeGeometry { return p }
        case .fillColor, .fillStops:
            if let fill = layer.shapeContent?.fills.first(where: { $0.id == id.target }) { return paintProperty(fill.paint, id.kind) }
        case .strokeColor, .strokeStops:
            if let stroke = layer.shapeContent?.strokes.first(where: { $0.id == id.target }) {
                return paintProperty(stroke.paint, id.kind == .strokeColor ? .fillColor : .fillStops)
            }
        case .strokeWidth: return layer.shapeContent?.strokes.first { $0.id == id.target }?.width
        case .trimStart: return layer.shapeContent?.strokes.first { $0.id == id.target }?.trimStart
        case .trimEnd: return layer.shapeContent?.strokes.first { $0.id == id.target }?.trimEnd
        case .shadowColor: return shadow(id.target, in: layer)?.color
        case .shadowOffset: return shadow(id.target, in: layer)?.offset
        case .shadowBlur: return shadow(id.target, in: layer)?.blur
        case .shadowOpacity: return shadow(id.target, in: layer)?.opacity
        case .blurRadius:
            if let e = layer.effects.first(where: { $0.id == id.target }), case .layerBlur(let b) = e.kind { return b.radius }
        case .textColor:
            if case .text(let text) = layer.content { return text.color }
        case .volume:
            if case .video(let v) = layer.content { return v.volume }
            if case .audio(let a) = layer.content { return a.volume }
        }
        return nil
    }

    /// Puts a property back. A value of the wrong type for `id` is ignored.
    public static func set(_ property: any AnyAnimatableProperty, for id: PropertyID, on layer: inout Layer) {
        switch id.kind {
        case .position: if let p = property as? AnimatableProperty<Vec2> { layer.transform.position = p }
        case .anchor: if let p = property as? AnimatableProperty<Vec2> { layer.transform.anchor = p }
        case .scale: if let p = property as? AnimatableProperty<Vec2> { layer.transform.scale = p }
        case .rotation: if let p = property as? AnimatableProperty<Double> { layer.transform.rotation = p }
        case .opacity: if let p = property as? AnimatableProperty<Double> { layer.opacity = p }
        case .size: if let p = property as? AnimatableProperty<Size2> { layer.size = p }
        case .cornerRadii:
            if let p = property as? AnimatableProperty<CornerRadii> { editGeometry(&layer) { $0 = .rectangle(cornerRadii: p) } }
        case .starInnerRadius:
            if let p = property as? AnimatableProperty<Double> {
                editGeometry(&layer) { g in if case .star(let n, _) = g { g = .star(points: n, innerRadius: p) } }
            }
        case .path:
            if let p = property as? AnimatableProperty<BezierPath> { editGeometry(&layer) { $0 = .path(p) } }
        case .fillColor, .fillStops:
            editShape(&layer) { s in
                if let i = s.fills.firstIndex(where: { $0.id == id.target }) { s.fills[i].paint = setPaint(s.fills[i].paint, property) }
            }
        case .strokeColor, .strokeStops:
            editShape(&layer) { s in
                if let i = s.strokes.firstIndex(where: { $0.id == id.target }) { s.strokes[i].paint = setPaint(s.strokes[i].paint, property) }
            }
        case .strokeWidth, .trimStart, .trimEnd:
            guard let p = property as? AnimatableProperty<Double> else { return }
            editShape(&layer) { s in
                guard let i = s.strokes.firstIndex(where: { $0.id == id.target }) else { return }
                switch id.kind {
                case .strokeWidth: s.strokes[i].width = p
                case .trimStart: s.strokes[i].trimStart = p
                default: s.strokes[i].trimEnd = p
                }
            }
        case .shadowColor:
            if let p = property as? AnimatableProperty<RGBA> { editShadow(id.target, &layer) { $0.color = p } }
        case .shadowOffset:
            if let p = property as? AnimatableProperty<Vec2> { editShadow(id.target, &layer) { $0.offset = p } }
        case .shadowBlur:
            if let p = property as? AnimatableProperty<Double> { editShadow(id.target, &layer) { $0.blur = p } }
        case .shadowOpacity:
            if let p = property as? AnimatableProperty<Double> { editShadow(id.target, &layer) { $0.opacity = p } }
        case .blurRadius:
            guard let p = property as? AnimatableProperty<Double>,
                  let i = layer.effects.firstIndex(where: { $0.id == id.target }),
                  case .layerBlur(var b) = layer.effects[i].kind else { return }
            b.radius = p
            layer.effects[i].kind = .layerBlur(b)
        case .textColor:
            if let p = property as? AnimatableProperty<RGBA>, case .text(var text) = layer.content {
                text.color = p
                layer.content = .text(text)
            }
        case .volume:
            guard let p = property as? AnimatableProperty<Double> else { return }
            if case .video(var v) = layer.content { v.volume = p; layer.content = .video(v) }
            if case .audio(var a) = layer.content { a.volume = p; layer.content = .audio(a) }
        }
    }

    /// Changes one property through its type-erased operations.
    public static func update(_ id: PropertyID, on layer: inout Layer,
                              _ change: (any AnyAnimatableProperty) -> any AnyAnimatableProperty) {
        guard let property = get(id, of: layer) else { return }
        set(change(property), for: id, on: &layer)
    }

    // MARK: Helpers

    private static func paintProperty(_ paint: Paint, _ kind: PropertyID.Kind) -> (any AnyAnimatableProperty)? {
        switch paint {
        case .solid(let c): return kind == .fillColor ? c : nil
        case .linearGradient(let g), .radialGradient(let g): return kind == .fillStops ? g.stops : nil
        }
    }

    private static func setPaint(_ paint: Paint, _ property: any AnyAnimatableProperty) -> Paint {
        switch paint {
        case .solid:
            if let c = property as? AnimatableProperty<RGBA> { return .solid(c) }
        case .linearGradient(var g):
            if let s = property as? AnimatableProperty<[GradientStop]> { g.stops = s; return .linearGradient(g) }
        case .radialGradient(var g):
            if let s = property as? AnimatableProperty<[GradientStop]> { g.stops = s; return .radialGradient(g) }
        }
        return paint
    }

    private static func shadow(_ target: UUID?, in layer: Layer) -> DropShadow? {
        guard let e = layer.effects.first(where: { $0.id == target }), case .dropShadow(let s) = e.kind else { return nil }
        return s
    }

    private static func editShadow(_ target: UUID?, _ layer: inout Layer, _ change: (inout DropShadow) -> Void) {
        guard let i = layer.effects.firstIndex(where: { $0.id == target }),
              case .dropShadow(var s) = layer.effects[i].kind else { return }
        change(&s)
        layer.effects[i].kind = .dropShadow(s)
    }

    private static func editShape(_ layer: inout Layer, _ change: (inout ShapeContent) -> Void) {
        guard case .shape(var s) = layer.content else { return }
        change(&s)
        layer.content = .shape(s)
    }

    private static func editGeometry(_ layer: inout Layer, _ change: (inout ShapeGeometry) -> Void) {
        editShape(&layer) { change(&$0.geometry) }
    }
}

extension Layer {
    public var shapeContent: ShapeContent? {
        if case .shape(let s) = content { return s }
        return nil
    }

    public var shapeGeometry: ShapeGeometry? { shapeContent?.geometry }

    /// The layer, everything in it, and every keyframe moved later by `delta`.
    public func shiftedInTime(by delta: Double) -> Layer {
        var copy = self
        copy.inPoint += delta
        copy.outPoint += delta
        for id in LayerProperties.all(of: self) {
            LayerProperties.update(id, on: &copy) { $0.shiftedInTime(by: delta) }
        }
        if case .group(var group) = copy.content {
            group.children = group.children.map { $0.shiftedInTime(by: delta) }
            copy.content = .group(group)
        }
        return copy
    }
}
