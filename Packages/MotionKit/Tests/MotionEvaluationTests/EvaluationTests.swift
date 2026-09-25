import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

private func rect(_ name: String = "Rect", at position: Vec2 = Vec2(100, 100), size: Size2 = Size2(50, 50)) -> Layer {
    Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                   fills: [Fill(paint: .color(.white))])),
          size: size, position: position)
}

@Suite struct InterpolationTests {
    @Test func vectorsAndSizes() {
        #expect(Vec2.interpolate(Vec2(0, 0), Vec2(10, -10), 0.25) == Vec2(2.5, -2.5))
        #expect(Size2.interpolate(Size2(0, 100), Size2(100, 0), 0.5) == Size2(50, 50))
        // Overshoot extrapolates rather than clamping.
        #expect(Double.interpolate(0, 10, 1.2) == 12)
    }

    @Test func coloursBlendPerceptuallyAndKeepTheirEnds() {
        let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1)
        let start = RGBA.interpolate(red, blue, 0), end = RGBA.interpolate(red, blue, 1)
        #expect(abs(start.r - 1) < 1e-6 && abs(start.b) < 1e-6)
        #expect(abs(end.b - 1) < 1e-6 && abs(end.r) < 1e-6)
        // OKLab passes through a purple that is brighter than the plain RGB
        // midpoint (0.5, 0, 0.5), which reads as muddy.
        let mid = RGBA.interpolate(red, blue, 0.5)
        #expect(mid.r > 0.5 && mid.b > 0.5)
        // Alpha is linear.
        #expect(abs(RGBA.interpolate(RGBA(0, 0, 0, 0), RGBA(0, 0, 0, 1), 0.3).a - 0.3) < 1e-9)
    }

    @Test func greyStaysGrey() {
        let mid = RGBA.interpolate(.black, .white, 0.5)
        #expect(abs(mid.r - mid.g) < 1e-6 && abs(mid.g - mid.b) < 1e-6)
    }

    @Test func gradientStopsBlendPairwiseOrHold() {
        let a = [GradientStop(position: 0, color: .black), GradientStop(position: 1, color: .white)]
        let b = [GradientStop(position: 0.5, color: .black), GradientStop(position: 1, color: .white)]
        #expect(abs([GradientStop].interpolate(a, b, 0.5)[0].position - 0.25) < 1e-12)
        let c = [GradientStop(position: 0, color: .black)]
        #expect([GradientStop].interpolate(a, c, 0.9) == a)
        #expect([GradientStop].interpolate(a, c, 1) == c)
    }

    @Test func radiiNeverGoNegative() {
        let r = CornerRadii.interpolate(CornerRadii(all: 0), CornerRadii(all: 10), -0.3)
        #expect(r.topLeft == 0)
    }
}

