import Foundation
import Testing
@testable import MotionModel

@Suite struct FrameRateTests {
    @Test func wholeRatesLandOnExactTimes() {
        #expect(FrameRate.fps60.time(ofFrame: 60) == 1)
        #expect(FrameRate.fps24.time(ofFrame: 12) == 0.5)
    }

    @Test func broadcastRatesDoNotDrift() {
        let rate = FrameRate.fps29_97
        // 30000 frames at 30000/1001 is exactly 1001 seconds.
        #expect(rate.time(ofFrame: 30000) == 1001)
        for frame in [0, 1, 29, 30, 1799, 107_892] {
            #expect(rate.frame(at: rate.time(ofFrame: frame)) == frame)
        }
    }

    @Test func snappingPicksTheNearestFrame() {
        #expect(FrameRate.fps60.snapped(0.51 / 60) == 1.0 / 60)
        #expect(FrameRate.fps60.snapped(0.49 / 60) == 0)
    }

    @Test func frameCountRoundsToTheNearestFrame() {
        #expect(Composition(frameRate: .fps60, duration: 5).frameCount == 300)
        #expect(Composition(frameRate: .fps29_97, duration: 5).frameCount == 150)
        #expect(Composition(frameRate: .fps60, duration: 0.001).frameCount == 1)
    }

    @Test func labels() {
        #expect(FrameRate.fps60.label == "60")
        #expect(FrameRate.fps29_97.label == "29.97")
        #expect(FrameRate.fps23_976.label == "23.98")
    }
}

@Suite struct GeometryTests {
    @Test func hexRoundTrips() throws {
        let color = try #require(RGBA(hex: "#1B8F51"))
        #expect(color.hex6 == "1B8F51")
        #expect(color.a == 1)
        #expect(RGBA(hex: "00000080")?.a == 128.0 / 255)
        #expect(RGBA(hex: "nope") == nil)
    }

    @Test func keyframesStaySorted() {
        var property = AnimatableProperty(0.0, keyframes: [
            Keyframe(time: 2, value: 2), Keyframe(time: 1, value: 1),
        ])
        #expect(property.keyframes.map(\.time) == [1, 2])
        property.setKeyframes([Keyframe(time: 5, value: 0), Keyframe(time: 0, value: 0)])
        #expect(property.keyframes.map(\.time) == [0, 5])
    }
}

@Suite struct LayerTreeTests {
    private func project() -> (Project, group: UUID, child: UUID, top: UUID) {
        let child = Layer(name: "Child", content: .shape(ShapeContent(geometry: .ellipse)),
                          size: Size2(10, 10), position: .zero, outPoint: 1)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          size: Size2(10, 10), position: .zero, outPoint: 1)
        let top = Layer(name: "Top", content: .shape(ShapeContent(geometry: .line)),
                        size: Size2(10, 0), position: .zero, outPoint: 1)
        return (Project(layers: [group, top]), group.id, child.id, top.id)
    }

    @Test func findsLayersAtAnyDepth() {
        let (p, group, child, top) = project()
        #expect(p.layer(withID: child)?.name == "Child")
        #expect(p.location(of: child)?.parentID == group)
        #expect(p.location(of: top)?.index == 1)
        #expect(p.ancestors(of: child) == [group])
        #expect(p.allLayers.map(\.name) == ["Group", "Child", "Top"])
    }

    @Test func updatesInsideGroups() {
        var (p, _, child, _) = project()
        let found = p.updateLayer(child) { $0.name = "Renamed" }
        let missing = p.updateLayer(UUID()) { _ in }
        #expect(found && !missing)
        #expect(p.layer(withID: child)?.name == "Renamed")
    }

    @Test func insertsIntoGroupsOnly() {
        var (p, group, _, top) = project()
        let new = Layer(name: "New", content: .shape(ShapeContent(geometry: .ellipse)),
                        size: Size2(1, 1), position: .zero, outPoint: 1)
        let intoShape = p.insertLayer(new, parentID: top, at: nil)
        let intoGroup = p.insertLayer(new, parentID: group, at: 0)
        #expect(!intoShape && intoGroup)
        #expect(p.layer(withID: group)?.children.first?.name == "New")
    }
}
