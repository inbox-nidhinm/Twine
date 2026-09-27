import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

/// A right-angled triangle with sharp corners at (0,0), (100,0), (0,100).
private let triangle = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(100, 0)),
                                                              PathPoint(Vec2(0, 100))], isClosed: true)])

private func near(_ a: Vec2, _ b: Vec2, _ tolerance: Double = 1e-6) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

private func geometry(_ layer: Layer) -> BezierPath? {
    if case .shape(let s) = layer.content, case .path(let p) = s.geometry { return p }
    return nil
}

@Suite struct PathEditingTests {
    @Test func boundsFollowTheCurveNotItsHandles() {
        // A hump from (0,0) to (100,0) whose handles reach up to y = -100:
        // the curve itself peaks at 75% of that.
        let hump = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0), outHandle: Vec2(0, -100)),
                                                          PathPoint(Vec2(100, 0), inHandle: Vec2(0, -100))], isClosed: false)])
        let box = PathEditing.bounds(of: hump)!
        #expect(abs(box.minY + 75) < 1e-6)
        #expect(box.minX == 0 && box.maxX == 100 && box.maxY == 0)
    }

    @Test func insertingAPointKeepsTheCurve() {
        let curve = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0), outHandle: Vec2(30, -60)),
                                                           PathPoint(Vec2(100, 0), inHandle: Vec2(-30, -60))], isClosed: false)])
        let before = PathEditing.segment(PointRef(0, 0), in: curve)
        let (split, added) = PathEditing.inserting(on: PointRef(0, 0), at: 0.3, in: curve)
        #expect(added == PointRef(0, 1))
        #expect(split.subpaths[0].points.count == 3)
        #expect(near(split.subpaths[0].points[1].position, before.point(at: 0.3)))
        // Each half traces its part of the original.
        let first = PathEditing.segment(PointRef(0, 0), in: split), second = PathEditing.segment(PointRef(0, 1), in: split)
        #expect(near(first.point(at: 0.5), before.point(at: 0.15)))
        #expect(near(second.point(at: 0.5), before.point(at: 0.65)))
    }

    @Test func aPointOnAStraightSideStaysSharp() {
        let (split, added) = PathEditing.inserting(on: PointRef(0, 0), at: 0.5, in: triangle)
        let p = split.subpaths[0].points[added.index]
        #expect(p.position == Vec2(50, 0) && p.inHandle == .zero && p.outHandle == .zero)
    }

    @Test func nearestSegmentFindsTheSideUnderThePointer() {
        let hit = PathEditing.nearestSegment(in: triangle, to: Vec2(48, 50), tolerance: 5)
        // The long side from (100,0) back round to (0,100) passes through (50,50).
        #expect(hit?.ref == PointRef(0, 1))
        #expect(PathEditing.nearestSegment(in: triangle, to: Vec2(30, 30), tolerance: 5) == nil)
    }

    @Test func deletingJoinsAcrossTheGap() {
        let square = BezierPath(subpaths: [Subpath(points: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)].map { PathPoint($0) },
                                                   isClosed: true)])
        let three = PathEditing.deleting([PointRef(0, 1)], from: square)
        #expect(three.subpaths[0].points.map(\.position) == [Vec2(0, 0), Vec2(10, 10), Vec2(0, 10)])
        #expect(three.subpaths[0].isClosed)
        #expect(PathEditing.deleting([PointRef(0, 0), PointRef(0, 1)], from: square).subpaths[0].isClosed == false)
        #expect(PathEditing.deleting([PointRef(0, 0), PointRef(0, 1), PointRef(0, 2)], from: square).subpaths.isEmpty)
    }

    @Test func aSmoothPointStaysSmoothUnlessBroken() {
        let smooth = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)),
                                                            PathPoint(Vec2(50, 0), inHandle: Vec2(-20, 0), outHandle: Vec2(20, 0)),
                                                            PathPoint(Vec2(100, 0))], isClosed: false)])
        let ref = PointRef(0, 1)
        let turned = PathEditing.settingHandle(.outHandle, of: ref, in: smooth, to: Vec2(0, 30), independent: false)
        let p = PathEditing.point(ref, in: turned)!
        // Equal lengths stay equal: mirrored angle and length.
        #expect(near(p.inHandle, Vec2(0, -30)))
        let broken = PathEditing.settingHandle(.outHandle, of: ref, in: smooth, to: Vec2(0, 30), independent: true)
        #expect(PathEditing.point(ref, in: broken)!.inHandle == Vec2(-20, 0))

        // Unequal lengths keep their own length and only turn.
        var uneven = smooth
        uneven.subpaths[0].points[1].inHandle = Vec2(-10, 0)
        let turnedUneven = PathEditing.settingHandle(.outHandle, of: ref, in: uneven, to: Vec2(0, 30), independent: false)
        #expect(near(PathEditing.point(ref, in: turnedUneven)!.inHandle, Vec2(0, -10)))
    }

    @Test func bendingTogglesSharpAndSmooth() {
        let smooth = PathEditing.togglingSmooth(PointRef(0, 1), in: triangle)
        let p = PathEditing.point(PointRef(0, 1), in: smooth)!
        #expect(PathEditing.isSmooth(p))
        let sharp = PathEditing.togglingSmooth(PointRef(0, 1), in: smooth)
        #expect(PathEditing.point(PointRef(0, 1), in: sharp) == PathPoint(Vec2(100, 0)))
    }

    @Test func thePenAppendsClosesAndCarriesOn() {
        var path = BezierPath()
        path = PathEditing.appending(PathPoint(Vec2(0, 0)), to: path).path
        path = PathEditing.appending(PathPoint(Vec2(10, 0)), to: path).path
        let (three, last) = PathEditing.appending(PathPoint(Vec2(10, 10)), to: path)
        #expect(last == PointRef(0, 2))
        #expect(PathEditing.isOpenEnd(PointRef(0, 0), in: three) && PathEditing.isOpenEnd(last, in: three))
        #expect(!PathEditing.isOpenEnd(PointRef(0, 1), in: three))

        // Carrying on from the first point turns the path round.
        let (turned, end) = PathEditing.continuing(from: PointRef(0, 0), in: three)
        #expect(turned.subpaths[0].points.map(\.position) == [Vec2(10, 10), Vec2(10, 0), Vec2(0, 0)])
        #expect(end == PointRef(0, 2))

        let closed = PathEditing.closing(three, onto: PointRef(0, 0))
        #expect(closed.subpaths[0].isClosed)
        // A closed path starts a new subpath for the next point.
        #expect(PathEditing.appending(PathPoint(Vec2(50, 50)), to: closed).point == PointRef(1, 0))
    }

    @Test func closingOntoAnotherOpenPathJoinsThem() {
        let two = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(10, 0))], isClosed: false),
                                        Subpath(points: [PathPoint(Vec2(20, 0)), PathPoint(Vec2(30, 0))], isClosed: false)])
        let joined = PathEditing.closing(two, onto: PointRef(0, 1))
        #expect(joined.subpaths.count == 1)
        #expect(joined.subpaths[0].points.map(\.position) == [Vec2(20, 0), Vec2(30, 0), Vec2(10, 0), Vec2(0, 0)])
    }

    @Test func reshapingRefitsTheBoxWithoutMovingAnything() {
        var layer = LayerFactory.shape(.rectangle, in: Box(minX: 100, minY: 100, maxX: 200, maxY: 150), name: "R")
        layer.transform.rotation = 30
        layer.transform.scale = Vec2(2, 1)
        let before = Affine.layer(position: layer.transform.position, anchor: layer.transform.anchor,
                                  scale: layer.transform.scale, rotation: layer.transform.rotation)
        // Pull the bottom-right corner out and up past the top.
        var path = PathEditing.path(of: layer)!
        path = PathEditing.moving([PointRef(0, 2)], in: path, by: Vec2(40, -80))
        let corner = before.apply(path.subpaths[0].points[2].position)
        let (edited, shift) = PathEditing.reshaped(layer, to: path)
        let after = Affine.layer(position: edited.transform.position, anchor: edited.transform.anchor,
                                 scale: edited.transform.scale, rotation: edited.transform.rotation)
        let stored = geometry(edited)!
        #expect(near(after.apply(stored.subpaths[0].points[2].position), corner, 1e-9))
        #expect(near(after.apply(stored.subpaths[0].points[0].position), before.apply(.zero), 1e-9))
        #expect(edited.size == Size2(140, 80))
        #expect(shift == Vec2(0, 30))
        // The anchor stays in the middle of the box.
        #expect(edited.transform.anchor == Vec2(70, 40))
        #expect(PathEditing.bounds(of: stored) == Box(minX: 0, minY: 0, maxX: 140, maxY: 80))
    }

    @Test func pathActionsFollowARefit() {
        let layer = PathEditing.reshaped(LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), name: "R"),
                                         to: triangle).layer
        let action = Action(target: layer.id, start: 0, duration: 1, spec: .path(PathAction(end: triangle)))
        let grown = PathEditing.moving([PointRef(0, 0)], in: triangle, by: Vec2(-20, 0))
        let (_, moved) = PathEditing.reshaped(layer, to: grown, actions: [action])
        guard case .path(let p) = moved.first?.spec else { Issue.record("no path action moved"); return }
        #expect(p.end.subpaths[0].points[0].position == Vec2(20, 0))
    }

    @Test func aNewPathLooksLikeALineUntilClosed() {
        let layer = PathEditing.newPath(at: Vec2(40, 60), name: "Path 1")
        guard case .shape(let open) = layer.content else { Issue.record("not a shape"); return }
        #expect(open.fills.isEmpty && open.strokes.count == 1)
        guard case .shape(let closed) = PathEditing.styledForClosing(layer).content else { return }
        #expect(closed.strokes.isEmpty && closed.fills.count == 1)
        // A stroke the user changed survives closing.
        var styled = layer
        if case .shape(var s) = styled.content { s.strokes[0].width = 9; styled.content = .shape(s) }
        #expect(PathEditing.styledForClosing(styled) == styled)
    }

    @Test func aNewPathActionVisiblyChangesTheShape() {
        let rounded = PathEditing.reshapedForNewAction(triangle)
        #expect(PathEditing.refs(in: rounded).allSatisfy { PathEditing.isSmooth(PathEditing.point($0, in: rounded)!) })
        let sharpened = PathEditing.reshapedForNewAction(rounded)
        #expect(sharpened == triangle)
    }
}

