import Foundation
import Testing
import MotionModel
@testable import MotionEditing

/// Any app can write to the clipboard: copied actions are held in range as
/// a project file's are (4 October 2026).
@Suite struct ClipboardSafetyTests {
    @Test func copiedActionsAreHeldInRange() throws {
        let action = Action(target: UUID(), start: 1.375, duration: 2.875, spec: .volume(VolumeAction(end: 0)))
        var json = String(decoding: try JSONEncoder().encode(ActionClipboard(actions: [action])), as: UTF8.self)
        json = json.replacingOccurrences(of: "1.375", with: "-1e300").replacingOccurrences(of: "2.875", with: "1e400")
        let read = try #require(ActionClipboard.read(Data(json.utf8)))
        #expect(read.actions.first?.start == 0)
        #expect(read.actions.first?.duration == Composition.longest)
        #expect(ActionClipboard.read(Data("not json".utf8)) == nil)
    }
}
