import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

private func shape(_ geometry: ShapeGeometry, size: Size2 = Size2(100, 100)) -> Layer {
    Layer(name: "S", content: .shape(ShapeContent(geometry: geometry, fills: [Fill(paint: .color(.white))])),
          size: size, position: Vec2(200, 200))
}

@Suite struct CornerEditingTests {
    @Test func aRectanglesPickedCornersChangeAndItStaysARectangle() {
        let layer = shape(.rectangle(cornerRadii: .zero))
        let (edited, _) = CornerEditing.setting(12, at: [PointRef(0, 1), PointRef(0, 3)], of: layer, actions: [])
        #expect(edited.look?.geometry == .rectangle(cornerRadii: CornerRadii(topLeft: 0, topRight: 12, bottomRight: 0, bottomLeft: 12)))
        #expect(CornerEditing.radii(of: edited, at: nil) == [0, 12, 0, 12])
    }

    @Test func aPolygonStaysOneUntilItsPointsDiffer() {
        let layer = shape(.polygon(sides: 5, cornerRadius: 0))
        let all = CornerEditing.setting(8, at: nil, of: layer, actions: []).layer
        #expect(all.look?.geometry == .polygon(sides: 5, cornerRadius: 8))
        let one = CornerEditing.setting(20, at: [PointRef(0, 0)], of: all, actions: []).layer
        guard case .path(let path)? = one.look?.geometry else { Issue.record("not a path"); return }
        #expect(path.subpaths[0].points.map(\.cornerRadius) == [20, 8, 8, 8, 8])
        // Its points stay where they were on screen.
        let before = evaluateDesign(Project(layers: [all])).layers[0]
        let after = evaluateDesign(Project(layers: [one])).layers[0]
        let top = after.transform.apply(path.subpaths[0].points[0].position)
        #expect(abs(top.x - before.transform.apply(Vec2(50, 0)).x) < 1e-6)
        #expect(abs(top.y - before.transform.apply(Vec2(50, 0)).y) < 1e-6)
    }

    @Test func aPathsPointTakesItsOwnRadiusAndItsPathActionsFollow() {
        let path = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(100, 0)),
                                                         PathPoint(Vec2(0, 100))], isClosed: true)])
        let layer = shape(.path(path))
        var moved = path
        moved.subpaths[0].points[1].position = Vec2(150, 0)
        let action = Action(target: layer.id, start: 0, duration: 1, spec: .path(PathAction(end: moved)))
        let (edited, actions) = CornerEditing.setting(10, at: [PointRef(0, 1)], of: layer, actions: [action])
        #expect(CornerEditing.radii(of: edited, at: nil) == [0, 10, 0])
        #expect(edited.size == layer.size)
        guard case .path(let p)? = actions.first?.spec else { Issue.record("no action"); return }
        #expect(p.end.subpaths[0].points[1].cornerRadius == 10)
        #expect(p.end.subpaths[0].points[1].position == Vec2(150, 0))
    }

    @Test func aRoundedShapesPointsAreItsSharpCorners() {
        let layer = shape(.rectangle(cornerRadii: CornerRadii(all: 10)))
        let points = PathEditing.path(of: layer)!
        #expect(points.subpaths[0].points.count == 4)
        #expect(points.subpaths[0].points.allSatisfy { $0.cornerRadius == 10 })
        #expect(!CornerEditing.hasCorners(shape(.ellipse(arc: .full))))
    }
}