@Suite struct EvaluateTests {
    @Test func resolvesPropertiesAtTheTimeAsked() {
        let layer = rect()
        let project = Project(layers: [layer], actions: [
            Action(target: layer.id, start: 0, duration: 2, easing: .linear,
                   spec: .move(MoveAction(mode: .to, initial: .zero, end: Vec2(200, 100)))),
            Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                   spec: .opacity(OpacityAction(initial: 0, end: 1))),
        ])
        let scene = evaluate(project, at: 0.5)
        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].position == Vec2(50, 25))
        #expect(abs(scene.layers[0].opacity - 0.5) < 1e-12)
        #expect(scene.time == 0.5)
    }

    @Test func sameInputSameOutput() {
        let project = Project(layers: [rect(), rect("B", at: Vec2(10, 10))])
        #expect(evaluate(project, at: 1.2345) == evaluate(project, at: 1.2345))
    }

    @Test func layersLastTheWholeComposition() {
        let project = Project(layers: [rect()])
        #expect(evaluate(project, at: 0).layers.count == 1)
        #expect(evaluate(project, at: 1000).layers.count == 1)
    }

    @Test func hiddenLayersAndTheirChildrenAreLeftOut() {
        var group = Layer(name: "G", content: .group(GroupContent(children: [rect()])), size: Size2(10, 10),
                          position: .zero)
        group.isVisible = false
        #expect(evaluate(Project(layers: [group, rect("Top")]), at: 0).layers.count == 1)
    }

    @Test func soloShowsOnlySoloedLayersAndTheGroupsAroundThem() {
        var soloed = rect("Soloed")
        soloed.isSoloed = true
        let sibling = rect("Sibling")
        let group = Layer(name: "G", content: .group(GroupContent(children: [soloed, sibling])),
                          size: Size2(10, 10), position: .zero)
        let outside = rect("Outside")
        let ids = evaluate(Project(layers: [group, outside]), at: 0).layers.map(\.id)
        #expect(ids == [group.id, soloed.id])
    }

    @Test func soloingAGroupShowsEverythingInside() {
        var group = Layer(name: "G", content: .group(GroupContent(children: [rect("A"), rect("B")])),
                          size: Size2(10, 10), position: .zero)
        group.isSoloed = true
        #expect(evaluate(Project(layers: [group, rect("Outside")]), at: 0).layers.count == 3)
    }

    @Test func childrenFollowTheirGroupInDrawingOrder() {
        let a = rect("A"), b = rect("B")
        let group = Layer(name: "G", content: .group(GroupContent(children: [a, b], clipsContent: true)),
                          size: Size2(10, 10), position: .zero)
        let scene = evaluate(Project(layers: [group]), at: 0)
        #expect(scene.layers.map(\.id) == [group.id, a.id, b.id])
        #expect(scene.layers[1].parentID == group.id)
        #expect(scene.layers[0].clipsContent)
    }

    @Test func maskLayersDoNotDrawOnTheirOwn() {
        let mask = rect("Mask")
        var masked = rect("Masked")
        masked.mask = MaskReference(layerID: mask.id)
        let scene = evaluate(Project(layers: [mask, masked]), at: 0)
        #expect(scene.layers.map(\.id) == [masked.id])
        #expect(scene.layers[0].mask?.layerID == mask.id)
    }

    @Test func transparentBackgroundIsNil() {
        var project = Project()
        #expect(evaluate(project, at: 0).background == .white)
        project.composition.background.isTransparent = true
        #expect(evaluate(project, at: 0).background == nil)
    }

    @Test func worldTransformsComposeThroughGroups() {
        // A 10x10 child at (5,5) in its group, the group moved by (100, 0)
        // and turned 90 degrees clockwise about its own origin.
        var child = rect("Child", at: Vec2(5, 5), size: Size2(10, 10))
        child.transform.anchor = .zero
        var group = Layer(name: "G", content: .group(GroupContent(children: [child])), size: Size2(100, 100),
                          position: Vec2(100, 0))
        group.transform.anchor = .zero
        group.transform.rotation = 90
        let scene = evaluate(Project(layers: [group]), at: 0)
        let corner = scene.worldTransform(of: child.id)!.apply(.zero)
        // (5,5) turned clockwise in y-down space lands at (-5, 5), then moved.
        #expect(abs(corner.x - 95) < 1e-9 && abs(corner.y - 5) < 1e-9)
    }

    @Test func videoSourceTimeFollowsTrim() {
        let clip = Layer(name: "Clip", content: .video(VideoContent(mediaID: UUID(), trimStart: 2)),
                         size: Size2(10, 10), position: .zero)
        guard case .video(_, let sourceTime) = evaluate(Project(layers: [clip]), at: 1.5).layers[0].content else {
            Issue.record("expected video")
            return
        }
        #expect(sourceTime == 3.5)
    }
}

@Suite struct GeometryTests {
    private func points(_ path: BezierPath) -> [Vec2] { path.subpaths.flatMap { $0.points.map(\.position) } }

    @Test func squareCornersWithoutRadius() {
        let path = ShapePaths.rectangle(Size2(40, 20), radii: .zero)
        #expect(points(path) == [Vec2(0, 0), Vec2(40, 0), Vec2(40, 20), Vec2(0, 20)])
        #expect(path.subpaths[0].isClosed)
    }

    @Test func radiiAreClampedToHalfTheShortSide() {
        let path = ShapePaths.rectangle(Size2(40, 20), radii: CornerRadii(all: 100))
        let box = Box(around: points(path))!
        #expect(box.minX == 0 && box.maxX == 40 && box.minY == 0 && box.maxY == 20)
        #expect(points(path).contains(Vec2(10, 0)))
    }

    @Test func polygonsAndStarsFitTheirBox() {
        let hexagon = ShapePaths.polygon(Size2(100, 100), sides: 6)
        #expect(hexagon.subpaths[0].points.count == 6)
        #expect(points(hexagon)[0] == Vec2(50, 0))
        let star = ShapePaths.star(Size2(100, 100), points: 5, innerRadius: 0.5)
        #expect(star.subpaths[0].points.count == 10)
        let box = Box(around: points(star))!
        #expect(box.minY >= 0 && box.maxY <= 100 && box.minX >= 0 && box.maxX <= 100)
    }

    @Test func linesAreOpenAndCrossTheMiddle() {
        let line = ShapePaths.line(Size2(80, 10))
        #expect(!line.subpaths[0].isClosed)
        #expect(points(line) == [Vec2(0, 5), Vec2(80, 5)])
    }

    @Test func openPathsStrokeCentred() {
        var line = Layer(name: "L", content: .shape(ShapeContent(geometry: .line,
            strokes: [Stroke(paint: .color(.black), width: 4, alignment: .inside)])),
            size: Size2(80, 0), position: .zero)
        line.name = "Line"
        guard case .shape(let shape) = evaluate(Project(layers: [line]), at: 0).layers[0].content else { return }
        #expect(shape.strokes[0].alignment == .center)
    }
}
