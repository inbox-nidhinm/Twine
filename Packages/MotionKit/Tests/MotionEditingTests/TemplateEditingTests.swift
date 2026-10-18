import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

/// Adding templates and splitting them into layers.
@Suite @MainActor struct TemplateEditingTests {
    private func store(_ project: Project) -> ProjectStore {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return ProjectStore(project: project, undoManager: undo)
    }

    private func picture(_ media: UUID) -> Layer {
        Layer(name: "P", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                     fills: [Fill(paint: .image(ImagePaint(mediaID: media)))])),
              size: Size2(100, 100), position: Vec2(50, 50))
    }

    @Test func theLibraryHasEveryTemplate() {
        #expect(Templates.library.count == 69)
        #expect(Set(Templates.library.map(\.kind)) == Set(TemplateKind.allCases))
        #expect(Set(Templates.library.map(\.name)).count == 69)
        #expect(Templates.library.filter { $0.group == .isometric }.count == 3)
        #expect(Templates.library.filter { $0.group == .orbit }.count == 8)
        let counts = Dictionary(grouping: Templates.library, by: \.group).mapValues(\.count)
        #expect(counts[.flow] == 10 && counts[.grid] == 8 && counts[.spotlight] == 4 && counts[.reveal] == 4 && counts[.stack] == 7)
        #expect(counts[.sequence] == 13)
    }

    @Test func addingTakesTheSelectedPicturesIntoItsSlots() throws {
        let a = UUID(), b = UUID()
        let pa = picture(a), pb = picture(b)
        let text = LayerFactory.text(at: .zero, name: "T")
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 6), layers: [pa, pb, text]))
        let (command, id) = Templates.adding(.ringStream, to: store.project, replacing: [pa, pb, text])
        try store.perform(command)
        let frame = try #require(store.project.layer(withID: id))
        #expect(frame.template?.slots.prefix(2) == [a, b])
        #expect(frame.template?.slots.count == 12)
        #expect(frame.size == Size2(1280, 720))
        // The pictures went in; the text stays.
        #expect(store.project.layer(withID: pa.id) == nil && store.project.layer(withID: pb.id) == nil)
        #expect(store.project.layer(withID: text.id) != nil)
        // Its bar spans the scene.
        let bar = try #require(store.project.actions.first { $0.targetLayerID == id })
        #expect(bar.start == 0 && bar.duration == 6 && bar.spec == .template(TemplatePlay()))
        // One step to undo.
        store.undoManager.undo()
        #expect(store.project.layer(withID: id) == nil && store.project.layer(withID: pa.id) != nil)
    }

    @Test func splittingMakesRealCardsThatPlayTheSame() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 4)))
        let (add, id) = Templates.adding(.photoLoop, to: store.project)
        try store.perform(add)
        let before = store.project
        let command = try #require(Templates.split(id, in: store.project))
        try store.perform(command)
        let frame = try #require(store.project.layer(withID: id))
        #expect(frame.template == nil && frame.space3D != nil)
        #expect(frame.children.count == 8)
        #expect(!store.project.actions.contains { $0.spec.kind == .template })
        #expect(store.project.scenes.last?.name == "Photo Loop")
        // At every step it is where the template was.
        for k in [0, 5, 12, 23] {
            let t = 4 * Double(k) / Double(Templates.splitSteps)
            let template = evaluate(before, at: t).layers.filter { $0.parentID == id }.map(\.projection)
            let split = evaluate(store.project, at: t).layers.filter { $0.parentID == id }.map(\.projection)
            #expect(template.count == split.count)
            for (a, b) in zip(template, split) {
                let p = Vec2(10, 10)
                #expect(abs(a.apply(p)!.x - b.apply(p)!.x) < 0.01 && abs(a.apply(p)!.y - b.apply(p)!.y) < 0.01, "at step \(k)")
            }
        }
        #expect(Templates.split(frame.children[0].id, in: store.project) == nil)
    }

    @Test func aSplitSequencePlaysTheSameAtEveryStep() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 8)))
        let (add, id) = Templates.adding(.ringBelt, to: store.project)
        try store.perform(add)
        let before = store.project
        try store.perform(try #require(Templates.split(id, in: store.project)))
        let steps = Templates.splitSteps(for: .ringBelt)
        #expect(steps == Templates.splitSteps * 2)
        for k in stride(from: 0, to: steps, by: 7) {
            let t = 8 * Double(k) / Double(steps)
            let template = evaluate(before, at: t).layers.filter { $0.parentID == id && $0.opacity > 0.01 }.map(\.projection)
            let split = evaluate(store.project, at: t).layers.filter { $0.parentID == id && $0.opacity > 0.01 }.map(\.projection)
            #expect(template.count == split.count, "at step \(k)")
            for (a, b) in zip(template, split) {
                let p = Vec2(10, 10)
                #expect(abs(a.apply(p)!.x - b.apply(p)!.x) < 0.05 && abs(a.apply(p)!.y - b.apply(p)!.y) < 0.05, "at step \(k)")
            }
        }
    }

    /// A wheel turning twice over its bar keeps turning the same way when
    /// split: no step turns back the long way round.
    @Test func splitTurnsNeverSpinBack() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 8)))
        let (add, id) = Templates.adding(.wheel, to: store.project)
        try store.perform(add)
        var bar = try #require(store.project.actions.first { $0.targetLayerID == id })
        bar.spec = .template(TemplatePlay(loops: 2))
        try store.perform(.updateActions([bar]))
        try store.perform(try #require(Templates.split(id, in: store.project)))
        let card = try #require(store.project.layer(withID: id)?.children.first)
        let turns = store.project.actions.filter { $0.targetLayerID == card.id }.sorted { $0.start < $1.start }
            .compactMap { action -> Double? in if case .rotate(let r) = action.spec { return r.end } else { return nil } }
        #expect(turns.count > 40)
        var last = card.transform.rotation
        for turn in turns {
            #expect(abs(turn - last) < 90)
            last = turn
        }
        #expect(abs(last - card.transform.rotation) > 700)
    }
}
