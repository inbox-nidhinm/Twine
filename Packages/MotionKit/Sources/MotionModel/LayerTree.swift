import Foundation

/// Finding and changing layers anywhere in the tree by id.
extension Project {
    public func layer(withID id: UUID) -> Layer? {
        Self.find(id, in: layers)
    }

    /// Every layer, parents before their children, back to front.
    public var allLayers: [Layer] {
        var out: [Layer] = []
        func walk(_ list: [Layer]) {
            for layer in list {
                out.append(layer)
                walk(layer.children)
            }
        }
        walk(layers)
        return out
    }

    /// Where a layer sits: its parent group's id (nil at the top level) and its
    /// index among its siblings.
    public func location(of id: UUID) -> (parentID: UUID?, index: Int)? {
        if let index = layers.firstIndex(where: { $0.id == id }) { return (nil, index) }
        for layer in allLayers where layer.isGroup {
            if let index = layer.children.firstIndex(where: { $0.id == id }) { return (layer.id, index) }
        }
        return nil
    }

    /// The ids of every group between the top level and this layer, outermost
    /// first.
    public func ancestors(of id: UUID) -> [UUID] {
        var chain: [UUID] = []
        var current = id
        while let parent = location(of: current)?.parentID {
            chain.insert(parent, at: 0)
            current = parent
        }
        return chain
    }

    /// Changes one layer in place. Returns false if no layer has that id.
    @discardableResult
    public mutating func updateLayer(_ id: UUID, _ change: (inout Layer) -> Void) -> Bool {
        Self.update(id, in: &layers, change)
    }

    /// Takes a layer out of the tree, children and all.
    @discardableResult
    public mutating func removeLayer(_ id: UUID) -> Layer? {
        Self.remove(id, from: &layers)
    }

    /// Puts a layer into a group, or at the top level when `parentID` is nil.
    /// `index` counts among the siblings; nil or past the end puts it in front.
    /// Returns false if the parent does not exist or is not a group.
    @discardableResult
    public mutating func insertLayer(_ layer: Layer, parentID: UUID?, at index: Int?) -> Bool {
        guard let parentID else {
            layers.insert(layer, at: Self.clamp(index, layers.count))
            return true
        }
        guard self.layer(withID: parentID)?.isGroup == true else { return false }
        return updateLayer(parentID) { parent in
            var children = parent.children
            children.insert(layer, at: Self.clamp(index, children.count))
            parent.children = children
        }
    }

    private static func clamp(_ index: Int?, _ count: Int) -> Int {
        guard let index else { return count }
        return min(max(index, 0), count)
    }

    private static func find(_ id: UUID, in list: [Layer]) -> Layer? {
        for layer in list {
            if layer.id == id { return layer }
            if let hit = find(id, in: layer.children) { return hit }
        }
        return nil
    }

    private static func update(_ id: UUID, in list: inout [Layer], _ change: (inout Layer) -> Void) -> Bool {
        for i in list.indices {
            if list[i].id == id {
                change(&list[i])
                return true
            }
            if list[i].isGroup {
                var children = list[i].children
                if update(id, in: &children, change) {
                    list[i].children = children
                    return true
                }
            }
        }
        return false
    }

    private static func remove(_ id: UUID, from list: inout [Layer]) -> Layer? {
        if let index = list.firstIndex(where: { $0.id == id }) { return list.remove(at: index) }
        for i in list.indices where list[i].isGroup {
            var children = list[i].children
            if let removed = remove(id, from: &children) {
                list[i].children = children
                return removed
            }
        }
        return nil
    }
}
