import Foundation
import Testing
@testable import MotionModel

/// Frames in 3D and Z, as files keep them.
@Suite struct Space3DModelTests {
    private func frame(_ space: Space3D?) -> Layer {
        Layer(name: "F", content: .group(GroupContent(children: [], frame: FrameStyle(space: space))),
              size: Size2(400, 300), position: Vec2(200, 150))
    }

    @Test func aNewSpaceWritesNothingButItsPresence() throws {
        let data = try JSONEncoder().encode(Space3D())
        #expect(String(decoding: data, as: UTF8.self) == "{}")
        #expect(try JSONDecoder().decode(Space3D.self, from: data) == Space3D())
    }

    @Test func aSpaceKeepsEverythingSet() throws {
        let space = Space3D(distance: 800, isIsometric: true, vanishingPoint: Vec2(0.25, 0.75),
                            depthFade: 0.4, depthBlur: 6, backOpacity: 0.3)
        let back = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(frame(space)))
        #expect(back.space3D == space)
    }

    @Test func flatFramesAndLayersAtZeroWriteNothingNew() throws {
        let json = String(decoding: try JSONEncoder().encode(frame(nil)), as: UTF8.self)
        #expect(!json.contains("space"))
        #expect(!json.contains("\"z\""))
        var layer = frame(nil)
        layer.transform.z = -120
        let back = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer))
        #expect(back.transform.z == -120)
    }

    @Test func spaceIsSetOnlyOnFrames() {
        var f = frame(nil)
        f.space3D = Space3D(distance: 600)
        #expect(f.space3D?.distance == 600)
        // Its look can change without losing it.
        f.look = ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .color(.black))])
        #expect(f.space3D?.distance == 600)
        var group = Layer(name: "G", content: .group(GroupContent()), size: Size2(10, 10), position: .zero)
        group.space3D = Space3D()
        #expect(group.space3D == nil)
    }

    @Test func aLayerKnowsTheSpaceItIsPlacedIn() {
        let card = Layer(name: "C", content: .group(GroupContent()), size: Size2(10, 10), position: .zero)
        var f = frame(Space3D())
        f.children = [card]
        let flat = Layer(name: "Flat", content: .group(GroupContent(children: [f])), size: Size2(10, 10), position: .zero)
        let project = Project(composition: Composition(width: 400, height: 300), layers: [flat])
        #expect(project.space3D(holding: card.id) == Space3D())
        #expect(project.space3D(holding: f.id) == nil)
        #expect(project.space3D(holding: flat.id) == nil)
    }

    @Test func filesBeforeSixReadAsFlat() throws {
        // A format 5 file carries no space or Z; it reads, and is written
        // back as 6.
        let project = Project(composition: Composition(width: 400, height: 300), layers: [frame(nil)])
        let data = try ProjectFormat.encode(project)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["formatVersion"] = 5
        let read = try ProjectFormat.decode(JSONSerialization.data(withJSONObject: object))
        #expect(read.layers.first?.space3D == nil)
        #expect(read.layers.first?.transform.z == 0)
        #expect(ProjectFormat.currentVersion >= 6)
    }
}
