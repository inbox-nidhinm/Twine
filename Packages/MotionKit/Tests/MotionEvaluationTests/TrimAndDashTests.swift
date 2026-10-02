import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// A 100 pixel level line, (0, 0) to (100, 0).
private let line = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(100, 0))], isClosed: false)])

private func ends(_ path: BezierPath) -> [[Double]] {
    path.subpaths.map { s in [s.points.first!.position.x, s.points.last!.position.x].map { ($0 * 1000).rounded() / 1000 } }
}

private func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-6 } }

/// A 100 pixel open line layer with a dashed 2 px stroke.
private func dashedLine(dotted: Bool = false) -> Layer {
    var stroke = Stroke(paint: .solid(.black), width: 2, dashPattern: [6, 4])
    stroke.dotted = dotted
    return Layer(name: "Line", content: .shape(ShapeContent(geometry: .path(line), fills: [], strokes: [stroke])),
                 size: Size2(100, 0), position: .zero)
}

private func stroke(_ layer: Layer, _ actions: [Action], at time: Double) -> ResolvedStroke? {
    if case .shape(let s) = evaluate(Project(layers: [layer], actions: actions), at: time).layers[0].content { return s.strokes.first }
    return nil
}

@Suite struct TrimAndDashTests {
    @Test func eachWayShowsItsOwnStretches() {
        func pieces(_ d: TrimDirection, _ a: Double, growing: Bool) -> [[Double]] {
            ends(PathTrim.trimmed(line, TrimRange(direction: d, amount: a), growing: growing).path)
        }
        #expect(pieces(.startToEnd, 0.3, growing: false) == [[0, 30]])
        #expect(pieces(.endToStart, 0.3, growing: false) == [[70, 100]])
        #expect(pieces(.toMiddle, 0.4, growing: false) == [[0, 20], [80, 100]])
        #expect(pieces(.fromMiddle, 0.4, growing: false) == [[30, 50], [50, 70]])
        // Growing, each stretch runs from where it starts to its tip.
        #expect(pieces(.endToStart, 0.3, growing: true) == [[100, 70]])
        #expect(pieces(.toMiddle, 0.4, growing: true) == [[0, 20], [100, 80]])
        #expect(pieces(.fromMiddle, 0.4, growing: true) == [[50, 30], [50, 70]])
        // None shows nothing; all of it the way it runs is the path itself.
        #expect(PathTrim.trimmed(line, TrimRange(amount: 0), growing: false).path.subpaths.isEmpty)
        #expect(PathTrim.trimmed(line, .whole, growing: false).path == line)
    }

    @Test func dashesStayPutAsATrimGrowsUnlessTheyFollowIt() {
        // Laid from the path's start, the far stretch's pattern starts 80 in.
        #expect(near(PathTrim.trimmed(line, TrimRange(direction: .toMiddle, amount: 0.4), growing: false).starts, [0, 80]))
        // Following the trim, each stretch lays it from its own start.
        #expect(near(PathTrim.trimmed(line, TrimRange(direction: .toMiddle, amount: 0.4), growing: true).starts, [0, 0]))
    }

    @Test func aCurveIsCutWhereItsLengthSays() {
        // A half circle of radius 50 from (0, 0) over to (100, 0).
        let k = 0.5522847498 * 50
        let arc = BezierPath(subpaths: [Subpath(points: [
            PathPoint(Vec2(0, 0), outHandle: Vec2(0, -k)),
            PathPoint(Vec2(50, -50), inHandle: Vec2(-k, 0), outHandle: Vec2(k, 0)),
            PathPoint(Vec2(100, 0), inHandle: Vec2(0, -k)),
        ], isClosed: false)])
        let half = PathTrim.trimmed(arc, TrimRange(amount: 0.5), growing: false).path
        let tip = half.subpaths[0].points.last!.position
        #expect(abs(tip.x - 50) < 0.5 && abs(tip.y + 50) < 0.5)
    }

    @Test func olderTrimsReadAsTheNearestWay() throws {
        let stroke = #"{"id":"6E1C5F2E-5D0B-4B0E-9C7C-2B8B6B4B9C11","isEnabled":true,"paint":{"type":"solid","color":{"r":0,"g":0,"b":0,"a":1}},"width":2,"alignment":"center","cap":"butt","join":"miter","dashPattern":[],"dashOffset":0,"trimStart":0.25,"trimEnd":1}"#
        let read = try JSONDecoder().decode(Stroke.self, from: Data(stroke.utf8))
        #expect(read.trim == TrimRange(direction: .endToStart, amount: 0.75))
        // An old wipe, all of it to none at the end, plays from the start forwards still.
        let wipe = #"{"initial":{"start":0,"end":1},"end":{"start":1,"end":1}}"#
        let action = try JSONDecoder().decode(TrimAction.self, from: Data(wipe.utf8))
        #expect(action.initial == TrimRange(direction: .endToStart, amount: 1))
        #expect(action.end == TrimRange(direction: .endToStart, amount: 0))
        // An old draw-on.
        let drawOn = #"{"initial":{"start":0,"end":0},"end":{"start":0,"end":1}}"#
        let on = try JSONDecoder().decode(TrimAction.self, from: Data(drawOn.utf8))
        #expect(on.initial == TrimRange(amount: 0) && on.end == .whole)
        // Written again, a whole trim and solid lines leave nothing new in the file.
        let written = String(decoding: try JSONEncoder().encode(read), as: UTF8.self)
        #expect(written.contains("\"trim\"") && !written.contains("trimStart") && !written.contains("dotted"))
    }

    @Test func dashesTravelForTheirBar() {
        let layer = dashedLine()
        let forward = Action(target: layer.id, start: 0, duration: 2, easing: .linear, spec: .dash(DashAction(speed: 10)))
        // 10 px a second for a second: the pattern (10 long) has come round.
        #expect(abs((stroke(layer, [forward], at: 0.5)?.dashOffset ?? 0) - 5) < 1e-6)
        let tracks = ActionTracks([forward])
        #expect(abs(tracks.state(of: layer, at: 1).dash.distance - 10) < 1e-6)
        // It stops where the bar ends.
        #expect(abs(tracks.state(of: layer, at: 5).dash.distance - 20) < 1e-6)
        var back = forward
        back.spec = .dash(DashAction(speed: 10, direction: .backward))
        #expect(abs(ActionTracks([back]).state(of: layer, at: 1).dash.distance + 10) < 1e-6)
        // Following the trim, the trim sets the way, and the stroke is cut
        // into stretches even when it is all drawn.
        var follow = forward
        follow.spec = .dash(DashAction(speed: 10, direction: .backward, followsTrim: true))
        #expect(ActionTracks([follow]).state(of: layer, at: 1).dash == DashTravel(distance: 10, followsTrim: true))
        #expect(stroke(layer, [follow], at: 1)?.trimmed != nil)
    }

    @Test func dotsAreRoundDashesOfNoLength() {
        let s = stroke(dashedLine(dotted: true), [], at: 0)
        // The gap is the clear space between dots, so they sit gap plus width apart.
        #expect(s?.dashPattern == [0, 6] && s?.cap == .round)
    }
}
