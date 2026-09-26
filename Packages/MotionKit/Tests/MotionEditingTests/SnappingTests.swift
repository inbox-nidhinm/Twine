import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box {
    Box(minX: x, minY: y, maxX: x + w, maxY: y + h)
}

private let frame = box(0, 0, 1000, 600)

@Suite struct SnappingTests {
    @Test func edgesSnapToOtherEdgesWithinReach() {
        // Its left edge is 3 past the other's right edge.
        let result = Snapping.move(box(203, 300, 50, 50), targets: [box(100, 100, 100, 50)], frame: frame, threshold: 5)
        #expect(result.offset.x == -3)
        #expect(result.guides.contains { $0.axis == .x && $0.value == 200 && $0.from == 100 && $0.to == 350 })
        // Too far: nothing.
        #expect(Snapping.move(box(210, 300, 50, 50), targets: [box(100, 100, 100, 50)], frame: frame, threshold: 5).offset.x == 0)
    }

    @Test func centresSnapToTheFramesCentre() {
        let result = Snapping.move(box(452, 277, 100, 50), targets: [], frame: frame, threshold: 5)
        #expect(result.offset == Vec2(-2, -2))
        // The guides run the height and width of the frame.
        #expect(result.guides.contains { $0.axis == .x && $0.value == 500 && $0.from == 0 && $0.to == 600 })
        #expect(result.guides.contains { $0.axis == .y && $0.value == 300 })
    }

    @Test func theNearestWinsAndEveryMatchShows() {
        // Left edge 2 from one target's left, right edge 2 from another's
        // right, and 4 from something else: the two at 2 both show.
        let targets = [box(100, 0, 10, 10), box(248, 100, 2, 10), box(90, 200, 10, 10)]
        let result = Snapping.move(box(102, 300, 150, 50), targets: targets, frame: frame, threshold: 5)
        #expect(result.offset.x == -2)
        #expect(Set(result.guides.filter { $0.axis == .x }.map(\.value)) == [100, 250])
    }

    @Test func centresBetweenNeighbours() {
        // Neighbours at 100 to 200 and 400 to 500; a 100 wide box centred
        // between them starts at 250, leaving 50 either side.
        let row = [box(100, 0, 100, 100), box(400, 0, 100, 100)]
        let result = Snapping.move(box(247, 20, 100, 60), targets: row, frame: frame, threshold: 5)
        #expect(result.offset.x == 3)
        #expect(result.gaps.map(\.length) == [50, 50])
        #expect(result.gaps.allSatisfy { $0.axis == .x && $0.cross == 50 })
    }

    @Test func carriesOnAGapTheRowAlreadyKeeps() {
        // Two boxes 40 apart; a third after them snaps 40 on from the second.
        let row = [box(0, 0, 100, 100), box(140, 0, 100, 100)]
        let result = Snapping.move(box(282, 10, 100, 80), targets: row, frame: frame, threshold: 5)
        #expect(result.offset.x == -2)
        #expect(result.gaps.count == 2 && result.gaps.allSatisfy { $0.length == 40 })
    }

    @Test func spacingOnlyCountsBoxesAlongside() {
        // The pair is far below, so it says nothing about this row.
        let row = [box(0, 400, 100, 100), box(140, 400, 100, 100)]
        let result = Snapping.move(box(282, 10, 50, 50), targets: row, frame: frame, threshold: 5)
        #expect(result.gaps.isEmpty)
    }

    @Test func aHeldAxisStaysPut() {
        let result = Snapping.move(box(452, 277, 100, 50), targets: [], frame: frame, threshold: 5, axes: [.y])
        #expect(result.offset == Vec2(0, -2))
    }

    @Test func aPointSnapsOnTheAxesItMoves() {
        let result = Snapping.point(Vec2(198, 51), box: box(150, 20, 48, 31), targets: [box(100, 50, 100, 100)],
                                    frame: frame, threshold: 5, axes: [.x])
        #expect(result.offset == Vec2(2, 0))
        #expect(result.guides.count == 1)
    }
}

@Suite struct AlignmentTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func alignsToTheReference() {
        let boxes = [a: box(10, 10, 50, 50), b: box(100, 40, 20, 20)]
        let all = box(10, 10, 110, 50)
        #expect(Alignment.align(boxes, .left, to: all) == [a: Vec2(0, 0), b: Vec2(-90, 0)])
        #expect(Alignment.align(boxes, .bottom, to: all) == [a: Vec2(0, 0), b: Vec2(0, 0)])
        #expect(Alignment.align(boxes, .centerY, to: all)[b] == Vec2(0, -15))
        #expect(Alignment.align([a: box(10, 10, 50, 50)], .centerX, to: frame)[a] == Vec2(465, 0))
    }

    @Test func distributesEqualSpacesKeepingTheEnds() {
        // 0 to 100, 110 to 130, 300 to 400: 400 across holding 220 of boxes
        // leaves two spaces of 90.
        let boxes = [a: box(0, 0, 100, 10), b: box(110, 50, 20, 10), c: box(300, 0, 100, 10)]
        let moves = Alignment.distribute(boxes, along: .x)
        #expect(moves[a] == .zero && moves[c] == .zero)
        #expect(moves[b] == Vec2(80, 0))
        #expect(Alignment.distribute([a: box(0, 0, 1, 1), b: box(5, 5, 1, 1)], along: .x).isEmpty)
    }
}
