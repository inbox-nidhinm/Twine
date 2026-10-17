import Foundation

/// Finding and changing layers anywhere in the tree by id.
extension Project {
    public func layer(withID id: UUID) -> Layer? {
        Self.find(id, in: layers)
    }

    /// Every layer, parents before their children, back to front.
    ///
    /// Every layer is copied into the list, which in a project of thousands
    /// takes a millisecond: anything that only looks goes through
    /// `forEachLayer` instead.
    public var allLayers: [Layer] {
        var out: [Layer] = []
        forEachLayer { out.append($0) }
        return out
    }

    /// Visits every layer, parents before their children, back to front,
    /// reading each where it is rather than copying it out. (`for in`
    /// copies every layer it passes, and the trees here are searched for
    /// every layer on screen.)
    @inlinable
    public func forEachLayer(_ body: (Layer) -> Void) {
        // Through the list's own storage, so each layer is lent to `body`
        // where it lies: handed over by index, every one was copied.
        func walk(_ list: [Layer]) {
            list.withUnsafeBufferPointer { layers in
                for i in layers.indices {
                    body(layers[i])
                    if layers[i].isGroup { walk(layers[i].children) }
                }
            }
        }
        walk(layers)
    }

    /// Where a layer sits: its parent group's id (nil at the top level) and its
    /// index among its siblings.
    public func location(of id: UUID) -> (parentID: UUID?, index: Int)? {
        func look(in list: [Layer], parent: UUID?) -> (parentID: UUID?, index: Int)? {
            for i in list.indices where list[i].id == id { return (parent, i) }
            for i in list.indices where list[i].isGroup {
                if let found = look(in: list[i].children, parent: list[i].id) { return found }
            }
            return nil
        }
        return look(in: layers, parent: nil)
    }

    /// The 3D space a layer is placed in: its parent frame's, when that
    /// frame is in 3D. Nil for a layer at the top level or in a flat group.
    public func space3D(holding id: UUID) -> Space3D? {
        guard let parent = location(of: id)?.parentID else { return nil }
        return layer(withID: parent)?.space3D
    }

    /// Every layer that is locked or sits in a locked group, which can be
    /// neither picked nor moved on the canvas.
    public var lockedLayers: Set<UUID> {
        var out = Set<UUID>()
        func walk(_ list: [Layer], locked: Bool) {
            for i in list.indices {
                let mine = locked || list[i].isLocked
                if mine { out.insert(list[i].id) }
                if list[i].isGroup { walk(list[i].children, locked: mine) }
            }
        }
        walk(layers, locked: false)
        return out
    }

    /// Whether a layer is locked or sits in a locked group: one walk, where
    /// asking for its groups and then each of them searched the tree once
    /// for each.
    public func isLocked(_ id: UUID) -> Bool {
        func look(in list: [Layer], locked: Bool) -> Bool? {
            for i in list.indices {
                let mine = locked || list[i].isLocked
                if list[i].id == id { return mine }
                if list[i].isGroup, let found = look(in: list[i].children, locked: mine) { return found }
            }
            return nil
        }
        return look(in: layers, locked: false) ?? false
    }

    /// Every layer's parent group, by id, for anything that asks for many
    /// layers' places at once: asking `location(of:)` for each searched
    /// the whole tree every time.
    public var parents: [UUID: UUID] {
        var out: [UUID: UUID] = [:]
        func walk(_ list: [Layer], parent: UUID?) {
            for i in list.indices {
                if let parent { out[list[i].id] = parent }
                if list[i].isGroup { walk(list[i].children, parent: list[i].id) }
            }
        }
        walk(layers, parent: nil)
        return out
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
        for i in list.indices {
            if list[i].id == id { return list[i] }
            if list[i].isGroup, let hit = find(id, in: list[i].children) { return hit }
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