@Suite struct PathFittingTests {
    /// A pen path layer drawn as a 100 by 100 triangle at (500, 500).
    private func pen() -> Layer {
        let rect = LayerFactory.shape(.rectangle, in: Box(minX: 450, minY: 450, maxX: 550, maxY: 550), name: "P")
        return PathEditing.reshaped(rect, to: triangle).layer
    }

    @Test func resizingADesignStretchesItsPoints() {
        var layer = pen()
        layer.size = Size2(200, 50)
        let drawn = PathEditing.path(of: layer)!
        #expect(drawn.subpaths[0].points.map(\.position) == [Vec2(0, 0), Vec2(200, 0), Vec2(0, 50)])
        let scene = evaluateDesign(Project(layers: [layer]))
        guard case .shape(let s) = scene.layers[0].content else { Issue.record("not a shape"); return }
        #expect(s.path == drawn)
    }

    @Test func editingAResizedPathKeepsItsPathActionsInPlace() {
        var layer = pen()
        let end = PathEditing.moving([PointRef(0, 1)], in: triangle, by: Vec2(50, 0))
        let action = Action(target: layer.id, start: 0, duration: 1, spec: .path(PathAction(end: end)))
        layer.size = Size2(200, 100)
        // Before the edit the action's end is drawn stretched: its second
        // point, 150 across in path space, lands at 300.
        let before = evaluate(Project(layers: [layer], actions: [action]), at: 2)
        guard case .shape(let s0) = before.layers[0].content else { return }
        #expect(s0.path.subpaths[0].points[1].position == Vec2(300, 0))
        // Moving the third point down refits the box; the action is carried
        // into the new space and still ends at the same place.
        let edited = PathEditing.moving([PointRef(0, 2)], in: PathEditing.path(of: layer)!, by: Vec2(0, 20))
        let (refit, moved) = PathEditing.reshaped(layer, to: edited, actions: [action])
        let after = evaluate(Project(layers: [refit], actions: moved), at: 2)
        guard case .shape(let s1) = after.layers[0].content else { return }
        #expect(s1.path.subpaths[0].points[1].position == Vec2(300, 0))
        #expect(refit.size == Size2(200, 120))
    }
}
