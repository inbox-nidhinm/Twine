import Foundation
import Testing
import MotionModel
@testable import MotionEditing

@Suite struct GradientEditingTests {
    private let redToBlue = Gradient(stops: [GradientStop(position: 0, color: RGBA(1, 0, 0)),
                                             GradientStop(position: 1, color: RGBA(0, 0, 1, 0))])

    @Test func aNewStopTakesTheColourAlreadyThere() {
        let (g, index) = GradientEditing.adding(to: redToBlue, at: 0.25)
        #expect(index == 2 && g.stops.count == 3)
        #expect(g.stops[2] == GradientStop(position: 0.25, color: RGBA(0.75, 0, 0.25, 0.75)))
        // Outside the stops, the nearest end's colour.
        let late = GradientEditing.adding(to: GradientEditing.moving(1, in: redToBlue, to: 0.5), at: 0.9).gradient
        #expect(late.stops[2].color == RGBA(0, 0, 1, 0))
    }

    @Test func theTwoEndStopsAreNeverRemoved() {
        #expect(GradientEditing.removing(0, from: redToBlue) == nil)
        let three = GradientEditing.adding(to: redToBlue, at: 0.5).gradient
        #expect(GradientEditing.removing(0, from: three)?.stops.map(\.position) == [1, 0.5])
        #expect(GradientEditing.removing(7, from: three) == nil)
    }

    @Test func stopsKeepTheirIndexWhenMovedPastEachOther() {
        let three = GradientEditing.adding(to: redToBlue, at: 0.5).gradient
        let moved = GradientEditing.moving(0, in: three, to: 0.8)
        #expect(moved.stops[0].position == 0.8)
        #expect(GradientEditing.order(of: moved) == [2, 0, 1])
        #expect(GradientEditing.moving(2, in: three, to: 3).stops[2].position == 1)
        #expect(GradientEditing.moving(2, in: three, to: -.infinity).stops[2].position == 0)
    }

    @Test func reversingPutsEveryStopAtTheOtherSide() {
        let three = GradientEditing.adding(to: redToBlue, at: 0.25).gradient
        #expect(GradientEditing.reversed(three).stops.map(\.position) == [1, 0, 0.75])
    }

    @Test func aPointIsPlacedAlongTheLine() {
        #expect(GradientEditing.position(of: Vec2(5, 3), from: Vec2(0, 0), to: Vec2(10, 0)) == 0.5)
        #expect(GradientEditing.position(of: Vec2(-4, 0), from: Vec2(0, 0), to: Vec2(10, 0)) == 0)
        #expect(GradientEditing.position(of: Vec2(1, 1), from: Vec2(2, 2), to: Vec2(2, 2)) == 0)
    }

    @Test func shiftKeepsAnEndToFifteenDegreeSteps() {
        let p = GradientEditing.snapped(Vec2(10, 1), around: .zero)
        #expect(abs(p.x - (101.0).squareRoot()) < 1e-9 && abs(p.y) < 1e-9)
        let q = GradientEditing.snapped(Vec2(7, 7.5), around: .zero)
        #expect(abs(atan2(q.y, q.x) * 180 / .pi - 45) < 1e-9)
    }

    @Test func theThirdHandleSetsHowFarTheOvalReachesAcross() {
        // A 200 by 100 box, the line from the centre to the right edge: 100 px.
        let size = Size2(200, 100)
        var g = Gradient(stops: [], start: Vec2(0.5, 0.5), end: Vec2(1, 0.5))
        // A circle's third handle is 100 px below the centre: a whole box down.
        let p = GradientEditing.acrossPoint(of: g, in: size)
        #expect(abs(p.x - 0.5) < 1e-9 && abs(p.y - 1.5) < 1e-9)
        // Dragged to 40 px below (sideways along the line counts for nothing).
        g = GradientEditing.reachingAcross(g, to: Vec2(0.7, 0.9), in: size)
        #expect(abs(g.aspect - 0.4) < 1e-9)
        #expect(g.end == Vec2(1, 0.5))
        let q = GradientEditing.acrossPoint(of: g, in: size)
        #expect(abs(q.y - 0.9) < 1e-9)
        // Back to the line: as thin as it goes, never nothing.
        #expect(GradientEditing.reachingAcross(g, to: Vec2(0.2, 0.5), in: size).aspect == Gradient.aspects.lowerBound)
    }

    @Test func aCircleKeepsNoReachAcrossInItsFile() throws {
        var g = Gradient(stops: [], start: Vec2(0.5, 0.5), end: Vec2(1, 0.5))
        #expect(g.across == nil)
        g.aspect = 1
        #expect(g.across == nil)
        #expect(!String(decoding: try JSONEncoder().encode(g), as: UTF8.self).contains("across"))
        g.aspect = 0.5
        let back = try JSONDecoder().decode(Gradient.self, from: try JSONEncoder().encode(g))
        #expect(back.aspect == 0.5)
    }

    @Test func anOvalFromTwoAxesKeepsItsReachAcrossInPixels() {
        // SVG's and Figma's own way: the ends of both axes. A circle of half
        // the box in a 200 by 100 box is an oval twice as wide as tall.
        let g = Gradient.radial(stops: [], center: Vec2(0.5, 0.5), edge: Vec2(1, 0.5), edgeAcross: Vec2(0.5, 1),
                                in: Size2(200, 100))
        #expect(abs(g.aspect - 0.5) < 1e-9)
        let square = Gradient.radial(stops: [], center: Vec2(0.5, 0.5), edge: Vec2(1, 0.5), edgeAcross: Vec2(0.5, 1),
                                     in: Size2(100, 100))
        #expect(square.across == nil)
    }
}
