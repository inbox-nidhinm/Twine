import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// Templates: every recipe, and a template frame as `evaluate` draws it.
@Suite struct TemplateTests {
    static let size = Size2(1280, 720)

    static func frame(_ kind: TemplateKind, slots: Int? = nil) -> Layer {
        let setup = TemplateSetup(kind: kind, slots: Array(repeating: nil, count: slots ?? TemplateRecipes.slotCount(kind)))
        return Layer(name: "T", content: .group(GroupContent(frame: FrameStyle(), template: setup)), size: size,
                     position: Vec2(size.width / 2, size.height / 2))
    }

    private func finite(_ c: TemplateCard) -> Bool {
        [c.position.x, c.position.y, c.z, c.rotation, c.tilt.x, c.tilt.y, c.curve.x, c.curve.y, c.scale, c.opacity,
         c.cell.width, c.cell.height].allSatisfy(\.isFinite)
    }

    @Test(arguments: TemplateKind.allCases)
    func everyTemplateMovesAndComesBackRound(_ kind: TemplateKind) {
        let setup = Self.frame(kind).template!
        let start = TemplateRecipes.scene(setup, phase: 0, size: Self.size)
        let middle = TemplateRecipes.scene(setup, phase: 0.37, size: Self.size)
        let almost = TemplateRecipes.scene(setup, phase: 0.99999, size: Self.size)
        #expect(start.cards.count >= 3, "\(kind) has cards")
        #expect(start.cards.allSatisfy(finite), "\(kind) has only real numbers")
        #expect(start.cards.allSatisfy { $0.opacity >= 0 && $0.opacity <= 1 && $0.cell.width > 0 && $0.cell.height > 0 })
        #expect(start != middle, "\(kind) moves")
        // The loop ends where it began, so it repeats without a seam. A
        // stream's cards go round from one end to the other faded right
        // out, where nothing shows.
        for (a, b) in zip(start.cards, almost.cards) where a.opacity > 0.01 && b.opacity > 0.01 {
            #expect(abs(a.position.x - b.position.x) < 0.5 && abs(a.position.y - b.position.y) < 0.5 && abs(a.z - b.z) < 0.5,
                    "\(kind) card \(a.index) ends where it began")
        }
        // Its settings are well formed: unique keys, defaults in range.
        let controls = TemplateRecipes.controls(kind)
        #expect(Set(controls.map(\.key)).count == controls.count)
        for c in controls {
            if case .number(let lo, let hi, let standard, _) = c.kind { #expect(standard >= lo && standard <= hi, "\(kind) \(c.key)") }
        }
    }

    @Test func aTemplateFrameDrawsItsCardsInItsSpace() throws {
        let frame = Self.frame(.ringStream)
        let scene = evaluate(Project(composition: Composition(width: 1280, height: 720), layers: [frame]), at: 0)
        let cards = scene.layers.filter { $0.parentID == frame.id }
        #expect(cards.count == 12)
        #expect(cards.allSatisfy { $0.placed != .none })
        // Each card's id is its own, steady, and known as the frame's.
        #expect(Set(cards.map(\.id)).count == 12)
        #expect(cards.allSatisfy { TemplateCards.isCard($0.id, of: frame.id) })
        #expect(!TemplateCards.isCard(frame.id, of: frame.id))
        #expect(cards.first?.id == TemplateCards.id(of: 0, in: frame.id))
        // Cards follow the ring's curve.
        #expect(cards.allSatisfy { $0.placed.mesh != nil })
    }

    @Test func picturesFillTheirSlotsAndGoRoundAgain() throws {
        let a = UUID(), b = UUID()
        var frame = Self.frame(.globe)
        frame.template?.slots = [a, b]
        let project = Project(composition: Composition(width: 1280, height: 720), layers: [frame],
                              media: [MediaAsset(id: a, kind: .image, fileName: "a.png", originalName: "a.png", contentHash: "a",
                                                 pixelWidth: 400, pixelHeight: 200),
                                      MediaAsset(id: b, kind: .image, fileName: "b.png", originalName: "b.png", contentHash: "b",
                                                 pixelWidth: 200, pixelHeight: 400)])
        let made = TemplateCards.make(frame, frame.template!, phase: 0, size: Self.size, pictures: project.pictureSizes)
        #expect(made.cards.count == 36)
        func media(_ l: Layer) -> UUID? { l.look?.fills.first?.paint.imagePaint?.mediaID }
        #expect(media(made.cards[0]) == a && media(made.cards[1]) == b && media(made.cards[2]) == a)
        // Auto cards take their pictures' shapes, fitted to their cells.
        #expect(abs(made.cards[0].size.width / made.cards[0].size.height - 2) < 1e-9)
        #expect(abs(made.cards[1].size.width / made.cards[1].size.height - 0.5) < 1e-9)
        // One shape for all, rounded as set.
        frame.template?.ratio = .square
        frame.template?.cornerRadius = 0.1
        let square = TemplateCards.make(frame, frame.template!, phase: 0, size: Self.size, pictures: project.pictureSizes)
        #expect(square.cards.allSatisfy { abs($0.size.width - $0.size.height) < 1e-9 })
        if case .shape(let shape) = square.cards[0].content, case .rectangle(let radii) = shape.geometry {
            #expect(abs(radii.topLeft - square.cards[0].size.width * 0.1) < 1e-9)
        } else {
            Issue.record("a rounded rectangle")
        }
    }

    @Test func itsBarPlaysTheLoop() throws {
        var frame = Self.frame(.carouselRing)
        frame.template?.pose = 0.25
        let bar = Action(target: frame.id, start: 1, duration: 4, easing: .linear, spec: .template(TemplatePlay(loops: 2)))
        let tracks = ActionTracks([bar])
        // Before its bar, where it rests; half way through two loops, a
        // whole loop on; at the end, back where it rests.
        #expect(tracks.state(of: frame, at: 0).template.phase == 0.25)
        #expect(abs(tracks.state(of: frame, at: 3).template.phase! - 0.25) < 1e-9)
        #expect(abs(tracks.state(of: frame, at: 2).template.phase! - 0.75) < 1e-9)
        #expect(abs(tracks.state(of: frame, at: 9).template.phase! - 0.25) < 1e-9)
        // Drawn there.
        let project = Project(composition: Composition(width: 1280, height: 720), layers: [frame], actions: [bar])
        let atTwo = evaluate(project, at: 2).layers.filter { $0.parentID == frame.id }
        var resting = frame
        resting.template?.pose = 0.75
        let still = evaluate(Project(composition: Composition(width: 1280, height: 720), layers: [resting]), at: 0)
            .layers.filter { $0.parentID == frame.id }
        #expect(atTwo == still)
    }

    @Test func settingsAreRead() {
        var frame = Self.frame(.ringStream)
        frame.template?.settings["count"] = .number(6)
        #expect(TemplateRecipes.scene(frame.template!, phase: 0, size: Self.size).cards.count == 6)
        frame.template?.settings["count"] = .choice("nonsense")
        #expect(TemplateRecipes.scene(frame.template!, phase: 0, size: Self.size).cards.count == 12)
    }

    @Test func templatesKeepInFiles() throws {
        var frame = Self.frame(.wheel)
        frame.template?.slots = [UUID(), nil]
        frame.template?.settings = ["count": .number(10), "spin": .choice("flip")]
        frame.template?.shadow = true
        let back = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(frame))
        #expect(back.template == frame.template)
        #expect(back.mediaIDs == frame.template!.mediaIDs)
    }
}
