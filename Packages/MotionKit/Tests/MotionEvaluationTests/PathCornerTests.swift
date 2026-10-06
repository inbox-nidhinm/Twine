import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

private func near(_ a: Vec2, _ b: Vec2, _ tolerance: Double = 1e-6) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

@Suite struct PathCornerTests {
    @Test func aRoundedRectangleOfPointsDrawsAsTheRectangleDoes() {
        let size = Size2(120, 80)
        let radii = CornerRadii(topLeft: 10, topRight: 0, bottomRight: 30, bottomLeft: 60)
        let drawn = ShapePaths.rectanglePoints(size, radii: radii).roundingCorners()
        let rect = ShapePaths.rectangle(size, radii: radii)
        #expect(drawn.subpaths[0].points.count == rect.subpaths[0].points.count)
        for (a, b) in zip(drawn.subpaths[0].points, rect.subpaths[0].points) {
            #expect(near(a.position, b.position))
            #expect(near(a.inHandle, b.inHandle))
            #expect(near(a.outHandle, b.outHandle))
        }
    }

    @Test func onlyPointsWithARadiusAreRounded() {
        var square = ShapePaths.rectanglePoints(Size2(100, 100), radii: .zero)
        #expect(square.roundingCorners() == square)
        square.subpaths[0].points[2].cornerRadius = 20
        let drawn = square.roundingCorners().subpaths[0].points
        #expect(drawn.count == 5)
        // The bottom right corner, cut 20 along each side.
        #expect(near(drawn[2].position, Vec2(100, 80)))
        #expect(near(drawn[3].position, Vec2(80, 100)))
        #expect(near(drawn[2].outHandle, Vec2(0, 20 * ShapePaths.kappa)))
        #expect(drawn[3].cornerRadius == 0)
    }

    @Test func aRadiusIsHeldToHalfOfEachSide() {
        let drawn = ShapePaths.polygon(Size2(100, 100), sides: 3, cornerRadius: 1e9).subpaths[0].points
        #expect(drawn.count == 6)
        // Two neighbouring corners meet at the middle of their side.
        #expect(near(drawn[1].position, drawn[2].position, 1e-6))
    }

    @Test func smoothPointsAndOpenEndsAreLeftAlone() {
        let line = BezierPath(subpaths: [Subpath(points: [
            PathPoint(Vec2(0, 0), cornerRadius: 10),
            PathPoint(Vec2(50, 0), inHandle: Vec2(-10, 0), outHandle: Vec2(10, 0), cornerRadius: 10),
            PathPoint(Vec2(100, 0), cornerRadius: 10),
        ], isClosed: false)])
        let drawn = line.roundingCorners().subpaths[0].points
        #expect(drawn.count == 3)
        #expect(drawn.map(\.position) == line.subpaths[0].points.map(\.position))
    }

    @Test func aCornerBetweenCurvesStaysOnTheCurves() {
        // A lens: two curves meeting at sharp points left and right.
        var lens = BezierPath(subpaths: [Subpath(points: [
            PathPoint(Vec2(0, 50), outHandle: Vec2(30, -50)),
            PathPoint(Vec2(200, 50), inHandle: Vec2(-30, -50), outHandle: Vec2(-30, 50)),
        ], isClosed: true)])
        lens.subpaths[0].points[0].inHandle = Vec2(30, 50)
        lens.subpaths[0].points[1].cornerRadius = 15
        let drawn = lens.roundingCorners().subpaths[0].points
        #expect(drawn.count == 3)
        // The cuts lie on the original curves, either side of the corner.
        let top = PathCorners.Piece(p0: Vec2(0, 50), c1: Vec2(30, 0), c2: Vec2(170, 0), p1: Vec2(200, 50), isStraight: false)
        let onTop = (0...400).map { top.point(at: Double($0) / 400) }.contains { near($0, drawn[1].position, 0.5) }
        #expect(onTop)
        #expect(drawn[1].position.x < 200 && drawn[2].position.x < 200)
        #expect(abs(drawn[1].position.y - (100 - drawn[2].position.y)) < 0.5)
    }

    @Test func pointRadiiBlendAndSurviveAFile() throws {
        let a = BezierPath(subpaths: [Subpath(points: [PathPoint(.zero, cornerRadius: 0), PathPoint(Vec2(1, 0), cornerRadius: 8)], isClosed: false)])
        var b = a
        b.subpaths[0].points[0].cornerRadius = 10
        #expect(BezierPath.interpolate(a, b, 0.5).subpaths[0].points[0].cornerRadius == 5)
        let data = try JSONEncoder().encode(a)
        #expect(try JSONDecoder().decode(BezierPath.self, from: data) == a)
        // A sharp point writes no radius, so older files read as they were.
        let sharp = try JSONEncoder().encode(PathPoint(.zero))
        #expect(!String(decoding: sharp, as: UTF8.self).contains("cornerRadius"))
    }

    @Test func aPolygonTakesTheCornerRadiusAction() {
        let layer = Layer(name: "P", content: .shape(ShapeContent(geometry: .polygon(sides: 5, cornerRadius: 4))),
                          size: Size2(100, 100), position: .zero)
        #expect(LayerState(design: layer).cornerRadii == CornerRadii(all: 4))
        let file = try? JSONEncoder().encode(ShapeGeometry.polygon(sides: 5, cornerRadius: 4))
        #expect(file.flatMap { try? JSONDecoder().decode(ShapeGeometry.self, from: $0) } == .polygon(sides: 5, cornerRadius: 4))
        let old = Data(#"{"type":"polygon","sides":7}"#.utf8)
        #expect((try? JSONDecoder().decode(ShapeGeometry.self, from: old)) == .polygon(sides: 7, cornerRadius: 0))
    }
}
