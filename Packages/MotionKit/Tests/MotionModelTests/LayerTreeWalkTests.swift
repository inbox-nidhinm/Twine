import Foundation
import Testing
import MotionModel

/// The tree walks that large projects lean on give what the slower ones
/// they replaced gave.
struct LayerTreeWalkTests {
    private func shape(_ name: String) -> Layer {
        Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero))), size: Size2(10, 10), position: .zero)
    }

    private func group(_ name: String, _ children: [Layer], locked: Bool = false) -> Layer {
        var g = Layer(name: name, content: .group(GroupContent(children: children)), size: Size2(10, 10), position: .zero)
        g.isLocked = locked
        return g
    }

    @Test func placesParentsAndLocksMatchTheTree() {
        let a = shape("a"), b = shape("b"), c = shape("c"), d = shape("d")
        var e = shape("e")
        e.isLocked = true
        let inner = group("inner", [c, d], locked: true)
        let outer = group("outer", [b, inner])
        let project = Project(composition: Composition(width: 100, height: 100), layers: [a, outer, e])

        #expect(project.location(of: a.id)! == (nil, 0))
        #expect(project.location(of: d.id)! == (inner.id, 1))
        #expect(project.location(of: UUID()) == nil)
        #expect(project.ancestors(of: d.id) == [outer.id, inner.id])
        #expect(project.parents == [b.id: outer.id, inner.id: outer.id, c.id: inner.id, d.id: inner.id])
        #expect(project.lockedLayers == [inner.id, c.id, d.id, e.id])
        for layer in project.allLayers {
            #expect(project.isLocked(layer.id) == project.lockedLayers.contains(layer.id))
        }
        var visited: [UUID] = []
        project.forEachLayer { visited.append($0.id) }
        #expect(visited == [a, outer, b, inner, c, d, e].map(\.id))
    }

    @Test func aLayerHasMaskCandidatesExactlyWhenTheyAreListed() {
        let a = shape("a"), b = shape("b")
        let only = group("only", [a])
        let alone = Project(composition: Composition(width: 100, height: 100), layers: [only])
        #expect(alone.maskCandidates(for: a.id).isEmpty)
        #expect(!alone.hasMaskCandidates(for: a.id))
        let two = Project(composition: Composition(width: 100, height: 100), layers: [only, b])
        #expect(two.maskCandidates(for: a.id).map(\.id) == [b.id])
        #expect(two.hasMaskCandidates(for: a.id))
    }
}
