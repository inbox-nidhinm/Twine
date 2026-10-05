import Foundation
import Testing
@testable import MotionEditing

@Suite struct CommandSearchTests {
    private func rank(_ query: String, _ titles: [String]) -> [String] {
        titles.compactMap { t in SearchMatch.score(query, in: t).map { (t, $0) } }
            .sorted { $0.1 > $1.1 }.map(\.0)
    }

    @Test func theWholeNameAndItsStartComeFirst() {
        #expect(rank("fade", ["Blur & Fade", "Fade Out", "Fade In", "Fade"]) == ["Fade", "Fade In", "Fade Out", "Blur & Fade"])
        #expect(rank("out", ["Fade Out", "Zoom Out", "Layout"]).prefix(2).sorted() == ["Fade Out", "Zoom Out"])
    }

    @Test func initialsWordsAndLettersInOrderMatch() {
        #expect(SearchMatch.score("bf", in: "Bring Forward") != nil)
        #expect(SearchMatch.score("forw bring", in: "Bring Forward") != nil)
        #expect(SearchMatch.score("brfw", in: "Bring Forward") != nil)
        #expect(SearchMatch.score("xyz", in: "Bring Forward") == nil)
        // One letter only matches a word's start, not anything containing it.
        #expect(SearchMatch.score("q", in: "Bring Forward") == nil)
        #expect(SearchMatch.score("BÉZIER", in: "bezier path") != nil)
    }

    @Test func keywordsMatchBelowTheName() throws {
        let byKeyword = try #require(SearchMatch.score("snapping", in: "Smart Guides", keywords: ["snapping"]))
        let byName = try #require(SearchMatch.score("smart guides", in: "Smart Guides"))
        #expect(byKeyword < byName)
    }

    @Test func timesAndFrames() {
        #expect(TypedEntry.parse("2.5s") == [.time(2.5)])
        #expect(TypedEntry.parse("2.5 sec") == [.time(2.5)])
        #expect(TypedEntry.parse("1:05.5") == [.time(65.5)])
        #expect(TypedEntry.parse("f120") == [.frame(120)])
        #expect(TypedEntry.parse("frame 12") == [.frame(12)])
        #expect(TypedEntry.parse("30f") == [.frame(30)])
        #expect(TypedEntry.parse("3") == [.time(3)])
        #expect(TypedEntry.parse("3", framesShown: true) == [.frame(3), .time(3)])
        #expect(TypedEntry.parse("fade").isEmpty)
        #expect(TypedEntry.parse("1:75").isEmpty)
    }

    @Test func propertiesByTheirNamesAndShortNames() {
        #expect(TypedEntry.parse("opacity 50") == [.property(.opacity, 50)])
        #expect(TypedEntry.parse("op 50%") == [.property(.opacity, 50)])
        #expect(TypedEntry.parse("w 400") == [.property(.width, 400)])
        #expect(TypedEntry.parse("W:400px") == [.property(.width, 400)])
        #expect(TypedEntry.parse("rot = 45°") == [.property(.rotation, 45)])
        #expect(TypedEntry.parse("x -20") == [.property(.x, -20)])
        #expect(TypedEntry.parse("corner radius 8") == [.property(.radius, 8)])
        #expect(TypedEntry.parse("length 6s") == [.property(.duration, 6)])
        #expect(TypedEntry.parse("scale .5") == [.property(.scale, 0.5)])
        // Unknown names, single letters that are no name, and huge numbers are nothing.
        #expect(TypedEntry.parse("q 5").isEmpty)
        #expect(TypedEntry.parse("blorp 5").isEmpty)
        #expect(TypedEntry.parse("x 1e99").isEmpty)
        #expect(TypedEntry.parse("x 99999999999").isEmpty)
    }
}
