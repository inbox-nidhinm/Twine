import Foundation
import Testing
@testable import MotionModel

/// Files put together by hand or by another tool: each opens as something
/// Twine's own commands can go on to edit.
@Suite struct DamagedFileTests {
    private func shape(_ name: String, id: UUID = UUID()) -> Layer {
        Layer(id: id, name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero))),
              size: Size2(10, 10), position: .zero)
    }

    private func reopened(_ project: Project) throws -> Project {
        try ProjectFormat.decode(try ProjectFormat.encode(project))
    }

    @Test func repeatedIDsAreMadeTheirOwn() throws {
        let twin = UUID()
        let inner = Layer(name: "Group", content: .group(GroupContent(children: [shape("Inside", id: twin)])),
                          size: Size2(10, 10), position: .zero)
        let first = shape("First", id: twin)
        let move = Action(target: twin, start: 0, duration: 1, spec: .move(MoveAction(mode: .by, end: Vec2(1, 0))))
        var again = move
        again.start = 2
        let project = try reopened(Project(layers: [first, inner, shape("Second", id: twin)], actions: [move, again]))

        var ids: [UUID] = []
        project.forEachLayer { ids.append($0.id) }
        #expect(Set(ids).count == ids.count)
        // The first keeps the id, and the actions that name it.
        #expect(project.layers[0].id == twin && project.layers[0].name == "First")
        #expect(Set(project.actions.map(\.id)).count == 2)
        #expect(project.actions.allSatisfy { $0.targetLayerID == twin })
        #expect(project.actions.map(\.start) == [0, 2])

        // A project with nothing repeated comes through as it was.
        let sound = Project(layers: [shape("A"), shape("B")], actions: [])
        #expect(try reopened(sound) == sound)
    }

    @Test func aSceneOfNoLengthOrAnAbsurdRateIsMadeUsable() throws {
        var project = Project(layers: [shape("A")])
        project.composition.duration = 0
        let opened = try reopened(project)
        #expect(opened.composition.duration > 0)

        let json = String(decoding: try ProjectFormat.encode(Project(layers: [shape("A")])), as: UTF8.self)
        let rate = try #require(json.range(of: #""frameRate"\s*:\s*\{[^}]*\}"#, options: .regularExpression))
        let slow = json.replacingCharacters(in: rate, with: #""frameRate":{"frames":1,"seconds":900000000}"#)
        #expect(try ProjectFormat.decode(Data(slow.utf8)).composition.frameRate == .fps30)
    }

    @Test func onlyWhatCanMaskIsAMask() throws {
        var sound = Layer(name: "Sound", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)
        sound.isMask = true
        var mask = shape("Mask")
        mask.isMask = true
        let opened = try reopened(Project(layers: [sound, mask, shape("Shown")]))
        #expect(opened.layers.map(\.isMask) == [false, true, false])
    }
}
